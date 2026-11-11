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
    /// Hecho en este idioma: `title` es su título original (el logo de metahub, en inglés, no le queda).
    public var native = false
    /// Su póster en TMDB (la dirección completa): de reserva, para cuando metahub no lo tiene (uno de cada cuatro en Buscar).
    public var poster = ""
    public init(title: String = "", overview: String = "", genres: [String] = [], episodes: [Key: EpisodeText] = [:], native: Bool = false, poster: String = "") {
        self.title = title; self.overview = overview; self.genres = genres; self.episodes = episodes; self.native = native; self.poster = poster
    }
    public var isEmpty: Bool { title.isEmpty && overview.isEmpty && genres.isEmpty && episodes.isEmpty && poster.isEmpty }
}

public struct PlatformInfo: Sendable, Equatable { public var id: Int; public var logo: String? }

public struct TmdbDetails: Sendable, Equatable, Codable {
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
        ("paramount", "Paramount+", ["paramount plus", "paramount+"]),   // Fernando, 31 oct 2026
    ]

    let http: HTTPClient
    public let key: String
    public var language: String

    /// Lo ya pedido de `details` (en disco) y la fila de lo que sale a la red: los da quien arma la app (`Services`), para que
    /// todas las copias de `Tmdb` (se rearma al cambiar una clave) compartan la misma memoria y la misma fila. Antes eran
    /// globales (`static`) y la demostración escribía en la memoria de tu iPhone (auditoría, 31 oct 2026, B6).
    let memo: TmdbDetailsMemo?
    let gate: TmdbDetailsGate

    /// `memo` nil (pruebas): sin memoria. Sin `gate`, una fila propia de 6.
    public init(http: HTTPClient, key: String, language: String = "es-MX", memo: TmdbDetailsMemo? = nil, gate: TmdbDetailsGate? = nil) {
        self.http = http; self.key = key; self.language = language; self.memo = memo; self.gate = gate ?? TmdbDetailsGate()
    }
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
        guard let url = Tmdb.url(path, items) else {
            Log.network.error("TMDB: dirección inválida para \(path, privacy: .public)")
            throw TmdbError.network("dirección inválida")
        }
        let response: HTTPResponse
        do { response = try await http.send(HTTPRequest(url: url, headers: headers, timeout: 10)) } catch { throw TmdbError.network("\(error)") }
        if response.status == 401 { throw TmdbError.badKey }
        guard response.status == 200, let json = JSON.parse(response.data), json.object != nil else { throw TmdbError.http(response.status) }
        return json
    }

    /// La dirección de una consulta: la ruta se codifica (un id raro con espacios, «?» o «#» no rompe la dirección ni la
    /// app; antes era `URLComponents(string:)!`). nil si aun así no se puede armar.
    static func url(_ path: String, _ items: [(String, String)]) -> URL? {
        guard var components = URLComponents(string: api) else { return nil }
        components.path += path.hasPrefix("/") ? path : "/" + path   // `path` codifica lo que no va en una ruta
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url
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

    /// Lo que ya se pidió (14 días, en disco, `memo`): cada título de Temporadas, Plataformas y Estudios pide sus detalles para
    /// saber su IMDb, y eran ~260 peticiones en cada arranque (Fernando, 31 oct 2026: «está muy lenta»).
    /// `urgent`: lo pediste tú (abrir una ficha): no hace fila detrás de lo que se carga de fondo (auditoría, 31 oct 2026).
    public func details(kind: String, tmdbID: Int, urgent: Bool = false) async throws -> TmdbDetails {
        let memoKey = "\(language):\(kind):\(tmdbID)"
        if let memo, let hit = await memo.get(memoKey) { return hit }
        let fresh = urgent ? try await fetchDetails(kind: kind, tmdbID: tmdbID)
            : try await gate.details(memoKey) { try await fetchDetails(kind: kind, tmdbID: tmdbID) }
        if let memo, fresh.imdb != nil { await memo.set(memoKey, fresh) }
        return fresh
    }

    private func fetchDetails(kind: String, tmdbID: Int) async throws -> TmdbDetails {
        let raw = try await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)", [("append_to_response", "external_ids")])
        let imdb = raw["imdb_id"]?.nonEmptyString ?? raw["external_ids"]?["imdb_id"]?.nonEmptyString
        func year(_ s: String?) -> Int? { s.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil } }
        func positive(_ j: JSON?) -> Int? { j?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        return TmdbDetails(
            kind: kind, tmdbID: raw["id"]?.intValue, imdb: imdb.flatMap { $0.hasPrefix("tt") ? $0 : nil },
            title: (raw["title"]?.nonEmptyString ?? raw["name"]?.nonEmptyString ?? "").trimmingCharacters(in: .whitespaces),
            year: year(raw["release_date"]?.string ?? raw["first_air_date"]?.string), overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            // Una serie no trae `runtime`: lo que dura un capítulo viene en `episode_run_time` o en el último que salió (antes
            // siempre quedaba sin duración y «Series · Corta» dejaba pasar dramas de una hora).
            runtime: positive(raw["runtime"]) ?? positive(raw["episode_run_time"]?.array?.first) ?? positive(raw["last_episode_to_air"]?["runtime"]), seasons: raw["number_of_seasons"]?.intValue, episodes: raw["number_of_episodes"]?.intValue,
            poster: Tmdb.image(raw["poster_path"]), backdrop: Tmdb.image(raw["backdrop_path"], size: "w1280"))
    }

    /// Título (sin año: el Top 10 de Netflix no lo trae) → id de IMDb del resultado más popular. Como `tmdb.search` de la TV.
    public func searchIMDb(kind: String, title: String) async throws -> String? {
        let data = try await get("/search/\(Tmdb.kinds[kind] ?? "movie")", [("query", title), ("include_adult", "false")])
        guard let id = data["results"]?.array?.first?["id"]?.intValue else { return nil }
        return try await details(kind: kind, tmdbID: id).imdb
    }

    /// Una película por su título y año (lo que trae el archivo de Letterboxd) → su id de TMDB: la del año exacto, si no la
    /// más popular de ese nombre.
    public func searchMovieID(title: String, year: Int?) async throws -> Int? {
        var params = [("query", title), ("include_adult", "false")]
        if let year { params.append(("primary_release_year", String(year))) }
        let data = try await get("/search/movie", params)
        if let id = data["results"]?.array?.first?["id"]?.intValue { return id }
        guard year != nil else { return nil }
        return try await searchMovieID(title: title, year: nil)
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

    /// La calificación y los votos de TMDB de un título (sin piso de votos): «Qué tan conocida» en Decide por mí. nil: TMDB
    /// no lo tiene.
    public func stats(imdb: String, kind: String) async throws -> (average: Double, votes: Int)? {
        guard imdb.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return nil }
        let data = try await get("/find/\(imdb)", [("external_source", "imdb_id")])
        guard let row = data[kind == "movie" ? "movie_results" : "tv_results"]?.array?.first else { return nil }
        return (row["vote_average"]?.doubleValue ?? 0, row["vote_count"]?.intValue ?? 0)
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

    /// El mejor póster sin texto de un título (TMDB marca sin idioma los que no traen el nombre impreso): el arte de un marco alto,
    /// como la portada de la ficha en el iPhone. nil si no tiene.
    public func textlessPoster(kind: String, tmdbID: Int) async throws -> String? {
        let data = try await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)/images", [("include_image_language", "null")])
        let rows = (data["posters"]?.array ?? []).filter { $0["iso_639_1"]?.string == nil && $0["file_path"]?.string != nil }
        let best = rows.max { (a: JSON, b: JSON) -> Bool in Tmdb.posterRanksBelow(a, b) }
        return Tmdb.image(best?["file_path"], size: "w780")
    }

    /// Orden de los pósters sin texto: primero la calificación y, si empatan, los votos. Separado y con tipos explícitos
    /// porque la comparación de tuplas en línea hacía que el compilador de la CI se rindiera (31 oct 2026).
    static func posterRanksBelow(_ a: JSON, _ b: JSON) -> Bool {
        let averageA: Double = a["vote_average"]?.doubleValue ?? 0
        let averageB: Double = b["vote_average"]?.doubleValue ?? 0
        if averageA != averageB { return averageA < averageB }
        let countA: Double = a["vote_count"]?.doubleValue ?? 0
        let countB: Double = b["vote_count"]?.doubleValue ?? 0
        return countA < countB
    }

    /// La ficha de un título de IMDb (lo de Trakt llega con sinopsis en inglés).
    public func find(imdb: String, kind: String) async throws -> TmdbDetails? {
        guard let id = try await findID(imdb: imdb, kind: kind) else { return nil }
        return try await details(kind: kind, tmdbID: id)
    }

    /// El título original si el título está hecho en el idioma pedido («es» para «es-MX»); nil si es de otro idioma.
    static func originalTitle(_ raw: JSON, language: String) -> String? {
        let base = language.split(separator: "-").first.map { String($0).lowercased() } ?? language.lowercased()
        guard raw["original_language"]?.string?.lowercased() == base else { return nil }
        return (raw["original_title"]?.nonEmptyString ?? raw["original_name"]?.nonEmptyString)?.trimmingCharacters(in: .whitespaces)
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
            genres: Array((raw["genres"]?.array ?? []).compactMap { $0["name"]?.string }.prefix(3)),
            poster: Tmdb.image(raw["poster_path"], size: "w342") ?? "")
        // Sin sinopsis en «es-MX», la de otro país del mismo idioma (la de España) antes que el inglés de Cinemeta.
        if found.overview.isEmpty, let all = try? await get("/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)/translations"),
           let other = Tmdb.sameLanguage(["translations": all], language: language) {
            found.overview = other.overview
            // El título de otro país solo si aquí no hay (TMDB pone el original cuando no está traducido): «Eterno resplandor de
            // una mente sin recuerdos» no se vuelve «¡Olvídate de mí!» (el de España) por faltar la sinopsis. Análisis de fondo, 3 nov.
            let untranslated = found.title.isEmpty || found.title == (raw["original_title"]?.string ?? raw["original_name"]?.string)
            if !other.title.isEmpty, untranslated { found.title = other.title }
        }
        // Hecha en tu idioma: su título original. TMDB no traduce al mismo idioma y en «es-MX» da el inglés (Fernando, 3 nov:
        // «El viento tiene miedo», mexicana, salía «Even the Wind Is Afraid» y las series sí en español).
        if let original = Tmdb.originalTitle(raw, language: language) { found.title = original; found.native = true }
        guard episodes, kind == "series" else { return found }
        let numbers = (raw["seasons"]?.array ?? []).compactMap { $0["season_number"]?.intValue }.filter { $0 >= 0 }
        found.episodes = try await episodeTexts(tmdbID: tmdbID, seasons: numbers, language: language)
        // Respaldo (R4): lo que no está en el español de México, en el del mismo idioma de otro país («es»: el de España)
        // antes que el inglés de Cinemeta. Solo las temporadas a las que les falta algo.
        if let base = Tmdb.baseLanguage(language) {
            let missing = Set(found.episodes.filter { Tmdb.untranslated($0.value) }.map(\.key.season))
            if !missing.isEmpty, let other = try? await episodeTexts(tmdbID: tmdbID, seasons: numbers.filter(missing.contains), language: base) {
                for (key, text) in other {
                    guard var mine = found.episodes[key] else { continue }
                    if Tmdb.genericName(mine.name), !Tmdb.genericName(text.name) { mine.name = text.name }
                    if mine.overview.isEmpty { mine.overview = text.overview }
                    found.episodes[key] = mine
                }
            }
        }
        return found
    }

    /// Nombre y sinopsis de los episodios de esas temporadas en ese idioma (TMDB: 20 temporadas por consulta).
    private func episodeTexts(tmdbID: Int, seasons numbers: [Int], language: String) async throws -> [Translation.Key: Translation.EpisodeText] {
        var episodes: [Translation.Key: Translation.EpisodeText] = [:]
        for start in stride(from: 0, to: numbers.count, by: 20) {
            let batch = Array(numbers[start..<min(start + 20, numbers.count)])
            let data = try await get("/tv/\(tmdbID)", [("language", language), ("append_to_response", batch.map { "season/\($0)" }.joined(separator: ","))])
            for n in batch {
                for ep in data["season/\(n)"]?["episodes"]?.array ?? [] {
                    guard let number = ep["episode_number"]?.intValue else { continue }
                    episodes[.init(season: n, episode: number)] = .init(
                        name: (ep["name"]?.string ?? "").trimmingCharacters(in: .whitespaces),
                        overview: (ep["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return episodes
    }

    /// «es-MX» → «es» (el mismo idioma, de respaldo); nil si ya no tiene país.
    static func baseLanguage(_ language: String) -> String? {
        let parts = language.split(separator: "-")
        return parts.count > 1 ? String(parts[0]).lowercased() : nil
    }

    /// Sin nombre propio en ese idioma: vacío o «Episodio 3».
    static func genericName(_ name: String) -> Bool {
        name.isEmpty || Localizer.genericEpisode.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    static func untranslated(_ text: Translation.EpisodeText) -> Bool { genericName(text.name) || text.overview.isEmpty }
}


/// La memoria en disco de `Tmdb.details`: un archivo JSON con lo pedido y cuándo; lo de más de `ttl` se vuelve a pedir.
public actor TmdbDetailsMemo {
    private struct Entry: Codable { var at: Date; var value: TmdbDetails }
    private let file: URL
    private let ttl: TimeInterval
    private var entries: [String: Entry]?
    private var dirty = 0
    private var saving = false

    public init(file: URL, ttl: TimeInterval = 14 * 86400) { self.file = file; self.ttl = ttl }

    private func load() -> [String: Entry] {
        if let entries { return entries }
        let read = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let now = Date()
        let alive = read.filter { now.timeIntervalSince($0.value.at) < ttl }
        entries = alive
        return alive
    }

    public func get(_ key: String) -> TmdbDetails? {
        guard let e = load()[key], Date().timeIntervalSince(e.at) < ttl else { return nil }
        return e.value
    }

    public func set(_ key: String, _ value: TmdbDetails) {
        var all = load()
        all[key] = Entry(at: Date(), value: value)
        entries = all
        dirty += 1
        // Se escribe de a poco (no en cada título): un segundo después del último cambio.
        guard !saving else { return }
        saving = true
        Task { try? await Task.sleep(nanoseconds: 1_000_000_000); self.flush() }
    }

    private func flush() {
        saving = false
        guard dirty > 0, let entries, let data = try? JSONEncoder().encode(entries) else { return }
        dirty = 0
        try? data.write(to: file, options: .atomic)
    }
}

/// Los detalles de TMDB que salen a la red: unos cuantos a la vez entre todas las secciones (Para ti, Plataformas,
/// Temporadas, Estudios…) y uno solo por título aunque lo pidan dos secciones a la vez. Antes cada lista los pedía todos
/// de golpe (decenas al abrir Para ti) y competían con lo que se ve primero (Fernando, 31 oct 2026: tardaba ~5 s).
public actor TmdbDetailsGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var inflight: [String: Task<TmdbDetails, any Error>] = [:]

    public init(limit: Int = 6) { self.limit = limit }

    /// Quiénes siguen esperando cada título: si todos se van (saliste de Para ti), la petición se cancela; si aún no
    /// empezaba, ni sale. Antes se contaban hasta que la espera terminaba, así que con dos secciones esperando el mismo
    /// título y las dos fuera, cada una veía a la otra y nadie cancelaba (auditoría, 31 oct 2026, B9).
    private var waiters: [String: Set<Int>] = [:]
    private var nextWaiter = 0

    func details(_ key: String, _ fetch: @escaping @Sendable () async throws -> TmdbDetails) async throws -> TmdbDetails {
        let task: Task<TmdbDetails, any Error>
        if let running = inflight[key] { task = running } else {
            task = Task { try await self.limited(fetch) }
            inflight[key] = task
        }
        nextWaiter += 1
        let me = nextWaiter
        waiters[key, default: []].insert(me)
        defer { leave(key, me, task) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: {
            Task { await self.leave(key, me, task) }
        }
    }

    /// Quien esperaba se fue (o ya recibió lo suyo): si era el último, se cancela la petición y se suelta.
    private func leave(_ key: String, _ waiter: Int, _ task: Task<TmdbDetails, any Error>) {
        guard waiters[key]?.remove(waiter) != nil, waiters[key]?.isEmpty == true else { return }
        waiters[key] = nil
        task.cancel()   // si ya terminó, no hace nada
        if inflight[key] == task { inflight[key] = nil }
    }

    /// Cuántos títulos siguen en vuelo (pruebas).
    var inflightCount: Int { inflight.count }

    private func limited(_ fetch: @Sendable () async throws -> TmdbDetails) async throws -> TmdbDetails {
        if running < limit { running += 1 } else { await withCheckedContinuation { waiting.append($0) } }   // el lugar lo pasa quien termina
        // Si mientras esperaba lugar ya nadie la quiere, no sale a la red.
        if Task.isCancelled { release(); throw CancellationError() }
        do { let value = try await fetch(); release(); return value } catch { release(); throw error }
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}
