import Foundation

/// Los tipos de Trakt (errores, entradas, estrenos, código de aparato, scrobble, destino) y cómo se leen sus respuestas.

public enum TraktError: Error, Sendable, CustomStringConvertible {
    case network(String), http(Int), invalid(String)
    /// Trakt ya no acepta la sesión: hay que volver a conectar la cuenta.
    case auth(String)
    public var description: String {
        switch self {
        case .network(let reason): return "No pude conectar con Trakt: \(reason)"
        case .http(let s): return "Trakt respondió HTTP \(s)"
        case .invalid(let m), .auth(let m): return m
        }
    }
}

/// Una película o serie de Trakt, con su id de IMDb (sin él no se podría ver).
/// Algo que viste según tu historial de Trakt: cuándo, qué (película o episodio de una serie), cuánto dura y sus géneros.
public struct TraktPlay: Sendable, Equatable {
    public var at: Date
    public var kind: String          // movie | series
    public var imdb: String
    public var title: String
    public var minutes: Int
    public var genres: [String]
    /// El episodio (temporada, número y nombre), si fue de una serie.
    public var season: Int?, episode: Int?, episodeTitle: String?
    public init(at: Date, kind: String, imdb: String, title: String, minutes: Int, genres: [String],
                season: Int? = nil, episode: Int? = nil, episodeTitle: String? = nil) {
        self.at = at; self.kind = kind; self.imdb = imdb; self.title = title; self.minutes = minutes; self.genres = genres
        self.season = season; self.episode = episode; self.episodeTitle = episodeTitle
    }
}

public struct TraktEntry: Sendable, Equatable, Identifiable {
    public var kind: String          // movie | series
    public var imdb: String
    public var title: String
    public var year: Int?
    public var runtime: Int?
    public var episodes: Int?
    public var overview: String
    public var traktID: Int?
    public var next: (season: Int, episode: Int)?
    /// Los géneros de Trakt («comedy», «science-fiction»), con `extended=full`.
    public var genres: [String] = []
    /// La calificación de Trakt (0 a 10), con `extended=full`.
    public var rating: Double?
    /// Cuándo lo viste (solo en el historial: «Porque viste» dice «la viste hace 3 días»).
    public var watchedAt: Date?
    public var id: String { imdb }

    public static func == (a: TraktEntry, b: TraktEntry) -> Bool {
        a.kind == b.kind && a.imdb == b.imdb && a.title == b.title && a.year == b.year && a.runtime == b.runtime
            && a.episodes == b.episodes && a.overview == b.overview && a.traktID == b.traktID
            && a.next?.season == b.next?.season && a.next?.episode == b.next?.episode
    }
}

/// Un episodio que sale de una serie que sigues («Próximos estrenos»): la serie, cuál episodio, cuándo (la hora
/// exacta; la interfaz la pone en la de aquí) y dónde sale.
public struct TraktAiring: Sendable, Equatable {
    public var show: TraktEntry
    public var season: Int
    public var episode: Int
    public var episodeTitle: String
    public var aired: Date
    public var network: String
    public init(show: TraktEntry, season: Int, episode: Int, episodeTitle: String = "", aired: Date, network: String = "") {
        self.show = show; self.season = season; self.episode = episode; self.episodeTitle = episodeTitle; self.aired = aired; self.network = network
    }
}

public struct DeviceCode: Sendable, Equatable {
    public var deviceCode: String, userCode: String, verificationURL: String
    public var interval: TimeInterval, expiresAt: Date
}

/// Algo que dejaste a medias según Trakt (`/sync/playback`): cuánto llevabas (0–100 %) y cuándo lo pausaste. Lo escribe
/// cualquier dispositivo que haga scrobble con tu cuenta (la consola, el iPhone): así se sigue donde ibas en el otro.
public struct TraktPlayback: Sendable, Equatable {
    public var id: Int
    public var progress: Double
    public var pausedAt: Date
    public var target: TraktTarget
    public init(id: Int, progress: Double, pausedAt: Date, target: TraktTarget) {
        self.id = id; self.progress = progress; self.pausedAt = pausedAt; self.target = target
    }
}

public enum DeviceStatus: Sendable, Equatable { case linked, pending, slow, expired, denied, invalid }

/// Lo que se avisa a Trakt de lo que reproduces.
public enum ScrobbleAction: String, Sendable { case start, pause, stop }

public enum ScrobbleResult: Sendable, Equatable {
    case sent
    /// 409: ya estaba registrado (dos dispositivos, o el mismo reproductor dos veces).
    case duplicate
    /// Menos de 1 % o respuesta que se ignora.
    case ignored
}

/// Cuál título se está viendo, para el scrobble: una película, o un episodio de una serie (por IMDb de la serie).
public struct TraktTarget: Sendable, Equatable, Codable {
    public var imdb: String
    public var season: Int?
    public var episode: Int?
    public init(imdb: String, season: Int? = nil, episode: Int? = nil) { self.imdb = imdb; self.season = season; self.episode = episode }
    public var isEpisode: Bool { season != nil && episode != nil }

    /// «tt0944947:1:5» → serie 1×5; «tt1160419» → película.
    public init?(videoID: String, kind: String) {
        let parts = videoID.split(separator: ":").map(String.init)
        guard let imdb = parts.first, imdb.hasPrefix("tt") else { return nil }
        if kind == "movie" { self.init(imdb: imdb); return }
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return nil }
        self.init(imdb: imdb, season: s, episode: e)
    }

    var body: JSON {
        isEpisode ? ["show": ["ids": ["imdb": .string(imdb)]], "episode": ["season": .int(season!), "number": .int(episode!)]]
                  : ["movie": ["ids": ["imdb": .string(imdb)]]]
    }
}

public enum TraktParsing {
    static let kinds = ["movie": "movies", "series": "shows"]

    public static func entry(_ raw: JSON?, kind: String) -> TraktEntry? {
        guard let raw, raw.object != nil, let ids = raw["ids"], let imdb = ids["imdb"]?.string, imdb.hasPrefix("tt"),
              let title = raw["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        func positive(_ j: JSON?) -> Int? { j?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        func isInt(_ j: JSON?) -> Int? { if case .int(let i)? = j { return i }; return nil }
        var entry = TraktEntry(kind: kind, imdb: imdb, title: title, year: isInt(raw["year"]), runtime: positive(raw["runtime"]),
                               episodes: positive(raw["aired_episodes"]), overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                               traktID: isInt(ids["trakt"]))
        entry.genres = (raw["genres"]?.array ?? []).compactMap(\.string)
        entry.rating = raw["rating"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
        return entry
    }

    /// Una fila del historial: una película o un episodio, con su `watched_at`. Sin IMDb o sin fecha: nada.
    public static func play(_ row: JSON) -> TraktPlay? {
        guard let stamp = row["watched_at"]?.string, let at = date(stamp) else { return nil }
        let isMovie = row["type"]?.string == "movie"
        let item = isMovie ? row["movie"] : row["show"]
        guard let item, let imdb = item["ids"]?["imdb"]?.string, imdb.hasPrefix("tt"), let title = item["title"]?.string else { return nil }
        let minutes = (isMovie ? item["runtime"]?.intValue : row["episode"]?["runtime"]?.intValue ?? item["runtime"]?.intValue) ?? 0
        let genres = (item["genres"]?.array ?? []).compactMap(\.string)
        let ep = isMovie ? nil : row["episode"]
        let episodeTitle = ep?["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TraktPlay(at: at, kind: isMovie ? "movie" : "series", imdb: imdb, title: title, minutes: max(0, minutes), genres: genres,
                         season: ep?["season"]?.intValue, episode: ep?["number"]?.intValue, episodeTitle: episodeTitle?.isEmpty == false ? episodeTitle : nil)
    }

    /// Una fila del calendario de Trakt («first_aired» en hora universal). Sin IMDb, fecha o número de episodio: nada.
    public static func airing(_ row: JSON) -> TraktAiring? {
        guard var show = entry(row["show"], kind: "series"), let ep = row["episode"], ep.object != nil,
              let season = ep["season"]?.intValue, let number = ep["number"]?.intValue,
              let stamp = row["first_aired"]?.string, let aired = date(stamp) else { return nil }
        if let minutes = ep["runtime"]?.intValue, minutes > 0 { show.runtime = minutes }
        return TraktAiring(show: show, season: season, episode: number,
                           episodeTitle: (ep["title"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines), aired: aired,
                           network: (row["show"]?["network"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Una fila de `/sync/playback`: una película (por su IMDb) o un episodio (IMDb de la serie, temporada y número).
    /// Sin IMDb, sin fecha o sin avance: nada.
    public static func playback(_ row: JSON) -> TraktPlayback? {
        guard let id = row["id"]?.intValue, let progress = row["progress"]?.doubleValue, progress > 0,
              let stamp = row["paused_at"]?.string, let at = date(stamp) else { return nil }
        let target: TraktTarget
        if row["type"]?.string == "episode" {
            guard let imdb = row["show"]?["ids"]?["imdb"]?.string, Trakt.isIMDb(imdb),
                  let season = row["episode"]?["season"]?.intValue, let number = row["episode"]?["number"]?.intValue else { return nil }
            target = TraktTarget(imdb: imdb, season: season, episode: number)
        } else {
            guard let imdb = row["movie"]?["ids"]?["imdb"]?.string, Trakt.isIMDb(imdb) else { return nil }
            target = TraktTarget(imdb: imdb)
        }
        return TraktPlayback(id: id, progress: min(100, progress), pausedAt: at, target: target)
    }

    /// «2025-10-16T01:00:00.000Z» (con o sin milésimas).
    static func date(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Las filas de `/sync/favorites/movies` y `/sync/favorites/shows` juntas: lo que marcaste al último primero (por
    /// `listed_at`), solo películas y series con IMDb, sin repetir.
    public static func favorites(_ rows: [JSON]) -> [TraktEntry] {
        typed(rows.filter { $0.object != nil }.sorted { ($0["listed_at"]?.string ?? "") > ($1["listed_at"]?.string ?? "") })
    }

    /// Filas mezcladas («type»: movie/show) → solo películas y series con IMDb, sin repetir.
    public static func typed(_ rows: [JSON]?) -> [TraktEntry] {
        var found: [TraktEntry] = [], seen = Set<String>()
        for row in rows ?? [] {
            guard let typeName = row["type"]?.string, let kind = ["movie": "movie", "show": "series"][typeName],
                  let item = entry(row[typeName], kind: kind), seen.insert(item.imdb).inserted else { continue }
            found.append(item)
        }
        return found
    }
}
