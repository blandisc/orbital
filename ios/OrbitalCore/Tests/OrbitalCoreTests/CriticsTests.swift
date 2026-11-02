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

    func testTitlesThatHaveNotComeOutYetAreLeftOut() async throws {
        let http = FakeHTTP()
        let clock = Clock(), year = Calendar.current.component(.year, from: clock.now)
        http.json[moviesURL] = [["imdb_id": "tt19850008", "title": "The Batman: Part II", "mediatype": "movie", "release_year": .int(year + 2)],
                                ["imdb_id": "tt1", "title": "Uno", "mediatype": "movie", "release_year": .int(year)],
                                ["imdb_id": "tt2", "title": "Sin año", "mediatype": "movie"]]
        http.json["https://v3-cinemeta.strem.io/meta/movie/tt1.json"] = ["meta": ["id": "tt1", "released": .string(ISO8601DateFormatter().string(from: clock.now.addingTimeInterval(30 * 86400)))]]
        http.json["https://v3-cinemeta.strem.io/meta/movie/tt3.json"] = ["meta": ["id": "tt3", "released": .string(ISO8601DateFormatter().string(from: clock.now.addingTimeInterval(-30 * 86400)))]]
        http.json[moviesURL] = [["imdb_id": "tt19850008", "title": "The Batman: Part II", "mediatype": "movie", "release_year": .int(year + 2)],
                                ["imdb_id": "tt1", "title": "Dune: Part Three", "mediatype": "movie", "release_year": .int(year)],
                                ["imdb_id": "tt3", "title": "Ya salió", "mediatype": "movie", "release_year": .int(year)],
                                ["imdb_id": "tt2", "title": "Sin año", "mediatype": "movie"]]
        let movies = try await forYou(http, clock: clock).items(listID: "critics", kind: "movie")
        XCTAssertEqual(movies.map(\.imdb), ["tt3", "tt2"], "ni lo de años que vienen ni lo de este año que sale después de hoy")
    }
}
