import Foundation

/// Lo que guardaste en Trakt (tu watchlist, tus favoritos, tus listas, tus calificaciones, tus notas y las series que dejaste) y
/// Trakt aún no recibió: sin internet o sin sesión ahora. Vive en la cola única de Trakt (`TraktQueue`, F4: el mismo archivo
/// que lo visto) y se manda en cuanto se pueda; lo último que elegiste para un título en una lista es lo que cuenta. Las listas
/// se recuerdan para poder elegirlas sin conexión.
public final class TraktOutbox: Sendable {
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
        /// Desde cuándo espera (segundos de 1970): pasado `TraktQueue.expiry` sin poder mandarse, vence. nil: de antes de la cola
        /// única (cuenta desde que se migró).
        public var queuedAt: Double?
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
    /// Lo que se manda uno por uno (no se junta en un solo envío por lista).
    static let singles: Set<String> = [favorites, ratings, hidden, notes]
    /// Donde vivía antes (UserDefaults): se migra una vez a la cola única.
    static let legacyKey = "trakt-outbox", listsKey = "trakt-lists"

    private let kv: KeyValueStore
    /// La cola única (lo visto y esto, en el mismo archivo y vaciados por el mismo motor).
    public let queue: TraktQueue
    private var store: PendingStore { queue.store }
    private let clock: @Sendable () -> Date

    public init(queue: TraktQueue, kv: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.queue = queue; self.kv = kv; self.clock = clock
        migrate()
    }

    /// Lo que esperaba en UserDefaults (antes de la cola única) pasa al archivo, sin perder nada y sin pisar lo que ya esté
    /// ahí; luego se borra de UserDefaults, SOLO si el archivo quedó escrito (si no, se intenta otra vez la próxima vez que
    /// abras la app). Si se vuelve a llamar, no duplica.
    private func migrate() {
        guard let data = kv.data(Self.legacyKey) else { return }
        let old = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
        let now = clock().timeIntervalSince1970
        let saved = store.commit { work in
            for var item in old where !work.outbox.contains(where: { $0.target == item.target && $0.imdb == item.imdb }) {
                item.queuedAt = item.queuedAt ?? now
                work.outbox.append(item)
            }
        }
        if saved { kv.set(Self.legacyKey, data: nil) }
        else { Log.storage.error("La cola de Trakt no se pudo guardar en el archivo: lo de antes se queda en los ajustes hasta poder") }
    }

    public var pending: [Item] { store.load().outbox }

    /// Lo pendiente de un título en una lista: true si va a entrar, false si va a salir, nil si no hay nada pendiente.
    public func pending(target: String, imdb: String) -> Bool? { pending.last { $0.target == target && $0.imdb == imdb }?.add }

    /// Las calificaciones que aún no llegan a Trakt: IMDb → 1…10, o nil si la quitaste.
    public var pendingRatings: [String: Int?] {
        Dictionary(pending.filter { $0.target == Self.ratings }.map { ($0.imdb, $0.rating) }, uniquingKeysWith: { $1 })
    }

    /// Tus notas que aún no llegan a Trakt: IMDb → texto ("" si la borraste).
    public var pendingNotes: [String: String] {
        Dictionary(pending.filter { $0.target == Self.notes }.map { ($0.imdb, $0.note ?? "") }, uniquingKeysWith: { $1 })
    }

    /// Las series que escondiste o mostraste y Trakt aún no sabe: IMDb → escondida. Lo que diga Trakt al recargar no las pisa.
    public var pendingHidden: [String: Bool] {
        Dictionary(pending.filter { $0.target == Self.hidden }.map { ($0.imdb, $0.add) }, uniquingKeysWith: { $1 })
    }

    /// Lo que Trakt no aceptó o venció (la bitácora de la cola única).
    public var discards: [TraktDiscard] { queue.discards }

    public func enqueue(_ item: Item) {
        var item = item
        item.queuedAt = item.queuedAt ?? clock().timeIntervalSince1970
        store.update { work in
            work.outbox.removeAll { $0.target == item.target && $0.imdb == item.imdb }   // lo último que elegiste es lo que cuenta
            work.outbox.append(item)
        }
    }

    /// ¿Vale la pena guardarlo para después? La misma política de toda la cola (`TraktQueue.retry`).
    public static func retryable(_ error: Error) -> Bool { TraktQueue.retry(error) }

    /// Manda lo pendiente (de esto y de lo visto: es la misma cola). Devuelve cuántos de tus listas, calificaciones y notas salieron.
    @discardableResult
    public func flush(_ trakt: Trakt?) async -> Int {
        let before = await queue.outboxSent
        await queue.flush(trakt)
        return await queue.outboxSent - before
    }

    /// Un envío de la cola a Trakt.
    static func send(_ item: Item, _ trakt: Trakt) async throws {
        if item.target == watchlist { try await trakt.setWatchlist(imdb: item.imdb, series: item.series, add: item.add) }
        else if item.target == favorites { try await trakt.setFavorite(imdb: item.imdb, series: item.series, add: item.add) }
        else if item.target == ratings { try await trakt.setRating(imdb: item.imdb, series: item.series, rating: item.add ? item.rating : nil) }
        else if item.target == notes {
            let existing = try await trakt.myNotes()[item.imdb]?.id
            try await trakt.setNote(imdb: item.imdb, series: item.series, text: item.note ?? "", existing: existing)
        }
        else if item.target == hidden { try await trakt.setHidden(imdb: item.imdb, hidden: item.add, sections: item.sections ?? Trakt.hiddenSections) }
        else { try await trakt.setListItem(listID: item.target, imdb: item.imdb, series: item.series, add: item.add) }
    }

    /// Cómo se dice el destino en la bitácora.
    static func label(_ target: String) -> String {
        switch target {
        case watchlist: "Mi lista"
        case favorites: "Favoritos"
        case ratings: "Calificación"
        case hidden: "Series que dejaste"
        case notes: "Nota"
        default: "Lista \(target)"
        }
    }

    // MARK: tus listas, para elegirlas sin conexión
    public var cachedLists: [(id: String, name: String)] {
        let raw = kv.data(Self.listsKey).flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        return raw.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
    public func remember(lists: [(id: String, name: String)]) {
        kv.set(Self.listsKey, data: try? JSONEncoder().encode(lists.map { [$0.id, $0.name] }))
    }
}
