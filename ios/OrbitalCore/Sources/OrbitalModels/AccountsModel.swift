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
    /// La clave se tomó de tu Torrentio importado de Stremio (no la pegaste): se dice en Ajustes.
    public var keyCameFromImport: Bool { services.debrid.keyCameFromImport }
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
    private func reload() { items = services.addonList.installed }
}
