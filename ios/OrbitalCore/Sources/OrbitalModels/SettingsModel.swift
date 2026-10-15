import Foundation
import OrbitalCore

@MainActor
public final class SettingsModel: ObservableModel {
    public enum TraktState: Equatable {
        case off                                   // sin aplicación de Trakt configurada
        case unlinked
        case linking(code: String, url: String)
        case linked(String)
        case failed(String)
    }

    public private(set) var settings: AppSettings { didSet { changed() } }
    public private(set) var trakt: TraktState { didSet { changed() } }
    public private(set) var hasTMDBKey: Bool { didSet { changed() } }
    public private(set) var hasOrbitalToken: Bool { didSet { changed() } }
    /// Resultado de «Probar conexión» con tu Orbital: nil sin probar, "" bien, o el problema.
    public private(set) var orbitalCheck: String? { didSet { changed() } }
    public private(set) var checkingOrbital = false { didSet { changed() } }
    private let services: Services
    private var linking: Task<Void, Never>?

    public init(_ services: Services) {
        self.services = services
        settings = services.appSettings
        hasTMDBKey = !(services.secrets.get(SecretKey.tmdbKey) ?? "").isEmpty
        hasOrbitalToken = !(services.secrets.get(SecretKey.orbitalToken) ?? "").isEmpty
        trakt = .off
        super.init()
        trakt = computeTraktState()
    }

    private func computeTraktState() -> TraktState {
        guard let t = services.trakt else { return .off }
        return t.linked ? .linked("") : .unlinked
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        let before = settings
        services.settings.update(change)
        settings = services.appSettings
        if before.traktClientID != settings.traktClientID || before.uiLanguage != settings.uiLanguage || before.region != settings.region {
            services.reconfigure()
            trakt = computeTraktState()
        }
    }

    /// El secreto de la aplicación de Trakt va al Keychain (no a los ajustes).
    public func setTraktSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        services.secrets.set(SecretKey.traktClientSecret, trimmed.isEmpty ? nil : trimmed)
        services.reconfigure()
        trakt = computeTraktState()
    }

    public func setOrbitalToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        services.secrets.set(SecretKey.orbitalToken, trimmed.isEmpty ? nil : trimmed)
        hasOrbitalToken = !trimmed.isEmpty
        orbitalCheck = nil
    }

    /// «Probar conexión»: ¿contesta tu Orbital y acepta el token?
    public func checkOrbital() async {
        checkingOrbital = true
        defer { checkingOrbital = false }
        do { try await services.orbital.check(); orbitalCheck = ""; await importFromOrbital() }
        catch { orbitalCheck = (error as? OrbitalRemote.Failure)?.description ?? "\(error)" }
    }

    /// Lo que se trajo de tu Orbital la última vez («TMDB y Trakt»), para decirlo en Ajustes.
    public private(set) var importedFromOrbital: [String] = [] { didSet { changed() } }

    /// Trae de tu Orbital la clave de TMDB, la aplicación y la sesión de Trakt y el país, sin pisar lo que ya escribiste aquí.
    public func importFromOrbital() async {
        guard let got = try? await services.connectOrbital() else { return }
        importedFromOrbital = got
        settings = services.appSettings
        hasTMDBKey = !(services.secrets.get(SecretKey.tmdbKey) ?? "").isEmpty
        trakt = computeTraktState()
    }

    public func setTMDBKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        services.secrets.set(SecretKey.tmdbKey, trimmed.isEmpty ? nil : trimmed)
        hasTMDBKey = !trimmed.isEmpty
        services.reconfigure()
    }

    public func loadTraktName() async {
        guard let t = services.trakt, t.linked else { return }
        if let name = try? await t.username() { trakt = .linked(name) }
    }

    /// Conecta Trakt con el código de dispositivo: se muestra un código y se espera a que lo escribas en trakt.tv/activate.
    public func linkTrakt() async {
        guard let t = services.trakt else { return trakt = .off }
        linking?.cancel()
        do {
            let code = try await t.deviceCode()
            trakt = .linking(code: code.userCode, url: code.verificationURL.replacingOccurrences(of: "https://", with: ""))
            let task = Task { [weak self] in
                var interval = max(code.interval, 1)
                while !Task.isCancelled, (self?.services.now() ?? .distantFuture) < code.expiresAt {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard let self, !Task.isCancelled else { return }
                    switch (try? await t.pollDevice(code)) ?? .pending {
                    case .linked: await self.finishLinking(); return
                    case .slow: interval += 5
                    case .expired: self.setTrakt(.failed("El código caducó. Vuelve a intentarlo.")); return
                    case .denied: self.setTrakt(.failed("Rechazaste la conexión en Trakt.")); return
                    case .invalid: self.setTrakt(.failed("Trakt no aceptó el código.")); return
                    case .pending: break
                    }
                }
            }
            linking = task
            await task.value
        } catch { trakt = .failed("\(error)") }
    }

    private func setTrakt(_ state: TraktState) { trakt = state }
    private func finishLinking() async {
        services.reconfigure()
        await services.forYou.clearCache()
        trakt = .linked("")
        await loadTraktName()
    }

    public func cancelLinking() { linking?.cancel(); trakt = computeTraktState() }

    public func unlinkTrakt() async {
        await services.trakt?.unlink()
        await services.forYou.clearCache()
        services.reconfigure()
        trakt = computeTraktState()
    }
}
