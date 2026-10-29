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
    public private(set) var check: Check = .idle { didSet { changed() } }
    /// Lo que se sabe de la clave guardada (nil sin clave).
    public private(set) var status: DebridStatus? { didSet { changed() } }
    public var token = "" { didSet { if oldValue != token { check = .idle; changed() } } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        status = services.debrid.saved
        super.init()
    }

    public var hasToken: Bool { services.debrid.hasToken }
    public var tokenURL: URL { services.debrid.provider.tokenURL }
    public var renewURL: URL { services.debrid.provider.renewURL }
    /// «Continuar» de la guía: la clave guardada sirve (Premium).
    public var ready: Bool { if case .ok = check { return true }; return hasToken && status?.isPremium == true }

    /// Al abrir Ajustes: el estado guardado, o uno nuevo si es de ayer.
    public func load(force: Bool = false) async { status = await services.debrid.status(force: force) }

    /// Comprueba la clave pegada. Si es Premium se guarda y tus complementos recomendados se arman con ella.
    public func verify() async {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        check = .checking
        do {
            let found = try await services.debrid.verify(clean)
            guard clean == token.trimmingCharacters(in: .whitespacesAndNewlines) else { return }   // cambiaste la clave mientras
            guard found.isPremium else { check = .free(found); return }
            await services.debrid.save(token: clean, status: found)
            services.addonList.startWithRecommended()
            await services.resetAccountCaches()
            status = found
            check = .ok(found)
        } catch let error as DebridError {
            check = .failed(error.description)
        } catch { check = .failed(DebridError.unexpected.description) }
    }

    /// «Quitar»: se olvida la clave (los recomendados se quedan sin fuentes hasta que pongas otra).
    public func remove() async {
        await services.debrid.remove()
        await services.resetAccountCaches()
        status = nil; token = ""; check = .idle
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
/// Real-Debrid. Agregar un recomendado, pegar una dirección (o un QR), quitar e importar una vez los de Stremio.
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
        reload()
    }

    public func setEnabled(_ id: String, _ on: Bool) async {
        services.addonList.setEnabled(id, on)
        reload(); await services.resetAccountCaches()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        services.addonList.move(fromOffsets: source, toOffset: destination)
        reload(); await services.resetAccountCaches()
    }

    public func remove(_ id: String) async {
        services.addonList.remove(id)
        reload(); await services.resetAccountCaches()
    }

    public func add(_ template: AddonTemplate) async {
        services.addonList.add(template)
        reload(); await services.resetAccountCaches()
    }

    /// Pega una dirección (también `stremio://`, o lo que trae un QR): se comprueba su manifiesto antes de guardarla.
    @discardableResult
    public func add(address input: String) async -> Bool {
        guard let url = Addons.manifestURL(input), let target = URL(string: url) else {
            error = "Pega la dirección completa del complemento (https://…)."; return false
        }
        working = true
        defer { working = false }
        guard let manifest = (try? await services.http.getJSON(target)).flatMap({ Addons.parseManifest($0, url: url) }) else {
            error = "Ese complemento no responde o no da videos ni fichas."; return false
        }
        services.addonList.add(url: url, name: manifest.name, resources: Set(manifest.rules.keys).union(manifest.catalogs.isEmpty ? [] : ["catalog"]).sorted())
        error = nil
        reload(); await services.resetAccountCaches()
        return true
    }

    /// «Volver a importar de Stremio».
    public func importAgain() async {
        working = true
        defer { working = false }
        do { _ = try await services.importAddonsFromStremio(again: true); error = nil } catch { self.error = "\(error)" }
        reload()
    }

    public func clearError() { error = nil }
    private func reload() { items = services.addonList.installed }
}
