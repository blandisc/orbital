import Foundation

/// Tus complementos, en el teléfono y en tu orden (cuál se pregunta primero): prender y apagar cada uno, ordenarlos, agregar
/// un recomendado o uno pegado, quitar, e importar una vez los de Stremio (no se escribe de vuelta). Mientras no la armes
/// (`isConfigured` es false), la app sigue con la lista de tu cuenta de Stremio, como antes.
public final class AddonList: @unchecked Sendable {
    private let vault: AddonVault
    private let lock = NSLock()
    private var items: [InstalledAddon]?

    /// Lo guardado que no se pudo leer entero: nunca se escribe encima (la próxima versión quizá sí lo lea), y queda una copia.
    public private(set) var readFailed = false
    /// Las entradas que esta versión no entiende (de una versión más nueva): se vuelven a escribir tal cual.
    private var unreadable: [StoredJSON] = []

    public init(vault: AddonVault) {
        self.vault = vault
        guard let raw = vault.data(AddonKeys.installed) else { return }
        switch StoredAddons.read(raw) {
        case .current(let list, let rest):
            items = list; unreadable = rest
        case .legacy(let list, let rest):
            // Antes de tocar nada, una copia de lo que había (una sola: la primera migración manda).
            if vault.data(AddonKeys.installedBackup) == nil { vault.setData(AddonKeys.installedBackup, raw) }
            items = list.map(Self.withExplicitDefaults); unreadable = rest
            write(items ?? [])
        case .unreadable:
            // No se entiende: se guarda aparte y no se escribe encima; la app sigue como si no hubiera lista (con Stremio).
            if vault.data(AddonKeys.installedUnreadable) == nil { vault.setData(AddonKeys.installedUnreadable, raw) }
            readFailed = true
        }
        purgeRemoved()   // si la app se cerró durante «Deshacer», la dirección de lo quitado no se queda
    }

    /// Las opciones de hoy, escritas (T10): «sin opciones» ya no quiere decir «las que traiga la app».
    static func withExplicitDefaults(_ addon: InstalledAddon) -> InstalledAddon {
        var addon = addon
        if case .recommended(let template) = addon.origin, addon.options == nil, AddonCatalog.template(template)?.usesOptions == true { addon.options = AddonOptions() }
        return addon
    }

    /// Ya hay una lista propia (aunque esté vacía): manda ella, no la cuenta de Stremio.
    public var isConfigured: Bool { lock.withLock { items != nil } }
    public var installed: [InstalledAddon] { lock.withLock { items ?? [] } }
    /// Ya se trajeron los de Stremio (una sola vez).
    public var hasImported: Bool { vault.data(AddonKeys.importedFromStremio) != nil }

    private func update(_ change: (inout [InstalledAddon]) -> Void) {
        let saved: [InstalledAddon] = lock.withLock {
            var list = items ?? []
            change(&list)
            items = list
            return list
        }
        write(saved)
    }

    private func write(_ list: [InstalledAddon]) {
        // Lo que no se pudo leer no se pisa: los cambios de esta sesión quedan en memoria.
        guard !readFailed, let data = StoredAddons.encode(list, unreadable: lock.withLock { unreadable }) else { return }
        vault.setData(AddonKeys.installed, data)
    }

    /// Arma la lista con los recomendados (los que vienen encendidos), si aún no hay una.
    public func startWithRecommended(_ templates: [AddonTemplate] = AddonCatalog.recommended) {
        guard !isConfigured else { return }
        update { list in
            for t in templates where !list.contains(where: { $0.origin == .recommended(t.id) }) {
                list.append(Self.withExplicitDefaults(InstalledAddon(id: t.id, name: t.name, resources: t.resources, enabled: t.onByDefault, origin: .recommended(t.id), usesDebrid: t.usesDebrid)))
            }
        }
    }

    /// Agrega un recomendado (al final). Si ya está, no se repite.
    public func add(_ template: AddonTemplate, options: AddonOptions? = nil) {
        update { list in
            guard !list.contains(where: { $0.origin == .recommended(template.id) }) else { return }
            list.append(Self.withExplicitDefaults(InstalledAddon(id: template.id, name: template.name, resources: template.resources, origin: .recommended(template.id),
                                       usesDebrid: template.usesDebrid, options: options)))
        }
    }

    /// Agrega uno pegado (o de un QR): su URL ya normalizada (`…/manifest.json`), el nombre y lo que aporta según su manifiesto.
    /// Si esa URL ya está, no se repite; devuelve su id.
    @discardableResult
    public func add(url: String, name: String, resources: [String], origin: InstalledAddon.Origin = .pasted) -> String {
        if let existing = installed.first(where: { resolvedURL($0) == url }) { return existing.id }
        let id = Self.newID(url)
        vault.setSecret(AddonKeys.addonURL(id), url)
        update { $0.append(InstalledAddon(id: id, name: name, resources: resources, origin: origin, usesDebrid: InstalledAddon.mentionsDebrid(url))) }
        return id
    }

    /// Un id estable y sin la URL adentro (la URL puede llevar claves).
    static func newID(_ url: String) -> String {
        var hash: UInt64 = 1469598103934665603   // FNV-1a: corto y sin dependencias
        for byte in url.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "a" + String(hash, radix: 36)
    }

    /// Quita uno traído de Stremio (o pegado antes). Los que vienen con Orbital no se quitan: solo se apagan (C7). Queda
    /// guardado aparte (con su dirección en el llavero) mientras dura «Deshacer» (`undoWindow`), y su huella para siempre:
    /// «Volver a traer» no lo regresa. Devuelve false si no se puede quitar.
    @discardableResult
    public func remove(_ id: String, now: Date = Date()) -> Bool {
        guard let index = installed.firstIndex(where: { $0.id == id }), !installed[index].isBuiltIn else { return false }
        let entry = installed[index]
        update { $0.removeAll { $0.id == id } }
        var stones = tombstones.filter { $0.entry.id != id }
        stones.append(Tombstone(entry: entry, index: index, removedAt: now, purged: false))
        tombstones = stones
        purgeRemoved(now: now)
        return true
    }

    /// «Deshacer»: vuelve a su lugar con todo (su dirección y sus opciones). false si ya pasó el tiempo o no estaba.
    @discardableResult
    public func undoRemove(_ id: String, now: Date = Date()) -> Bool {
        guard let stone = tombstones.first(where: { $0.entry.id == id }), !stone.purged,
              now.timeIntervalSince(stone.removedAt) <= Self.undoWindow, vault.secret(AddonKeys.addonURL(id)) != nil else { return false }
        update { list in list.insert(stone.entry, at: min(stone.index, list.count)) }
        tombstones = tombstones.filter { $0.entry.id != id }
        return true
    }

    /// Lo que dura «Deshacer» (algo más que el aviso): después se borra su dirección del llavero.
    public static let undoWindow: TimeInterval = 60

    /// Borra del llavero la dirección de los quitados hace más de `undoWindow` (se queda su huella, sin la dirección).
    public func purgeRemoved(now: Date = Date()) {
        var stones = tombstones, changed = false
        for i in stones.indices where !stones[i].purged && now.timeIntervalSince(stones[i].removedAt) > Self.undoWindow {
            vault.setSecret(AddonKeys.addonURL(stones[i].entry.id), nil)
            stones[i].purged = true; stones[i].entry.options = nil; changed = true
        }
        if changed { tombstones = stones }
    }

    /// Los ids de los que quitaste (para no traerlos otra vez de Stremio).
    public var removedIDs: Set<String> { Set(tombstones.map(\.entry.id)) }

    struct Tombstone: Codable, Equatable {
        var entry: InstalledAddon
        var index: Int
        var removedAt: Date
        var purged: Bool
    }

    private var tombstones: [Tombstone] {
        get { vault.data(AddonKeys.removed).flatMap { try? JSONDecoder().decode([Tombstone].self, from: $0) } ?? [] }
        set { vault.setData(AddonKeys.removed, try? JSONEncoder().encode(newValue)) }
    }

    /// Es la última fuente de video prendida: apagarla o quitarla te deja sin versiones (se pregunta antes, C7).
    public func isLastSource(_ id: String) -> Bool {
        let sources = installed.filter { $0.enabled && $0.resources.contains("stream") && resolvedURL($0) != nil }
        return sources.count == 1 && sources[0].id == id
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        update { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].enabled = enabled } }
    }

    public func setOptions(_ id: String, _ options: AddonOptions) {
        update { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].options = options } }
    }

    /// Como `.onMove` de SwiftUI: los de `source` pasan a quedar antes de `destination`.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        update { list in
            let moving = source.sorted().filter { list.indices.contains($0) }.map { list[$0] }
            let before = source.filter { $0 < destination }.count
            for i in source.sorted(by: >) where list.indices.contains(i) { list.remove(at: i) }
            list.insert(contentsOf: moving, at: max(0, min(list.count, destination - before)))
        }
    }

    /// La URL de un complemento: la de un recomendado se arma con tu clave de ahora; la de uno pegado sale del llavero.
    public func resolvedURL(_ addon: InstalledAddon) -> String? {
        switch addon.origin {
        case .recommended(let template): AddonCatalog.template(template)?.manifestURL(token: vault.secret(AddonKeys.realDebridToken), options: addon.options)
        case .pasted, .imported: vault.secret(AddonKeys.addonURL(addon.id))
        }
    }

    /// Las URLs de los encendidos, en tu orden (los que no se pueden armar, p. ej. sin clave, se saltan).
    public func enabledURLs() -> [String] { installed.filter(\.enabled).compactMap(resolvedURL) }

    /// Cambia si cambia la lista o la clave: quien guarda manifiestos en caché lo usa para saber que hay que volver a pedir.
    public func fingerprint() -> String {
        let urls = enabledURLs().joined(separator: "\n")
        return AddonList.newID(urls)
    }

    /// Lo que se trae de Stremio: nombre, URL y lo que aporta.
    public struct Imported: Sendable, Equatable {
        public var name: String, url: String, resources: [String]
        public init(name: String, url: String, resources: [String]) { self.name = name; self.url = url; self.resources = resources }
    }

    /// Trae una vez tus complementos de Stremio (los que no estén ya), en su orden, después de los que ya tengas. La segunda
    /// vez no hace nada (devuelve 0); `again` lo vuelve a hacer («Volver a traer»), sin los que quitaste. Devuelve cuántos agregó.
    @discardableResult
    public func importOnce(_ addons: [Imported], again: Bool = false) -> Int {
        guard again || !hasImported else { return 0 }
        if !isConfigured { update { _ in } }
        var added = 0
        let removed = removedIDs
        for addon in addons where !removed.contains(Self.newID(addon.url)) {   // lo que quitaste no regresa solo
            let before = installed.count
            add(url: addon.url, name: addon.name, resources: addon.resources, origin: .imported)
            if installed.count > before { added += 1 }
        }
        vault.setData(AddonKeys.importedFromStremio, Data("1".utf8))
        return added
    }

    /// Las claves que hay que tapar en lo que se muestra o se anota (tu Real-Debrid).
    /// También las que vienen dentro de un complemento importado o pegado (su Torrentio de Stremio lleva la clave en la URL).
    public func secretsToRedact() -> [String] {
        let imported = installed.filter { !$0.isBuiltIn }.compactMap { vault.secret(AddonKeys.addonURL($0.id)) }.flatMap(AddonSecrets.keys(in:))
        return Array(Set([vault.secret(AddonKeys.realDebridToken)].compactMap { $0 } + imported)).sorted()
    }
}

/// Cómo se guarda la lista: `{"version": 2, "items": [...], "unreadable": [...]}`. Antes era el arreglo solo.
enum StoredAddons {
    static let version = 2
    enum Read { case current([InstalledAddon], [StoredJSON]), legacy([InstalledAddon], [StoredJSON]), unreadable }

    static func read(_ data: Data) -> Read {
        guard let json = try? JSONDecoder().decode(StoredJSON.self, from: data) else { return .unreadable }
        switch json {
        case .array(let entries):
            let (list, rest) = split(entries)
            return .legacy(list, rest)
        case .object(let object):
            guard case .array(let entries)? = object["items"] else { return .unreadable }
            var (list, rest) = split(entries)
            if case .array(let more)? = object["unreadable"] { rest += more }
            return .current(list, rest)
        default: return .unreadable
        }
    }

    /// Cada entrada por su lado: la que no se entiende no se lleva a las demás.
    private static func split(_ entries: [StoredJSON]) -> ([InstalledAddon], [StoredJSON]) {
        var list: [InstalledAddon] = [], rest: [StoredJSON] = []
        for entry in entries {
            if let data = try? JSONEncoder().encode(entry), let addon = try? JSONDecoder().decode(InstalledAddon.self, from: data) { list.append(addon) }
            else { rest.append(entry) }
        }
        return (list, rest)
    }

    static func encode(_ list: [InstalledAddon], unreadable: [StoredJSON]) -> Data? {
        struct Box: Encodable { var version: Int; var items: [InstalledAddon]; var unreadable: [StoredJSON]? }
        return try? JSONEncoder().encode(Box(version: version, items: list, unreadable: unreadable.isEmpty ? nil : unreadable))
    }
}
