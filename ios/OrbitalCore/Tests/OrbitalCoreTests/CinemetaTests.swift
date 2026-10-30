import XCTest
@testable import OrbitalCore

final class CinemetaTests: XCTestCase {
    let golden = try! Fixtures.json("ios/cinemeta.json")
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let movie = try! Fixtures.json("cinemeta/meta_movie_tt0816692.json")

    func testPlaceholderEpisodeNamesCountAsMissing() {
        for name in ["Episode 1", "episodio 12", "Ep. 3", "TBA", "  Episode 10 "] { XCTAssertTrue(CinemetaParsing.isPlaceholderEpisodeName(name), name) }
        for name in ["Pilot", "Episode One Hundred", "The Episode 1 Special"] { XCTAssertFalse(CinemetaParsing.isPlaceholderEpisodeName(name), name) }
        let meta: JSON = ["videos": [["id": "tt1:1:1", "season": 1, "episode": 1, "name": "Episode 1"], ["id": "tt1:1:2", "season": 1, "episode": 2, "name": "Pilot"]]]
        let eps = CinemetaParsing.seasons(meta).first?.episodes ?? []
        XCTAssertEqual(eps.map(\.hasTitle), [false, true])
    }

    func testSeasonsMatchPython() throws {
        let expected = try XCTUnwrap(golden["seasons"]?.array)
        let got = CinemetaParsing.seasons(series)
        XCTAssertEqual(got.map(\.season), expected.compactMap { $0["season"]?.intValue })
        for (g, e) in zip(got, expected) {
            let eps = try XCTUnwrap(e["episodes"]?.array)
            XCTAssertEqual(g.episodes.map(\.id), eps.compactMap { $0["id"]?.string })
            XCTAssertEqual(g.episodes.map(\.title), eps.compactMap { $0["title"]?.string })
            XCTAssertEqual(g.episodes.map(\.episode), eps.compactMap { $0["episode"]?.intValue })
            XCTAssertEqual(g.episodes.map(\.overview), eps.compactMap { $0["overview"]?.string })
        }
    }

    func testNextEpisodeMatchesPython() throws {
        for (id, next) in try XCTUnwrap(golden["next"]?.object) {
            XCTAssertEqual(CinemetaParsing.nextEpisode(series, after: id), next.string, id)
        }
    }

    func testDescribeAndCreditsMatchPython() throws {
        for (key, meta) in [("describe_series", series), ("describe_movie", movie)] {
            let e = try XCTUnwrap(golden[key]), g = CinemetaParsing.describe(meta)
            XCTAssertEqual(g.year, e["year"]?.string); XCTAssertEqual(g.rating, e["rating"]?.string)
            XCTAssertEqual(g.genres, e["genres"]?.array?.compactMap(\.string)); XCTAssertEqual(g.description, e["description"]?.string)
            XCTAssertEqual(g.logo, e["logo"]?.string); XCTAssertEqual(g.runtime, e["runtime"]?.string)
        }
        let e = try XCTUnwrap(golden["credits"]), g = CinemetaParsing.credits(series)
        XCTAssertEqual(g.cast, e["cast"]?.array?.compactMap(\.string)); XCTAssertEqual(g.directors, e["directors"]?.array?.compactMap(\.string))
        XCTAssertEqual(g.writers, e["writers"]?.array?.compactMap(\.string)); XCTAssertEqual(g.released, e["released"]?.string)
    }

    func testSearchResultsMatchPython() throws {
        let movies = try XCTUnwrap(Fixtures.json("cinemeta/search_movie_dune.json").array)
        let series = try XCTUnwrap(Fixtures.json("cinemeta/search_series_dune.json").array)
        for (query, expected) in try XCTUnwrap(golden["search"]?.object) {
            let got = CinemetaParsing.searchResults(query: query, movies: movies, series: series)
            let want = expected.array ?? []
            XCTAssertEqual(got.map(\.metaID), want.compactMap { $0["meta_id"]?.string }, query)
            XCTAssertEqual(got.map(\.kind), want.compactMap { $0["kind"]?.string }, query)
            XCTAssertEqual(got.map(\.title), want.compactMap { $0["title"]?.string }, query)
        }
    }

    /// «office»: The Office (primera en Cinemeta) no pierde contra una serie nueva llamada exactamente «Office».
    func testLeadingArticleStillCountsAsExact() {
        let series: [JSON] = [["id": "tt0386676", "name": "The Office"], ["id": "tt9", "name": "Office"]]
        let movies: [JSON] = [["id": "tt2", "name": "Office Space"]]
        XCTAssertEqual(CinemetaParsing.searchResults(query: "office", movies: movies, series: series).map(\.metaID).first, "tt0386676")
        XCTAssertEqual(CinemetaParsing.searchResults(query: "the office", movies: movies, series: series).map(\.metaID).first, "tt0386676")
    }

    func testUnusableMetasAreDropped() {
        XCTAssertFalse(CinemetaParsing.isUsable(["id": "tt1", "name": 1917]))
        XCTAssertFalse(CinemetaParsing.isUsable(["id": "", "name": "x"]))
        XCTAssertTrue(CinemetaParsing.isUsable(["id": "tt1", "name": "x"]))
    }

    func testMetaIsFetchedOriginalAndCached() async throws {
        let http = FakeHTTP()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        let cinemeta = Cinemeta(http: http)
        let first = try await cinemeta.meta(kind: "series", id: "tt0386676")
        XCTAssertEqual(first["name"]?.string, series["name"]?.string)
        _ = try await cinemeta.meta(kind: "series", id: "tt0386676")
        XCTAssertEqual(http.calls.count, 1)
    }

    func testGenreCatalogAsksCinemetaForThatGenre() async throws {
        let http = FakeHTTP()
        http.json["https://v3-cinemeta.strem.io/catalog/movie/top/genre=Sci-Fi.json"] = ["metas": [["id": "tt1", "name": "Dune", "type": "movie"]]]
        let found = try await Cinemeta(http: http).catalog("movie", genre: "Sci-Fi")
        XCTAssertEqual(found.compactMap { $0["name"]?.string }, ["Dune"])
    }

    func testKitsuTitlesAskAddonsThatKnowThem() async throws {
        let http = FakeHTTP()
        http.json["https://anime.example/manifest.json"] = ["name": "Anime", "resources": ["meta"], "types": ["series"], "idPrefixes": ["kitsu:"]]
        http.json["https://anime.example/meta/series/kitsu:1.json"] = ["meta": ["id": "kitsu:1", "name": "Anime"]]
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://anime.example"] })
        let cinemeta = Cinemeta(http: http, registry: registry)
        let meta = try await cinemeta.meta(kind: "series", id: "kitsu:1")
        XCTAssertEqual(meta["name"]?.string, "Anime")
        XCTAssertFalse(http.calls.contains { $0.contains("cinemeta") }, "un id de kitsu no se le pregunta primero a Cinemeta")
    }

    func testImdbMetaDoesNotWaitForAddons() async throws {
        let http = FakeHTTP()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json["https://anime.example/manifest.json"] = ["name": "Anime", "resources": ["meta"], "types": ["series"], "idPrefixes": ["tt"]]
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://anime.example"] })
        _ = try await Cinemeta(http: http, registry: registry).meta(kind: "series", id: "tt0386676")
        XCTAssertEqual(http.calls, ["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"], "Cinemeta respondió: los complementos ni se piden")
    }

    func testSimultaneousCatalogRequestsShareOneFetch() async throws {
        let http = FakeHTTP()
        let url = "https://v3-cinemeta.strem.io/catalog/movie/top.json"
        http.json[url] = ["metas": [["id": "tt1", "name": "Dune", "type": "movie"]]]
        http.delays[url] = 50
        let cinemeta = Cinemeta(http: http)
        async let a = cinemeta.catalog("movie")
        async let b = cinemeta.catalog("movie")
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(second.count, 1)
        XCTAssertEqual(http.calls.filter { $0 == url }.count, 1, "dos consumidores a la vez: una sola petición")
    }

    func testCatalogIsShownFromDiskAndRevalidatedWhenStale() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = "https://v3-cinemeta.strem.io/catalog/series/top.json"
        let http = FakeHTTP()
        http.json[url] = ["metas": [["id": "tt1", "name": "Viejo", "type": "series"]]]
        let clock = Clock()
        _ = try await Cinemeta(http: http, disk: dir, clock: { clock.now }).catalog("series")
        XCTAssertEqual(http.calls.count, 1)

        // Otra apertura, dentro del plazo: sale del disco sin red.
        let fresh = try await Cinemeta(http: http, disk: dir, clock: { clock.now }).catalog("series")
        XCTAssertEqual(fresh.first?["name"]?.string, "Viejo")
        XCTAssertEqual(http.calls.count, 1)

        // Pasado el plazo: enseña lo guardado al instante y revalida aparte.
        clock.now = clock.now.addingTimeInterval(7 * 3600)
        http.json[url] = ["metas": [["id": "tt2", "name": "Nuevo", "type": "series"]]]
        let stale = try await Cinemeta(http: http, disk: dir, clock: { clock.now }).catalog("series")
        XCTAssertEqual(stale.first?["name"]?.string, "Viejo")
        for _ in 0..<200 where http.calls.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(http.calls.count, 2, "revalida en segundo plano")
    }
}
