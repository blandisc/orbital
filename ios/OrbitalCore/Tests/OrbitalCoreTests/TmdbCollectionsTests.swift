import XCTest
@testable import OrbitalCore

/// Responde a TMDB según la ruta y los parámetros (sin importar su orden) y apunta lo que se pidió.
private final class RoutedTMDB: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(path: String, query: [String: String])] = []
    let route: @Sendable (String, [String: String]) -> JSON?
    init(_ route: @escaping @Sendable (String, [String: String]) -> JSON?) { self.route = route }
    var calls: [(path: String, query: [String: String])] { lock.withLock { _calls } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let full = parts?.path ?? ""
        let path = full.hasPrefix("/3/") ? String(full.dropFirst(2)) : full
        var query: [String: String] = [:]
        for item in parts?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        lock.withLock { _calls.append((path, query)) }
        guard let body = route(path, query) else { return HTTPResponse(status: 404, data: Data()) }
        return HTTPResponse(status: 200, data: body.serialized())
    }
}

/// `n` filas de discover con ids desde `from` (nota y popularidad que bajan).
private func rows(_ n: Int, from: Int = 1) -> JSON {
    ["results": .array((0..<n).map { i in ["id": .int(from + i), "vote_average": .double(9 - Double(i) / 10), "popularity": .double(100 - Double(i))] })]
}

/// La ficha de un título de TMDB con su IMDb (para volver filas en sugerencias).
private func details(_ path: String) -> JSON? {
    guard let id = Int(path.split(separator: "/").last ?? ""), path.hasPrefix("/movie/") || path.hasPrefix("/tv/") else { return nil }
    let tv = path.hasPrefix("/tv/")
    return ["id": .int(id), "title": .string("T\(id)"), "imdb_id": .string(tv ? "tt9\(id)" : "tt1\(id)"), "release_date": "2026-01-01"]
}

final class TmdbCollectionsTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func order(_ y: Int, _ m: Int, _ d: Int) -> [String] {
        Tmdb.orderedSeasons(today: date(y, m, d), calendar: Calendar(identifier: .gregorian)).map(\.slug)
    }

    // MARK: temporadas en orden

    func testSeasonOnTodayGoesFirstThenTheRestInArrivalOrder() {
        XCTAssertEqual(order(2026, 10, 26), ["halloween", "muertos", "navidad", "sanvalentin", "verano"])
        XCTAssertEqual(order(2026, 11, 3), ["muertos", "navidad", "sanvalentin", "verano", "halloween"])
        XCTAssertEqual(order(2026, 7, 15), ["verano", "halloween", "muertos", "navidad", "sanvalentin"])
    }

    func testChristmasCrossesTheYear() {
        XCTAssertEqual(order(2026, 12, 24).first, "navidad")
        XCTAssertEqual(order(2027, 1, 3), ["navidad", "sanvalentin", "verano", "halloween", "muertos"])
        XCTAssertEqual(order(2027, 1, 6).first, "navidad")   // el último día todavía cuenta
        XCTAssertEqual(order(2027, 1, 7).first, "sanvalentin")
    }

    func testBetweenSeasonsTheNextOneToArriveGoesFirst() {
        XCTAssertEqual(order(2026, 11, 15), ["navidad", "sanvalentin", "verano", "halloween", "muertos"])
        XCTAssertEqual(order(2026, 3, 10), ["verano", "halloween", "muertos", "navidad", "sanvalentin"])
        XCTAssertEqual(order(2026, 9, 1).first, "halloween")
    }

    func testSameCatalogAsTheTV() {
        XCTAssertEqual(Tmdb.genres.map(\.slug), ["accion", "aventura", "animacion", "comedia", "crimen", "documental", "drama", "familia",
                                                 "fantasia", "terror", "misterio", "romance", "ciencia-ficcion", "suspenso"])
        XCTAssertEqual(Tmdb.genres.first { $0.slug == "accion" }?.tv, 10759)
        XCTAssertNil(Tmdb.genres.first { $0.slug == "terror" }?.tv)
        XCTAssertEqual(Tmdb.seasons.first { $0.slug == "halloween" }?.blurb, "Sustos, brujas y calabazas")
    }

    // MARK: lo mejor del género

    func testGenreTopUsesVotesWithTheHighFloorWhenThereAreTen() async throws {
        let http = RoutedTMDB { path, q in
            guard path.hasPrefix("/discover/") else { return nil }
            return q["vote_count.gte"] == "150" ? rows(path.hasSuffix("/movie") ? 6 : 5, from: path.hasSuffix("/movie") ? 1 : 100) : rows(0)
        }
        let top = try await Tmdb(http: http, key: "K").genreTop(movie: 28, tv: 10759, year: 2026)
        XCTAssertEqual(top.basis, .votes)
        XCTAssertEqual(top.year, 2026)
        XCTAssertEqual(top.rows.count, 11)
        XCTAssertEqual(top.rows.first?.voteAverage, 9)   // película y serie juntas, por nota
        let first = http.calls.first { $0.path == "/discover/movie" }!.query
        XCTAssertEqual(first["with_genres"], "28"); XCTAssertEqual(first["primary_release_year"], "2026"); XCTAssertEqual(first["sort_by"], "vote_average.desc")
        let tv = http.calls.first { $0.path == "/discover/tv" }!.query
        XCTAssertEqual(tv["with_genres"], "10759"); XCTAssertEqual(tv["first_air_date_year"], "2026")
    }

    func testGenreTopFallsBackToLowerFloorThenPopularThenPreviousYear() async throws {
        // Solo con el piso de 50: «votes».
        var http = RoutedTMDB { path, q in path.hasPrefix("/discover/") ? (q["vote_count.gte"] == "50" ? rows(12) : rows(3)) : nil }
        var top = try await Tmdb(http: http, key: "K").genreTop(movie: 27, tv: nil, year: 2026)
        XCTAssertEqual(top.basis, .votes)
        XCTAssertFalse(http.calls.contains { $0.path == "/discover/tv" })   // terror no tiene género de serie

        // Por nota no llegan a 10: lo más popular del año, sin piso.
        http = RoutedTMDB { path, q in path.hasPrefix("/discover/") ? (q["sort_by"] == "popularity.desc" && q["primary_release_year"] == "2026" ? rows(10) : rows(4)) : nil }
        top = try await Tmdb(http: http, key: "K").genreTop(movie: 27, tv: nil, year: 2026)
        XCTAssertEqual(top.basis, .popular)
        XCTAssertNil(http.calls.last?.query["vote_count.gte"])

        // El año anterior por nota (piso 50).
        http = RoutedTMDB { path, q in path.hasPrefix("/discover/") ? (q["primary_release_year"] == "2025" && q["sort_by"] == "vote_average.desc" ? rows(25) : rows(2)) : nil }
        top = try await Tmdb(http: http, key: "K").genreTop(movie: 27, tv: nil, year: 2026)
        XCTAssertEqual(top.basis, .previous)
        XCTAssertEqual(top.year, 2025)
        XCTAssertEqual(top.rows.count, 20)   // hasta 20
        XCTAssertEqual(http.calls.last?.query["vote_count.gte"], "50")

        // Y al final, lo más popular del año anterior, aunque sean pocas.
        http = RoutedTMDB { path, _ in path.hasPrefix("/discover/") ? rows(3) : nil }
        top = try await Tmdb(http: http, key: "K").genreTop(movie: 27, tv: nil, year: 2026)
        XCTAssertEqual(top.basis, .previousPopular)
        XCTAssertEqual(top.year, 2025)
        XCTAssertEqual(top.rows.count, 3)
        XCTAssertEqual(http.calls.count, 5)
    }

    func testGenreTopDedupesAndSortsByVotesThenPopularity() {
        let ranked = Tmdb.rank([TmdbRow(kind: "movie", id: 1, voteAverage: 8, popularity: 10), TmdbRow(kind: "series", id: 2, voteAverage: 8, popularity: 50),
                                TmdbRow(kind: "movie", id: 1, voteAverage: 8, popularity: 10), TmdbRow(kind: "movie", id: 3, voteAverage: 9, popularity: 1)], byVotes: true)
        XCTAssertEqual(ranked.map(\.id), [3, 2, 1])
    }

    func testGenreChartRanksTheTopTenAndSaysTheRealYear() async {
        let http = RoutedTMDB { path, q in
            if path.hasPrefix("/discover/") { return q["primary_release_year"] == "2025" || q["first_air_date_year"] == "2025" ? rows(8, from: path.hasSuffix("/tv") ? 50 : 1) : rows(1) }
            return details(path)
        }
        let clock = Clock(); clock.now = date(2026, 10, 26)
        let forYou = ForYou(trakt: nil, tmdb: Tmdb(http: http, key: "K"), region: { "MX" }, kv: InMemoryKeyValueStore(), clock: { clock.now })
        let chart = await forYou.genreChart(slug: "comedia")
        XCTAssertEqual(chart?.asked, 2026)
        XCTAssertEqual(chart?.year, 2025)
        XCTAssertEqual(chart?.basis, .previous)
        XCTAssertEqual(chart?.items.count, 10)
        XCTAssertEqual(chart?.items.map { $0.rank ?? 0 }, Array(1...10))
        XCTAssertTrue(chart?.items.contains { $0.kind == "series" } ?? false)
        let calls = http.calls.count
        _ = await forYou.genreChart(slug: "comedia")   // de la caché
        XCTAssertEqual(http.calls.count, calls)
    }

    // MARK: temporadas: palabra clave y títulos

    func testKeywordPrefersTheExactNameInEnglishAndTriesTheNextQuery() async throws {
        let http = RoutedTMDB { path, q in
            guard path == "/search/keyword" else { return nil }
            if q["query"] == "day of the dead" { return ["results": []] }
            return ["results": [["id": 7, "name": "dia de los muertos festival"], ["id": 9, "name": "Dia de los Muertos"]]]
        }
        let id = try await Tmdb(http: http, key: "K").keywordID(["day of the dead", "dia de los muertos"])
        XCTAssertEqual(id, 9)
        XCTAssertEqual(http.calls.map { $0.query["language"] }, ["en-US", "en-US"])
        let none = try await Tmdb(http: RoutedTMDB { _, _ in ["results": []] }, key: "K").keywordID(["nada"])
        XCTAssertNil(none)
    }

    func testSeasonTitlesLowerTheFloorUntilTenThenDropIt() async throws {
        // Con 50 votos, 4; con 10, 6 de películas y 5 de series → 11: se queda ahí.
        var http = RoutedTMDB { path, q in
            guard path.hasPrefix("/discover/") else { return nil }
            XCTAssertEqual(q["with_keywords"], "3335"); XCTAssertEqual(q["sort_by"], "popularity.desc")
            switch q["vote_count.gte"] { case "50": return rows(2, from: path.hasSuffix("/tv") ? 100 : 1); case "10": return rows(path.hasSuffix("/tv") ? 5 : 6, from: path.hasSuffix("/tv") ? 100 : 1); default: return rows(30) }
        }
        var titles = try await Tmdb(http: http, key: "K").seasonTitles(keywordID: 3335)
        XCTAssertEqual(titles.count, 11)
        XCTAssertEqual(http.calls.count, 4)
        XCTAssertEqual(titles.map(\.popularity), titles.map(\.popularity).sorted(by: >))   // lo más popular primero

        // Ni con 10: sin piso, hasta 20 (aunque sean menos de 10, ya no hay otro respaldo).
        http = RoutedTMDB { path, q in path.hasPrefix("/discover/") ? (q["vote_count.gte"] == nil ? rows(15, from: path.hasSuffix("/tv") ? 100 : 1) : rows(1)) : nil }
        titles = try await Tmdb(http: http, key: "K").seasonTitles(keywordID: 3335)
        XCTAssertEqual(titles.count, 20)
        XCTAssertEqual(http.calls.count, 6)
    }

    func testSeasonItemsRememberTheKeywordOnTheIPhone() async {
        let http = RoutedTMDB { path, q in
            if path == "/search/keyword" { return ["results": [["id": 3335, "name": "halloween"]]] }
            if path.hasPrefix("/discover/") { return rows(6, from: path.hasSuffix("/tv") ? 100 : 1) }
            return details(path)
        }
        let kv = InMemoryKeyValueStore()
        let forYou = ForYou(trakt: nil, tmdb: Tmdb(http: http, key: "K"), region: { "MX" }, kv: kv)
        let items = await forYou.seasonItems(slug: "halloween")
        XCTAssertEqual(items.count, 12)
        XCTAssertEqual(kv.data("tmdb-keyword.halloween").flatMap { String(data: $0, encoding: .utf8) }, "3335")
        // Otra sesión: la palabra clave ya no se busca.
        let again = ForYou(trakt: nil, tmdb: Tmdb(http: http, key: "K"), region: { "MX" }, kv: kv)
        let before = http.calls.filter { $0.path == "/search/keyword" }.count
        _ = await again.seasonItems(slug: "halloween")
        XCTAssertEqual(http.calls.filter { $0.path == "/search/keyword" }.count, before)
        // Sin TMDB, nada.
        let none = await ForYou(trakt: nil, tmdb: nil, region: { "MX" }, kv: kv).seasonItems(slug: "halloween")
        XCTAssertTrue(none.isEmpty)
    }
}
