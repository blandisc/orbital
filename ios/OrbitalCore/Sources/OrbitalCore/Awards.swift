import Foundation

/// Una colección de premio (Colecciones › Premios): los ganadores, del más reciente al más viejo. Los IMDb se fijaron a
/// mano una vez y se comprobaron contra Cinemeta (nombre y año).
public struct AwardCollection: Sendable, Identifiable, Equatable {
    public struct Winner: Sendable, Equatable {
        public let imdb: String, title: String, year: Int, awardYear: Int
    }
    /// oscar | emmy | globe | palm | bafta | ariel (también el nombre de su imagen).
    public let id: String
    public let kind: String
    public let winners: [Winner]

    /// Los ganadores como sugerencias (con el año del premio como motivo: «2025»).
    public var suggestions: [Suggestion] {
        winners.map { Suggestion(art: $0.imdb, kind: kind, title: $0.title, year: $0.year, reason: .console(String($0.awardYear))) }
    }
}

public extension Suggestion {
    /// Una sugerencia con el arte de metahub (póster, fondo y logo del IMDb).
    init(art imdb: String, kind: String, title: String, year: Int?, reason: SuggestionReason) {
        self.init(kind: kind, imdb: imdb, title: title, year: year, poster: String(format: ForYou.metahubPoster, imdb),
                  wide: String(format: ForYou.metahubBackground, imdb), logo: String(format: ForYou.metahubLogo, imdb), reason: reason)
    }

    init(_ e: TraktEntry, reason: SuggestionReason) {
        self.init(art: e.imdb, kind: e.kind, title: e.title, year: e.year, reason: reason)
        runtime = e.runtime; overview = e.overview; genres = e.genres
    }
}
