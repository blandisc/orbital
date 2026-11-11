import Foundation

/// Lo que espera para subirse a Trakt cuando vuelva la red: vistos, desmarcados, tu avance, lo que quitaste de «Seguir
/// viendo» y, desde la cola única (F4), tus listas, calificaciones y notas. (La copia a Stremio, `progress`, se fue en F8: un
/// archivo de antes que la traiga se lee igual y la ignora.) Lo del teléfono ya quedó guardado: esto solo es el viaje. Lo
/// descartado queda en `discards`.
public struct PendingWork: Sendable, Equatable, Codable {
    public var traktWatched: [TraktWatched] = []
    /// «Marcar como no vista» que aún no llega a Trakt (y que una sincronización no debe regresar).
    public var traktUnwatched: [TraktTarget] = []
    /// Tu avance que no llegó a Trakt: al volver la red se manda solo si Trakt no tiene uno más nuevo.
    public var traktProgress: [ProgressEvent] = []
    /// Lo que quitaste de «Seguir viendo» (id del título y cuándo): se borra de Trakt lo que estaba a medias hasta esa hora.
    public var playbackRemovals: [TraktWatched] = []
    /// Vistas que borraste (id en tu historial de Trakt) y aún no llegan (gestor ola 3).
    public var traktViewingRemovals: [Int] = []
    /// «La vi otra vez» o una fecha cambiada: se suben aunque haya otra vista cerca (las pediste tú).
    public var traktRewatched: [TraktWatched] = []
    /// Tus listas, Mi lista, favoritos, calificaciones, notas y series escondidas (antes `TraktOutbox` en UserDefaults).
    public var outbox: [TraktOutbox.Item] = []
    /// Lo que Trakt no aceptó o venció: la bitácora que la app puede enseñar (los más nuevos al final, con tope).
    public var discards: [TraktDiscard] = []
    /// Elementos del archivo que no se entendieron (uno mal formado no tumba la cola: los demás siguen). No se escriben de
    /// vuelta: `FilePendingStore` los aparta junto al archivo.
    public var rejected: [JSON] = []
    public init() {}
    public struct TraktWatched: Sendable, Equatable, Codable {
        public var target: TraktTarget
        public var at: Double
        /// Una fecha cambiada: el id de la vista vieja, que se borra solo cuando la nueva ya llegó (si Trakt la rechaza, la
        /// vieja se queda: nunca se pierde la vista).
        public var replaces: Int?
        /// Desde cuándo espera en la cola (no es `at`: una vista puede ser de hace años). La cola lo anota la primera vez que lo
        /// intenta; pasado `TraktQueue.expiry` sin poder mandarse, vence.
        public var queuedAt: Double?
        public init(target: TraktTarget, at: Double, replaces: Int? = nil) { self.target = target; self.at = at; self.replaces = replaces }
    }
    /// Las vistas de Trakt que ya no se enseñan: las borradas y las que una fecha cambiada está reemplazando.
    public var goneViewings: Set<Int> { Set(traktViewingRemovals + traktRewatched.compactMap(\.replaces)) }
    /// Nada que mandar (la bitácora de descartes no cuenta: no se manda).
    public var isEmpty: Bool { !hasTraktWork }
    /// Algo espera para Trakt.
    public var hasTraktWork: Bool {
        !(traktWatched.isEmpty && traktUnwatched.isEmpty && traktProgress.isEmpty && playbackRemovals.isEmpty && traktViewingRemovals.isEmpty
          && traktRewatched.isEmpty && outbox.isEmpty)
    }

    /// Elemento por elemento (revisión del 11 nov 2026): antes un solo elemento mal formado hacía ilegible el archivo entero y
    /// se apartaba toda la cola.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rejected: [JSON] = []
        func list<T: Decodable>(_ key: CodingKeys) throws -> [T] {
            guard let lossy = try c.decodeIfPresent(LossyList<T>.self, forKey: key) else { return [] }
            rejected += lossy.rejected
            return lossy.items
        }
        traktWatched = try list(.traktWatched)
        traktUnwatched = try list(.traktUnwatched)
        traktProgress = try list(.traktProgress)
        playbackRemovals = try list(.playbackRemovals)
        traktViewingRemovals = try list(.traktViewingRemovals)
        traktRewatched = try list(.traktRewatched)
        outbox = try list(.outbox)
        discards = try list(.discards)
        self.rejected = rejected
    }
    enum CodingKeys: String, CodingKey { case traktWatched, traktUnwatched, traktProgress, playbackRemovals, traktViewingRemovals, traktRewatched, outbox, discards }

    /// Lo de los dos lados, sin repetir (lo de `self` primero). Para juntar lo que se anotó en memoria mientras el archivo no
    /// se podía leer con lo que el archivo tenía.
    func union(_ other: PendingWork) -> PendingWork {
        func merge<T: Equatable>(_ a: [T], _ b: [T]) -> [T] { a + b.filter { !a.contains($0) } }
        var out = self
        out.traktWatched = merge(traktWatched, other.traktWatched)
        out.traktUnwatched = merge(traktUnwatched, other.traktUnwatched)
        out.traktProgress = merge(traktProgress, other.traktProgress)
        out.playbackRemovals = merge(playbackRemovals, other.playbackRemovals)
        out.traktViewingRemovals = merge(traktViewingRemovals, other.traktViewingRemovals)
        out.traktRewatched = merge(traktRewatched, other.traktRewatched)
        out.outbox = merge(outbox, other.outbox)
        out.discards = merge(discards, other.discards)
        return out
    }
}

/// Una lista que se lee elemento por elemento: lo que no se entiende se guarda tal cual (para apartarlo) y lo demás sigue.
struct LossyList<T: Decodable>: Decodable {
    var items: [T] = []
    var rejected: [JSON] = []
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let item = try? c.decode(T.self) { items.append(item) } else { rejected.append(try c.decode(JSON.self)) }
        }
    }
}
