import Foundation
import OrbitalCore

/// Cuenta de Stremio (el eje de todo) y tus complementos propios.
@MainActor
public final class SessionModel: ObservableModel {
    public enum State: Equatable { case signedOut, signingIn, signedIn, failed(String) }
    public private(set) var state: State { didSet { changed() } }
    public private(set) var addons: [Addon] = [] { didSet { changed() } }
    public private(set) var addonError: String? { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        state = services.isSignedIn ? .signedIn : .signedOut
        super.init()
    }

    public func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { return state = .failed("Escribe tu correo y tu contraseña de Stremio.") }
        state = .signingIn
        do {
            let key = try await services.stremio.login(email: email, password: password)
            services.secrets.set(SecretKey.stremioAuth, key)   // la contraseña no se guarda: solo la clave de sesión
            await services.resetAccountCaches()
            state = .signedIn
            _ = await services.watch.flushPending()
        } catch let error as StremioError {
            state = .failed(error.description)
        } catch { state = .failed("\(error)") }
    }

    public func signOut() async {
        services.secrets.set(SecretKey.stremioAuth, nil)
        services.clearAccountData()
        await services.resetAccountCaches()
        addons = []
        state = .signedOut
    }

    // MARK: complementos
    public var ownAddonURLs: [String] { (services.secrets.get(SecretKey.ownAddons) ?? "").split(separator: "\n").map(String.init) }

    public func loadAddons() async {
        do { addons = try await services.registry.addons(); addonError = nil } catch { addonError = "\(error)" }
    }

    /// Agrega un complemento tuyo pegando su URL (también acepta `stremio://`). Se comprueba su manifiesto antes de guardarlo.
    public func addAddon(_ input: String) async {
        guard let url = Addons.manifestURL(input), let target = URL(string: url) else { return addonError = "Pega la dirección completa del complemento (https://…)." }
        guard (try? await services.http.getJSON(target)).flatMap({ Addons.parseManifest($0, url: url) }) != nil else {
            return addonError = "Ese complemento no responde o no da fuentes ni fichas."
        }
        var urls = ownAddonURLs
        if !urls.contains(url) { urls.append(url) }
        services.secrets.set(SecretKey.ownAddons, urls.joined(separator: "\n"))  // su URL lleva tu clave de Real-Debrid: al Keychain
        await services.resetAccountCaches()
        await loadAddons()
        addonError = nil
    }

    public func removeAddon(url: String) async {
        services.secrets.set(SecretKey.ownAddons, ownAddonURLs.filter { $0 != url }.joined(separator: "\n"))
        await services.resetAccountCaches()
        await loadAddons()
    }
}
