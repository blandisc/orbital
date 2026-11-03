import Foundation
import OrbitalCore
import OrbitalAddons

/// Configuras una vez en el iPhone y tu TV lo toma (S1, S3, S6; corte S6 de la TV): al abrir Complementos o Torrentio y al
/// volver a la app se lee la lista de la TV; cada cambio de aquí se le manda con la revisión de la que partió; si la TV ya
/// tenía otra (409), se junta complemento por complemento y opción por opción y se reintenta una vez. Si al juntar quedan
/// iguales, ya está.
///
/// Solo en Orbital Ultra con una TV emparejada (S4): en Plus, o sin TV, no hace nada y Complementos no dice nada de la TV.
/// Sin llave por aparato nunca manda una clave. Con llave (K1) escribe solo `enabled[<su id>]`, lo que lleva clave también
/// viaja, y los de la TV que este aparato no tiene se piden una vez con `?full=1` y se guardan aquí (la dirección, en el llavero).
@MainActor
public final class AddonTVSync: ObservableModel {
    public enum Status: Equatable, Sendable {
        /// Sin TV emparejada (o en Plus): no se enseña nada.
        case off
        case checking
        /// Igual que tu TV; `by` es quién hizo el último cambio («tv» o el nombre de un aparato).
        case same(at: Date?, by: String?)
        /// Tu TV no contestó: lo de aquí se le manda cuando conteste.
        case unreachable
        /// Tu Orbital es de antes de poder compartir la lista.
        case outdated
        /// La TV no aceptó la lista (con su motivo).
        case refused(String)
    }

    /// Las opciones que chocaron (S3): «Se quedó la de la TV (9:40) · Usar la de este iPhone».
    public struct Clash: Equatable, Sendable {
        public var at: Date?
        public var options: [String]
        public var mine: AddonOptions
    }

    public private(set) var status: Status = .off { didSet { if oldValue != status { changed() } } }
    /// Los que se quedan en este iPhone porque su dirección lleva una clave («Espera las llaves por aparato»).
    public private(set) var waitingForKeys: [String] = [] { didSet { if oldValue != waitingForKeys { changed() } } }
    /// Los de tu TV que este iPhone no tiene (S5): «Archivos de la TV · Solo en la TV».
    public private(set) var tvOnly: [SharedAddon] = [] { didSet { if oldValue != tvOnly { changed() } } }
    /// El último choque, para avisar una vez con «Usar la de este iPhone». Lo vacía quien avisa.
    public private(set) var clash: Clash? { didSet { if oldValue != clash { changed() } } }
    /// Algo de la TV cambió tu lista aquí: quien enseña la lista la vuelve a leer.
    public var onListChanged: (@MainActor () async -> Void)?

    static let stateKey = "addons-tv-sync"
    /// Lo que se recuerda entre aperturas: la última lista en que quedaron de acuerdo (sin direcciones), qué es cada uno
    /// allá y si quedó algo por mandar.
    struct State: Codable, Equatable {
        var base: SharedAddonList?
        var links: [String: String] = [:]
        var pending = false
        /// K1 · los de la TV ya pedidos con `?full=1` (cuenta para el tope de 20 por hora: no se piden otra vez).
        var fullAsked: [String] = []

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            base = try c.decodeIfPresent(SharedAddonList.self, forKey: .base)
            links = try c.decodeIfPresent([String: String].self, forKey: .links) ?? [:]
            pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
            fullAsked = try c.decodeIfPresent([String].self, forKey: .fullAsked) ?? []
        }
    }

    private let list: AddonList
    private let vault: AddonVault
    private let remote: AddonListRemote
    private let available: @MainActor () -> Bool
    private let device: @MainActor () -> AddonDevice
    private let deviceName: @MainActor () -> String
    /// El nombre y lo que aporta un complemento, de su manifiesto (para guardar uno de la TV). nil: no se guardan.
    private let manifest: (@Sendable (String) async -> (name: String, resources: [String])?)?
    private let clock: @Sendable () -> Date
    private var running: Task<Void, Never>?
    private var again = false
    private var debounce: Task<Void, Never>?

    /// `device`: este aparato en `enabled`: su plataforma («iphone», «ipad») y, con llave (K1), el id que le dio la TV.
    public init(list: AddonList, vault: AddonVault, remote: AddonListRemote, available: @escaping @MainActor () -> Bool,
                device: @escaping @MainActor () -> AddonDevice, deviceName: @escaping @MainActor () -> String,
                manifest: (@Sendable (String) async -> (name: String, resources: [String])?)? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.list = list; self.vault = vault; self.remote = remote; self.available = available; self.device = device
        self.deviceName = deviceName; self.manifest = manifest; self.clock = clock
        super.init()
        list.onLocalChange = { [weak self] in Task { @MainActor in self?.localChanged() } }
    }

    /// Sin llave por aparato: la plataforma de siempre.
    public convenience init(list: AddonList, vault: AddonVault, remote: AddonListRemote, available: @escaping @MainActor () -> Bool,
                            device: String, deviceName: @escaping @MainActor () -> String, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(list: list, vault: vault, remote: remote, available: available, device: { AddonDevice(platform: device) },
                  deviceName: deviceName, clock: clock)
    }

    private var state: State {
        get { vault.data(Self.stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State() }
        set { vault.setData(Self.stateKey, try? JSONEncoder().encode(newValue)) }
    }

    public var isOn: Bool { available() && remote.isConfigured }

    /// Cambiaste algo aquí: se manda en un momento (varios toques seguidos van juntos).
    func localChanged() {
        guard isOn else { return }
        var saved = state; saved.pending = true; state = saved
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Lee la lista de la TV, junta y manda lo que falte. Una a la vez; si llega otra mientras, se repite al terminar.
    public func refresh() async {
        guard isOn else { status = .off; tvOnly = []; waitingForKeys = []; return }
        if let running { again = true; await running.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat { again = false; await self.round() } while again
        }
        running = task
        await task.value
        running = nil
    }

    private func round() async {
        if case .off = status { status = .checking }
        switch await remote.get() {
        case .list(let tv): await settle(tv, retries: 1)
        case .outdated: status = .outdated
        case .refused(let why): status = .refused(why)
        case .conflict, .unreachable: status = .unreachable
        }
    }

    /// Junta lo de la TV con lo de aquí y manda lo que falte; con un 409, junta otra vez y reintenta (`retries`).
    private func settle(_ tv: SharedAddonList, retries: Int) async {
        var saved = state
        saved.links = list.link(tv, links: saved.links)
        let merge = saved.base?.revision == tv.revision ? AddonTVMerge() : list.absorb(tv, base: saved.base, links: saved.links)
        if !merge.conflicts.isEmpty, let mine = merge.mine {
            clash = Clash(at: tv.changedAt, options: merge.conflicts.map { AddonShare.optionNames[$0] ?? "Orden" }, mine: mine)
        }
        if merge.changed, let onListChanged { await onListChanged() }
        let me = device(), keyed = remote.hasDeviceKey
        var plan = list.plan(for: tv, links: saved.links, device: me.key, platform: me.platform, deviceKey: keyed, changedBy: deviceName(), now: clock())
        if keyed, await adopt(plan.tvOnly, into: &saved, device: me) {
            if let onListChanged { await onListChanged() }
            plan = list.plan(for: tv, links: saved.links, device: me.key, platform: me.platform, deviceKey: keyed, changedBy: deviceName(), now: clock())
        }
        saved.links = plan.links
        tvOnly = plan.tvOnly; waitingForKeys = plan.waitingForKeys
        guard plan.needsPut else {
            saved.base = tv.withoutURLs; saved.pending = false; state = saved
            status = .same(at: tv.changedAt, by: tv.changedBy)
            return
        }
        state = saved
        switch await remote.put(plan.body) {
        case .list(let stored):
            saved.base = stored.withoutURLs; saved.pending = false; state = saved
            tvOnly = list.plan(for: stored, links: saved.links, device: me.key, platform: me.platform, deviceKey: keyed, changedBy: deviceName(), now: clock()).tvOnly
            status = .same(at: stored.changedAt, by: stored.changedBy)
        case .conflict(let current) where retries > 0:
            await settle(current, retries: retries - 1)
        case .conflict: status = .unreachable   // otra vez cambió en la TV: se intenta la próxima vez
        case .refused(let why): status = .refused(why)
        case .outdated: status = .outdated
        case .unreachable: status = .unreachable
        }
    }

    /// K1 · los de la TV que este aparato no tiene: una sola lectura con `?full=1` (tope de 20 por hora) y se guardan aquí
    /// con su dirección completa en el llavero. Cada uno se pide una vez. Devuelve si se guardó alguno.
    private func adopt(_ tvOnly: [SharedAddon], into saved: inout State, device me: AddonDevice) async -> Bool {
        let wanted = tvOnly.filter { !$0.isTVFiles && !saved.fullAsked.contains($0.id) }
        guard let manifest, !wanted.isEmpty, case .list(let full) = await remote.get(full: true) else { return false }
        saved.fullAsked.append(contentsOf: wanted.map(\.id))
        var added = false
        for shared in wanted {
            guard let url = full.addons.first(where: { $0.id == shared.id })?.url, let found = await manifest(url),
                  let id = list.adoptFromTV(shared, url: url, name: found.name, resources: found.resources, device: me.key, platform: me.platform)
            else { continue }
            saved.links[id] = shared.id
            added = true
        }
        state = saved
        return added
    }

    /// «Usar la de este iPhone» (S3): tus opciones de antes del choque vuelven y se mandan.
    public func useMine() async {
        guard let mine = clash?.mine else { return }
        clash = nil
        list.restoreTorrentio(mine)
        if let onListChanged { await onListChanged() }
    }

    public func clearClash() { clash = nil }

    /// La TV pidió una clave que este iPhone no manda: la frase tranquila de la página (no es un error).
    /// La TV de antes decía «Espera las llaves por aparato»; la de hoy, «…esa dirección lleva una clave».
    public static func waitsForKeys(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("llaves por aparato") || reason.localizedCaseInsensitiveContains("lleva una clave")
    }
}
