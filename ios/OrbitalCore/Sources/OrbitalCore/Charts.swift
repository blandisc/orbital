import Foundation

/// Un título de una lista con puesto (el Top 10 de Netflix o la tendencia de una plataforma en JustWatch), ya con su IMDb.
public struct ChartEntry: Codable, Sendable, Equatable {
    public var imdb: String
    public var title: String
    public var year: Int?
    /// Su lugar en la lista (1-10).
    public var rank: Int
    /// Semanas en el Top 10 (solo Netflix).
    public var weeks: Int?
    /// +2 subió dos, −1 bajó uno, 0 igual; nil si no hay con qué comparar (no se inventan flechas).
    public var movement: Int?
    /// Entró esta semana (Netflix) o este día (JustWatch).
    public var isNew: Bool

    public init(imdb: String, title: String, year: Int? = nil, rank: Int, weeks: Int? = nil, movement: Int? = nil, isNew: Bool = false) {
        self.imdb = imdb; self.title = title; self.year = year; self.rank = rank; self.weeks = weeks; self.movement = movement; self.isNew = isNew
    }
}

/// Las listas con puesto de «Para ti», calculadas en el iPhone (sin depender de tu Orbital), con la misma cuenta que la TV
/// (`orbital/library/charts.py`):
///
/// - **Netflix**: el Top 10 oficial de la semana por país, de su página pública (`netflix.com/tudum/top10/<país>`, ~600 KB
///   comprimida) en vez del TSV de todas las semanas (32 MB, demasiado para un teléfono). La página trae la tabla (puesto,
///   título, semanas) y la lista de semanas: la anterior (`?week=`) da el sube y baja. Solo trae títulos: el IMDb sale de
///   TMDB (si hay clave) o de la búsqueda de Cinemeta, y lo que no se resuelve se omite.
/// - **JustWatch**: la tendencia diaria por plataforma (GraphQL público). El puesto es el lugar dentro de la plataforma
///   (1-10); el sube y baja sale de la foto del día anterior, guardada en el iPhone (`ChartSnapshots`).
///
/// Se guardan en disco (Netflix 12 h, JustWatch 6 h): abrir Para ti no vuelve a bajar nada.
public actor Charts {
    public static let netflixTTL: TimeInterval = 12 * 3600
    public static let justWatchTTL: TimeInterval = 6 * 3600
    static let justWatchURL = URL(string: "https://apis.justwatch.com/graphql")!
    static let justWatchImages = "https://images.justwatch.com"
    static let justWatchFetch = 20   // se piden de más: algunos no traen IMDb y quedan fuera; se enseñan 10

    /// Las plataformas de JustWatch con su lista «Tendencias en …» (como `JW_LIST_BRANDS` en la TV): marca, nombre corto
    /// de JustWatch (3 letras), nombre y logo.
    public static let justWatchPlatforms: [(brand: String, shortName: String, name: String, logo: String)] = [
        ("disney", "dnp", "Disney+", "/icon/313118777/s100/disneyplus.png"),
        ("hbo", "mxx", "HBO Max", "/icon/332884837/s100/max.png"),
        ("prime", "prv", "Prime Video", "/icon/322992749/s100/amazonprimevideo.png"),
        ("appletv", "atp", "Apple TV+", "/icon/338367329/s100/appletvplus.png"),
        ("paramount", "pmp", "Paramount+", "/icon/242706661/s100/paramountplus.png"),
    ]
    public static let netflixLogo = justWatchImages + "/icon/207360008/s100/netflix.png"

    public static func justWatchLogo(_ brand: String) -> String? {
        justWatchPlatforms.first { $0.brand == brand }.map { justWatchImages + $0.logo }
    }

    private let http: HTTPClient
    private let tmdb: Tmdb?
    private let cinemeta: Cinemeta
    private let kv: KeyValueStore
    private let region: @Sendable () -> String
    private let clock: @Sendable () -> Date
    private let snapshots: ChartSnapshots

    public init(http: HTTPClient, tmdb: Tmdb?, cinemeta: Cinemeta, kv: KeyValueStore, region: @escaping @Sendable () -> String,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.tmdb = tmdb; self.cinemeta = cinemeta; self.kv = kv; self.region = region; self.clock = clock
        snapshots = ChartSnapshots(kv: kv)
    }

    // MARK: caché en disco
    private struct Stored: Codable { var savedAt: Date; var entries: [ChartEntry] }

    private func cached(_ key: String, ttl: TimeInterval, _ load: () async throws -> [ChartEntry]) async throws -> [ChartEntry] {
        let storeKey = "charts:" + key
        let stored = kv.data(storeKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        if let stored, clock().timeIntervalSince(stored.savedAt) < ttl { return stored.entries }
        do {
            let fresh = try await load()
            if !fresh.isEmpty { kv.set(storeKey, data: try? JSONEncoder().encode(Stored(savedAt: clock(), entries: fresh))) }
            return fresh.isEmpty ? (stored?.entries ?? []) : fresh
        } catch {
            if let stored { return stored.entries }   // sin red: lo último que se supo es mejor que nada
            throw error
        }
    }

    // MARK: Netflix
    /// El Top 10 de Netflix de ese tipo en tu país (o el global, si Netflix no publica el de tu país), con IMDb.
    public func netflix(kind: String) async throws -> [ChartEntry] {
        let kind = kind == "movie" ? "movie" : "series"
        let country = region().uppercased()
        return try await cached("netflix2:\(country):\(kind)", ttl: Self.netflixTTL) {
            let base = Self.netflixPage(country: country, kind: kind)
            let latest = try await page(base)
            guard !latest.rows.isEmpty else { return [] }
            var previousRows: [NetflixRow]?
            if let previousWeek = latest.weeks.dropLast().last { previousRows = try? await page(base + "?week=" + previousWeek).rows }
            let marked = Self.withMovement(latest.rows, previous: previousRows)
            return await resolve(marked, kind: kind)
        }
    }

    struct NetflixRow: Equatable { var rank: Int; var title: String; var weeks: Int? }
    struct NetflixPage { var rows: [NetflixRow]; var weeks: [String] }

    private func page(_ url: String) async throws -> NetflixPage {
        guard let url = URL(string: url) else { return NetflixPage(rows: [], weeks: []) }
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": "Mozilla/5.0", "Accept-Language": "en-US"], timeout: 20))
        guard response.status < 400, let html = String(data: response.data, encoding: .utf8) else { throw NetworkError("Netflix respondió HTTP \(response.status)") }
        return Self.parseNetflixPage(html)
    }

    /// La página del Top 10 de ese país (o la global), de películas o de series.
    static func netflixPage(country: String, kind: String) -> String {
        let slug = netflixCountries[country]
        var url = "https://www.netflix.com/tudum/top10"
        if let slug { url += "/" + slug }
        if kind == "series" { url += "/tv" }
        return url
    }

    /// Los países de la página de Netflix (ISO2 → nombre en la URL). Uno que no esté: el Top 10 global.
    static let netflixCountries: [String: String] = [
        "MX": "mexico", "US": "united-states", "CA": "canada", "AR": "argentina", "BO": "bolivia", "BR": "brazil", "CL": "chile",
        "CO": "colombia", "CR": "costa-rica", "DO": "dominican-republic", "EC": "ecuador", "SV": "el-salvador", "GT": "guatemala",
        "HN": "honduras", "NI": "nicaragua", "PA": "panama", "PY": "paraguay", "PE": "peru", "UY": "uruguay", "VE": "venezuela",
        "ES": "spain", "GB": "united-kingdom", "FR": "france", "DE": "germany", "IT": "italy", "PT": "portugal", "JP": "japan",
        "KR": "south-korea", "AU": "australia", "IN": "india",
    ]

    /// La tabla de la página (puesto, título, semanas en el Top 10) y las semanas que tiene (la última, la que enseña).
    static func parseNetflixPage(_ html: String) -> NetflixPage {
        var rows: [NetflixRow] = []
        let rowPattern = #"<span class="rank">(\d+)</span>.*?<button>(.*?)</button></td><td data-uia="top10-table-row-weeks">(\d+)</td>"#
        if let regex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) {
            let ns = html as NSString
            for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard let rank = Int(ns.substring(with: m.range(at: 1))) else { continue }
                let title = decodeEntities(ns.substring(with: m.range(at: 2))).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty, rows.count < 10 else { continue }
                rows.append(NetflixRow(rank: rank, title: title, weeks: Int(ns.substring(with: m.range(at: 3)))))
            }
        }
        var weeks: [String] = []
        if let regex = try? NSRegularExpression(pattern: #""endDate":"(\d{4}-\d{2}-\d{2})""#) {
            let ns = html as NSString
            weeks = Array(Set(regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })).sorted()
        }
        return NetflixPage(rows: rows.sorted { $0.rank < $1.rank }, weeks: weeks)
    }

    /// El sube y baja contra la semana anterior, como `_with_movement` de la TV: +2 si subió dos; nil si la semana pasada no
    /// estaba o no hay semana pasada. Nuevo: su primera semana en el Top 10, o no estaba la semana pasada.
    static func withMovement(_ latest: [NetflixRow], previous: [NetflixRow]?) -> [(row: NetflixRow, movement: Int?, isNew: Bool)] {
        let before = previous.map { Dictionary($0.map { (fold($0.title), $0.rank) }, uniquingKeysWith: { a, _ in a }) }
        return latest.map { row in
            let was = before?[fold(row.title)]
            return (row, was.map { $0 - row.rank }, row.weeks == 1 || (before != nil && was == nil))
        }
    }

    /// Los títulos → IMDb (a la vez); los que no se encuentran, fuera.
    private func resolve(_ marked: [(row: NetflixRow, movement: Int?, isNew: Bool)], kind: String) async -> [ChartEntry] {
        let tmdb = tmdb, cinemeta = cinemeta
        let found = await withTaskGroup(of: (Int, String?).self) { group in
            for (i, item) in marked.enumerated() {
                let title = Self.showTitle(item.row.title)
                group.addTask {
                    // TMDB primero; si no lo encuentra (le pasaba a uno o dos del Top 10), Cinemeta: antes ese puesto se perdía.
                    if let tmdb, tmdb.configured, let found = try? await tmdb.searchIMDb(kind: kind, title: title) { return (i, found) }
                    let metas = (try? await cinemeta.search(kind, query: title)) ?? []
                    return (i, Self.bestMatch(title, metas)?["id"]?.string)
                }
            }
            var out = [String?](repeating: nil, count: marked.count)
            for await (i, imdb) in group { out[i] = imdb }
            return out
        }
        return marked.enumerated().compactMap { i, item in
            guard let imdb = found[i], imdb.hasPrefix("tt") else { return nil }
            return ChartEntry(imdb: imdb, title: Self.showTitle(item.row.title), rank: item.row.rank, weeks: item.row.weeks,
                              movement: item.movement, isNew: item.isNew)
        }
    }

    /// «Below: Limited Series» → «Below»; «Physical 100: Mexico: Season 1» → «Physical 100: Mexico» (la página trae la
    /// temporada pegada al nombre; para encontrar la serie va sin ella, como `show_title` en el TSV).
    static func showTitle(_ title: String) -> String {
        let pattern = #":\s*(Season|Limited Series|Temporada|Miniserie|Part|Parte|Volume|Vol\.|Book|Chapter|Series)\b[^:]*$"#
        return title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
    }

    /// El que se llama igual (el más nuevo, si hay varios: un Top 10 es de ahora); si no, uno que contenga el nombre; si no,
    /// el más nuevo de los primeros resultados (antes, el primero aunque fuera de hace 30 años).
    static func bestMatch(_ title: String, _ metas: [JSON]) -> JSON? {
        let target = fold(title)
        func year(_ m: JSON) -> Int { Int(CinemetaParsing.describe(m).year.prefix(4)) ?? 0 }
        func newest(_ list: [JSON]) -> JSON? { list.max { year($0) < year($1) } }
        let names = metas.map { fold($0["name"]?.string ?? "") }
        if let exact = newest(zip(metas, names).filter { $0.1 == target }.map(\.0)) { return exact }
        if let loose = newest(zip(metas, names).filter { $0.1.count >= 4 && ($0.1.contains(target) || target.contains($0.1)) }.map(\.0)) { return loose }
        return newest(Array(metas.prefix(3)))
    }

    /// Para comparar títulos sin pensar en mayúsculas o signos (como `_fold` en la TV).
    static func fold(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(String.init).joined()
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        for (entity, char) in [("&amp;", "&"), ("&#x27;", "'"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&#x2F;", "/")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    // MARK: JustWatch
    /// La tendencia de hoy en esa plataforma (hasta 10, con IMDb), con el sube y baja contra la foto del día anterior.
    public func justWatch(brand: String, kind: String) async throws -> [ChartEntry] {
        let kind = kind == "movie" ? "movie" : "series"
        guard let platform = Self.justWatchPlatforms.first(where: { $0.brand == brand }) else { return [] }
        let country = region().uppercased()
        return try await cached("jw:\(country):\(brand):\(kind)", ttl: Self.justWatchTTL) {
            let body: JSON = .object([
                "operationName": "GetStreamingCharts",
                "variables": .object([
                    "country": .string(country), "language": "es", "first": .int(Self.justWatchFetch),
                    "filter": .object(["category": "DAILY_POPULARITY_SAME_CONTENT_TYPE", "objectType": .string(kind == "movie" ? "MOVIE" : "SHOW"),
                                       "packages": .array([.string(platform.shortName)])]),
                ]),
                "query": .string(Self.justWatchQuery),
            ])
            let response = try await http.send(HTTPRequest(url: Self.justWatchURL, method: "POST", headers: ["Content-Type": "application/json", "User-Agent": "Orbital"],
                                                           body: body.serialized(), timeout: 12))
            guard response.status == 200, let json = JSON.parse(response.data), json["errors"] == nil else {
                throw NetworkError("JustWatch respondió HTTP \(response.status)")
            }
            let entries = Self.parseJustWatch(json)
            return snapshots.annotate(listID: "jw:\(brand)", kind: kind, entries: entries, today: clock())
        }
    }

    static let justWatchQuery = """
    query GetStreamingCharts($country: Country!, $language: Language!, $first: Int!, $filter: StreamingChartsFilter) {
      streamingCharts(country: $country, first: $first, filter: $filter) {
        edges {
          streamingChartInfo { rank }
          node {
            objectType
            content(country: $country, language: $language) {
              title
              originalReleaseYear
              externalIds { imdbId }
            }
          }
        }
      }
    }
    """

    /// Los títulos de la respuesta, en orden, con su lugar en la plataforma (1-10). Sin IMDb, fuera.
    static func parseJustWatch(_ json: JSON) -> [ChartEntry] {
        var out: [ChartEntry] = []
        for edge in json["data"]?["streamingCharts"]?["edges"]?.array ?? [] {
            let content = edge["node"]?["content"]
            guard let imdb = content?["externalIds"]?["imdbId"]?.string, imdb.range(of: #"^tt\d+$"#, options: .regularExpression) != nil,
                  let title = content?["title"]?.string?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
            out.append(ChartEntry(imdb: imdb, title: title, year: content?["originalReleaseYear"]?.intValue, rank: out.count + 1))
            if out.count >= 10 { break }
        }
        return out
    }
}

/// Una foto por día de cada lista de JustWatch (IMDb → puesto), unas 8 semanas, en el iPhone: así el sube y baja y
/// «Nuevo» no dependen de que la app siga abierta desde ayer (como `ChartSnapshots` en la TV).
final class ChartSnapshots: @unchecked Sendable {
    static let keepDays = 56
    private let kv: KeyValueStore
    private let lock = NSLock()

    init(kv: KeyValueStore) { self.kv = kv }

    /// Guarda la foto de hoy y marca cada título contra la del día anterior que haya.
    func annotate(listID: String, kind: String, entries: [ChartEntry], today: Date) -> [ChartEntry] {
        let key = "chart-snapshots:\(listID):\(kind)"
        let day = Self.dayString(today)
        let previous: [String: Int]? = lock.withLock {
            var days = kv.data(key).flatMap { try? JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
            let oldest = Self.dayString(today.addingTimeInterval(-Double(Self.keepDays) * 86_400))
            let before = days.keys.filter { $0 < day && $0 >= oldest }.max().flatMap { days[$0] }
            days[day] = Dictionary(entries.map { ($0.imdb, $0.rank) }, uniquingKeysWith: { a, _ in a })
            days = days.filter { $0.key >= oldest }
            kv.set(key, data: try? JSONEncoder().encode(days))
            return before
        }
        return entries.map { e in
            var e = e
            let was = previous?[e.imdb]
            e.movement = was.map { $0 - e.rank }
            e.isNew = previous != nil && was == nil
            return e
        }
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
