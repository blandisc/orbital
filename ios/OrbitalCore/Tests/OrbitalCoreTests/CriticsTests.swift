import XCTest
@testable import OrbitalCore

/// «Aprobadas por la crítica» calculada en el iPhone, igual que en la consola: películas de MDBList, series de Trakt.
final class CriticsTests: XCTestCase {
    let moviesURL = "https://mdblist.com/lists/tbotcotw/recent-certified-fresh/json"
    let seriesURL = "https://api.trakt.tv/users/truckclancy/lists/rotten-tomatoes-certified-fresh-tv-shows-ranked-by-tomatometer-score/items?extended=full"

    private func forYou(_ http: FakeHTTP, kv: KeyValueStore = InMemoryKeyValueStore(), clock: Clock = Clock()) -> ForYou {
        let trakt = Trakt(http: http, secrets: InMemorySecrets(), clientID: "CID", clock: { clock.now }, pause: { _ in })
        return ForYou(trakt: trakt, tmdb: nil, http: http, region: { "MX" }, kv: kv, clock: { clock.now })
    }

    func testMDBListAnswersEitherAListOrMoviesAndShows() {
        let list: JSON = [["imdb_id": "tt1", "title": " Uno ", "mediatype": "movie", "release_year": 2025],
                          ["imdb_id": "tt1", "title": "Repetido", "mediatype": "movie"],
                          ["imdb_id": "sin-imdb", "title": "Nada", "mediatype": "movie"],
                          ["imdbid": "tt2", "title": "Dos", "mediatype": "show", "year": 2024]]
        XCTAssertEqual(Critics.entries(list).map(\.imdb), ["tt1", "tt2"], "sin repetir y solo con IMDb")
        XCTAssertEqual(Critics.entries(list).map(\.kind), ["movie", "series"])
        XCTAssertEqual(Critics.entries(list).first?.title, "Uno")
        XCTAssertEqual(Critics.entries(list).first?.year, 2025)
        let split: JSON = ["movies": [["imdb_id": "tt3", "title": "Tres", "mediatype": "movie"]], "shows": [["imdb_id": "tt4", "title": "Cuatro", "mediatype": "show"]]]
        XCTAssertEqual(Critics.entries(split).map(\.imdb), ["tt3", "tt4"])
    }

    func testTheShelfHasMoviesFromMDBListAndSeriesFromTraktWithTheConsolesReasons() async throws {
        let http = FakeHTTP()
        http.json[moviesURL] = ["movies": [["imdb_id": "tt15239678", "title": "Dune: Part Two", "mediatype": "movie", "release_year": 2024]], "shows": []]
        http.json[seriesURL] = [["type": "show", "show": ["title": "Chernobyl", "year": 2019, "ids": ["trakt": 1, "imdb": "tt7366338"]]]]
        let fy = forYou(http)
        let lists = await fy.lists()
        let list = try XCTUnwrap(lists.first { $0.id == "critics" })
        XCTAssertEqual(list.source, "Rotten Tomatoes")
        XCTAssertTrue(list.splitsKinds)
        let movies = try await fy.items(listID: "critics", kind: "movie"), series = try await fy.items(listID: "critics", kind: "series")
        XCTAssertEqual(movies.map(\.imdb), ["tt15239678"])
        XCTAssertEqual(movies.first?.reason, .console("Certified Fresh"))
        XCTAssertEqual(series.map(\.imdb), ["tt7366338"])
        XCTAssertEqual(series.first?.reason, .console("Fresh en Rotten Tomatoes"))
        XCTAssertFalse(http.calls.contains { $0.contains("apikey") }, "sin clave")
    }

    func testWithoutAnAnswerTheLastGoodCopyStays() async throws {
        let http = FakeHTTP(), kv = InMemoryKeyValueStore(), clock = Clock()
        http.json[moviesURL] = [["imdb_id": "tt1", "title": "Uno", "mediatype": "movie"]]
        _ = try await forYou(http, kv: kv, clock: clock).items(listID: "critics", kind: "movie")
        http.json[moviesURL] = nil   // MDBList no contesta (404)
        let again = try await forYou(http, kv: kv, clock: clock).items(listID: "critics", kind: "movie")
        XCTAssertEqual(again.map(\.imdb), ["tt1"])
        let none = try? await forYou(http).items(listID: "critics", kind: "movie")
        XCTAssertTrue(none?.isEmpty ?? true, "sin copia, nada (el estante no se pinta)")
    }
}
