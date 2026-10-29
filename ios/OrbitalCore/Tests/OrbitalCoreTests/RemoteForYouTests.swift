import XCTest
@testable import OrbitalCore

/// «Para ti» tomado de tu Orbital por el puerto público (CEN-18): convierte el JSON de `/api/foryou*` en los mismos
/// tipos que `ForYou` local, sin juegos y conservando el puesto de un chart.
final class RemoteForYouTests: XCTestCase {
    private func remote(_ http: FakeHTTP) -> RemoteForYou {
        RemoteForYou(remote: { OrbitalRemote(http: http, address: "tv.example", token: "secreto") })
    }

    /// Desacoplar Stremio: en el iPhone ningún estante dice «Stremio» ni «Cinemeta», venga de una consola nueva o de una anterior.
    func testListOriginsNeverSayStremio() async throws {
        let http = FakeHTTP()
        func row(_ id: String, _ source: String) -> JSON { ["id": .string(id), "title": "x", "source": .string(source), "meta": "", "split": false] }
        http.json["https://tv.example/api/foryou"] = ["lists": [row("cinemeta", "Stremio"), row("addon:a:b", "Stremio"), row("cinemeta", "Cinemeta"),
                                                                row("addon:c:d", "Complemento"), row("critics", "Rotten Tomatoes")], "mosaic": []]
        let lists = try await remote(http).lists()
        XCTAssertEqual(lists.map(\.source), ["", ForYouList.addonSource, "", ForYouList.addonSource, "Rotten Tomatoes"])
    }

    func testOverviewConvertsListsAndKeepsPlatformLogoAndRankInTheMosaic() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/foryou"] = [
            "lists": [
                ["id": "watchlist", "title": "", "icon": "bookmark", "source": "Trakt", "meta": "x", "split": false],
                ["id": "netflix", "title": "Netflix", "icon": "trailer", "source": "TMDB", "meta": "x", "split": true,
                 "brand": "netflix", "logo": "https://logo/netflix.png"],
                ["id": "mygames", "title": "Tus juegos", "group": "games"],   // de la consola: el iPhone no la pide
            ],
            "mosaic": [
                ["key": "video:tt1160419", "id": "cinemeta:movie:tt1160419", "source": "cinemeta", "kind": "movie", "meta_id": "tt1160419",
                 "title": "Dune", "year": 2021, "why": "En Netflix", "rank": 3, "movement": 2, "new": false, "image": "https://img/p.jpg", "hero": "https://img/h.jpg",
                 "overview": "Sinopsis", "video_id": "tt1160419"],
                // Un juego nunca debería llegar por el puerto público (ya se filtra allá), pero por si acaso se filtra aquí también.
                ["key": "game:1", "kind": "game", "title": "Juego"],
            ],
        ]
        let fy = remote(http)
        let lists = try await fy.lists()
        XCTAssertEqual(lists.map(\.id), ["watchlist", "netflix"])
        XCTAssertEqual(lists[0].group, .mine)
        XCTAssertEqual(lists[1].group, .platforms)
        XCTAssertEqual(lists[1].logo, "https://logo/netflix.png")

        let mosaic = try await fy.mosaic()
        XCTAssertEqual(mosaic.map(\.imdb), ["tt1160419"], "el juego no pasa el filtro")
        XCTAssertEqual(mosaic[0].rank, 3)
        XCTAssertEqual(mosaic[0].movement, 2, "subió 2 lugares (Top 10 real de la TV)")
        XCTAssertFalse(mosaic[0].isNew)
        XCTAssertEqual(mosaic[0].reason, .onPlatform("Netflix"))
        XCTAssertEqual(mosaic[0].poster, "https://img/p.jpg")
    }

    func testListItemsConvertKnownReasonsAndTheEpisodeInProgress() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/foryou/list?id=mine&kind=series"] = ["items": [
            ["key": "video:tt0386676", "kind": "series", "meta_id": "tt0386676", "title": "The Office", "year": 2005,
             "why": "Sigues viéndola", "episode": "T2 E5", "video_id": "tt0386676:2:5", "image": "https://p.jpg", "hero": "https://h.jpg", "overview": ""],
        ]]
        let items = try await remote(http).items(listID: "mine", kind: "series")
        XCTAssertEqual(items.map(\.imdb), ["tt0386676"])
        XCTAssertEqual(items[0].reason, .watching)
        XCTAssertEqual(items[0].next?.season, 2)
        XCTAssertEqual(items[0].next?.episode, 5)
    }

    func testAListWithoutAnEpisodeInProgressHasNoNext() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/foryou/list?id=trend&kind=movie"] = ["items": [
            ["key": "video:tt1160419", "kind": "movie", "meta_id": "tt1160419", "title": "Dune", "why": "En tendencia",
             "video_id": "tt1160419:1:1", "image": "https://p.jpg", "hero": "https://h.jpg", "overview": ""],
        ]]
        let items = try await remote(http).items(listID: "trend", kind: "movie")
        XCTAssertEqual(items[0].reason, .trending)
        XCTAssertNil(items[0].next, "sin «episode» en el JSON, el «1:1» del video_id es solo el valor por omisión")
    }

    func testDismissSendsTheConsolesKeyFormat() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/foryou/dismiss"] = ["ok": true]
        await remote(http).dismiss("tt0386676")
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(http.bodies(for: "https://tv.example/api/foryou/dismiss").first)))
        XCTAssertEqual(sent["key"]?.string, "video:tt0386676")
    }

    func testWhenTheConsoleDoesNotAnswerItThrowsSoTheCallerFallsBackToLocal() async {
        let http = FakeHTTP()   // sin registrar /api/foryou: responde 404, como una consola que no la tiene todavía
        do { _ = try await remote(http).lists(); XCTFail("debió lanzar") } catch {}
    }
}
