import Foundation

/// Por qué se te sugiere algo (la interfaz lo pone en tu idioma: «Recomendada», «En tu lista»…).
public enum SuggestionReason: Sendable, Equatable, Hashable {
    case recommended, watching, inWatchlist, inList(String), trending, popular, onPlatform(String)
    /// El motivo tal como lo dice tu Orbital (uno que el iPhone no calcula por sí mismo): se enseña igual que en la TV.
    case console(String)
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
    /// Logo del título (metahub), como en la TV; si no carga o no hay, la interfaz cae al nombre en texto.
    public var logo: String?
    public var reason: SuggestionReason
    public var next: (season: Int, episode: Int)?
    /// El puesto en un Top 10 (chart de Netflix, JustWatch…), si la lista lo trae. Nil: no se pinta número.
    public var rank: Int?
    /// Cuántos lugares subió (+) o bajó (−) en su lista desde la foto anterior; nil si no hay foto (no se inventan flechas).
    public var movement: Int?
    /// Entró a la lista en esta foto (semana o día).
    public var isNew = false
    public var id: String { imdb }

    public init(kind: String, imdb: String, title: String, year: Int? = nil, runtime: Int? = nil, overview: String = "", poster: String, wide: String,
                logo: String? = nil, reason: SuggestionReason, next: (season: Int, episode: Int)? = nil, rank: Int? = nil) {
        self.kind = kind; self.imdb = imdb; self.title = title; self.year = year; self.runtime = runtime; self.overview = overview
        self.poster = poster; self.wide = wide; self.logo = logo; self.reason = reason; self.next = next; self.rank = rank
    }

    public static func == (a: Suggestion, b: Suggestion) -> Bool {
        a.kind == b.kind && a.imdb == b.imdb && a.title == b.title && a.year == b.year && a.reason == b.reason
            && a.poster == b.poster && a.next?.season == b.next?.season && a.next?.episode == b.next?.episode
    }
}

public enum ForYouGroup: String, Sendable { case mine, discover, platforms }

/// Un día de «Próximos estrenos» con lo que sale (vacío en la semana: «Nada este día»).
public struct AiringDay: Sendable, Equatable, Identifiable {
    public var day: Date
    public var airings: [Airing]
    public var id: Date { day }

    /// Por día: solo los días con estrenos, en orden.
    public static func byDay(_ airings: [Airing]) -> [AiringDay] {
        var out: [AiringDay] = []
        for a in airings {
            if out.last?.day == a.day { out[out.count - 1].airings.append(a) } else { out.append(AiringDay(day: a.day, airings: [a])) }
        }
        return out
    }

    /// La semana desde hoy: siete días, también los que no tienen nada.
    public static func week(_ airings: [Airing], from now: Date, calendar: Calendar = .current, days: Int = 7) -> [AiringDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .map { day in AiringDay(day: day, airings: airings.filter { $0.day == day }) }
    }
}

/// Un estreno de «Próximos estrenos»: la serie (pulsar abre su ficha), el día y la hora de aquí, el episodio y dónde sale.
/// Varios episodios de la misma serie el mismo día (las plataformas sueltan tres juntos) son uno solo: «T2 E4–E6».
public struct Airing: Sendable, Equatable, Identifiable {
    public var series: Suggestion
    public var season: Int
    public var first: Int
    public var last: Int
    public var count: Int
    public var episodeTitle: String
    public var aired: Date
    /// El día (a medianoche, en la hora de aquí).
    public var day: Date
    public var network: String
    /// Sale antes de las 6 de la mañana (lo de streaming): «Desde la madrugada» en vez de la hora.
    public var atDawn: Bool
    public var id: String { "\(series.imdb):\(Int(day.timeIntervalSince1970))" }
    /// Un episodio como lo escribe la TV en español («T2 E5»): lo que se usa si la interfaz no da otro.
    public static let spanishEpisode: @Sendable (Int, Int) -> String = { "T\($0) E\($1)" }
    public var episodeLabel: String { episodeLabel(Self.spanishEpisode) }
    /// «T2 E4–E6» / «S2 E4–E6»: con cómo se escribe un episodio en el idioma de la app (`Services.episodeLabel`).
    public func episodeLabel(_ episode: (Int, Int) -> String) -> String { count > 1 ? "\(episode(season, first))–E\(last)" : episode(season, first) }
}

public struct ForYouList: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String           // nombre propio (listas de Trakt, plataformas); vacío = la interfaz lo nombra
    public var group: ForYouGroup
    public var brand: String?          // netflix | disney | hbo
    public var logo: String?
    public var splitsKinds: Bool       // tiene «Series | Películas»
    /// De dónde sale («Trakt», «Stremio», «Netflix», «JustWatch»…) y el dato secundario del estante («Esta semana en
    /// México»). Solo los trae la consola; local, la interfaz los pone según el id.
    public var source = ""
    public var meta = ""

    public init(id: String, title: String, group: ForYouGroup, brand: String? = nil, logo: String? = nil, splitsKinds: Bool, source: String = "", meta: String = "") {
        self.id = id; self.title = title; self.group = group; self.brand = brand; self.logo = logo; self.splitsKinds = splitsKinds
        self.source = source; self.meta = meta
    }
}

/// «Para ti»: lo tuyo (Trakt) y lo popular en tus plataformas (TMDB), siempre de películas y series. Cada fuente
/// es opcional y una que falla no tumba a las demás: su lista queda vacía y se reintenta más tarde.
public actor ForYou {
    public static let mineTTL: TimeInterval = 15 * 60
    public static let recsTTL: TimeInterval = 3600
    public static let popularTTL: TimeInterval = 6 * 3600
    public static let slowTTL: TimeInterval = 24 * 3600
    public static let mosaicSize = 48
    public static let calendarDays = 14
    public static let dawnHour = 6
    public static let metahubPoster = "https://images.metahub.space/poster/medium/%@/img"
    public static let metahubBackground = "https://images.metahub.space/background/medium/%@/img"
    static let metahubLogo = "https://images.metahub.space/logo/medium/%@/img"

    private let trakt: Trakt?
    private let tmdb: Tmdb?
    /// Las listas con puesto (Top 10 de Netflix, tendencias de JustWatch), calculadas en el iPhone.
    private let charts: Charts?
    /// Tus complementos de Stremio (sus catálogos son estantes) y con qué pedir cada catálogo.
    private let addons: AddonRegistry?
    private let http: HTTPClient?
    private let region: @Sendable () -> String
    private let kv: KeyValueStore
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, value: Any)] = [:]
    private var dismissed: Set<String>

    public init(trakt: Trakt?, tmdb: Tmdb?, charts: Charts? = nil, addons: AddonRegistry? = nil, http: HTTPClient? = nil,
                region: @escaping @Sendable () -> String, kv: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.trakt = trakt; self.tmdb = tmdb; self.charts = charts; self.addons = addons; self.http = http
        self.region = region; self.kv = kv; self.clock = clock
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
                    ForYouList(id: "mine", title: "", group: .mine, brand: nil, logo: nil, splitsKinds: false),
                    ForYouList(id: "estrenos", title: "", group: .mine, brand: nil, logo: nil, splitsKinds: false)]
            let own = (try? await remember("trakt:lists", ttl: Self.mineTTL) { try await trakt.lists() }) ?? []
            out += own.prefix(8).map { ForYouList(id: "list:\($0.id)", title: $0.name, group: .mine, brand: nil, logo: nil, splitsKinds: false) }
            out.append(ForYouList(id: "recs", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true))
        }
        if let trakt, trakt.configured {
            out += [ForYouList(id: "trend", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true),
                    ForYouList(id: "popular", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: true)]
        }
        // Los catálogos de tus complementos de Stremio (como `addon_catalogs` en la TV).
        for entry in await addonCatalogs() {
            out.append(ForYouList(id: entry.id, title: entry.title, group: .discover, brand: nil, logo: nil, splitsKinds: entry.kinds.count > 1,
                                  source: "Stremio", meta: "De \(entry.addon)"))
        }
        // Las listas con puesto, como en la TV: el Top 10 oficial de Netflix y la tendencia de cada plataforma en JustWatch.
        // Ninguna pide clave; si una no trae nada, su estante no se pinta (y entra el respaldo de TMDB de esa marca).
        if charts != nil {
            let country = Self.countryName(region())
            out.append(ForYouList(id: "chart:netflix", title: "Top 10 en Netflix", group: .platforms, brand: "netflix", logo: Charts.netflixLogo,
                                  splitsKinds: true, source: "Netflix", meta: "Esta semana en \(country)"))
            for p in Charts.justWatchPlatforms {
                out.append(ForYouList(id: "jw:\(p.brand)", title: "Tendencias en \(p.name)", group: .platforms, brand: p.brand, logo: Charts.justWatchLogo(p.brand),
                                      splitsKinds: true, source: "JustWatch", meta: "Tendencia en JustWatch · \(country)"))
            }
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

    /// «Porque viste X»: lo último que viste (película o serie) y lo que Trakt relaciona con él, sin lo que ya descartaste.
    public func becauseYouWatched() async -> (seed: TraktEntry, items: [Suggestion])? {
        guard let trakt, trakt.linked,
              let seed = try? await remember("trakt:recent", ttl: Self.mineTTL, { try await trakt.recentlyWatched(limit: 1) }).first else { return nil }
        let related = (try? await remember("trakt:related:\(seed.imdb)", ttl: Self.recsTTL) { try await trakt.related(kind: seed.kind, imdb: seed.imdb) }) ?? []
        let items = related.map { suggestion($0, .recommended) }.filter { !dismissed.contains($0.imdb) }
        return items.isEmpty ? nil : (seed, items)
    }

    /// «Tu año»: lo que viste desde el 1 de enero, del historial de Trakt (se guarda unas horas: son varias páginas).
    public func yearInReview(calendar: Calendar = .current) async -> YearInReview? {
        guard let trakt, trakt.linked else { return nil }
        let now = clock()
        guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)) else { return nil }
        guard let plays = try? await remember("trakt:year:\(calendar.component(.year, from: now))", ttl: Self.recsTTL, { try await trakt.plays(since: start, until: now) }) else { return nil }
        return YearInReview.make(plays, year: calendar.component(.year, from: now), calendar: calendar)
    }

    private func suggestion(_ e: TraktEntry, _ reason: SuggestionReason) -> Suggestion {
        Suggestion(kind: e.kind, imdb: e.imdb, title: e.title, year: e.year, runtime: e.runtime, overview: e.overview,
                   poster: String(format: Self.metahubPoster, e.imdb), wide: String(format: Self.metahubBackground, e.imdb),
                   logo: String(format: Self.metahubLogo, e.imdb), reason: reason, next: e.next)
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
        if listID.hasPrefix("addon:"), let entry = await addonCatalogs().first(where: { $0.id == listID }) {
            return try await remember("\(listID):\(kind)", ttl: Self.recsTTL) { try await addonItems(entry, kind: kind) }
        }
        if let charts, listID == "chart:netflix" { return try await charts.netflix(kind: kind).map { chartSuggestion($0, kind: kind, platform: "Netflix") } }
        if let charts, listID.hasPrefix("jw:"), let p = Charts.justWatchPlatforms.first(where: { "jw:\($0.brand)" == listID }) {
            return try await charts.justWatch(brand: p.brand, kind: kind).map { chartSuggestion($0, kind: kind, platform: p.name) }
        }
        throw TraktError.invalid("Lista desconocida")
    }

    // MARK: catálogos de complementos
    struct AddonCatalog: Sendable { var id: String; var title: String; var addon: String; var base: String; var catalog: String; var kinds: [String] }

    static let skipAddons = ["cinemeta", "torrent", "opensubtitles", "local files"]
    static let traktAddon = "trakt integration"
    static let genericCatalogs: Set<String> = ["popular", "year", "language", "search", "new", "featured", "top seeded", "trending",
                                               "last videos", "calendar videos", "realdebrid", "anime"]

    /// Los catálogos de tus complementos que agregan algo: uno por nombre, con sus tipos y de qué complemento salen (las
    /// mismas reglas que la TV). Sin Stremio conectado o sin red: ninguno.
    func addonCatalogs() async -> [AddonCatalog] {
        guard let addons, let installed = try? await addons.addons() else { return [] }
        let covered: Set<String> = await platforms().isEmpty ? [] : Set(Tmdb.platforms.map { Charts.fold($0.name) })
        var found: [String: AddonCatalog] = [:], order: [String] = []
        for addon in installed where addon.url.hasPrefix("https://") {
            let name = addon.name, lower = name.lowercased()
            if Self.skipAddons.contains(where: { lower.contains($0) }) { continue }
            if lower == Self.traktAddon, trakt?.linked == true { continue }   // Trakt conectado: esas listas ya llegan de Trakt
            for cat in addon.catalogs {
                guard let id = cat["id"]?.string, let catName = cat["name"]?.string, let type = cat["type"]?.string,
                      type == "movie" || type == "series",
                      !(cat["extra"]?.array ?? []).contains(where: { $0["isRequired"]?.bool == true }) else { continue }
                let title = lower == Self.traktAddon && catName.hasPrefix("Trakt ") ? String(catName.dropFirst(6)).trimmingCharacters(in: .whitespaces) : catName
                if Self.genericCatalogs.contains(catName.lowercased()) || covered.contains(Charts.fold(title)) { continue }
                let key = "addon:\(Charts.fold(name)):\(id)"
                if found[key] == nil { found[key] = AddonCatalog(id: key, title: title, addon: name, base: addon.base, catalog: id, kinds: []); order.append(key) }
                found[key]?.kinds.append(type)
            }
        }
        return order.compactMap { found[$0] }
    }

    private func addonItems(_ entry: AddonCatalog, kind: String) async throws -> [Suggestion] {
        guard let http else { return [] }
        let kind = entry.kinds.contains(kind) ? kind : entry.kinds[0]
        let catalog = entry.catalog.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? entry.catalog
        guard let url = URL(string: "\(entry.base)/catalog/\(kind)/\(catalog).json") else { return [] }
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": "Orbital"], timeout: 12))
        guard response.status < 400, let json = JSON.parse(response.data) else { throw NetworkError("\(entry.addon) no respondió") }
        let reason: SuggestionReason = entry.title == "Watchlist" ? .inWatchlist : entry.title == "Recommendations" ? .recommended : .inList(entry.title)
        return (json["metas"]?.array ?? []).compactMap { m in
            guard let imdb = m["id"]?.string, imdb.range(of: #"^tt\d+$"#, options: .regularExpression) != nil, let name = m["name"]?.string else { return nil }
            let year = (m["releaseInfo"]?.string ?? m["year"]?.string).flatMap { Int($0.prefix(4)) }
            return Suggestion(kind: kind, imdb: imdb, title: name, year: year, runtime: nil, overview: m["description"]?.string ?? "",
                              poster: String(format: Self.metahubPoster, imdb), wide: String(format: Self.metahubBackground, imdb),
                              logo: String(format: Self.metahubLogo, imdb), reason: reason, next: nil)
        }
    }

    /// Un título de una lista con puesto, como `_chart_item` de la TV: «N.º 3 en Netflix», con puesto, movimiento y «Nuevo».
    private func chartSuggestion(_ e: ChartEntry, kind: String, platform: String) -> Suggestion {
        var s = Suggestion(kind: kind, imdb: e.imdb, title: e.title, year: e.year, runtime: nil, overview: "",
                           poster: String(format: Self.metahubPoster, e.imdb), wide: String(format: Self.metahubBackground, e.imdb),
                           logo: String(format: Self.metahubLogo, e.imdb), reason: .onPlatform(platform), next: nil, rank: e.rank)
        s.movement = e.movement
        s.isNew = e.isNew
        return s
    }

    /// «México» (para «Esta semana en México»), en español como el resto de los datos de la consola.
    static func countryName(_ iso2: String) -> String {
        Locale(identifier: "es_MX").localizedString(forRegionCode: iso2.uppercased()) ?? iso2.uppercased()
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
                                  logo: String(format: Self.metahubLogo, imdb), reason: .onPlatform(platform.name), next: nil)
            }
        }
    }

    // MARK: próximos estrenos
    /// Lo que sale hoy y los próximos 14 días de las series que sigues en Trakt, con la hora de aquí. Sin Trakt: nada.
    /// `skip` días después de hoy y los `days` siguientes (las semanas que siguen, al deslizar la tira de «Próximos estrenos»).
    public func calendar(skip: Int = 0, days: Int = calendarDays, calendar: Calendar = .current) async throws -> [Airing] {
        guard let trakt, trakt.linked else { return [] }
        let now = clock()
        // Trakt va en hora universal: se pide desde un día antes para no perder lo de hoy.
        let start = Self.dayString(calendar.date(byAdding: .day, value: skip - 1, to: calendar.startOfDay(for: now))!, calendar: calendar)
        let rows = try await remember("trakt:calendar:\(start):\(days)", ttl: Self.recsTTL) { try await trakt.calendar(start: start, days: days + 2) }
        return Self.airings(rows, now: now, calendar: calendar, skip: skip, days: days).filter { !dismissed.contains($0.series.imdb) }
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Agrupa por serie y día (en la hora de aquí), de hoy (más `skip`) a `days` días, en orden de hora y luego de nombre.
    public static func airings(_ rows: [TraktAiring], now: Date, calendar: Calendar, skip: Int = 0, days: Int = calendarDays) -> [Airing] {
        guard let today = calendar.date(byAdding: .day, value: skip, to: calendar.startOfDay(for: now)),
              let end = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        var groups: [Airing] = [], index: [String: Int] = [:]
        for row in rows {
            let day = calendar.startOfDay(for: row.aired)
            guard day >= today, day < end else { continue }
            let key = "\(row.show.imdb)|\(day.timeIntervalSince1970)"
            if let i = index[key] {
                groups[i].first = min(groups[i].first, row.episode)
                groups[i].last = max(groups[i].last, row.episode)
                groups[i].count += 1
                continue
            }
            let e = row.show
            let series = Suggestion(kind: "series", imdb: e.imdb, title: e.title, year: e.year, runtime: e.runtime, overview: e.overview,
                                    poster: String(format: metahubPoster, e.imdb), wide: String(format: metahubBackground, e.imdb), reason: .watching)
            index[key] = groups.count
            groups.append(Airing(series: series, season: row.season, first: row.episode, last: row.episode, count: 1, episodeTitle: row.episodeTitle,
                                 aired: row.aired, day: day, network: row.network, atDawn: calendar.component(.hour, from: row.aired) < dawnHour))
        }
        return groups.sorted { ($0.aired, $0.series.title) < ($1.aired, $1.series.title) }
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
        let mosaic = Self.interleave(batches, limit: Self.mosaicSize)
        if !mosaic.isEmpty { kv.set(Self.mosaicKey, data: try? JSONEncoder().encode(mosaic.map(SavedSuggestion.init))) }
        return mosaic
    }

    /// El último mosaico, guardado en el teléfono: al abrir la app se pinta al instante mientras llega el nuevo (sin red,
    /// se queda ese). Sin lo que marcaste «No me interesa» desde entonces.
    /// Guarda un mosaico que llegó de otra fuente (tu Orbital): la próxima vez aparece al instante, como el del iPhone.
    public func saveMosaic(_ mosaic: [Suggestion]) {
        guard !mosaic.isEmpty else { return }
        kv.set(Self.mosaicKey, data: try? JSONEncoder().encode(mosaic.map(SavedSuggestion.init)))
    }

    public func cachedMosaic() -> [Suggestion] {
        guard let data = kv.data(Self.mosaicKey), let saved = try? JSONDecoder().decode([SavedSuggestion].self, from: data) else { return [] }
        return saved.map(\.suggestion).filter { !dismissed.contains($0.imdb) }
    }

    static let mosaicKey = "foryou-mosaic"

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

/// Una sugerencia tal como se guarda en el teléfono (`Suggestion` lleva una tupla y un motivo con datos).
struct SavedSuggestion: Codable {
    var kind, imdb, title, overview, poster, wide: String
    var year, runtime, rank, movement, nextSeason, nextEpisode: Int?
    var logo: String?
    var reason: String
    var reasonText: String?
    var isNew: Bool

    init(_ s: Suggestion) {
        kind = s.kind; imdb = s.imdb; title = s.title; overview = s.overview; poster = s.poster; wide = s.wide
        year = s.year; runtime = s.runtime; rank = s.rank; movement = s.movement; logo = s.logo; isNew = s.isNew
        nextSeason = s.next?.season; nextEpisode = s.next?.episode
        switch s.reason {
        case .recommended: reason = "recommended"
        case .watching: reason = "watching"
        case .inWatchlist: reason = "inWatchlist"
        case .inList(let name): reason = "inList"; reasonText = name
        case .trending: reason = "trending"
        case .popular: reason = "popular"
        case .onPlatform(let name): reason = "onPlatform"; reasonText = name
        case .console(let text): reason = "console"; reasonText = text
        }
    }

    var suggestion: Suggestion {
        let why: SuggestionReason = switch reason {
        case "watching": .watching
        case "inWatchlist": .inWatchlist
        case "inList": .inList(reasonText ?? "")
        case "trending": .trending
        case "popular": .popular
        case "onPlatform": .onPlatform(reasonText ?? "")
        case "console": .console(reasonText ?? "")
        default: .recommended
        }
        var s = Suggestion(kind: kind, imdb: imdb, title: title, year: year, runtime: runtime, overview: overview, poster: poster, wide: wide,
                           logo: logo, reason: why)
        if let nextSeason, let nextEpisode { s.next = (nextSeason, nextEpisode) }
        s.rank = rank; s.movement = movement; s.isNew = isNew
        return s
    }
}


/// «Tu año»: lo que viste en el año, día por día (película, serie o las dos), horas, racha más larga, tu género y lo que más viste.
public struct YearInReview: Sendable, Equatable {
    public enum Day: Sendable, Equatable { case movies, series, both }
    public struct Top: Sendable, Equatable, Identifiable { public var imdb: String; public var kind: String; public var title: String; public var plays: Int; public var id: String { imdb } }
    public var year: Int
    public var days: [Date: Day]
    public var hours: Int
    public var movies: Int
    public var episodes: Int
    public var longestStreak: Int
    public var topGenre: String?
    public var top: [Top]

    public static func make(_ plays: [TraktPlay], year: Int, calendar: Calendar) -> YearInReview {
        var days: [Date: Day] = [:], minutes = 0, movies = 0, episodes = 0
        var genres: [String: Int] = [:], counts: [String: Top] = [:]
        for p in plays {
            let day = calendar.startOfDay(for: p.at)
            let kind: Day = p.kind == "movie" ? .movies : .series
            days[day] = days[day].map { $0 == kind ? $0 : .both } ?? kind
            minutes += p.minutes
            if p.kind == "movie" { movies += 1 } else { episodes += 1 }
            for g in p.genres { genres[g, default: 0] += 1 }
            counts[p.imdb, default: Top(imdb: p.imdb, kind: p.kind, title: p.title, plays: 0)].plays += 1
        }
        // La racha más larga: días seguidos con algo visto.
        var longest = 0, run = 0, previous: Date?
        for day in days.keys.sorted() {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) { run += 1 } else { run = 1 }
            longest = max(longest, run); previous = day
        }
        let top = counts.values.sorted { ($0.plays, $1.title) > ($1.plays, $0.title) }.prefix(10)
        return YearInReview(year: year, days: days, hours: Int((Double(minutes) / 60).rounded()), movies: movies, episodes: episodes,
                            longestStreak: longest, topGenre: genres.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key, top: Array(top))
    }
}
