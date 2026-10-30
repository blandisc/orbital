import Foundation

/// Tus calificaciones en Trakt: entero del 1 al 10 (contrato oficial `ratingsParamSchema` de `trakt/trakt-api`). La app las
/// muestra como 5 estrellas con medias (`RatingScale`); aquí solo se leen y se escriben.
extension Trakt {
    /// Todo lo que calificaste (películas y series), por IMDb → 1…10.
    public func myRatings() async throws -> [String: Int] {
        async let movies = get("/sync/ratings/movies")
        async let shows = get("/sync/ratings/shows")
        let rows = (try await movies?.array ?? []) + (try await shows?.array ?? [])
        var out: [String: Int] = [:]
        for row in rows {
            guard let imdb = (row["movie"] ?? row["show"])?["ids"]?["imdb"]?.string, let value = row["rating"]?.intValue,
                  RatingScale.traktRange.contains(value) else { continue }
            out[imdb] = value
        }
        return out
    }

    /// Califica un título (1…10) o, con nil, quita tu calificación.
    public func setRating(imdb: String, series: Bool, rating: Int?) async throws {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        if let rating, !RatingScale.traktRange.contains(rating) { throw TraktError.invalid("Calificación inválida") }
        let item: JSON = rating.map { ["ids": ["imdb": .string(imdb)], "rating": .int($0)] } ?? ["ids": ["imdb": .string(imdb)]]
        let body: JSON = series ? ["shows": [item]] : ["movies": [item]]
        let (status, _) = try await write(rating == nil ? "/sync/ratings/remove" : "/sync/ratings", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }
}

/// 5 estrellas con medias ↔ el 1…10 de Trakt: media estrella = 1 punto.
public enum RatingScale {
    public static let traktRange = 1...10
    /// De estrellas (0.5…5, de media en media) al entero de Trakt.
    public static func trakt(stars: Double) -> Int { min(10, max(1, Int((stars * 2).rounded()))) }
    /// Del entero de Trakt a estrellas.
    public static func stars(trakt: Int) -> Double { Double(min(10, max(1, trakt))) / 2 }
    /// Redondea una posición libre (p. ej. donde cae el dedo) a la media estrella más cercana, de 0.5 a 5.
    public static func snap(_ stars: Double) -> Double { min(5, max(0.5, (stars * 2).rounded(.up) / 2)) }
}
