import Foundation

/// Cómo vas con un título (G1-A, Fernando, 9 nov 2026: «me gusta tu sugerencia»): una sola respuesta en el botón de estado de
/// la ficha. Se deduce de lo que ya se sabe (Mi lista, lo visto, lo escondido); no se guarda aparte.
/// docs/producto/live-activity-2026-11-08/gestor-maquetas.html
public enum TitleStatus: String, Sendable, Equatable, CaseIterable {
    /// No está en ningún lado: el botón dice «Mi lista» y un toque la guarda.
    case none
    /// En Mi lista (tu watchlist de Trakt).
    case inList
    /// Una serie con episodios vistos y otros por ver (o por salir). En una película no es estado: la barra de avance.
    case watching
    /// La película vista, o la serie que terminó y viste toda.
    case watched
    /// Una serie que dejaste (la «Esconder» de Series que sigues).
    case dropped

    /// - Parameters:
    ///   - isSeries: serie o película.
    ///   - inList: está en Mi lista.
    ///   - watchedCount: episodios vistos (en una película, 1 si está vista).
    ///   - releasedCount: episodios que ya salieron (en una película, 1).
    ///   - upcoming: a la serie le faltan episodios por salir (va al día pero no ha terminado).
    ///   - dropped: la serie está escondida.
    public static func decide(isSeries: Bool, inList: Bool, watchedCount: Int, releasedCount: Int, upcoming: Bool, dropped: Bool) -> TitleStatus {
        if isSeries {
            if dropped { return .dropped }
            // Trakt saca una serie de la watchlist al ver su primer episodio: si sigue (o regresó) en Mi lista, la volviste a
            // poner tú y eso manda solo mientras no la empiezas.
            if watchedCount > 0 {
                let all = releasedCount > 0 && watchedCount >= releasedCount
                return all && !upcoming ? .watched : .watching
            }
            return inList ? .inList : .none
        }
        // Película: Trakt la saca de la watchlist al verla; si está en Mi lista después, la volviste a guardar para verla otra vez.
        if inList { return .inList }
        return watchedCount > 0 ? .watched : .none
    }
}
