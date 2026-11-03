import Foundation
import OrbitalCore
import OrbitalAddons

/// Tu Real-Debrid en la guía y en Ajustes › Cuentas: pegar la clave, comprobarla al momento y ver cuánto te queda.
@MainActor
public final class DebridModel: ObservableModel {
    public enum Check: Equatable {
        case idle, checking
        /// Premium: ya quedó guardada.
        case ok(DebridStatus)
        /// La cuenta es gratuita: sin Premium no hay videos (no se guarda).
        case free(DebridStatus)
        case failed(String)
    }
    public internal(set) var check: Check = .idle { didSet { changed() } }
    /// Lo que se sabe de la clave guardada (nil sin clave).
    public internal(set) var status: DebridStatus? { didSet { changed() } }
    /// P6-A · si tu clave sirve, según Real-Debrid en esta visita (`recheck`). Mientras pregunta, `checking`: la página enseña
    /// lo último que se supo sin la palomita; nunca «Conectada ✓» de algo que no se confirmó ahora.
    public enum KeyCheck: Equatable, Sendable { case checking, confirmed, rejected, unreachable }
    public internal(set) var keyCheck: KeyCheck = .checking { didSet { if oldValue != keyCheck { changed() } } }
    public var token = "" { didSet { if oldValue != token { check = .idle; changed() } } }
    let services: Services

    public init(_ services: Services) {
        self.services = services
        status = services.debrid.saved
        super.init()
    }

    public var hasToken: Bool { services.debrid.hasToken }
    /// La clave se tomó de tu Torrentio importado de Stremio (no la pegaste): se dice en Ajustes.
    public var keyCameFromImport: Bool { services.debrid.keyCameFromImport }
    public var tokenURL: URL { services.debrid.provider.tokenURL }
    public var renewURL: URL { services.debrid.provider.renewURL }
    /// «Continuar» de la guía: la clave guardada sirve (Premium).
    public var ready: Bool { if case .ok = check { return true }; return hasToken && status?.isPremium == true }

    /// Al abrir Ajustes: el estado guardado, o uno nuevo si es de ayer.
    public func load(force: Bool = false) async { status = await services.debrid.status(force: force) }

    /// P6-A · al abrir tu cuenta de Real-Debrid: se le pregunta si tu clave sirve. Rechazada: «Vuelve a conectar Real-Debrid»;
    /// sin respuesta: «No pude ver tu cuenta»; confirmada: «Conectada ✓».
    public func recheck() async {
        keyCheck = .checking
        switch await services.debrid.checkNow() {
        case .status(let fresh): status = fresh; keyCheck = .confirmed
        case .invalidToken: keyCheck = .rejected
        case .unreachable: keyCheck = .unreachable
        case .noKey: status = nil; keyCheck = .checking
        }
    }

    /// Comprueba la clave pegada. Si es Premium se guarda y tus complementos recomendados se arman con ella.
    public func verify() async {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        check = .checking
        do {
            let found = try await services.debrid.verify(clean)
            guard clean == token.trimmingCharacters(in: .whitespacesAndNewlines) else { return }   // cambiaste la clave mientras
            guard found.isPremium else { check = .free(found); return }
            await keep(clean, found)
            check = .ok(found)
        } catch let error as DebridError {
            check = .failed(error.description)
        } catch { check = .failed(DebridError.unexpected.description) }
    }

    /// Guarda una clave que Real-Debrid ya aceptó (Premium): la pegada o la de tu TV.
    func keep(_ clean: String, _ found: DebridStatus) async {
        await services.debrid.save(token: clean, status: found)
        services.addonList.startWithRecommended()
        await services.resetAccountCaches()
        status = found
        keyCheck = .confirmed   // Real-Debrid la acaba de aceptar
    }

    /// K1 · «Pasar a la TV» y «Usar la de la TV»: trabajando, lo que quedó o por qué no (en palabras).
    public enum TVShare: Equatable, Sendable { case idle, working, passed(OrbitalTVDebrid), used, failed(String) }
    public internal(set) var tvShare: TVShare = .idle { didSet { if oldValue != tvShare { changed() } } }

    /// D1: las últimas 4 letras de tu clave («3F2A»); nunca completa.
    public var keyTail: String? { services.debrid.keyTail }

    /// D4: el canje de puntos: trabajando, hecho o por qué no.
    public enum Redeem: Equatable { case idle, working, done, failed(String) }
    public private(set) var redeem: Redeem = .idle { didSet { changed() } }

    /// D4: canjea tus puntos por días de Premium (la pantalla pregunta antes: no se puede deshacer).
    public func redeemPoints() async {
        redeem = .working
        do {
            if let fresh = try await services.debrid.redeemPoints() { status = fresh }
            redeem = .done
        } catch let error as DebridError { redeem = .failed(error.description) }
        catch { redeem = .failed(DebridError.unexpected.description) }
    }

    /// «Quitar»: se olvida la clave (los recomendados se quedan sin fuentes hasta que pongas otra). CX3-A: «Solo de este
    /// iPhone» o, con `everywhere`, «De todos tus aparatos Apple».
    public func remove(everywhere: Bool = false) async {
        await services.debrid.remove(everywhere: everywhere)
        services.sharedDebrid = .none
        await services.resetAccountCaches()
        status = nil; token = ""; check = .idle; keyCheck = .checking
    }

    /// «Te quedan 143 días» / «Vence hoy» / «Venció hace 2 días» / «Cuenta gratuita»: cómo está, en palabras.
    nonisolated public static func summary(_ status: DebridStatus, now: Date) -> (state: DebridStatus.State, days: Int) {
        let state = status.state(now: now)
        switch state {
        case .active(let d), .expiringSoon(let d): return (state, d)
        case .expired(let d): return (state, d)
        case .free: return (state, 0)
        }
    }
}

/// Tus complementos (Ajustes › Complementos y la guía): en tu orden, con interruptor, de dónde vino cada uno y si usa tu
/// Real-Debrid. Agregar un recomendado que falte, quitar los traídos de Stremio e importarlos (ya no se pega una dirección, C9).
@MainActor
public final class AddonsModel: ObservableModel {
    public private(set) var items: [InstalledAddon] = [] { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    public private(set) var working = false { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
        items = services.addonList.installed
        torrentioChoice = Self.choices(services.addonList)
    }

    /// Los recomendados que todavía no tienes (para «Agregar › Recomendados»).
    public var missingRecommended: [AddonTemplate] {
        AddonCatalog.recommended.filter { t in !items.contains { $0.origin == .recommended(t.id) } }
    }

    /// Qué dice cada uno debajo de su nombre: «Usa tu Real-Debrid», «Subtítulos»…, y si vino de Stremio.
    public static func summary(_ addon: InstalledAddon) -> (usesDebrid: Bool, subtitles: Bool, imported: Bool) {
        (addon.usesDebrid, addon.resources == ["subtitles"], addon.origin == .imported)
    }

    /// La primera vez (la guía o la primera visita a Ajustes): con los recomendados, y lo que tenías en Stremio.
    public func prepare() async {
        services.addonList.startWithRecommended()
        if !services.addonList.hasImported { _ = try? await services.importAddonsFromStremio() }
        // C5 también para lo que ya tenías: un Torrentio traído antes pasa al de Orbital si este sigue como vino.
        if services.addonList.adoptImportedTorrentio() { await services.resetAccountCaches() }
        // M6: el que ya contestó solo con torrents se apaga aquí (una vez); en la TV sigue.
        if !services.addonList.turnOffTorrentsOnly(services.addonHealth.onlyTorrents).isEmpty { await services.resetAccountCaches() }
        reload()
        await loadConfigurable()
    }

    public func setEnabled(_ id: String, _ on: Bool) async {
        services.addonList.setEnabled(id, on)
        reload(); await services.resetAccountCaches()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        services.addonList.move(fromOffsets: source, toOffset: destination)
        reload(); await services.resetAccountCaches()
    }

    /// Se puede quitar: solo los traídos de Stremio (o pegados antes); los que vienen con Orbital solo se apagan (C7).
    public func canRemove(_ addon: InstalledAddon) -> Bool { !addon.isBuiltIn }

    /// Es tu última fuente de video prendida: apagarla o quitarla te deja sin versiones (se avisa antes).
    public func isLastSource(_ id: String) -> Bool { services.addonList.isLastSource(id) }

    /// Quita uno traído de Stremio; «Deshacer» (`undoRemove`) lo regresa con todo mientras dura el aviso.
    @discardableResult
    public func remove(_ id: String) async -> Bool {
        guard services.addonList.remove(id) else { return false }
        reload(); await services.resetAccountCaches()
        return true
    }

    @discardableResult
    public func undoRemove(_ id: String) async -> Bool {
        guard services.addonList.undoRemove(id) else { return false }
        reload(); await services.resetAccountCaches()
        return true
    }

    public func add(_ template: AddonTemplate) async {
        services.addonList.add(template)
        reload(); await services.resetAccountCaches()
    }

    /// «Volver a traer» de Stremio (sin los que quitaste).
    public func importAgain() async {
        working = true
        defer { working = false }
        // El error puede traer la URL de un complemento con su clave (D2): nunca se enseña.
        do { _ = try await services.importAddonsFromStremio(again: true); error = nil }
        catch { self.error = AddonRedaction.redact(stripURLs("\(error)"), secrets: services.addonList.secretsToRedact()) }
        reload()
    }

    public func clearError() { error = nil }

    /// Tu lista y la de tu TV (S6): al abrir Complementos se lee la de la TV y se junta; lo que cambie aquí se le manda solo.
    public var tv: AddonTVSync { services.addonSync }
    public func syncWithTV() async {
        await services.addonSync.refresh()
        reload()
    }

    private func reload() { items = services.addonList.installed; torrentioChoice = Self.choices(services.addonList) }

    // MARK: C1 · cómo le va a cada uno; C3 y M4 · «Configurar»; C5 · con cuál Torrentio quedarse

    /// M6: solo da torrents: «En el iPhone no se puede reproducir; en la TV sí».
    public func onlyTorrents(_ addon: InstalledAddon) -> Bool {
        !addon.isBuiltIn && services.addonList.resolvedURL(addon).map(services.addonHealth.onlyTorrents) == true
    }

    /// Cómo le ha ido en este aparato (sin dato si está apagado o aún no se le ha preguntado).
    public func health(_ addon: InstalledAddon) -> AddonHealth.State {
        guard addon.enabled, let url = services.addonList.resolvedURL(addon) else { return .unknown }
        return services.addonHealth.status(url)
    }

    public enum Configure: Equatable, Sendable {
        /// Torrentio: la página de la app (T1).
        case torrentio
        /// Uno traído que tiene su propia página: se abre dentro de la app (M4).
        case page(URL)
    }

    /// Los traídos con página de configuración (de su manifiesto); se llena con `loadConfigurable`.
    public private(set) var configurableIDs: Set<String> = [] { didSet { changed() } }

    public func configure(_ addon: InstalledAddon) -> Configure? {
        if addon.origin == .recommended(AddonCatalog.torrentio.id) { return .torrentio }
        guard configurableIDs.contains(addon.id), let url = services.addonList.resolvedURL(addon) else { return nil }
        let base = url.hasSuffix("/manifest.json") ? String(url.dropLast("/manifest.json".count)) : url
        return URL(string: "\(base)/configure").map(Configure.page)
    }

    /// Lee de los manifiestos cuáles tienen página propia (solo los prendidos: los apagados no se preguntan).
    public func loadConfigurable() async {
        guard let addons = try? await services.registry.addons() else { return }
        let configurable = Set(addons.filter(\.configurable).map(\.url))
        configurableIDs = Set(items.filter { !$0.isBuiltIn && services.addonList.resolvedURL($0).map(configurable.contains) == true }.map(\.id))
    }

    /// M4: su página dio una dirección nueva al tocar «Install»: se guarda en el mismo complemento, nunca uno nuevo.
    @discardableResult
    public func saveConfiguration(_ id: String, url: String) async -> Bool {
        guard services.addonList.replaceURL(id, with: url) else { return false }
        reload(); await services.resetAccountCaches()
        return true
    }

    /// Un Torrentio para elegir (C5): el de Orbital (`id` nil) o uno traído de tu Stremio, con sus opciones.
    public struct TorrentioCandidate: Equatable, Identifiable, Sendable {
        public var id: String { addonID ?? "orbital" }
        public var addonID: String?
        public var options: AddonOptions
    }

    /// Hay dos o más Torrentio: con cuál te quedas (vacío si no hay que preguntar).
    public private(set) var torrentioChoice: [TorrentioCandidate] = [] { didSet { changed() } }

    nonisolated static func choices(_ list: AddonList) -> [TorrentioCandidate] {
        guard list.needsTorrentioChoice else { return [] }
        let mine = TorrentioCandidate(addonID: nil, options: list.torrentio?.options ?? TorrentioConfig.recommended)
        return list.importedTorrentios.compactMap { addon in
            list.resolvedURL(addon).flatMap(TorrentioConfig.parse).map { TorrentioCandidate(addonID: addon.id, options: $0.options) }
        } + [mine]
    }

    public func keepTorrentio(_ candidate: TorrentioCandidate) async {
        services.addonList.keepTorrentio(from: candidate.addonID)
        reload(); await services.resetAccountCaches()
    }
}
