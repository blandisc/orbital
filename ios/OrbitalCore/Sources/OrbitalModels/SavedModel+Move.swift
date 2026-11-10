import Foundation
import OrbitalCore

/// «Mover a…» del tablero de Guardado (G2-A, Fernando, 9 nov 2026: «Completa todos los pendientes»): mantener el dedo sobre un
/// póster lo pasa a otro estado sin abrir su ficha. Las mismas respuestas del botón de estado (`TitleStatus`); el tablero
/// cambia al instante y Trakt lo recibe por su cola (sin internet, en cuanto haya).
extension SavedModel {
    /// A dónde se puede mover un título desde el montón en el que está. «Viendo» es de series que dejaste (regresa a Seguir
    /// viendo); «Vista» desde aquí es de películas (una serie se marca episodio por episodio en su ficha).
    public nonisolated static func moves(kind: String, from: TitleStatus) -> [TitleStatus] {
        let series = kind == "series"
        var out: [TitleStatus] = []
        if from != .inList { out.append(.inList) }
        if series, from == .dropped { out.append(.watching) }
        if !series, from != .watched { out.append(.watched) }
        if from != .dropped, series || from == .inList { out.append(.dropped) }
        return out
    }

    /// Pone o quita un título de Mi lista y el tablero lo refleja ya.
    public func setInWatchlist(_ s: Suggestion, _ add: Bool) async {
        if add { if !watchlist.contains(where: { $0.imdb == s.imdb }) { watchlist.insert(s, at: 0) } }
        else { watchlist.removeAll { $0.imdb == s.imdb } }
        if selected == Self.watchlist { setShown(s, shown: add) }
        try? await actions.setSaved(s, add: add)
    }

    /// «Vista» (una película): pasa a Vistas hoy y sale de Mi lista (Trakt hace lo mismo al verla).
    public func markMovieWatched(_ s: Suggestion, at date: Date = Date()) async {
        noteWatched(s, at: date)
        noteMoved(s.imdb, to: .watched)
        if watchlist.contains(where: { $0.imdb == s.imdb }) { await setInWatchlist(s, false) }
        try? await actions.markWatched(s, at: date)
    }

    /// «Deshacer» de «Vista»: sale de lo visto (aquí y en Trakt).
    public func unmarkMovieWatched(_ s: Suggestion) async {
        forgetWatched(s.imdb)
        await services.watch.unmarkWatched(kind: s.kind, metaID: s.imdb, videoID: s.imdb)
    }

    /// «La dejé» de una película desde Mi lista: sale de Mi lista y de Seguir viendo; lo visto se queda.
    public func dropMovie(_ s: Suggestion) async {
        await setInWatchlist(s, false)
        await services.watch.dismissContinue(metaID: s.imdb)
    }
}
