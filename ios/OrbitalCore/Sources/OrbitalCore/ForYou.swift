import Foundation

/// Por qué se te sugiere algo (la interfaz lo pone en tu idioma: «Recomendada», «En tu lista»…).
public enum SuggestionReason: Sendable, Equatable, Hashable {
    case recommended, watching, inWatchlist, inList(String), trending, popular, onPlatform(String)
}

/// Una sugerencia: una película o serie (siempre con IMDb: sin él no se podrían pedir fuentes).
public struct Suggestion: Sendable, Equatable, Identifiable {
    public var kind: String            // movie | series
    public var imdb: String
    public var title: String
    public var year: Int?
    public var runtime: Int?
    public var overview: String
    public var poster: String
    public var wide: String
    public var reason: SuggestionReason
    public var next: (season: Int, episode: Int)?
    public var id: String { imdb }

    public init(kind: String, imdb: String, title: String, year: Int? = nil, runtime: Int? = nil, overview: String = "", poster: String, wide: String,
                reason: SuggestionReason, next: (season: Int, episode: Int)? = nil) {
        self.kind = kind; self.imdb = imdb; self.title = title; self.year = year; self.runtime = runtime; self.overview = overview
        self.poster = poster; self.wide = wide; self.reason = reason; self.next = next
    }

    public static func == (a: Suggestion, b: Suggestion) -> Bool {
        a.kind == b.kind && a.imdb == b.imdb && a.title == b.title && a.year == b.year && a.reason == b.reason
            && a.poster == b.poster && a.next?.season == b.next?.season && a.next?.episode == b.next?.episode
    }
}

public enum ForYouGroup: String, Sendable { case mine, discover, platforms }

public struct ForYouList: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String           // nombre propio (listas de Trakt, plataformas); vacío = la interfaz lo nombra
    public var group: ForYouGroup
    public var brand: String?          // netflix | disney | hbo
    public var logo: String?
    public var splitsKinds: Bool       // tiene «Series | Películas»
}

/// «Para ti»: lo tuyo (Trakt) y lo popular en tus plataformas (TMDB), siempre de películas y series. Cada fuente
/// es opcional y una que falla no tumba a las demás: su lista queda vacía y se reintenta más tarde.
public actor ForYou {
    public static let mineTTL: TimeInterval = 15 * 60
    public static let recsTTL: TimeInterval = 3600
    public static let popularTTL: TimeInterval = 6 * 3600
    public static let slowTTL: TimeInterval = 24 * 3600
    public static let mosaicSize = 48
    static let metahubPoster = "https://images.metahub.space/poster/medium/%@/img"
    static let metahubBackground = "https://images.metahub.space/background/medium/%@/img"

    private let trakt: Trakt?
    private let tmdb: Tmdb?
    private let region: @Sendable () -> String
    private let kv: KeyValueStore
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, value: Any)] = [:]
    private var dismissed: Set<String>

    public init(trakt: Trakt?, tmdb: Tmdb?, region: @escaping @Sendable () -> String, kv: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.trakt = trakt; self.tmdb = tmdb; self.region = region; self.kv = kv; self.clock = clock
        dismissed = Set(kv.data("foryou-dismissed").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }

    public var traktLinked: Bool { trakt?.linked ?? false }
    public var traktConfigured: Bool { trakt?.configured ?? false }
    public var tmdbConfigured: Bool { tmdb?.configured ?? false }

    private func remember<T>(_ key: String, ttl: TimeInterval, _ load: () async throws -> T) async throws -> T {
        if let hit = cache[key], clock() < hit.expires, let value = hit.value as? T { return value }
        let value = try await load()
        cache[key] = (clock().addingTimeInterval(ttl), value)
        return value
    }

    public func clearCache() { cache.removeAll() }

    /// «No me interesa»: esa sugerencia no vuelve a salir.
    /// Lo que marcaste «No me interesa» (también vale para el mosaico de lo popular).
    public func dismissedIDs() -> Set<String> { dismissed }

    public func dismiss(_ imdb: String) {
        dismissed.insert(imdb)
        kv.set("foryou-dismissed", data: try? JSONEncoder().encode(Array(dismissed)))
    }

    // MARK: listas disponibles
    public func platforms() async -> [String: PlatformInfo] {
        guard let tmdb, tmdb.configured else { return [:] }
        return (try? await remember("tmdb:platforms", ttl: Self.slowTTL) { try await tmdb.platforms(region: region()) }) ?? [:]
    }

    public func lists() async -> [ForYouList] {
        var out: [ForYouList] = []
        if let trakt, trakt.linked {
            out += [ForYouList(id: "watchlist", title: "", group: .mine, brand: nil, logo: nil, splitsKinds: false),
                    ForYouList(id: "mine", title: "", group: .mine, brand: nil, logo: nil, splitsKinds: false)]
            let own = (try? await remember("trakt:lists", ttl: Self.mineTTL) { try await trakt.lists() }) ?? []
            out += own.prefix(8).map { ForYouList(id: "list:\($0.id)", title: $0.name, group: .mine, brand: nil, logo: nil, splitsKinds: false) }
            out.append(ForYouList(id: "recs", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true))
        }
        if let trakt, trakt.configured {
            out += [ForYouList(id: "trend", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true),
                    ForYouList(id: "popular", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true)]
        }
        let found = await platforms()
        for p in Tmdb.platforms where found[p.brand] != nil {
            out.append(ForYouList(id: p.brand, title: p.name, group: .platforms, brand: p.brand, logo: found[p.brand]?.logo, splitsKinds: true))
        }
        return out
    }

    // MARK: contenido de una lista
    public func items(listID: String, kind: String? = nil) async throws -> [Suggestion] {
        let kind = kind == "movie" ? "movie" : "series"
        return try await raw(listID: listID, kind: kind).filter { !dismissed.contains($0.imdb) }
    }

    private func suggestion(_ e: TraktEntry, _ reason: SuggestionReason) -> Suggestion {
        Suggestion(kind: e.kind, imdb: e.imdb, title: e.title, year: e.year, runtime: e.runtime, overview: e.overview,
                   poster: String(format: Self.metahubPoster, e.imdb), wide: String(format: Self.metahubBackground, e.imdb), reason: reason, next: e.next)
    }

    private func raw(listID: String, kind: String) async throws -> [Suggestion] {
        if let trakt, ["recs", "mine", "watchlist", "trend", "popular"].contains(listID) || listID.hasPrefix("list:") {
            switch listID {
            case "recs": return try await remember("trakt:recs:\(kind)", ttl: Self.recsTTL) { try await trakt.recommendations(kind: kind) }.map { suggestion($0, .recommended) }
            case "mine": return try await remember("trakt:watching", ttl: Self.mineTTL) { try await trakt.watching() }.map { suggestion($0, .watching) }
            case "watchlist": return try await remember("trakt:watchlist", ttl: Self.mineTTL) { try await trakt.watchlist() }.map { suggestion($0, .inWatchlist) }
            case "trend": return try await remember("trakt:trend:\(kind)", ttl: Self.recsTTL) { try await trakt.trending(kind: kind) }.map { suggestion($0, .trending) }
            case "popular": return try await remember("trakt:popular:\(kind)", ttl: Self.popularTTL) { try await trakt.popular(kind: kind) }.map { suggestion($0, .popular) }
            default:
                let id = String(listID.dropFirst("list:".count))
                let name = ((try? await remember("trakt:lists", ttl: Self.mineTTL) { try await trakt.lists() }) ?? []).first { $0.id == id }?.name ?? ""
                return try await remember("trakt:list:\(id)", ttl: Self.mineTTL) { try await trakt.listItems(id) }.map { suggestion($0, .inList(name)) }
            }
        }
        if let platform = Tmdb.platforms.first(where: { $0.brand == listID }) { return try await platformItems(platform, kind: kind) }
        throw TraktError.invalid("Lista desconocida")
    }

    private func platformItems(_ platform: (brand: String, name: String, aliases: [String]), kind: String) async throws -> [Suggestion] {
        guard let tmdb, let info = await platforms()[platform.brand] else { return [] }
        return try await remember("tmdb:\(platform.brand):\(kind)", ttl: Self.popularTTL) {
            let rows = try await tmdb.discover(kind: kind, providerID: info.id, region: region()).prefix(20)
            let details = await withTaskGroup(of: (Int, TmdbDetails?).self) { group in
                for (i, row) in rows.enumerated() {
                    group.addTask { (i, try? await tmdb.details(kind: kind, tmdbID: row["id"]!.intValue!)) }  // una que falla se salta
                }
                var out = [TmdbDetails?](repeating: nil, count: rows.count)
                for await (i, d) in group { out[i] = d }
                return out
            }
            return details.compactMap { d -> Suggestion? in
                guard let d, let imdb = d.imdb, !d.title.isEmpty else { return nil }
                return Suggestion(kind: kind, imdb: imdb, title: d.title, year: d.year, runtime: d.runtime, overview: d.overview,
                                  poster: d.poster ?? String(format: Self.metahubPoster, imdb), wide: d.backdrop ?? String(format: Self.metahubBackground, imdb),
                                  reason: .onPlatform(platform.name), next: nil)
            }
        }
    }

    // MARK: mosaico
    /// Lo tuyo mezclado: tus recomendaciones, tu watchlist, tus listas y lo que sigues. Sin Trakt conectado, lo que
    /// está en tendencia (o lo popular en tus plataformas). Solo películas y series.
    public func mosaic() async -> [Suggestion] {
        var sources: [(String, String)] = []
        if let trakt, trakt.linked {
            sources = [("recs", "series"), ("recs", "movie"), ("watchlist", "series"), ("mine", "series")]
            let own = (try? await remember("trakt:lists", ttl: Self.mineTTL) { try await trakt.lists() }) ?? []
            sources += own.prefix(3).map { ("list:\($0.id)", "series") }
        } else if let trakt, trakt.configured {
            sources = [("trend", "series"), ("trend", "movie")]
        } else {
            let brands = await platforms().keys.sorted()
            sources = brands.flatMap { [($0, "series"), ($0, "movie")] }
        }
        let batches = await withTaskGroup(of: (Int, [Suggestion]).self) { group in
            for (i, source) in sources.enumerated() {
                group.addTask { (i, Array(((try? await self.items(listID: source.0, kind: source.1)) ?? []).prefix(10))) }
            }
            var out = [[Suggestion]](repeating: [], count: sources.count)
            for await (i, b) in group { out[i] = b }
            return out
        }
        return Self.interleave(batches, limit: Self.mosaicSize)
    }

    /// Una de cada fuente por turno (así el mosaico no es solo recomendaciones), sin repetir.
    public static func interleave(_ batches: [[Suggestion]], limit: Int) -> [Suggestion] {
        var out: [Suggestion] = [], seen = Set<String>(), i = 0
        while batches.contains(where: { i < $0.count }) && out.count < limit {
            for batch in batches where i < batch.count && seen.insert(batch[i].imdb).inserted { out.append(batch[i]) }
            i += 1
        }
        return Array(out.prefix(limit))
    }

    /// Los títulos de tu watchlist (para la etiqueta «En tu lista» en cualquier póster).
    public func watchlistKeys() async -> Set<String> {
        guard let trakt, trakt.linked else { return [] }
        return Set(((try? await remember("trakt:watchlist", ttl: Self.mineTTL) { try await trakt.watchlist() }) ?? []).map(\.imdb))
    }
}
