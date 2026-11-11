import Foundation

/// Almacén de pares clave–valor para ajustes y cachés pequeñas (en la app, `UserDefaults`).
public protocol KeyValueStore: Sendable {
    func data(_ key: String) -> Data?
    func set(_ key: String, data: Data?)
    /// Las claves que empiezan así (para limpiar lo de antes de un tope, `BoundedKeys`); nil si el almacén no sabe listar.
    func keys(prefix: String) -> [String]?
}

public extension KeyValueStore {
    func keys(prefix: String) -> [String]? { nil }
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    public init() {}
    public func data(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ key: String, data: Data?) { lock.withLock { values[key] = data } }
    public func keys(prefix: String) -> [String]? { lock.withLock { values.keys.filter { $0.hasPrefix(prefix) } } }
}

public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    public init(defaults: UserDefaults = .standard, prefix: String = "orbital.") { self.defaults = defaults; self.prefix = prefix }
    public func data(_ key: String) -> Data? { defaults.data(forKey: prefix + key) }
    public func set(_ key: String, data: Data?) { defaults.set(data, forKey: prefix + key) }
    public func keys(prefix p: String) -> [String]? {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix + p) }.map { String($0.dropFirst(prefix.count)) }
    }
}
