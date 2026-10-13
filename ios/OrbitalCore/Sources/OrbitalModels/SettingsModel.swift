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
    private let services: Services
    private var linking: Task<Void, Never>?

    public init(_ services: Services) {
        self.services = services
        settings = services.appSettings
        hasTMDBKey = !(services.secrets.get(SecretKey.tmdbKey) ?? "").isEmpty
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
        if before.traktClientID != settings.traktClientID || before.traktClientSecret != settings.traktClientSecret || before.uiLanguage != settings.uiLanguage || before.region != settings.region {
            services.reconfigure()
            trakt = computeTraktState()
        }
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
                while !Task.isCancelled, await self?.services.now() ?? .distantFuture < code.expiresAt {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard let self, !Task.isCancelled else { return }
                    switch (try? await t.pollDevice(code)) ?? .pending {
                    case .linked: await self.finishLinking(); return
                    case .slow: interval += 5
                    case .expired: await self.setTrakt(.failed("El código caducó. Vuelve a intentarlo.")); return
                    case .denied: await self.setTrakt(.failed("Rechazaste la conexión en Trakt.")); return
                    case .invalid: await self.setTrakt(.failed("Trakt no aceptó el código.")); return
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
