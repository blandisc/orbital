import Foundation

/// Cuándo cambió cada cosa en tu cuenta de Trakt (`/sync/last_activities`), desde cualquier aparato. Las marcas son texto ISO:
/// se comparan tal cual con las de la última vez y, si no cambiaron, no se baja nada.
public struct TraktActivities: Sendable, Equatable, Codable {
    /// El avance a medias (`movies.paused_at` y `episodes.paused_at`).
    public var playback: String?
    /// Lo visto (`movies.watched_at` y `episodes.watched_at`).
    public var watched: String?
    /// La watchlist (`watchlist.updated_at`, o lo último que entró o salió de ella).
    public var watchlist: String?
    public init(playback: String? = nil, watched: String? = nil, watchlist: String? = nil) {
        self.playback = playback; self.watched = watched; self.watchlist = watchlist
    }

    static func parse(_ json: JSON?) -> TraktActivities {
        func latest(_ values: [JSON?]) -> String? { values.compactMap { $0?.nonEmptyString }.max() }
        let movies = json?["movies"], episodes = json?["episodes"], shows = json?["shows"]
        return TraktActivities(
            playback: latest([movies?["paused_at"], episodes?["paused_at"]]),
            watched: latest([movies?["watched_at"], episodes?["watched_at"]]),
            watchlist: latest([json?["watchlist"]?["updated_at"], movies?["watchlisted_at"], shows?["watchlisted_at"], episodes?["watchlisted_at"]]))
    }
}

/// Cómo vas en una serie según Trakt (`/shows/{id}/progress/watched`): los episodios vistos, el último y el que sigue.
public struct TraktShowProgress: Sendable, Equatable {
    public var imdb: String
    public var lastWatchedAt: Date?
    public var completed: [(season: Int, episode: Int)]
    public var next: (season: Int, episode: Int)?
    public var last: (season: Int, episode: Int)?

    public init(imdb: String, lastWatchedAt: Date?, completed: [(season: Int, episode: Int)], next: (season: Int, episode: Int)?, last: (season: Int, episode: Int)?) {
        self.imdb = imdb; self.lastWatchedAt = lastWatchedAt; self.completed = completed; self.next = next; self.last = last
    }

    public static func == (a: TraktShowProgress, b: TraktShowProgress) -> Bool {
        a.imdb == b.imdb && a.lastWatchedAt == b.lastWatchedAt && a.completed.map { [$0.season, $0.episode] } == b.completed.map { [$0.season, $0.episode] }
            && a.next.map { [$0.season, $0.episode] } == b.next.map { [$0.season, $0.episode] } && a.last.map { [$0.season, $0.episode] } == b.last.map { [$0.season, $0.episode] }
    }

    /// El id de video de Stremio de un episodio de esta serie («tt0944947:1:5»).
    public func videoID(_ ep: (season: Int, episode: Int)) -> String { "\(imdb):\(ep.season):\(ep.episode)" }

    static func parse(_ json: JSON?, imdb: String) -> TraktShowProgress? {
        guard let json, json.object != nil else { return nil }
        var done: [(season: Int, episode: Int)] = []
        for season in json["seasons"]?.array ?? [] {
            guard let s = season["number"]?.intValue, s > 0 else { continue }
            for ep in season["episodes"]?.array ?? [] where ep["completed"] == .bool(true) {
                if let n = ep["number"]?.intValue { done.append((s, n)) }
            }
        }
        func pair(_ j: JSON?) -> (season: Int, episode: Int)? {
            guard let s = j?["season"]?.intValue, let n = j?["number"]?.intValue else { return nil }
            return (s, n)
        }
        return TraktShowProgress(imdb: imdb, lastWatchedAt: json["last_watched_at"]?.string.flatMap(TraktParsing.date), completed: done,
                                 next: pair(json["next_episode"]), last: pair(json["last_episode"]))
    }
}

/// Algo que viste según Trakt (`/sync/watched/movies` o `/sync/watched/shows`): una película o una serie y cuándo fue lo último.
public struct TraktWatchedTitle: Sendable, Equatable {
    public var kind: String
    public var imdb: String
    public var traktID: Int?
    public var title: String
    public var lastWatchedAt: Date
}

extension Trakt {
    /// Cuándo cambió cada cosa (una llamada chica): si nada cambió desde la última vez, no se baja nada más.
    public func activities() async throws -> TraktActivities {
        TraktActivities.parse(try await get("/sync/last_activities"))
    }

    /// Las películas o series que viste, con la fecha de lo último (sin las temporadas: es para saber cuáles cambiaron).
    public func watchedTitles(kind: String) async throws -> [TraktWatchedTitle] {
        let series = kind == "series"
        let rows = try await get(series ? "/sync/watched/shows" : "/sync/watched/movies", series ? [("extended", "noseasons")] : [])?.array ?? []
        return rows.compactMap { row in
            let item = row[series ? "show" : "movie"]
            guard let imdb = item?["ids"]?["imdb"]?.string, Trakt.isIMDb(imdb),
                  let at = row["last_watched_at"]?.string.flatMap(TraktParsing.date) else { return nil }
            return TraktWatchedTitle(kind: kind, imdb: imdb, traktID: item?["ids"]?["trakt"]?.intValue, title: item?["title"]?.string ?? "", lastWatchedAt: at)
        }
    }

    /// Cómo vas en una serie (por su id de Trakt o su IMDb): episodios vistos, el último y el siguiente que ya salió.
    public func showProgress(_ id: String, imdb: String) async throws -> TraktShowProgress? {
        guard Trakt.isIMDb(id) || Trakt.isListID(id) else { throw TraktError.invalid("Serie inválida") }
        return TraktShowProgress.parse(try await get("/shows/\(id)/progress/watched", [("hidden", "false"), ("specials", "false")]), imdb: imdb)
    }

    /// Quita de Trakt un avance a medias («Quitar de Seguir viendo»). Ya no estaba (404): no es un error.
    public func removePlayback(id: Int) async throws {
        let (status, _) = try await write("/sync/playback/\(id)", nil, method: "DELETE")
        playbackCache = nil
        guard status == 204 || status == 200 || status == 404 else { throw TraktError.http(status) }
    }

    /// «Marcar como no vista»: quita del historial de Trakt todas las veces que viste esa película o ese episodio.
    public func removeFromHistory(_ target: TraktTarget) async throws {
        guard Trakt.isIMDb(target.imdb) else { throw TraktError.invalid("Título inválido") }
        let body: JSON = target.isEpisode
            ? ["shows": [["ids": ["imdb": .string(target.imdb)], "seasons": [["number": .int(target.season!), "episodes": [["number": .int(target.episode!)]]]]]]]
            : ["movies": [["ids": ["imdb": .string(target.imdb)]]]]
        let (status, _) = try await write("/sync/history/remove", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }
}
