import XCTest
@testable import OrbitalCore

final class CinemetaTests: XCTestCase {
    let golden = try! Fixtures.json("ios/cinemeta.json")
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let movie = try! Fixtures.json("cinemeta/meta_movie_tt0816692.json")

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
}
