#if DEBUG
import Foundation
import OrbitalCore

/// `-demo-trakt-discards`: lo que no llegó a Trakt, de mentira, para ver Ajustes › Cuentas › «N cosas no se pudieron guardar
/// en Trakt» y su lista (capturas). Uno vencido (con «Reintentar»), uno que Trakt rechazó y una lista que ya no existe.
extension Demo {
    static var traktDiscards: Bool { has("-demo-trakt-discards") }

    static func seedTraktDiscards(_ pending: PendingStore) {
        guard traktDiscards else { return }
        let now = Date().timeIntervalSince1970
        let episode = TraktTarget(imdb: "tt0386676", season: 2, episode: 5)
        var expired = TraktDiscard(what: "Visto · tt0386676 T2 E5", reason: "venció sin poder mandarse", at: now - 3_600)
        expired.kind = .watched; expired.target = episode; expired.cause = .expired
        expired.retry = TraktRetry(traktWatched: [PendingWork.TraktWatched(target: episode, at: now - 40 * 86_400)])
        var rating = TraktDiscard(what: "Tu calificación · tt0816692", reason: "Trakt respondió 422", at: now - 86_400)
        rating.kind = .rating; rating.target = TraktTarget(imdb: "tt0816692"); rating.cause = .refused; rating.status = 422
        var list = TraktDiscard(what: "Lista 77 · tt0903747", reason: "Trakt respondió 404", at: now - 3 * 86_400)
        list.kind = .list; list.target = TraktTarget(imdb: "tt0903747"); list.cause = .refused; list.status = 404
        pending.update { $0.discards = [list, rating, expired] }
    }
}
#endif
