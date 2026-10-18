import Foundation
import OrbitalCore

/// Ajustes › OneDrive: el ID de la aplicación, conectar con un código (microsoft.com/link), elegir la carpeta y revisarla.
@MainActor
public final class OneDriveModel: ObservableModel {
    public enum State: Equatable {
        case off                                  // sin «ID de la aplicación»
        case unlinked
        case linking(code: String, url: String)
        case linked
        case failed(String)
    }

    public private(set) var state: State = .off { didSet { changed() } }
    public private(set) var clientID: String { didSet { changed() } }
    public private(set) var folder: String { didSet { changed() } }
    /// Lo que se reconoció la última vez: cuántos videos con ficha, cuántos sin ella y cuándo.
    public private(set) var index: OneDriveLibrary.Index? { didSet { changed() } }
    public private(set) var scanning = false { didSet { changed() } }
    public private(set) var scanError: String? { didSet { changed() } }

    private let services: Services
    private var linking: Task<Void, Never>?

    public init(_ services: Services) {
        self.services = services
        clientID = services.appSettings.oneDriveClientID
        folder = services.appSettings.oneDriveFolder
        index = services.oneDriveLibrary.saved
        super.init()
        state = computed()
    }

    private func computed() -> State {
        guard services.oneDrive.configured else { return .off }
        return services.oneDrive.linked ? .linked : .unlinked
    }

    public var movies: Int { index?.entries.filter { $0.kind == "movie" }.count ?? 0 }
    public var episodes: Int { index?.entries.filter { $0.kind == "series" }.count ?? 0 }

    public func setClientID(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        services.settings.update { $0.oneDriveClientID = clean }
        clientID = clean
        if case .linking = state { return }
        state = computed()
    }

    /// Conecta con el código de dispositivo: se muestra un código y se espera a que lo escribas en microsoft.com/link.
    public func link() async {
        linking?.cancel()
        let drive = services.oneDrive
        do {
            let code = try await drive.deviceCode()
            state = .linking(code: code.userCode, url: code.verificationURL)
            let task = Task { [weak self] in
                var interval = max(code.interval, 1)
                while !Task.isCancelled, (self?.services.now() ?? .distantFuture) < code.expiresAt {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard let self, !Task.isCancelled else { return }
                    switch (try? await drive.pollDevice(code)) ?? .pending {
                    case .linked: self.state = .linked; if !self.folder.isEmpty { await self.rescan() }; return
                    case .slow: interval += 5
                    case .expired: self.state = .failed("El código caducó. Vuelve a intentarlo."); return
                    case .denied: self.state = .failed("Rechazaste la conexión en Microsoft."); return
                    case .invalid: self.state = .failed("Microsoft no aceptó el código."); return
                    case .pending: break
                    }
                }
                if !Task.isCancelled { self?.state = .failed("El código caducó. Vuelve a intentarlo.") }
            }
            linking = task
            await task.value
        } catch { state = .failed("\(error)") }
    }

    public func cancelLinking() { linking?.cancel(); state = computed() }

    public func unlink() async {
        services.oneDrive.unlink()
        services.oneDriveLibrary.forget()
        await services.finder.forget()
        index = nil
        state = computed()
    }

    /// Las subcarpetas de una carpeta (para elegir dónde están tus películas).
    public func folders(_ path: String) async throws -> [OneDriveFolder] { try await services.oneDrive.folders(path) }

    public func choose(_ raw: String) async {
        // Sin «..» ni «.»: solo una ruta dentro de tu OneDrive.
        let path = raw.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }.joined(separator: "/")
        guard !path.isEmpty else { return }
        services.settings.update { $0.oneDriveFolder = path }
        folder = path
        services.oneDriveLibrary.forget()
        index = nil
        await rescan()
    }

    /// Vuelve a revisar la carpeta (lo nuevo que subiste sale como fuente).
    public func rescan() async {
        guard !folder.isEmpty, services.oneDrive.linked else { return }
        scanning = true; scanError = nil
        defer { scanning = false }
        do { index = try await services.oneDriveLibrary.scan(); await services.finder.forget() }
        catch let error as OneDriveError {
            scanError = error.description
            if case .auth = error { state = computed() }
        } catch { scanError = "\(error)" }
    }
}
