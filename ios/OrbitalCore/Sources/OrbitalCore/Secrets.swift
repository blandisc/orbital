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

    public func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
#endif
