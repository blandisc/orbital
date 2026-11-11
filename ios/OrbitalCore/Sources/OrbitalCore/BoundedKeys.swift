import Foundation

/// Claves de un mismo tipo en un almacén de claves (UserDefaults) con tope (F10, 10 nov 2026): las marcas de IntroDB y los
/// sustos se guardaban una clave por video, para siempre. Un índice (`<prefijo>.index`) lleva el orden; al pasar de `limit`
/// se borran las más viejas. Lo guardado antes de que existiera el índice no se cuenta (no se puede listar UserDefaults).
public struct BoundedKeys: Sendable {
    let store: KeyValueStore
    let index: String
    let limit: Int
    private static let lock = NSLock()   // leer, cambiar y escribir el índice, de uno en uno

    public init(store: KeyValueStore, prefix: String, limit: Int) {
        self.store = store; self.index = "\(prefix).index"; self.limit = limit
    }

    public func set(_ key: String, data: Data) {
        Self.lock.withLock {
            store.set(key, data: data)
            var keys = store.data(index).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            keys.removeAll { $0 == key }
            keys.append(key)
            while keys.count > limit { store.set(keys.removeFirst(), data: nil) }
            store.set(index, data: try? JSONEncoder().encode(keys))
        }
    }
}
