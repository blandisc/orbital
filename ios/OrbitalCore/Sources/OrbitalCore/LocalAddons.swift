import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OrbitalAddons

/// El llavero y los ajustes de la app, con la forma que pide `OrbitalAddons` (que no conoce ni a uno ni a otro).
public struct AppAddonVault: AddonVault {
    let secrets: SecretsStore
    let kv: KeyValueStore
    public init(secrets: SecretsStore, kv: KeyValueStore) { self.secrets = secrets; self.kv = kv }
    public func secret(_ key: String) -> String? { secrets.get(key) }
    public func setSecret(_ key: String, _ value: String?) { secrets.set(key, value) }
    public func data(_ key: String) -> Data? { kv.data(key) }
    public func setData(_ key: String, _ value: Data?) { kv.set(key, data: value) }
}

public extension RealDebrid {
    /// Real-Debrid por la red de la app (la de verdad, o la fingida de la demostración y las pruebas).
    init(http: HTTPClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(fetch: { request in
            guard let url = request.url else { throw NetworkError("Dirección inválida") }
            let response = try await http.send(HTTPRequest(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
                                                           timeout: request.timeoutInterval))
            return (response.status, response.data)
        }, clock: clock)
    }
}

public enum StremioImport {
    /// Los complementos de tu cuenta de Stremio (y los que pegaste en Ajustes › Avanzado), para traerlos una vez a la lista
    /// del teléfono. Cinemeta no se trae: la app ya lo usa por su cuenta para las fichas.
    public static func addons(account: [JSON], own: [String]) -> [AddonList.Imported] {
        var out: [AddonList.Imported] = []
        for entry in account {
            guard let url = entry["transportUrl"]?.string, let addon = Addons.parseManifest(entry["manifest"], url: url),
                  !addon.name.lowercased().contains("cinemeta") else { continue }
            out.append(AddonList.Imported(name: addon.name, url: url, resources: addon.rules.keys.sorted()))
        }
        for url in Addons.cleanURLs(own) where !out.contains(where: { $0.url == url }) {
            out.append(AddonList.Imported(name: URL(string: url)?.host ?? "Complemento", url: url, resources: []))
        }
        return out
    }
}
