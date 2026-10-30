import Foundation
import OrbitalCore

#if DEBUG   // solo la demo: DemoHTTPClient no existe en la versión del iPhone

/// Calificar en modo demostración (`-demo-rate`): un historial con dos películas recientes y una serie con varios episodios,
/// y nada calificado todavía, para ver la pastilla «¿Qué tal …?» y su fila.
extension DemoHTTPClient {
    static func ratingsDemo(_ path: String) -> JSON? {
        func at(_ days: Double) -> JSON { .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-days * 86_400))) }
        func movie(_ id: String, _ title: String, _ days: Double) -> JSON {
            ["type": "movie", "watched_at": at(days), "movie": ["title": .string(title), "year": 2016, "runtime": 111, "genres": ["drama"], "ids": ["imdb": .string(id), "trakt": 1]]]
        }
        func episode(_ n: Int, _ days: Double) -> JSON {
            ["type": "episode", "watched_at": at(days), "episode": ["season": 1, "number": .int(n), "title": "Episodio", "runtime": 45],
             "show": ["title": "Severance", "year": 2022, "genres": ["drama"], "ids": ["imdb": "tt11280740", "trakt": 2]]]
        }
        switch path {
        case "/sync/history": return [movie("tt4975722", "Moonlight", 0.5), movie("tt6751668", "Parásitos", 3), episode(1, 4), episode(2, 4), episode(3, 5)]
        case "/sync/ratings/movies", "/sync/ratings/shows", "/sync/ratings/episodes": return []
        case "/sync/ratings", "/sync/ratings/remove": return ["added": ["movies": 1]]
        default: return nil
        }
    }
}
#endif
