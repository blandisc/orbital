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
    /// Una serie que ganó varias veces sale una sola vez, con sus años («2026, 2025»): repetida, la cuadrícula confundía sus
    /// celdas y la portada mostraba dos veces el mismo póster (revisión del 28 nov 2026).
    public var suggestions: [Suggestion] {
        var years: [String: [Int]] = [:], order: [Winner] = []
        for w in winners {
            if years[w.imdb] == nil { order.append(w) }
            years[w.imdb, default: []].append(w.awardYear)
        }
        return order.map { w in
            Suggestion(art: w.imdb, kind: kind, title: w.title, year: w.year,
                       reason: .console((years[w.imdb] ?? [w.awardYear]).map(String.init).joined(separator: ", ")))
        }
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
        runtime = e.runtime; overview = e.overview; genres = e.genres; traktRating = e.rating
    }
}
