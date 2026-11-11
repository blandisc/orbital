import Foundation

/// Claves de un mismo tipo en un almacén de claves (UserDefaults) con tope (F10, 10 nov 2026): las marcas de IntroDB y los
/// sustos se guardaban una clave por video, para siempre. Un índice (`<prefijo>.index`) lleva el orden; al pasar de `limit`
/// se borran las más viejas.
///
/// Lo guardado antes de que existiera el índice (revisión del 11 nov 2026) ya no se queda para siempre: la primera vez que se
/// arma el índice se buscan esas claves en el almacén (`KeyValueStore.keys(prefix:)`, en UserDefaults con
/// `dictionaryRepresentation()`) y entran al índice como las más viejas, así que el tope también las alcanza.
public struct BoundedKeys: Sendable {
    let store: KeyValueStore
    let prefix: String
    let index: String
    let limit: Int
    private static let lock = NSLock()   // leer, cambiar y escribir el índice, de uno en uno

    public init(store: KeyValueStore, prefix: String, limit: Int) {
        self.store = store; self.prefix = prefix; self.index = "\(prefix).index"; self.limit = limit
    }

    public func set(_ key: String, data: Data) {
        Self.lock.withLock {
            store.set(key, data: data)
            var keys = store.data(index).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? older(than: key)
            keys.removeAll { $0 == key }
            keys.append(key)
            while keys.count > limit { store.set(keys.removeFirst(), data: nil) }
            store.set(index, data: try? JSONEncoder().encode(keys))
        }
    }

    /// Sin índice todavía: lo de este tipo que ya estaba guardado (sin orden conocido: por nombre), antes de lo nuevo.
    private func older(than key: String) -> [String] {
        (store.keys(prefix: prefix + ".") ?? []).filter { $0 != index && $0 != key }.sorted()
    }
}
