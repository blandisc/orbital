import Foundation
import OrbitalCore

/// Tu cuenta de OpenSubtitles (Ajustes › Cuentas y el paso de la bienvenida): más subtítulos y los de tu copia exacta.
/// La contraseña solo viaja al conectar; se guarda el token, en el llavero.
@MainActor
public final class OpenSubtitlesModel: ObservableModel {
    public private(set) var account: OpenSubtitlesAccount? { didSet { if oldValue != account { changed() } } }
    public private(set) var loading = false { didSet { if oldValue != loading { changed() } } }
    public private(set) var error: String? { didSet { if oldValue != error { changed() } } }
    private let api: OpenSubtitlesAPI?
    private let tv: (@MainActor () -> OrbitalRemote?)

    public init(api: OpenSubtitlesAPI?, tv: @escaping @MainActor () -> OrbitalRemote? = { nil }) {
        self.api = api; self.tv = tv
        super.init()
        Task { await refresh() }
    }

    public convenience init(_ services: Services) {
        self.init(api: services.finder.openSubtitles) { services.orbitalOn && services.orbital.isConfigured ? services.orbital : nil }
    }

    /// ¿Hay una TV a la que pasarle tu cuenta?
    public var hasTV: Bool { tv() != nil }

    /// «Pasar a tu TV»: la misma cuenta, sin volver a escribir la contraseña. Devuelve el motivo si no se pudo.
    public func sendToTV() async -> String? {
        guard let account, let remote = tv() else { return "Primero conecta tu TV" }
        do { try await remote.putOpenSubtitles(account); return nil }
        catch { return "Tu TV no contestó. Intenta de nuevo en un momento." }
    }

    /// ¿Esta versión trae la clave de la app? Sin ella no se ofrece conectar (no serviría de nada).
    public var available: Bool { api?.available ?? false }
    public var connected: Bool { account != nil }

    public func refresh() async { account = await api?.account() }

    /// Devuelve el motivo si no se pudo (en español, para enseñarlo tal cual).
    @discardableResult
    public func connect(username: String, password: String) async -> String? {
        guard let api else { error = OpenSubtitlesError.noAppKey.description; return error }
        loading = true
        defer { loading = false }
        do {
            account = try await api.login(username: username, password: password)
            error = nil
        } catch let e as OpenSubtitlesError { error = e.description }
        catch { self.error = OpenSubtitlesError.offline.description }
        return error
    }

    public func disconnect() {
        account = nil; error = nil
        Task { await api?.logout() }
    }
}
