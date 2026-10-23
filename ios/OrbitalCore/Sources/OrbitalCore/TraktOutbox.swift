import Foundation

/// Lo que guardaste en Trakt (tu watchlist y tus listas) y Trakt aún no recibió: sin internet, o con la sesión prestada por tu
/// Orbital caducada y la consola apagada. Se guarda aquí (sobrevive al cierre de la app) y se manda en cuanto se pueda; lo
/// último que elegiste para un título en una lista es lo que cuenta. Las listas se recuerdan para poder elegirlas sin conexión.
public final class TraktOutbox: @unchecked Sendable {
    public struct Item: Codable, Equatable, Sendable {
        /// «watchlist» o el id de una de tus listas.
        public var target: String
        public var imdb: String
        public var series: Bool
        public var add: Bool
        public init(target: String, imdb: String, series: Bool, add: Bool) { self.target = target; self.imdb = imdb; self.series = series; self.add = add }
    }
    public static let watchlist = "watchlist"
    static let key = "trakt-outbox", listsKey = "trakt-lists"

    private let kv: KeyValueStore
    private let lock = NSLock()
    private var items: [Item]
    private var flushing = false

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        items = kv.data(Self.key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }

    public var pending: [Item] { lock.withLock { items } }

    /// Lo pendiente de un título en una lista: true si va a entrar, false si va a salir, nil si no hay nada pendiente.
    public func pending(target: String, imdb: String) -> Bool? { lock.withLock { items.last { $0.target == target && $0.imdb == imdb }?.add } }

    public func enqueue(_ item: Item) {
        lock.withLock {
            items.removeAll { $0.target == item.target && $0.imdb == item.imdb }   // lo último que elegiste es lo que cuenta
            items.append(item)
            save()
        }
    }

    /// ¿Vale la pena guardarlo para después? Sin red, sin sesión ahora mismo, o Trakt ocupado/caído: sí. Un título inválido o
    /// una lista que ya no existe: no (reintentarlo no lo arregla).
    public static func retryable(_ error: Error) -> Bool {
        guard let trakt = error as? TraktError else { return true }
        switch trakt {
        case .network, .auth: return true
        case .http(let status): return status == 401 || status == 408 || status == 429 || status >= 500
        case .invalid: return false
        }
    }

    /// Manda lo pendiente, en orden. Se detiene al primer error que se puede reintentar (sigue sin conexión): lo demás espera.
    @discardableResult
    public func flush(_ trakt: Trakt?) async -> Int {
        guard let trakt, trakt.linked else { return 0 }
        guard lock.withLock({ flushing ? false : { flushing = true; return true }() }) else { return 0 }
        defer { lock.withLock { flushing = false } }
        var sent = 0
        for item in pending {
            do {
                if item.target == Self.watchlist { try await trakt.setWatchlist(imdb: item.imdb, series: item.series, add: item.add) }
                else { try await trakt.setListItem(listID: item.target, imdb: item.imdb, series: item.series, add: item.add) }
                sent += 1
            } catch where Self.retryable(error) {
                break
            } catch {}   // no se puede (título inválido, lista borrada): se descarta
            lock.withLock { if let i = items.firstIndex(of: item) { items.remove(at: i); save() } }
        }
        return sent
    }

    // MARK: tus listas, para elegirlas sin conexión
    public var cachedLists: [(id: String, name: String)] {
        let raw = kv.data(Self.listsKey).flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        return raw.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
    public func remember(lists: [(id: String, name: String)]) {
        kv.set(Self.listsKey, data: try? JSONEncoder().encode(lists.map { [$0.id, $0.name] }))
    }

    private func save() { kv.set(Self.key, data: try? JSONEncoder().encode(items)) }
}
