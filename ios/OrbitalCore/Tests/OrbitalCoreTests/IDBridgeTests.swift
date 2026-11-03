import XCTest
@testable import OrbitalCore

/// M5: «kitsu:» y «tmdb:» al id de IMDb, para Trakt y los complementos que solo saben de IMDb.
final class IDBridgeTests: XCTestCase {
    func testTmdbAndKitsuBecomeImdbAndAnimeEpisodesStayAsTheyAre() async {
        let http = FakeHTTP()
        http.prefix["https://api.themoviedb.org/3/movie/603"] = ["id": 603, "imdb_id": "tt0133093", "title": "The Matrix"]
        http.prefix["https://api.themoviedb.org/3/tv/1399"] = ["id": 1399, "name": "Game of Thrones", "external_ids": ["imdb_id": "tt0944947"]]
        http.json["\(IDBridge.armBase)?source=kitsu&id=1376"] = ["kitsu": 1376, "imdb": "tt0213338"]
        http.json["\(IDBridge.armBase)?source=kitsu&id=7442"] = ["kitsu": 7442, "themoviedb": 603]
        let bridge = IDBridge(http: http, tmdb: { Tmdb(http: http, key: "clave") })
        let result1 = await bridge.videoID("tmdb:603", kind: "movie")
        XCTAssertEqual(result1, "tt0133093")
        let result2 = await bridge.videoID("tmdb:1399:1:2", kind: "series")
        XCTAssertEqual(result2, "tt0944947:1:2")
        let result3 = await bridge.videoID("kitsu:1376", kind: "movie")
        XCTAssertEqual(result3, "tt0213338")
        let result4 = await bridge.videoID("kitsu:7442", kind: "movie")
        XCTAssertEqual(result4, "tt0133093", "sin IMDb en la tabla, por TMDB")
        let result5 = await bridge.videoID("kitsu:1376:5", kind: "series")
        XCTAssertNil(result5, "un episodio de anime va de corrido: no se traduce")
        XCTAssertNil(IDBridge.split("tt0133093"))
        // Ya traducido, Trakt lo usa sin esperar.
        XCTAssertEqual(TraktTarget(videoID: "tmdb:1399:1:2", kind: "series"), TraktTarget(imdb: "tt0944947", season: 1, episode: 2))
        XCTAssertEqual(TraktTarget(videoID: "kitsu:1376", kind: "movie"), TraktTarget(imdb: "tt0213338"))
        XCTAssertNil(TraktTarget(videoID: "kitsu:99999", kind: "movie"), "lo que no se sabe sigue sin ir a Trakt")
        let calls = http.calls.count
        _ = await bridge.videoID("kitsu:1376", kind: "movie")
        XCTAssertEqual(http.calls.count, calls, "se recuerda")
    }
}
