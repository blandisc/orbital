import Foundation
import OrbitalCore

/// Biblioteca › Guardado por estado (G2-A, Fernando, 9 nov 2026: «G2-A, check. Déjalo como guardado en la pestaña»): lo tuyo
/// en cuatro montones, con su cifra. Las mismas reglas del botón de estado de la ficha (`TitleStatus`).
public struct SavedBoard: Equatable, Sendable {
    public var inList: [Suggestion] = []
    public var watching: [Suggestion] = []
    /// Lo más reciente primero (la pantalla lo junta por mes).
    public var watched: [Suggestion] = []
    public var dropped: [Suggestion] = []
    /// Series a medias que no ves hace más de seis meses: no cuentan en Viendo y Orbital pregunta «¿La dejaste?».
    public var stale: [Suggestion] = []
    /// Cuándo viste por última vez cada uno (para «Noviembre», «Octubre»…).
    public var lastWatched: [String: Date] = [:]

    public init() {}

    public func items(_ status: TitleStatus) -> [Suggestion] {
        switch status {
        case .inList: inList
        case .watching: watching
        case .watched: watched
        case .dropped: dropped
        case .none: []
        }
    }

    /// - Parameters:
    ///   - watchlist: Mi lista (tu watchlist de Trakt).
    ///   - watched: lo que viste según Trakt (con nombres, fechas y qué series siguen saliendo).
    ///   - hidden: las series que dejaste (escondidas).
    ///   - hiddenNames: el nombre de las dejadas que no están en lo visto.
    ///   - now: hoy (para «¿La dejaste?»: seis meses sin verla).
    public static let staleAfter: TimeInterval = 182 * 24 * 3600
    public static func build(watchlist: [Suggestion], watched: TraktWatchedState, hidden: Set<String>, hiddenNames: [String: String] = [:],
                             now: Date = Date()) -> SavedBoard {
        var board = SavedBoard()
        let listed = Set(watchlist.map(\.imdb))
        // Mi lista tal cual (es lo que abre la tarjeta). Trakt saca una serie de la watchlist al ver su primer episodio, así que
        // casi nunca está a la vez en Mi lista y en Viendo; las dejadas sí salen.
        board.inList = watchlist.filter { !hidden.contains($0.imdb) }
        func suggestion(_ imdb: String) -> Suggestion? {
            // Viendo, Vistas y Las dejé no tienen «agregada» (es de Mi lista): sin la fecha, no ofrecen ese orden.
            if var s = watchlist.first(where: { $0.imdb == imdb }) { s.addedAt = nil; return s }
            guard let info = watched.info[imdb] else {
                return hiddenNames[imdb].map { Suggestion(art: imdb, kind: "series", title: $0, year: nil, reason: .watching) }
            }
            return Suggestion(art: imdb, kind: info.kind, title: info.title, year: info.year, reason: .watching)
        }
        let recent = { (a: String, b: String) in (watched.info[a]?.lastWatchedAt ?? .distantPast) > (watched.info[b]?.lastWatchedAt ?? .distantPast) }
        var seen: [String] = [], going: [String] = []
        for (imdb, fraction) in watched.shows where !hidden.contains(imdb) && fraction > 0 {
            if fraction >= 1 && !watched.airing.contains(imdb) { seen.append(imdb) } else { going.append(imdb) }
        }
        // Una película vista que volviste a poner en Mi lista cuenta en Mi lista (la quieres ver otra vez).
        seen += watched.movies.filter { !listed.contains($0) }
        let old = { (imdb: String) in (watched.info[imdb]?.lastWatchedAt).map { now.timeIntervalSince($0) > staleAfter } ?? false }
        board.watching = going.filter { !old($0) }.sorted(by: recent).compactMap(suggestion)
        board.stale = going.filter(old).sorted(by: recent).compactMap(suggestion)
        board.watched = seen.sorted(by: recent).compactMap(suggestion)
        board.dropped = hidden.sorted(by: recent).compactMap(suggestion)
        board.lastWatched = watched.info.compactMapValues(\.lastWatchedAt)
        return board
    }
}

/// Un título que cambió de estado solo, sin que lo movieras aquí (G2-A: «si el estado cambia solo, te avisa»): terminaste la
/// película en la TV, acabaste una serie o una serie vista estrenó temporada.
public struct SavedChange: Equatable, Sendable {
    public var imdb: String
    public var title: String
    public var to: TitleStatus
}

extension SavedBoard {
    /// Cada título y su estado (una serie que no ves hace seis meses sigue contando como a medias aquí).
    public var statuses: [String: TitleStatus] {
        var out: [String: TitleStatus] = [:]
        for s in inList { out[s.imdb] = .inList }
        for s in watching + stale { out[s.imdb] = .watching }
        for s in watched { out[s.imdb] = .watched }
        for s in dropped { out[s.imdb] = .dropped }
        return out
    }

    /// Lo que cambió solo desde la última vez: algo que pasó a Vistas, o una vista que regresó a Viendo. Lo que tú mueves
    /// (a Mi lista o a «Las dejé») no se avisa, y un título nuevo tampoco.
    public func automaticChanges(since old: [String: TitleStatus]) -> [SavedChange] {
        let all = inList + watching + stale + watched
        var out: [SavedChange] = []
        for (imdb, now) in statuses {
            guard let before = old[imdb], before != now, before != .dropped else { continue }
            let auto = (now == .watched) || (now == .watching && before == .watched)
            if auto, let s = all.first(where: { $0.imdb == imdb }) { out.append(SavedChange(imdb: imdb, title: s.title, to: now)) }
        }
        let order = watched.map(\.imdb) + watching.map(\.imdb) + stale.map(\.imdb)
        return out.sorted { (order.firstIndex(of: $0.imdb) ?? .max) < (order.firstIndex(of: $1.imdb) ?? .max) }
    }
}

