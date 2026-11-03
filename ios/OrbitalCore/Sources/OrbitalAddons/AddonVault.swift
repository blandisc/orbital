import Foundation

/// Dónde guarda este módulo lo suyo, sin saber si es el Keychain o la memoria: los secretos (tu clave de Real-Debrid, la
/// URL completa de un complemento pegado o importado, que puede llevar claves) y lo demás (la lista, el estado de tu
/// cuenta, los avisos ya programados). La app lo arma con su llavero y sus ajustes; las pruebas, con memoria.
public protocol AddonVault: Sendable {
    func secret(_ key: String) -> String?
    func setSecret(_ key: String, _ value: String?)
    func data(_ key: String) -> Data?
    func setData(_ key: String, _ value: Data?)
    /// Como `setSecret`, pero dice si el llavero lo aceptó (TEC-5).
    func storeSecret(_ key: String, _ value: String?) -> Bool
}

public extension AddonVault {
    func storeSecret(_ key: String, _ value: String?) -> Bool { setSecret(key, value); return true }
}

/// Los nombres con que se guarda cada cosa.
public enum AddonKeys {
    /// Tu clave de Real-Debrid (sale de real-debrid.com/apitoken). Un solo secreto: las URLs de los recomendados se derivan.
    public static let realDebridToken = "realdebrid_token"
    /// CX2-A · la copia de tu clave que comparten tus aparatos Apple (llavero de iCloud, si lo usas): `SharedDebridKey`.
    /// La de arriba es la de este aparato y es la que se usa; esta solo sirve para ofrecerla o preguntar si cambió.
    public static let sharedRealDebridToken = "realdebrid_token.shared"
    /// CX2-A · la copia compartida que este aparato ya vio y decidió («Seguir con la de este iPhone»): no se pregunta otra vez.
    public static let sharedRealDebridSeen = "realdebrid_token.shared.seen"
    /// La URL completa de un complemento pegado o importado (en el llavero: puede llevar tu clave adentro).
    public static func addonURL(_ id: String) -> String { "addon_url.\(id)" }
    static let installed = "addons-installed"
    /// Copia de la lista tal como estaba antes de la primera migración de formato (T10).
    static let installedBackup = "addons-installed.backup-v1"
    /// Copia de una lista que no se pudo leer (no se escribe encima de ella).
    static let installedUnreadable = "addons-installed.unreadable"
    static let importedFromStremio = "addons-imported-from-stremio"
    /// Los que quitaste (su huella; su dirección solo mientras dura «Deshacer»).
    static let removed = "addons-removed"
    static let debridStatus = "debrid-status"
    /// De dónde salió tu clave de Real-Debrid (si se tomó de tu Torrentio importado).
    static let debridKeySource = "debrid-key-source"
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
        var plain = secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: mask) }
        // La clave de un servicio de descarga dentro de una URL se tapa aunque no se sepa cuál es (una importada de Stremio).
        plain = AddonSecrets.keyPattern.stringByReplacingMatches(in: plain, range: NSRange(plain.startIndex..., in: plain), withTemplate: "$1=\(mask)")
        // Comet guarda la clave dentro de un tramo en base64 de la URL: ese tramo también se tapa.
        var out = plain
        for segment in plain.split(separator: "/") where segment.count >= 16 && segment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "=" }) {
            guard let data = Data(base64Encoded: String(segment)), let decoded = String(data: data, encoding: .utf8),
                  secrets.contains(where: decoded.contains) || !AddonSecrets.keys(inJSON: decoded).isEmpty else { continue }
            out = out.replacingOccurrences(of: String(segment), with: mask)
        }
        return out
    }
}

/// Las claves que puede llevar la URL de un complemento (D2): para taparlas y para no escribirlas en disco.
public enum AddonSecrets {
    static let services = "realdebrid|alldebrid|premiumize|debridlink|offcloud|putio|torbox|easydebrid"
    /// `realdebrid=CLAVE` (Torrentio y los que copian su forma), hasta el siguiente «|», «/», «&», «?» o comillas.
    static let keyPattern = try! NSRegularExpression(pattern: "(?i)\\b(\(services))=([^|/&?#\\s\"'<>,;]+)")

    /// Las claves que trae una URL: las de la forma de Torrentio y las de una configuración en base64 (Comet).
    public static func keys(in url: String) -> [String] {
        var found = keyPattern.matches(in: url, range: NSRange(url.startIndex..., in: url)).compactMap { Range($0.range(at: 2), in: url).map { String(url[$0]) } }
        for segment in url.split(separator: "/") where segment.count >= 16 {
            guard let data = Data(base64Encoded: String(segment)), let decoded = String(data: data, encoding: .utf8) else { continue }
            found += keys(inJSON: decoded)
        }
        return found.filter { $0.count >= 6 && $0 != AddonRedaction.mask }
    }

    /// `"apiKey": "…"` y parecidos dentro de un JSON.
    static func keys(inJSON text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)"(apiKey|debridApiKey|token|key)"\s*:\s*"([^"]{6,})""#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 2), in: text).map { String(text[$0]) } }
    }

    /// Una URL que puede llevar una clave: no se escribe tal cual en un archivo (solo en el llavero).
    public static func mayCarrySecret(_ url: String) -> Bool {
        if !keys(in: url).isEmpty || InstalledAddon.mentionsDebrid(url) { return true }
        if url.contains("?") { return true }
        let parts: [Substring] = url.split(separator: "/")
        return parts.dropFirst(2).contains { (part: Substring) in part.count >= 24 }
    }
}
