import Foundation
import OrbitalCore

/// Tus complementos propios (los que pegaste por su dirección).
@MainActor
public final class SessionModel: ObservableModel {
    public private(set) var addons: [Addon] = [] { didSet { changed() } }
    public private(set) var addonError: String? { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
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
            return addonError = "Ese complemento no responde o no da videos ni fichas."
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
