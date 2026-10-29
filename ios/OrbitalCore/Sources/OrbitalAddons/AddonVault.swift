import Foundation

/// Dónde guarda este módulo lo suyo, sin saber si es el Keychain o la memoria: los secretos (tu clave de Real-Debrid, la
/// URL completa de un complemento pegado o importado, que puede llevar claves) y lo demás (la lista, el estado de tu
/// cuenta, los avisos ya programados). La app lo arma con su llavero y sus ajustes; las pruebas, con memoria.
public protocol AddonVault: Sendable {
    func secret(_ key: String) -> String?
    func setSecret(_ key: String, _ value: String?)
    func data(_ key: String) -> Data?
    func setData(_ key: String, _ value: Data?)
}

/// Los nombres con que se guarda cada cosa.
public enum AddonKeys {
    /// Tu clave de Real-Debrid (sale de real-debrid.com/apitoken). Un solo secreto: las URLs de los recomendados se derivan.
    public static let realDebridToken = "realdebrid_token"
    /// La URL completa de un complemento pegado o importado (en el llavero: puede llevar tu clave adentro).
    public static func addonURL(_ id: String) -> String { "addon_url.\(id)" }
    static let installed = "addons-installed"
    static let importedFromStremio = "addons-imported-from-stremio"
    static let debridStatus = "debrid-status"
    static let reminders = "debrid-reminders"
}

/// En memoria (pruebas y modo demostración).
public final class InMemoryAddonVault: AddonVault, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:], values: [String: Data] = [:]
    public init() {}
    public func secret(_ key: String) -> String? { lock.withLock { secrets[key] } }
    public func setSecret(_ key: String, _ value: String?) { lock.withLock { secrets[key] = value } }
    public func data(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func setData(_ key: String, _ value: Data?) { lock.withLock { values[key] = value } }
}

/// Tapa una clave en un texto (bitácoras, errores): «…/realdebrid=ABC123/…» → «…/realdebrid=•••/…».
public enum AddonRedaction {
    public static let mask = "•••"
    public static func redact(_ text: String, secrets: [String]) -> String {
        let secrets = secrets.filter { $0.count >= 6 }
        let plain = secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: mask) }
        // Comet guarda la clave dentro de un tramo en base64 de la URL: ese tramo también se tapa.
        var out = plain
        for segment in plain.split(separator: "/") where segment.count >= 16 && segment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "=" }) {
            guard let data = Data(base64Encoded: String(segment)), let decoded = String(data: data, encoding: .utf8),
                  secrets.contains(where: decoded.contains) else { continue }
            out = out.replacingOccurrences(of: String(segment), with: mask)
        }
        return out
    }
}
