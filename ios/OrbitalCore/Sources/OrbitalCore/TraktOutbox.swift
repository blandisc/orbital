import Foundation

/// Lo que guardaste en Trakt (tu watchlist, tus favoritos, tus listas, tus calificaciones y las series que dejaste) y Trakt aún no recibió: sin internet, o con la sesión prestada por tu
/// Orbital caducada y la consola apagada. Se guarda aquí (sobrevive al cierre de la app) y se manda en cuanto se pueda; lo
/// último que elegiste para un título en una lista es lo que cuenta. Las listas se recuerdan para poder elegirlas sin conexión.
public final class TraktOutbox: @unchecked Sendable {
    public struct Item: Codable, Equatable, Sendable {
        /// «watchlist», «favorites» o el id de una de tus listas.
        public var target: String
        public var imdb: String
        public var series: Bool
        public var add: Bool
        /// Solo en `ratings`: el 1…10 que diste (nil con `add == false`: quitar tu calificación).
        public var rating: Int?
        /// Solo en `hidden`: las secciones de Trakt donde se esconde o se vuelve a mostrar la serie.
        public var sections: [String]?
        /// Solo en `notes`: tu nota (vacía: borrarla).
        public var note: String?
        public init(target: String, imdb: String, series: Bool, add: Bool, rating: Int? = nil, sections: [String]? = nil, note: String? = nil) {
            self.target = target; self.imdb = imdb; self.series = series; self.add = add; self.rating = rating; self.sections = sections; self.note = note
        }
        /// Tu nota privada (G6, solo con Trakt VIP); vacía la borra.
        public static func note(imdb: String, series: Bool, _ text: String) -> Item {
            Item(target: TraktOutbox.notes, imdb: imdb, series: series, add: !text.isEmpty, note: text)
        }
        /// Esconder una serie («La dejé») o volver a mostrarla, en esas secciones de Trakt.
        public static func hidden(imdb: String, _ hidden: Bool, sections: [String]) -> Item {
            Item(target: TraktOutbox.hidden, imdb: imdb, series: true, add: hidden, sections: sections)
        }
        /// Calificar (o, con nil, quitar tu calificación).
        public static func rating(imdb: String, series: Bool, _ value: Int?) -> Item {
            Item(target: TraktOutbox.ratings, imdb: imdb, series: series, add: value != nil, rating: value)
        }
    }
    public static let watchlist = "watchlist", favorites = "favorites", ratings = "ratings", hidden = "hidden", notes = "notes"
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

    /// Las calificaciones que aún no llegan a Trakt: IMDb → 1…10, o nil si la quitaste.
    public var pendingRatings: [String: Int?] {
        lock.withLock { Dictionary(items.filter { $0.target == Self.ratings }.map { ($0.imdb, $0.rating) }, uniquingKeysWith: { $1 }) }
    }

    /// Tus notas que aún no llegan a Trakt: IMDb → texto ("" si la borraste).
    public var pendingNotes: [String: String] {
        lock.withLock { Dictionary(items.filter { $0.target == Self.notes }.map { ($0.imdb, $0.note ?? "") }, uniquingKeysWith: { $1 }) }
    }

    /// Las series que escondiste o mostraste y Trakt aún no sabe: IMDb → escondida. Lo que diga Trakt al recargar no las pisa.
    public var pendingHidden: [String: Bool] {
        lock.withLock { Dictionary(items.filter { $0.target == Self.hidden }.map { ($0.imdb, $0.add) }, uniquingKeysWith: { $1 }) }
    }

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
        var queue = pending[...]
        while let item = queue.first {
            // Varios seguidos a la misma lista (o a Mi lista), todos para poner o todos para quitar: un solo envío (G3-A).
            if item.target != Self.favorites, item.target != Self.ratings, item.target != Self.hidden, item.target != Self.notes {
                let run = queue.prefix { $0.target == item.target && $0.add == item.add }
                if run.count > 1 {
                    do {
                        try await trakt.setItems(target: item.target, run.map { ($0.imdb, $0.series) }, add: item.add)
                        sent += run.count
                    } catch where Self.retryable(error) {
                        break
                    } catch {}   // no se puede (lista borrada): se descartan
                    let done = Array(run)
                    lock.withLock { for d in done { if let i = items.firstIndex(of: d) { items.remove(at: i) } }; save() }
                    queue = queue.dropFirst(run.count)
                    continue
                }
            }
            queue = queue.dropFirst()
            do {
                if item.target == Self.watchlist { try await trakt.setWatchlist(imdb: item.imdb, series: item.series, add: item.add) }
                else if item.target == Self.favorites { try await trakt.setFavorite(imdb: item.imdb, series: item.series, add: item.add) }
                else if item.target == Self.ratings { try await trakt.setRating(imdb: item.imdb, series: item.series, rating: item.add ? item.rating : nil) }
                else if item.target == Self.notes {
                    let existing = try await trakt.myNotes()[item.imdb]?.id
                    try await trakt.setNote(imdb: item.imdb, series: item.series, text: item.note ?? "", existing: existing)
                }
                else if item.target == Self.hidden { try await trakt.setHidden(imdb: item.imdb, hidden: item.add, sections: item.sections ?? Trakt.hiddenSections) }
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
