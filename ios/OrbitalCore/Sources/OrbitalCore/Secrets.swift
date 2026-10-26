import Foundation
#if canImport(Security)
import Security
#endif

/// Dónde se guardan los secretos: la clave de sesión de Stremio, los tokens de Trakt, la clave de TMDB y las
/// URLs de tus complementos (llevan tu clave de Real-Debrid). En la app es el Keychain; en las pruebas, memoria.
public protocol SecretsStore: Sendable {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String?)
}

public enum SecretKey {
    public static let stremioAuth = "stremio_auth_key"
    public static let ownAddons = "stremio_addons"
    public static let traktTokens = "trakt_tokens"
    public static let tmdbKey = "tmdb_key"
    public static let traktClientID = "trakt_client_id"
    public static let traktClientSecret = "trakt_client_secret"
    public static let orbitalToken = "orbital_token"     // el token de tu Orbital (el mismo de Alexa): «Ver en la TV»
    public static let orbitalAddress = "orbital_address" // la dirección de tu Orbital, también aquí: sobrevive a borrar la app
    public static let oneDriveTokens = "onedrive_tokens"  // la sesión de OneDrive (Files.Read)
}

public final class InMemorySecrets: SecretsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func get(_ key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ key: String, _ value: String?) { lock.withLock { values[key] = value } }
}

#if canImport(Security)
/// Keychain de iOS: los secretos no salen del teléfono ni entran en copias de seguridad sin cifrar.
public final class KeychainSecrets: SecretsStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.example.orbital.ios") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    /// Lo leído del Keychain, en memoria (también lo que no existe): leerlo en cada acceso desde las vistas trababa la interfaz.
    private var cache: [String: String?] = [:]
    private let lock = NSLock()

    public func get(_ key: String) -> String? {
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let (value, certain) = read(key)
        // «No existe» solo se recuerda si el Keychain lo dijo. Con el iPhone recién prendido y aún sin desbloquear (la app
        // arranca en segundo plano), el Keychain no deja leer: recordar ese nil dejaba «Orbital no conectado» hasta cerrarla.
        if certain { lock.withLock { cache[key] = .some(value) } }
        return value
    }

    private func read(_ key: String) -> (String?, certain: Bool) {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return (nil, status == errSecItemNotFound) }
        return (String(data: data, encoding: .utf8), true)
    }

    public func set(_ key: String, _ value: String?) {
        lock.withLock { cache[key] = .some(value) }
        guard let value, let data = value.data(using: .utf8) else { SecItemDelete(query(key) as CFDictionary); return }
        // Se actualiza en su sitio: si falla el guardado, el valor anterior (p. ej. el token de Trakt, de un solo uso) no se pierde.
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query(key)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
#endif
