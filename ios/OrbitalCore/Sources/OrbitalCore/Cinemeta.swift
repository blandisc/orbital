import Foundation

public enum CinemetaError: Error, Sendable, CustomStringConvertible {
    case network(String), unexpected, notFound
    public var description: String {
        switch self {
        case .network(let reason): return "No pude leer el catálogo de Stremio: \(reason)"
        case .unexpected: return "Respuesta inesperada de Cinemeta"
        case .notFound: return "Título no encontrado"
        }
    }
}

public struct Episode: Sendable, Equatable, Identifiable {
    public var id: String
    public var episode: Int
    public var title: String
    public var thumbnail: String?
    public var overview: String
    public var released: String?
    /// `false` si no trae nombre propio («Episodio 5»): la interfaz puede mostrarlo en su idioma.
    public var hasTitle: Bool
}

public struct Season: Sendable, Equatable, Identifiable {
    public var season: Int
    public var episodes: [Episode]
    public var id: Int { season }
    public var isSpecials: Bool { season == 0 }
}

public struct MetaInfo: Sendable, Equatable {
    public var year: String
    public var rating: String
    public var genres: [String]
    public var description: String
    public var logo: String?
    public var runtime: String
    public init(year: String, rating: String, genres: [String], description: String, logo: String?, runtime: String) {
        self.year = year; self.rating = rating; self.genres = genres; self.description = description; self.logo = logo; self.runtime = runtime
    }
}

public struct Credits: Sendable, Equatable {
    public var cast: [String], directors: [String], writers: [String]
    public var released: String, awards: String, country: String
    public init(cast: [String], directors: [String], writers: [String], released: String, awards: String, country: String) {
        self.cast = cast; self.directors = directors; self.writers = writers; self.released = released; self.awards = awards; self.country = country
    }
}

public struct SearchResult: Sendable, Equatable, Identifiable {
    public var kind: String      // movie | series
    public var metaID: String
    public var title: String
    public var poster: String?
    public var year: String
    public var id: String { "\(kind):\(metaID)" }
}

/// Cinemeta: el catálogo público de Stremio (no necesita cuenta). La ficha original siempre viene de aquí,
/// en inglés; el idioma de la interfaz se aplica aparte (`Localizer`) y lo que se guarda en Stremio usa
/// SIEMPRE el nombre original.
public actor Cinemeta {
    public static let base = URL(string: "https://v3-cinemeta.strem.io")!
    public static let manifestURL = "https://v3-cinemeta.strem.io/manifest.json"
    static let cacheSeconds: TimeInterval = 6 * 3600
    static let cacheMax = 400

    private let http: HTTPClient
    private let root: URL
    private let registry: AddonRegistry?
    private let clock: @Sendable () -> Date
    private var cache: [URL: (expires: Date, json: JSON)] = [:]

    public init(http: HTTPClient, base: URL = Cinemeta.base, registry: AddonRegistry? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.root = base; self.registry = registry; self.clock = clock
    }

    private func get(_ url: URL) async throws -> JSON {
        let now = clock()
        if let hit = cache[url], now < hit.expires { return hit.json }
        let json: JSON?
        do { json = try await http.getJSON(url, timeout: 10) } catch { throw CinemetaError.network("\(error)") }
        guard let json, json.object != nil else { throw CinemetaError.unexpected }
        if cache.count >= Self.cacheMax {  // la caché no crece sin tope
            for key in cache.filter({ now >= $0.value.expires }).keys { cache[key] = nil }
            if cache.count >= Self.cacheMax { for key in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 4).map(\.key) { cache[key] = nil } }
        }
        cache[url] = (now.addingTimeInterval(Self.cacheSeconds), json)
        return json
    }

    private func url(_ path: String, base: String? = nil) -> URL? { URL(string: (base ?? root.absoluteString) + path) }

    /// Lo más popular (`top`), o lo más popular de un género de Cinemeta («Action», «Sci-Fi»: los nombres en inglés).
    public func catalog(_ kind: String, genre: String? = nil) async throws -> [JSON] {
        let path = genre.map { "/catalog/\(kind)/top/genre=\(uriComponent($0)).json" } ?? "/catalog/\(kind)/top.json"
        guard let url = url(path) else { throw CinemetaError.unexpected }
        return CinemetaParsing.usable(try await get(url)["metas"]?.array)
    }

    /// Búsqueda tolerante a errores («ofice» encuentra The Office); 2-3 letras suelen bastar.
    public func search(_ kind: String, query: String) async throws -> [JSON] {
        let q = uriComponent(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = url("/catalog/\(kind)/top/search=\(q).json") else { throw CinemetaError.unexpected }
        return CinemetaParsing.usable(try await get(url)["metas"]?.array)
    }

    /// Películas y series juntas, alternando tipos.
    public func searchAll(_ query: String, limit: Int = 18) async throws -> [SearchResult] {
        async let movies = search("movie", query: query)
        async let series = search("series", query: query)
        return CinemetaParsing.searchResults(query: query, movies: try await movies, series: try await series, limit: limit)
    }

    /// De dónde pedir la ficha, en orden (nil = Cinemeta). Un id de IMDb, primero Cinemeta; otro (kitsu:…),
    /// primero los complementos que saben de él.
    func metaSources(kind: String, metaID: String) async -> [String?] {
        let others = ((try? await registry?.addons()) ?? []).filter { $0.handles("meta", kind: kind, itemID: metaID) && $0.base != root.absoluteString }.map(\.base)
        return metaID.hasPrefix("tt") ? [nil] + others : others + [nil]
    }

    /// La ficha ORIGINAL (sin traducir).
    public func meta(kind: String, id: String) async throws -> JSON {
        let path = "/meta/\(uriComponent(kind))/\(uriComponent(id, safe: ":")).json"
        var failure: Error = CinemetaError.notFound
        for source in await metaSources(kind: kind, metaID: id) {
            guard let url = url(path, base: source) else { continue }
            do {
                if let meta = try await get(url)["meta"], meta.object != nil { return meta }
            } catch { failure = error }
        }
        throw failure
    }
}

/// Las partes de Cinemeta que no necesitan red (se prueban con las respuestas guardadas de Python).
public enum CinemetaParsing {
    static func list(_ value: JSON?) -> [JSON] { value?.array ?? [] }

    /// Un título con id y nombre de texto: un nombre numérico (1917) o una lista tumbaban la biblioteca.
    public static func isUsable(_ meta: JSON) -> Bool {
        meta.object != nil && (meta["id"]?.string.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false)
            && (meta["name"]?.string.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false)
    }
    public static func usable(_ metas: [JSON]?) -> [JSON] { (metas ?? []).filter(isUsable) }

    public static func medium(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        return url.replacingOccurrences(of: "/poster/small/", with: "/poster/medium/")
    }

    private static func text(_ json: JSON?) -> String {
        switch json {
        case .string(let s)?: return s
        case .int(let i)?: return String(i)
        case .double(let d)?: return String(d)
        default: return ""
        }
    }

    public static func describe(_ meta: JSON) -> MetaInfo {
        let rating = text(meta["imdbRating"]).trimmingCharacters(in: .whitespaces)
        let year = (text(meta["releaseInfo"]).isEmpty ? text(meta["year"]) : text(meta["releaseInfo"])).trimmingCharacters(in: .whitespaces)
        let genres = (meta["genres"]?.array ?? meta["genre"]?.array ?? []).compactMap(\.string)
        return MetaInfo(year: year, rating: rating == "0" ? "" : rating, genres: Array(genres.prefix(3)),
                        description: text(meta["description"]).trimmingCharacters(in: .whitespacesAndNewlines),
                        logo: meta["logo"]?.string, runtime: text(meta["runtime"]).trimmingCharacters(in: .whitespaces))
    }

    static func names(_ value: JSON?) -> [String] {
        if let s = value?.string { return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return (value?.array ?? []).map { text($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Reparto, dirección, guion, estreno y premios (Cinemeta los trae).
    public static func credits(_ meta: JSON) -> Credits {
        var byCategory: [String: [String]] = [:]
        for link in list(meta["links"]) {
            if let name = link["name"]?.nonEmptyString { byCategory[text(link["category"]).lowercased(), default: []].append(name) }
        }
        let cast = names(meta["cast"]).isEmpty ? byCategory["cast", default: []] : names(meta["cast"])
        let directors = names(meta["director"]).isEmpty ? byCategory["directors", default: []] : names(meta["director"])
        let writers = names(meta["writer"]).isEmpty ? byCategory["writers", default: []] : names(meta["writer"])
        return Credits(cast: Array(cast.prefix(6)), directors: Array(directors.prefix(3)), writers: Array(writers.prefix(3)),
                       released: String(text(meta["released"]).prefix(10)), awards: text(meta["awards"]).trimmingCharacters(in: .whitespaces),
                       country: text(meta["country"]).trimmingCharacters(in: .whitespaces))
    }

    /// Temporadas con sus episodios, en orden; los especiales (temporada 0) al final.
    public static func seasons(_ meta: JSON) -> [Season] {
        var bySeason: [Int: [Episode]] = [:]
        for video in list(meta["videos"]) {
            guard let season = video["season"]?.intValue, let episode = video["episode"]?.intValue, case .int = video["season"]!, case .int = video["episode"]!,
                  let id = video["id"]?.nonEmptyString else { continue }
            let named = text(video["name"]).isEmpty ? text(video["title"]) : text(video["name"])
            let overview = text(video["overview"]).isEmpty ? text(video["description"]) : text(video["overview"])
            bySeason[season, default: []].append(Episode(
                id: id, episode: episode, title: named.isEmpty ? "Episodio \(episode)" : named, thumbnail: video["thumbnail"]?.nonEmptyString,
                overview: overview.trimmingCharacters(in: .whitespacesAndNewlines), released: video["released"]?.nonEmptyString, hasTitle: !named.isEmpty))
        }
        let order = bySeason.keys.sorted { ($0 == 0 ? 1 : 0, $0) < ($1 == 0 ? 1 : 0, $1) }
        return order.map { Season(season: $0, episodes: bySeason[$0]!.sorted { $0.episode < $1.episode }) }
    }

    /// El episodio que sigue a `videoID` (pasa de temporada; los especiales no cuentan).
    public static func nextEpisode(_ meta: JSON, after videoID: String) -> String? {
        let ids = seasons(meta).filter { $0.season != 0 }.flatMap { $0.episodes.map(\.id) }
        guard let i = ids.firstIndex(of: videoID), i + 1 < ids.count else { return nil }
        return ids[i + 1]
    }

    /// Une películas y series alternando tipos y respetando el orden de Cinemeta; solo sube una coincidencia exacta.
    public static func searchResults(query: String, movies: [JSON], series: [JSON], limit: Int = 18) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var merged: [(String, JSON)] = []
        for i in 0..<min(series.count, movies.count) { merged.append(("series", series[i])); merged.append(("movie", movies[i])) }
        let longer = series.count > movies.count ? series : movies
        let kindLeft = series.count > movies.count ? "series" : "movie"
        merged += longer.dropFirst(min(series.count, movies.count)).map { (kindLeft, $0) }
        let exact = merged.filter { $0.1["name"]?.string?.trimmingCharacters(in: .whitespaces).lowercased() == q }
        let rest = merged.filter { $0.1["name"]?.string?.trimmingCharacters(in: .whitespaces).lowercased() != q }  // estable
        var seen = Set<String>(), results: [SearchResult] = []
        for (kind, meta) in exact + rest {
            guard let id = meta["id"]?.string, seen.insert(id).inserted else { continue }
            let info = describe(meta)
            results.append(SearchResult(kind: kind, metaID: id, title: meta["name"]?.string ?? "", poster: medium(meta["poster"]?.string), year: info.year))
            if results.count >= limit { break }
        }
        return results
    }
}
