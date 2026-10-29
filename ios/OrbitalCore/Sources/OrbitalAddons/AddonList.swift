import Foundation

/// Tus complementos, en el teléfono y en tu orden (cuál se pregunta primero): prender y apagar cada uno, ordenarlos, agregar
/// un recomendado o uno pegado, quitar, e importar una vez los de Stremio (no se escribe de vuelta). Mientras no la armes
/// (`isConfigured` es false), la app sigue con la lista de tu cuenta de Stremio, como antes.
public final class AddonList: @unchecked Sendable {
    private let vault: AddonVault
    private let lock = NSLock()
    private var items: [InstalledAddon]?

    public init(vault: AddonVault) {
        self.vault = vault
        items = vault.data(AddonKeys.installed).flatMap { try? JSONDecoder().decode([InstalledAddon].self, from: $0) }
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
        vault.setData(AddonKeys.installed, try? JSONEncoder().encode(saved))
    }

    /// Arma la lista con los recomendados (los que vienen encendidos), si aún no hay una.
    public func startWithRecommended(_ templates: [AddonTemplate] = AddonCatalog.recommended) {
        guard !isConfigured else { return }
        update { list in
            for t in templates where !list.contains(where: { $0.origin == .recommended(t.id) }) {
                list.append(InstalledAddon(id: t.id, name: t.name, resources: t.resources, enabled: t.onByDefault, origin: .recommended(t.id), usesDebrid: t.usesDebrid))
            }
        }
    }

    /// Agrega un recomendado (al final). Si ya está, no se repite.
    public func add(_ template: AddonTemplate, options: AddonOptions? = nil) {
        update { list in
            guard !list.contains(where: { $0.origin == .recommended(template.id) }) else { return }
            list.append(InstalledAddon(id: template.id, name: template.name, resources: template.resources, origin: .recommended(template.id),
                                       usesDebrid: template.usesDebrid, options: options))
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

    public func remove(_ id: String) {
        update { $0.removeAll { $0.id == id } }
        vault.setSecret(AddonKeys.addonURL(id), nil)
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
    /// vez no hace nada (devuelve 0); `again` lo vuelve a hacer (un botón «Volver a importar»). Devuelve cuántos agregó.
    @discardableResult
    public func importOnce(_ addons: [Imported], again: Bool = false) -> Int {
        guard again || !hasImported else { return 0 }
        if !isConfigured { update { _ in } }
        var added = 0
        for addon in addons {
            let before = installed.count
            add(url: addon.url, name: addon.name, resources: addon.resources, origin: .imported)
            if installed.count > before { added += 1 }
        }
        vault.setData(AddonKeys.importedFromStremio, Data("1".utf8))
        return added
    }

    /// Las claves que hay que tapar en lo que se muestra o se anota (tu Real-Debrid).
    public func secretsToRedact() -> [String] { [vault.secret(AddonKeys.realDebridToken)].compactMap { $0 } }
}
