import Foundation

/// Tus calificaciones en Trakt: entero del 1 al 10 (contrato oficial `ratingsParamSchema` de `trakt/trakt-api`). La app las
/// muestra como 5 estrellas con medias (`RatingScale`); aquí solo se leen y se escriben. Se califican películas, series y
/// capítulos; un capítulo se nombra con su video id («tt0386676:2:5»: la serie, la temporada y el número).
extension Trakt {
    /// Todo lo que calificaste: películas y series por IMDb, capítulos por video id → 1…10.
    public func myRatings() async throws -> [String: Int] {
        async let movies = get("/sync/ratings/movies")
        async let shows = get("/sync/ratings/shows")
        async let episodes = get("/sync/ratings/episodes")
        let eps: JSON? = (try? await episodes).flatMap { $0 }   // los capítulos son extra: si fallan, lo demás sigue
        let rows = (try await movies?.array ?? []) + (try await shows?.array ?? []) + (eps?.array ?? [])
        var out: [String: Int] = [:]
        for row in rows {
            guard let imdb = (row["movie"] ?? row["show"])?["ids"]?["imdb"]?.string, let value = row["rating"]?.intValue,
                  RatingScale.traktRange.contains(value) else { continue }
            if let ep = row["episode"] {
                guard let s = ep["season"]?.intValue, let n = ep["number"]?.intValue else { continue }
                out[RatingKey.episode(show: imdb, season: s, number: n)] = value
            } else {
                out[imdb] = value
            }
        }
        return out
    }

    /// Califica un título (1…10) o, con nil, quita tu calificación.
    /// `imdb` puede ser el video id de un capítulo («tt…:2:5»): entonces califica ese capítulo.
    public func setRating(imdb: String, series: Bool, rating: Int?) async throws {
        let episode = RatingKey.parseEpisode(imdb)
        let id = episode?.show ?? imdb
        guard Self.isIMDb(id) else { throw TraktError.invalid("Título inválido") }
        if let rating, !RatingScale.traktRange.contains(rating) { throw TraktError.invalid("Calificación inválida") }
        let value: [String: JSON] = rating.map { ["rating": .int($0)] } ?? [:]
        let body: JSON
        if let episode {
            // Por la serie: {"shows":[{"ids":…,"seasons":[{"number":2,"episodes":[{"number":5,"rating":8}]}]}]}
            let ep = JSON.object(["number": .int(episode.number)].merging(value) { $1 })
            body = ["shows": [["ids": ["imdb": .string(id)], "seasons": [["number": .int(episode.season), "episodes": [ep]]]]]]
        } else {
            let item = JSON.object(["ids": ["imdb": .string(id)]].merging(value) { $1 })
            body = series ? ["shows": [item]] : ["movies": [item]]
        }
        let (status, _) = try await write(rating == nil ? "/sync/ratings/remove" : "/sync/ratings", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }
}

/// Cómo se nombra lo calificado: el IMDb de una película o serie, o el video id de un capítulo («tt…:temporada:número»).
public enum RatingKey {
    public static func episode(show: String, season: Int, number: Int) -> String { "\(show):\(season):\(number)" }
    public static func parseEpisode(_ key: String) -> (show: String, season: Int, number: Int)? {
        let parts = key.split(separator: ":")
        guard parts.count == 3, let s = Int(parts[1]), let n = Int(parts[2]) else { return nil }
        return (String(parts[0]), s, n)
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
