import XCTest
@testable import OrbitalCore

final class ForYouTests: XCTestCase {
    let api = "https://api.trakt.tv"
    func entry(_ imdb: String, _ title: String, kind: String = "show") -> JSON {
        [kind: ["title": .string(title), "year": 2020, "ids": ["imdb": .string(imdb), "trakt": 1]]]
    }

    func makeForYou(_ http: FakeHTTP, linked: Bool = true, tmdbKey: String = "", clock: Clock = Clock()) -> ForYou {
        let secrets = InMemorySecrets()
        if linked { secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#) }
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        let tmdb = tmdbKey.isEmpty ? nil : Tmdb(http: http, key: tmdbKey)
        return ForYou(trakt: trakt, tmdb: tmdb, region: { "MX" }, kv: InMemoryKeyValueStore(), clock: { clock.now })
    }

    func stubTrakt(_ http: FakeHTTP) {
        http.json["\(api)/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = [
            ["type": "show", "listed_at": "2025-06-01T00:00:00.000Z", "show": ["title": "Severance", "ids": ["imdb": "tt11280740"]]],
            ["type": "movie", "listed_at": "2025-05-01T00:00:00.000Z", "movie": ["title": "Dune", "ids": ["imdb": "tt1160419"]]]]
        http.json["\(api)/recommendations/shows?limit=30&ignore_collected=true&ignore_watchlisted=true&extended=full"] = [
            ["title": "Shōgun", "ids": ["imdb": "tt2788316"]], ["title": "Severance", "ids": ["imdb": "tt11280740"]]]
        http.json["\(api)/recommendations/movies?limit=30&ignore_collected=true&ignore_watchlisted=true&extended=full"] = [["title": "Past Lives", "ids": ["imdb": "tt13238346"]]]
        http.json["\(api)/users/me/lists"] = [["name": "Terror", "ids": ["trakt": 77]]]
        http.json["\(api)/users/me/lists/77/items?extended=full"] = [["type": "movie", "movie": ["title": "Hereditary", "ids": ["imdb": "tt7784604"]]]]
        http.json["\(api)/sync/history/episodes?limit=100"] = []
    }

    func testMosaicMixesYourTraktSourcesWithoutRepeatsAndOnlyMoviesAndSeries() async {
        let http = FakeHTTP(); stubTrakt(http)
        let items = await makeForYou(http).mosaic()
        let imdbs = items.map(\.imdb)
        XCTAssertEqual(Set(imdbs).count, imdbs.count, "sin repetidos")
        XCTAssertEqual(Set(imdbs), ["tt2788316", "tt11280740", "tt13238346", "tt1160419", "tt7784604"])
        XCTAssertTrue(items.allSatisfy { ["movie", "series"].contains($0.kind) }, "sin juegos")
        XCTAssertEqual(items.first(where: { $0.imdb == "tt11280740" })?.reason, .inWatchlist, "se entrelaza una por fuente y turno, como en Orbital: la watchlist llega antes que la segunda recomendación")
        XCTAssertTrue(items[0].poster.contains("images.metahub.space/poster/medium/"))
    }

    func testListsShowMineBeforeDiscover() async {
        let http = FakeHTTP(); stubTrakt(http)
        http.json["https://api.themoviedb.org/3/watch/providers/movie?watch_region=MX&api_key=K&language=es-MX"] = ["results": [["provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.jpg"]]]
        http.json["https://api.themoviedb.org/3/watch/providers/tv?watch_region=MX&api_key=K&language=es-MX"] = ["results": []]
        let lists = await makeForYou(http, tmdbKey: "K").lists()
        XCTAssertEqual(lists.map(\.id), ["watchlist", "mine", "estrenos", "list:77", "recs", "trend", "popular", "netflix"])
        XCTAssertEqual(lists.map(\.group), [.mine, .mine, .mine, .mine, .discover, .discover, .discover, .platforms])
        XCTAssertEqual(lists.first { $0.id == "list:77" }?.title, "Terror")
        XCTAssertEqual(lists.last?.brand, "netflix")
    }

    func testPlatformItemsNeedTheIMDbIdAndKeepGoingWhenOneFails() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/watch/providers/movie?watch_region=MX&api_key=K&language=es-MX"] = ["results": [["provider_id": 8, "provider_name": "Netflix"]]]
        http.json["https://api.themoviedb.org/3/watch/providers/tv?watch_region=MX&api_key=K&language=es-MX"] = ["results": []]
        http.json["https://api.themoviedb.org/3/discover/tv?with_watch_providers=8&watch_region=MX&sort_by=popularity.desc&with_watch_monetization_types=flatrate&page=1&api_key=K&language=es-MX"] =
            ["results": [["id": 1], ["id": 2], ["id": 3]]]
        http.json["https://api.themoviedb.org/3/tv/1?append_to_response=external_ids&api_key=K&language=es-MX"] = ["id": 1, "name": "Uno", "external_ids": ["imdb_id": "tt1"], "poster_path": "/p.jpg"]
        http.json["https://api.themoviedb.org/3/tv/2?append_to_response=external_ids&api_key=K&language=es-MX"] = ["id": 2, "name": "Sin IMDb", "external_ids": [:]]
        // el 3 no responde: se salta
        let items = try await makeForYou(http, linked: false, tmdbKey: "K").items(listID: "netflix", kind: "series")
        XCTAssertEqual(items.map(\.imdb), ["tt1"])
        XCTAssertEqual(items.first?.reason, .onPlatform("Netflix"))
        XCTAssertEqual(items.first?.poster, "https://image.tmdb.org/t/p/w500/p.jpg")
    }

    func testWithoutTraktTheMosaicFallsBackToPlatforms() async {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/watch/providers/movie?watch_region=MX&api_key=K&language=es-MX"] = ["results": [["provider_id": 8, "provider_name": "Netflix"]]]
        http.json["https://api.themoviedb.org/3/watch/providers/tv?watch_region=MX&api_key=K&language=es-MX"] = ["results": []]
        http.json["https://api.themoviedb.org/3/discover/tv?with_watch_providers=8&watch_region=MX&sort_by=popularity.desc&with_watch_monetization_types=flatrate&page=1&api_key=K&language=es-MX"] = ["results": [["id": 1]]]
        http.json["https://api.themoviedb.org/3/tv/1?append_to_response=external_ids&api_key=K&language=es-MX"] = ["id": 1, "name": "Uno", "external_ids": ["imdb_id": "tt1"]]
        let secrets = InMemorySecrets()
        let forYou = ForYou(trakt: Trakt(http: http, secrets: secrets, clientID: ""), tmdb: Tmdb(http: http, key: "K"), region: { "MX" }, kv: InMemoryKeyValueStore())
        let items = await forYou.mosaic()
        XCTAssertEqual(items.map(\.imdb), ["tt1"])
    }

    func testDismissedSuggestionsDoNotComeBack() async throws {
        let http = FakeHTTP(); stubTrakt(http)
        let kv = InMemoryKeyValueStore(), clock = Clock()
        let make = { () -> ForYou in
            let secrets = InMemorySecrets()
            secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
            return ForYou(trakt: Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in }), tmdb: nil, region: { "MX" }, kv: kv, clock: { clock.now })
        }
        let first = make()
        await first.dismiss("tt2788316")
        let again = try await make().items(listID: "recs", kind: "series")
        XCTAssertEqual(again.map(\.imdb), ["tt11280740"], "el «No me interesa» se recuerda aunque se cierre la app")
    }

    func testWatchlistKeysForTheInWatchlistBadge() async {
        let http = FakeHTTP(); stubTrakt(http)
        let keys = await makeForYou(http).watchlistKeys()
        XCTAssertEqual(keys, ["tt11280740", "tt1160419"])
        let none = await makeForYou(http, linked: false).watchlistKeys()
        XCTAssertTrue(none.isEmpty)
    }

    func testAFailingSourceDoesNotBringDownTheMosaic() async {
        let http = FakeHTTP(); stubTrakt(http)
        http.statuses["\(api)/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = 500
        let items = await makeForYou(http).mosaic()
        XCTAssertFalse(items.isEmpty)
        XCTAssertFalse(items.contains { $0.reason == .inWatchlist })
    }

    func testInterleaveTakesOneFromEachSourcePerTurn() {
        func s(_ id: String) -> Suggestion { Suggestion(kind: "movie", imdb: id, title: id, year: nil, runtime: nil, overview: "", poster: "", wide: "", reason: .popular, next: nil) }
        let out = ForYou.interleave([[s("a1"), s("a2"), s("a3")], [s("b1"), s("a1")], [s("c1")]], limit: 10)
        XCTAssertEqual(out.map(\.imdb), ["a1", "b1", "c1", "a2", "a3"])
        XCTAssertEqual(ForYou.interleave([[s("a1"), s("a2")]], limit: 1).count, 1)
    }

    func testUpcomingEpisodesByDayInLocalTimeGroupingDropsAndSkippingThePast() async throws {
        let http = FakeHTTP()
        // 1_760_000_000 = 9 oct 2025 08:53 UTC = 02:53 en la Ciudad de México (UTC−6): hoy es el 9.
        var mexico = Calendar(identifier: .gregorian)
        mexico.timeZone = TimeZone(secondsFromGMT: -6 * 3600)!
        func row(_ imdb: String, _ title: String, _ episode: Int, _ aired: String, network: String = "") -> JSON {
            ["first_aired": .string(aired), "episode": ["season": 2, "number": .int(episode), "title": .string("Episodio \(episode)")],
             "show": ["title": .string(title), "network": .string(network), "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        http.json["\(api)/calendars/my/shows/2025-10-08/16?extended=full"] = [
            row("tt0000001", "Ya salió", 1, "2025-10-08T20:00:00.000Z"),                      // ayer, aquí
            row("tt11280740", "Severance", 7, "2025-10-10T02:00:00.000Z", network: "Apple TV"), // hoy 20:00
            row("tt9253284", "Andor", 4, "2025-10-10T07:00:00.000Z"),                          // mañana 01:00 (madrugada)
            row("tt9253284", "Andor", 6, "2025-10-10T07:00:00.000Z"),
            row("tt9253284", "Andor", 5, "2025-10-10T07:00:00.000Z"),
            row("tt0000002", "Muy lejos", 1, "2025-10-30T20:00:00.000Z"),                     // más de 14 días
            ["first_aired": "2025-10-10T02:00:00.000Z", "episode": ["season": 1, "number": 1], "show": ["title": "Sin IMDb", "ids": ["trakt": 9]]]]
        let airings = try await makeForYou(http).calendar(calendar: mexico)
        XCTAssertEqual(airings.map(\.series.title), ["Severance", "Andor"])
        let severance = airings[0], andor = airings[1]
        XCTAssertEqual(severance.episodeLabel, "T2 E7")
        XCTAssertEqual(severance.episodeTitle, "Episodio 7")
        XCTAssertEqual(severance.network, "Apple TV")
        XCTAssertFalse(severance.atDawn)
        XCTAssertEqual(severance.day, mexico.startOfDay(for: Clock().now), "sale hoy, en la hora de aquí")
        XCTAssertEqual(andor.episodeLabel, "T2 E4–E6", "tres episodios el mismo día: una sola tarjeta")
        XCTAssertEqual(andor.count, 3)
        XCTAssertTrue(andor.atDawn, "a la 1:00: «Desde la madrugada»")
        XCTAssertEqual(andor.series.kind, "series", "pulsar abre la ficha de la serie")
        XCTAssertEqual(AiringDay.byDay(airings).map { $0.airings.count }, [1, 1], "hoy y mañana")
        let week = AiringDay.week(airings, from: Clock().now, calendar: mexico)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map { $0.airings.count }, [1, 1, 0, 0, 0, 0, 0], "los días sin nada también están")
    }

    func testNoUpcomingEpisodesWithoutTrakt() async throws {
        let airings = try await makeForYou(FakeHTTP(), linked: false).calendar()
        XCTAssertTrue(airings.isEmpty)
    }
}
