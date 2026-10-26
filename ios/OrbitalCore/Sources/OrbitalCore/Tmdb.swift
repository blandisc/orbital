import Foundation

public enum TmdbError: Error, Sendable, CustomStringConvertible {
    case network(String), badKey, http(Int)
    public var description: String {
        switch self {
        case .network(let m): return "No pude conectar con TMDB: \(m)"
        case .badKey: return "TMDB no aceptó la clave."
        case .http(let s): return "TMDB respondió HTTP \(s)"
        }
    }
}

/// Lo que TMDB tiene traducido de un título (y de sus episodios).
public struct Translation: Sendable, Equatable {
    public struct Key: Hashable, Sendable { public var season: Int; public var episode: Int }
    public struct EpisodeText: Sendable, Equatable { public var name: String; public var overview: String
        public init(name: String, overview: String) { self.name = name; self.overview = overview } }
    public var title = "", overview = "", genres: [String] = []
    public var episodes: [Key: EpisodeText] = [:]
    public init(title: String = "", overview: String = "", genres: [String] = [], episodes: [Key: EpisodeText] = [:]) {
        self.title = title; self.overview = overview; self.genres = genres; self.episodes = episodes
    }
    public var isEmpty: Bool { title.isEmpty && overview.isEmpty && genres.isEmpty && episodes.isEmpty }
}

public struct PlatformInfo: Sendable, Equatable { public var id: Int; public var logo: String? }

public struct TmdbDetails: Sendable, Equatable {
    public var kind: String, tmdbID: Int?, imdb: String?, title: String, year: Int?, overview: String
    public var runtime: Int?, seasons: Int?, episodes: Int?, poster: String?, backdrop: String?
}

/// TMDB (themoviedb.org): lo más popular en cada plataforma de tu país y fichas en tu idioma.
/// La clave puede ser la «API Key» (v3) o el «Read Access Token» (v4, empieza con eyJ).
public struct Tmdb: Sendable {
    public static let api = "https://api.themoviedb.org/3"
    public static let images = "https://image.tmdb.org/t/p"
    public static let kinds = ["movie": "movie", "series": "tv"]
    /// Cómo se llama cada plataforma en TMDB (cambian de nombre: «HBO Max» → «Max» → «HBO Max»).
    public static let platforms: [(brand: String, name: String, aliases: [String])] = [
        ("netflix", "Netflix", ["netflix"]), ("disney", "Disney+", ["disney plus", "disney+"]), ("hbo", "HBO Max", ["hbo max", "max"]),
    ]

    let http: HTTPClient
    public let key: String
    public var language: String

    public init(http: HTTPClient, key: String, language: String = "es-MX") { self.http = http; self.key = key; self.language = language }
    public var configured: Bool { !key.isEmpty }

    public static func image(_ path: JSON?, size: String = "w500") -> String? {
        guard let p = path?.string, p.hasPrefix("/") else { return nil }
        return "\(images)/\(size)\(p)"
    }

    /// De la lista de TMDB: Netflix, Disney+ y HBO Max (por nombre exacto, sin mayúsculas).
    public static func matchPlatforms(_ rows: JSON?) -> [String: PlatformInfo] {
        var found: [String: PlatformInfo] = [:]
        for row in rows?.array ?? [] {
            guard let id = row["provider_id"]?.intValue, case .int = row["provider_id"]! else { continue }
            let name = (row["provider_name"]?.string ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            for p in platforms where found[p.brand] == nil && p.aliases.contains(name) {
                found[p.brand] = PlatformInfo(id: id, logo: image(row["logo_path"], size: "w154"))
            }
        }
        return found
    }

    func get(_ path: String, _ params: [(String, String)] = []) async throws -> JSON {
        var items = params
        var headers: [String: String] = [:]
        if key.hasPrefix("eyJ") { headers["Authorization"] = "Bearer \(key)" } else { items.append(("api_key", key)) }
        if !items.contains(where: { $0.0 == "language" }) { items.append(("language", language)) }
        var components = URLComponents(string: Tmdb.api + path)!
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        let response: HTTPResponse
        do { response = try await http.send(HTTPRequest(url: components.url!, headers: headers, timeout: 10)) } catch { throw TmdbError.network("\(error)") }
        if response.status == 401 { throw TmdbError.badKey }
        guard response.status == 200, let json = JSON.parse(response.data), json.object != nil else { throw TmdbError.http(response.status) }
        return json
    }

    public func platforms(region: String) async throws -> [String: PlatformInfo] {
        var rows: [JSON] = []
        for kind in ["movie", "tv"] { rows += try await get("/watch/providers/\(kind)", [("watch_region", region)])["results"]?.array ?? [] }
        return Tmdb.matchPlatforms(.array(rows))
    }

    public func discover(kind: String, providerID: Int, region: String) async throws -> [JSON] {
        let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", [
            ("with_watch_providers", String(providerID)), ("watch_region", region), ("sort_by", "popularity.desc"),
            ("with_watch_monetization_types", "flatrate"), ("page", "1")])
        return (data["results"]?.array ?? []).filter { $0["id"]?.intValue != nil }
    }

    /// Lo nuevo en una plataforma: series con episodios de las dos últimas semanas; películas estrenadas en los últimos
    /// tres meses que ya están ahí. (TMDB no dice cuándo llegó algo a una plataforma: esto es lo más cercano.)
    public func fresh(kind: String, providerID: Int, region: String, now: Date) async throws -> [JSON] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        var params = [("with_watch_providers", String(providerID)), ("watch_region", region), ("with_watch_monetization_types", "flatrate"),
                      ("sort_by", "popularity.desc"), ("page", "1")]
        if kind == "series" {
            params += [("air_date.gte", f.string(from: now.addingTimeInterval(-14 * 86_400))), ("air_date.lte", today)]
        } else {
            params += [("primary_release_date.gte", f.string(from: now.addingTimeInterval(-90 * 86_400))), ("primary_release_date.lte", today),
                       ("vote_count.gte", "10")]
        }
        let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", params)
        return (data["results"]?.array ?? []).filter { $0["id"]?.intValue != nil }
    }

    /// Lo más popular de un estudio (A24, Pixar, Ghibli…).
    public func studio(companyID: Int, kind: String = "movie") async throws -> [JSON] {
        let data = try await get("/discover/\(Tmdb.kinds[kind] ?? "movie")", [("with_companies", String(companyID)), ("sort_by", "popularity.desc"),
                                                                              ("vote_count.gte", "50"), ("page", "1")])
        return (data["results"]?.array ?? []).filter { $0["id"]?.intValue != nil }
    }

    /// El logo de un estudio (PNG con fondo transparente), si TMDB lo tiene.
    public func companyLogo(_ companyID: Int) async throws -> String? {
        Tmdb.image(try await get("/company/\(companyID)")["logo_path"], size: "w300")
    }

    /// Los estudios de Colecciones › Estudios (su id en TMDB).
    public static let studios: [(id: Int, name: String)] = [
        (41077, "A24"), (3, "Pixar"), (10342, "Studio Ghibli"), (420, "Marvel Studios"), (1, "Lucasfilm"),
        (3172, "Blumhouse"), (521, "DreamWorks Animation"), (90733, "NEON"),
    ]

    public func details(kind: String, tmdbID: Int) async throws -> TmdbDetails {
        let raw = try await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)", [("append_to_response", "external_ids")])
        let imdb = raw["imdb_id"]?.nonEmptyString ?? raw["external_ids"]?["imdb_id"]?.nonEmptyString
        func year(_ s: String?) -> Int? { s.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil } }
        func positive(_ j: JSON?) -> Int? { j?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        return TmdbDetails(
            kind: kind, tmdbID: raw["id"]?.intValue, imdb: imdb.flatMap { $0.hasPrefix("tt") ? $0 : nil },
            title: (raw["title"]?.nonEmptyString ?? raw["name"]?.nonEmptyString ?? "").trimmingCharacters(in: .whitespaces),
            year: year(raw["release_date"]?.string ?? raw["first_air_date"]?.string), overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            runtime: positive(raw["runtime"]), seasons: raw["number_of_seasons"]?.intValue, episodes: raw["number_of_episodes"]?.intValue,
            poster: Tmdb.image(raw["poster_path"]), backdrop: Tmdb.image(raw["backdrop_path"], size: "w1280"))
    }

    /// Título (sin año: el Top 10 de Netflix no lo trae) → id de IMDb del resultado más popular. Como `tmdb.search` de la TV.
    public func searchIMDb(kind: String, title: String) async throws -> String? {
        let data = try await get("/search/\(Tmdb.kinds[kind] ?? "movie")", [("query", title), ("include_adult", "false")])
        guard let id = data["results"]?.array?.first?["id"]?.intValue else { return nil }
        return try await details(kind: kind, tmdbID: id).imdb
    }

    /// El id de TMDB de un título de IMDb (nil si TMDB no lo tiene).
    public func findID(imdb: String, kind: String) async throws -> Int? {
        guard imdb.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return nil }
        let data = try await get("/find/\(imdb)", [("external_source", "imdb_id")])
        let rows = data[kind == "movie" ? "movie_results" : "tv_results"]?.array ?? []
        return rows.first?["id"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
    }

    /// La calificación de TMDB (0–10) de un título de IMDb, en la misma consulta de `find` (nil: TMDB no la tiene).
    public func rating(imdb: String, kind: String) async throws -> Double? {
        guard imdb.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return nil }
        let data = try await get("/find/\(imdb)", [("external_source", "imdb_id")])
        let row = data[kind == "movie" ? "movie_results" : "tv_results"]?.array?.first
        guard let votes = row?["vote_count"]?.intValue, votes >= Self.minVotes, let r = row?["vote_average"]?.doubleValue, r > 0 else { return nil }
        return r
    }
    /// El idioma original de un título de IMDb («es», «en», «ja»…), de la misma consulta de `find`; nil si TMDB no lo tiene.
    public func originalLanguage(imdb: String, kind: String) async throws -> String? {
        try await original(imdb: imdb, kind: kind).language
    }

    /// El idioma original y los nombres de un título (como `original` de la TV): para el audio de las versiones que no lo
    /// dicen y para notar las que traen otro título.
    public func original(imdb: String, kind: String) async throws -> (language: String?, titles: [String]) {
        guard imdb.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return (nil, []) }
        let data = try await get("/find/\(imdb)", [("external_source", "imdb_id")])
        let row = data[kind == "movie" ? "movie_results" : "tv_results"]?.array?.first
        var titles: [String] = []
        for key in ["title", "original_title", "name", "original_name"] {
            if let t = row?[key]?.string?.trimmingCharacters(in: .whitespaces), !t.isEmpty, !titles.contains(t) { titles.append(t) }
        }
        return (row?["original_language"]?.nonEmptyString, titles)
    }

    /// Con menos votos, la calificación de TMDB no dice mucho (un 9 con 3 votos).
    public static let minVotes = 20

    /// La saga de una película («Dune: colección»), si TMDB la tiene: su id y su nombre en tu idioma.
    public func collection(imdb: String) async throws -> (id: Int, name: String)? {
        guard let id = try await findID(imdb: imdb, kind: "movie") else { return nil }
        let data = try await get("/movie/\(id)")
        guard let saga = data["belongs_to_collection"], let sagaID = saga["id"]?.intValue, let name = saga["name"]?.nonEmptyString else { return nil }
        return (sagaID, name)
    }

    /// La ficha de un título de IMDb (lo de Trakt llega con sinopsis en inglés).
    public func find(imdb: String, kind: String) async throws -> TmdbDetails? {
        guard let id = try await findID(imdb: imdb, kind: kind) else { return nil }
        return try await details(kind: kind, tmdbID: id)
    }

    /// De `/translations` (envuelto en `translations`): la traducción de otro país del mismo idioma que sí tiene sinopsis.
    static func sameLanguage(_ raw: JSON, language: String) -> (title: String, overview: String)? {
        let base = language.split(separator: "-").first.map { String($0).lowercased() } ?? language
        for t in raw["translations"]?["translations"]?.array ?? [] where t["iso_639_1"]?.string?.lowercased() == base {
            let overview = (t["data"]?["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !overview.isEmpty else { continue }
            let title = (t["data"]?["title"]?.nonEmptyString ?? t["data"]?["name"]?.nonEmptyString ?? "").trimmingCharacters(in: .whitespaces)
            return (title, overview)
        }
        return nil
    }

    /// Título, sinopsis, géneros y (en series) los episodios en ese idioma.
    public func translation(kind: String, tmdbID: Int, language: String, episodes: Bool = false) async throws -> Translation {
        let raw = try await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)", [("language", language)])
        var found = Translation(
            title: (raw["title"]?.nonEmptyString ?? raw["name"]?.nonEmptyString ?? "").trimmingCharacters(in: .whitespaces),
            overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            genres: Array((raw["genres"]?.array ?? []).compactMap { $0["name"]?.string }.prefix(3)))
        // Sin sinopsis en «es-MX», la de otro país del mismo idioma (la de España) antes que el inglés de Cinemeta.
        if found.overview.isEmpty, let all = try? await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)/translations"),
           let other = Tmdb.sameLanguage(["translations": all], language: language) {
            found.overview = other.overview
            if !other.title.isEmpty { found.title = other.title }
        }
        guard episodes, kind == "series" else { return found }
        let numbers = (raw["seasons"]?.array ?? []).compactMap { $0["season_number"]?.intValue }.filter { $0 >= 0 }
        for start in stride(from: 0, to: numbers.count, by: 20) {  // TMDB: 20 por consulta
            let batch = Array(numbers[start..<min(start + 20, numbers.count)])
            let data = try await get("/tv/\(tmdbID)", [("language", language), ("append_to_response", batch.map { "season/\($0)" }.joined(separator: ","))])
            for n in batch {
                for ep in data["season/\(n)"]?["episodes"]?.array ?? [] {
                    guard let number = ep["episode_number"]?.intValue else { continue }
                    found.episodes[.init(season: n, episode: number)] = .init(
                        name: (ep["name"]?.string ?? "").trimmingCharacters(in: .whitespaces),
                        overview: (ep["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return found
    }
}

/// Fichas en el idioma de la app: Cinemeta solo habla inglés; TMDB pone título, sinopsis, géneros y episodios.
/// En inglés no se toca nada. Lo que TMDB no tiene traducido se queda como venía de Cinemeta.
public actor Localizer {
    public static let cacheSeconds: TimeInterval = 24 * 3600
    public static let retrySeconds: TimeInterval = 600
    static let regions = ["es": "es-MX", "pt": "pt-BR"]  // el español de México, no el de España
    /// Sin traducción, TMDB llama al episodio «Episodio 3»: mejor el título original de Cinemeta.
    static let genericEpisode = try! NSRegularExpression(pattern: #"^(episodio|episode|épisode|episódio|folge|episodio n\.?)\s*\d+$"#, options: [.caseInsensitive])

    /// «es» → «es-MX»; nil si no hay que traducir (inglés, o nada).
    public static func tmdbLanguage(_ language: String?) -> String? {
        let lang = (language ?? "").trimmingCharacters(in: .whitespaces)
        if lang.isEmpty || lang.lowercased().hasPrefix("en") { return nil }
        return regions[lang.lowercased()] ?? lang
    }

    private let tmdb: Tmdb
    private let language: @Sendable () -> String?
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, value: Translation?)] = [:]
    /// Lo que ya se está pidiendo: dos listas con el mismo título (Seguir viendo y Mi lista) comparten la petición.
    private var inflight: [String: Task<Translation?, Never>] = [:]
    /// Título, sinopsis y géneros en disco (sin episodios): al abrir la app ya salen en tu idioma, sin esperar a TMDB.
    private let store: KeyValueStore?
    private var disk: [String: Saved]?
    private var saveScheduled = false
    private struct Saved: Codable { var t: String; var o: String; var g: [String]; var d: Double }
    static let diskKey = "tmdb-translations", diskSeconds: TimeInterval = 7 * 24 * 3600, diskLimit = 3000
    /// Cuántas traducciones a la vez (antes, cientos juntas: TMDB contestaba 429 y se quedaban en inglés).
    static let concurrency = 8

    public init(tmdb: Tmdb, language: @escaping @Sendable () -> String?, clock: @escaping @Sendable () -> Date = { Date() }, store: KeyValueStore? = nil) {
        self.tmdb = tmdb; self.language = language; self.clock = clock; self.store = store
    }

    private func saved(_ key: String) -> Translation? {
        if disk == nil { disk = store?.data(Self.diskKey).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:] }
        guard let s = disk?[key], clock().timeIntervalSince1970 - s.d < Self.diskSeconds else { return nil }
        return Translation(title: s.t, overview: s.o, genres: s.g)
    }

    private func remember(_ key: String, _ t: Translation) {
        guard store != nil else { return }
        if disk == nil { _ = saved(key) }
        disk?[key] = Saved(t: t.title, o: t.overview, g: t.genres, d: clock().timeIntervalSince1970)
        if let count = disk?.count, count > Self.diskLimit, let oldest = disk?.sorted(by: { $0.value.d < $1.value.d }).prefix(count - Self.diskLimit).map(\.key) {
            for k in oldest { disk?[k] = nil }
        }
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { [weak self] in try? await Task.sleep(nanoseconds: 2_000_000_000); await self?.flush() }   // ds-exception: se juntan las escrituras a disco
    }

    private func flush() {
        saveScheduled = false
        if let disk, let data = try? JSONEncoder().encode(disk) { store?.set(Self.diskKey, data: data) }
    }

    public var active: String? { tmdb.configured ? Localizer.tmdbLanguage(language()) : nil }

    private func translation(kind: String, imdb: String, lang: String, episodes: Bool) async -> Translation? {
        let key = "\(lang)|\(imdb)|\(kind)|\(episodes)"
        if let hit = cache[key], clock() < hit.expires { return hit.value }
        if !episodes, let hit = saved(key) { cache[key] = (clock().addingTimeInterval(Localizer.cacheSeconds), hit); return hit }
        if let running = inflight[key] { return await running.value }
        let tmdb = tmdb
        let task = Task<Translation?, Never> {
            do {
                guard let id = try await tmdb.findID(imdb: imdb, kind: kind) else { return Translation() }
                return try await tmdb.translation(kind: kind, tmdbID: id, language: lang, episodes: episodes)
            } catch { return nil }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        // nil: falló (sin red, 429): se reintenta pronto. Vacío: TMDB no lo tiene; eso sí se recuerda.
        let value = result.flatMap { $0.isEmpty ? nil : $0 }
        if cache.count >= 500 { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(125).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(result == nil ? Localizer.retrySeconds : Localizer.cacheSeconds), value)
        if !episodes, let value { remember(key, value) }
        return value
    }

    /// Los nombres en tu idioma que ya se tienen (memoria o disco), sin pedir nada: así una búsqueda se ve traducida desde
    /// el primer momento en lo ya conocido, en vez de salir en inglés y cambiar al rato.
    public func knownTitles(kind: String, ids: [String]) -> [String: String] {
        guard let lang = active else { return [:] }
        var names: [String: String] = [:]
        for id in ids {
            let key = "\(lang)|\(id)|\(kind)|false"
            let found = cache[key].flatMap { clock() < $0.expires ? $0.value : nil } ?? saved(key)
            if let title = found?.title, !title.isEmpty { names[id] = title }
        }
        return names
    }

    /// La ficha en tu idioma (una copia; la original no se toca).
    public func meta(kind: String, meta: JSON) async -> JSON {
        let imdb = meta["imdb_id"]?.string ?? meta["id"]?.string
        guard let lang = active, kind == "movie" || kind == "series", let imdb, imdb.hasPrefix("tt"),
              let found = await translation(kind: kind, imdb: imdb, lang: lang, episodes: kind == "series"), !found.isEmpty else { return meta }
        return Localizer.apply(meta, found)
    }

    /// Título y sinopsis de una fila (sin episodios: una consulta por título).
    public func catalog(kind: String, metas: [JSON]) async -> [JSON] {
        guard let lang = active else { return metas }
        return await withTaskGroup(of: (Int, JSON).self) { group in
            var out = metas, next = 0
            func add() {
                guard next < metas.count else { return }
                let i = next, meta = metas[i]
                next += 1
                group.addTask {
                    guard let imdb = meta["id"]?.string, imdb.hasPrefix("tt"),
                          let found = await self.translation(kind: kind, imdb: imdb, lang: lang, episodes: false), !found.isEmpty else { return (i, meta) }
                    return (i, Localizer.apply(meta, found))
                }
            }
            for _ in 0..<Localizer.concurrency { add() }   // unas cuantas a la vez; al terminar una, entra la siguiente
            for await (i, meta) in group { out[i] = meta; add() }
            return out
        }
    }

    /// La ficha de Cinemeta con lo que TMDB tiene traducido; lo vacío se queda como estaba.
    public static func apply(_ meta: JSON, _ found: Translation) -> JSON {
        guard var out = meta.object else { return meta }
        if !found.title.isEmpty { out["name"] = .string(found.title) }
        if !found.overview.isEmpty { out["description"] = .string(found.overview) }
        if !found.genres.isEmpty { out["genres"] = .array(found.genres.map(JSON.string)) }
        if !found.episodes.isEmpty, let videos = meta["videos"]?.array {
            out["videos"] = .array(videos.map { video in
                guard var v = video.object, let season = video["season"]?.intValue, let episode = video["episode"]?.intValue,
                      let ep = found.episodes[.init(season: season, episode: episode)] else { return video }
                let generic = genericEpisode.firstMatch(in: ep.name, range: NSRange(ep.name.startIndex..., in: ep.name)) != nil
                if !ep.name.isEmpty && !generic { v["name"] = .string(ep.name); v["title"] = nil }
                if !ep.overview.isEmpty { v["overview"] = .string(ep.overview); v["description"] = nil }
                return .object(v)
            })
        }
        return .object(out)
    }
}
