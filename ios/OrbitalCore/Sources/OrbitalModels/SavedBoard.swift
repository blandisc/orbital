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
    public static func build(watchlist: [Suggestion], watched: TraktWatchedState, hidden: Set<String>, hiddenNames: [String: String] = [:]) -> SavedBoard {
        var board = SavedBoard()
        let listed = Set(watchlist.map(\.imdb))
        // Mi lista tal cual (es lo que abre la tarjeta). Trakt saca una serie de la watchlist al ver su primer episodio, así que
        // casi nunca está a la vez en Mi lista y en Viendo; las dejadas sí salen.
        board.inList = watchlist.filter { !hidden.contains($0.imdb) }
        func suggestion(_ imdb: String) -> Suggestion? {
            if let s = watchlist.first(where: { $0.imdb == imdb }) { return s }
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
        board.watching = going.sorted(by: recent).compactMap(suggestion)
        board.watched = seen.sorted(by: recent).compactMap(suggestion)
        board.dropped = hidden.sorted(by: recent).compactMap(suggestion)
        board.lastWatched = watched.info.compactMapValues(\.lastWatchedAt)
        return board
    }
}
