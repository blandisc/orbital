import Foundation
import OrbitalAddons
#if canImport(Security)
import Security
#endif

/// Dónde se guardan los secretos: la clave de sesión de Stremio, los tokens de Trakt, la clave de TMDB y las
/// URLs de tus complementos (llevan tu clave de Real-Debrid). En la app es el Keychain; en las pruebas, memoria.
public protocol SecretsStore: Sendable {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String?)
    /// Como `set`, pero dice si de verdad se guardó (CX2-A, TEC-5: el llavero puede negarse; entonces nada cambia).
    func store(_ key: String, _ value: String?) -> Bool
}

public extension SecretsStore {
    func store(_ key: String, _ value: String?) -> Bool { set(key, value); return true }
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
    /// K1 · la llave de este aparato para tu Orbital («od1.…»): solo de este aparato (ni iCloud ni copias a otro iPhone).
    public static let orbitalDeviceKey = "orbital_device_key"
    public static let oneDriveTokens = "onedrive_tokens"  // la sesión de OneDrive (Files.Read)
    /// TEC-30 · el `tv_id` de la TV con que se emparejó este aparato: si cambia, «Tu TV es nueva».
    public static let orbitalTVID = "orbital_tv_id"
    /// CX2-A · la copia de tu clave de Real-Debrid que comparten tus aparatos Apple (llavero de iCloud), con quién la puso.
    public static let sharedRealDebrid = AddonKeys.sharedRealDebridToken
    /// CX2-A · la última copia compartida que este aparato ya decidió (para no preguntar dos veces). Solo de este aparato.
    public static let sharedRealDebridSeen = AddonKeys.sharedRealDebridSeen
    /// CX4-A · la invitación de tu iPhone para conectar tu iPad (llavero de iCloud): la TV, su dirección y un código de un uso.
    public static let orbitalInvite = "orbital_invite"
    /// Tu cuenta de OpenSubtitles (usuario, token y cuota; nunca la contraseña): solo de este aparato.
    public static let openSubtitlesAccount = "opensubtitles_account"

    /// TEC-5 · lo ÚNICO que viaja por el llavero de iCloud. Todo lo demás (la llave de este aparato, el token del túnel,
    /// Trakt, OneDrive, las direcciones de complementos, tu clave local de Real-Debrid) se queda en este aparato.
    /// `SecretPolicyTests` falla si esta lista cambia sin que se note.
    public static let synchronizable: Set<String> = [sharedRealDebrid, orbitalInvite]

    public static func policy(_ key: String) -> SecretPolicy { synchronizable.contains(key) ? .shared : .thisDevice }
}

/// Dónde vive cada secreto: solo en este aparato, o también en tus aparatos Apple (llavero de iCloud, si lo usas).
public enum SecretPolicy: Sendable, Equatable { case thisDevice, shared }

public final class InMemorySecrets: SecretsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    /// Para las pruebas: lo que se guarde con `store` falla (el llavero se niega).
    public var refuses: Set<String> = []
    public init() {}
    public func get(_ key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ key: String, _ value: String?) { _ = store(key, value) }
    public func store(_ key: String, _ value: String?) -> Bool {
        lock.withLock { if refuses.contains(key) { return false }; values[key] = value; return true }
    }
}

#if canImport(Security)
/// Las cuatro llamadas al llavero, para probar `KeychainSecrets` sin tocar el de verdad.
public struct KeychainCalls: Sendable {
    public var copy: @Sendable (_ query: [String: Any]) -> (OSStatus, Data?)
    public var add: @Sendable (_ attributes: [String: Any]) -> OSStatus
    public var update: @Sendable (_ query: [String: Any], _ changes: [String: Any]) -> OSStatus
    public var delete: @Sendable (_ query: [String: Any]) -> OSStatus
    public init(copy: @escaping @Sendable ([String: Any]) -> (OSStatus, Data?), add: @escaping @Sendable ([String: Any]) -> OSStatus,
                update: @escaping @Sendable ([String: Any], [String: Any]) -> OSStatus, delete: @escaping @Sendable ([String: Any]) -> OSStatus) {
        self.copy = copy; self.add = add; self.update = update; self.delete = delete
    }

    public static let system = KeychainCalls(
        copy: { query in
            var out: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &out)
            return (status, out as? Data)
        },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        delete: { SecItemDelete($0 as CFDictionary) })
}

/// Keychain de iOS: los secretos no salen del teléfono ni entran en copias de seguridad sin cifrar. Solo los de
/// `SecretKey.synchronizable` viajan por el llavero de iCloud (CX2-A, CX4-A).
public final class KeychainSecrets: SecretsStore, @unchecked Sendable {
    private let service: String
    private let calls: KeychainCalls
    public init(service: String = "com.example.orbital.ios", calls: KeychainCalls = .system) { self.service = service; self.calls = calls }

    /// Para buscar, cambiar o borrar. Lo compartido se busca con `SynchronizableAny` (TEC-5): sin él, la búsqueda solo ve lo
    /// que no se sincroniza y la copia que llega de iCloud sería invisible. Lo de este aparato, como siempre (no sincronizable).
    func query(_ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        if SecretKey.policy(key) == .shared { q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny }
        return q
    }

    /// Lo leído del Keychain, en memoria (también lo que no existe): leerlo en cada acceso desde las vistas trababa la interfaz.
    /// Lo compartido nunca se guarda aquí (TEC-6): puede llegar de iCloud en cualquier momento y se lee cada vez.
    private var cache: [String: String?] = [:]
    private let lock = NSLock()

    public func get(_ key: String) -> String? {
        let shared = SecretKey.policy(key) == .shared
        if !shared, let hit = lock.withLock({ cache[key] }) { return hit }
        let (value, certain) = read(key)
        // «No existe» solo se recuerda si el Keychain lo dijo. Con el iPhone recién prendido y aún sin desbloquear (la app
        // arranca en segundo plano), el Keychain no deja leer: recordar ese nil dejaba «Orbital no conectado» hasta cerrarla.
        if certain, !shared { lock.withLock { cache[key] = .some(value) } }
        return value
    }

    private func read(_ key: String) -> (String?, certain: Bool) {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = calls.copy(q)
        guard status == errSecSuccess, let data else { return (nil, status == errSecItemNotFound) }
        return (String(data: data, encoding: .utf8), true)
    }

    public func set(_ key: String, _ value: String?) { _ = store(key, value) }

    /// Guarda (o borra con nil) y dice si el llavero lo aceptó. Si no, la memoria sigue con lo de antes: nunca dice «guardado»
    /// de algo que al reabrir la app ya no está (TEC-5).
    public func store(_ key: String, _ value: String?) -> Bool {
        let shared = SecretKey.policy(key) == .shared
        guard let value, let data = value.data(using: .utf8) else {
            let status = calls.delete(query(key))   // lo compartido se borra en todos tus aparatos (por eso se pregunta antes, CX3-A)
            guard status == errSecSuccess || status == errSecItemNotFound else { return false }
            if !shared { lock.withLock { cache[key] = .some(nil) } }
            return true
        }
        // Se actualiza en su sitio: si falla el guardado, el valor anterior (p. ej. el token de Trakt, de un solo uso) no se pierde.
        var status = calls.update(query(key), [kSecValueData as String: data])
        if status == errSecItemNotFound {
            var q = query(key)
            q[kSecValueData as String] = data
            q.merge(Self.attributes(for: key)) { _, new in new }
            status = calls.add(q)
        }
        guard status == errSecSuccess else { return false }
        if !shared { lock.withLock { cache[key] = .some(value) } }
        return true
    }

    /// Cómo se guarda cada secreto nuevo, según su política (TEC-5). En este aparato: después del primer desbloqueo y nunca en
    /// el llavero de iCloud (K1: la llave por aparato no debe aparecer en tu otro iPhone ni en uno restaurado de una copia).
    /// Compartido: después del primer desbloqueo y sincronizable (con `…ThisDeviceOnly` el llavero lo rechaza).
    public static func attributes(for key: String) -> [String: Any] {
        switch SecretKey.policy(key) {
        case .thisDevice:
            [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
        case .shared:
            [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock, kSecAttrSynchronizable as String: kCFBooleanTrue as Any]
        }
    }

    /// Lo de este aparato (lo de antes de CX2-A).
    public static var addAttributes: [String: Any] { attributes(for: SecretKey.orbitalDeviceKey) }
}
#endif
