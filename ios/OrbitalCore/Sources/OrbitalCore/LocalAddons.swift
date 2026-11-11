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
    public func storeSecret(_ key: String, _ value: String?) -> Bool { secrets.store(key, value) }
    public func data(_ key: String) -> Data? { kv.data(key) }
    public func setData(_ key: String, _ value: Data?) { kv.set(key, data: value) }
}

public extension RealDebrid {
    /// Real-Debrid por la red de la app (la de verdad, o la fingida de la demostración y las pruebas).
    init(http: HTTPClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(fetch: RealDebrid.fetch(http), clock: clock)
    }

    /// Una petición de Real-Debrid por la red de la app (con su cuerpo: `addMagnet` y `selectFiles` mandan un formulario).
    static func fetch(_ http: HTTPClient) -> DebridFetch {
        { request in
            guard let url = request.url else { throw NetworkError("Dirección inválida") }
            let response = try await http.send(HTTPRequest(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
                                                           body: request.httpBody, timeout: request.timeoutInterval))
            return (response.status, response.data)
        }
    }
}

public extension RealDebridTorrents {
    /// Los torrents de tu Real-Debrid por la red de la app.
    init(http: HTTPClient, gate: RDGate = RDGate()) { self.init(fetch: RealDebrid.fetch(http), gate: gate) }
}

public enum AddonImport {
    /// Los complementos que pegaste en Ajustes › Avanzado, para traerlos una vez a la lista del teléfono. (Antes también los de
    /// tu cuenta de Stremio; esa cuenta ya no se usa desde el 3 nov.)
    public static func addons(own: [String]) -> [AddonList.Imported] {
        var out: [AddonList.Imported] = []
        for url in Addons.cleanURLs(own) where !out.contains(where: { $0.url == url }) {
            out.append(AddonList.Imported(name: URL(string: url)?.host ?? "Complemento", url: url, resources: []))
        }
        return out
    }
}
