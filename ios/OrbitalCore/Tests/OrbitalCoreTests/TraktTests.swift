import XCTest
@testable import OrbitalCore

final class TraktTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func makeTrakt(_ http: FakeHTTP, secrets: InMemorySecrets = InMemorySecrets(), clock: Clock = Clock(), linked: Bool = true) -> Trakt {
        if linked {
            let expires = clock.now.timeIntervalSince1970 + 7 * 86400
            secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(expires)}"#)
        }
        return Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
    }

    func testEntryAndTypedMatchPython() throws {
        let golden = try Fixtures.json("ios/trakt.json")
        for (i, c) in try XCTUnwrap(golden["entry"]?.array).enumerated() {
            let got = TraktParsing.entry(c["raw"], kind: c["kind"]!.string!)
            let raw = c["result"]
            let wantNil = raw == nil || raw!.isNull
            XCTAssertEqual(got == nil, wantNil, "caso \(i)")
            if let got, let want = raw, !wantNil {
                XCTAssertEqual(got.imdb, want["imdb"]?.string); XCTAssertEqual(got.title, want["title"]?.string)
                XCTAssertEqual(got.year, want["year"]?.intValue); XCTAssertEqual(got.runtime, want["runtime"]?.intValue)
                XCTAssertEqual(got.episodes, want["episodes"]?.intValue); XCTAssertEqual(got.overview, want["overview"]?.string)
                XCTAssertEqual(got.traktID, want["trakt_id"]?.intValue, "caso \(i)")
            }
        }
        let typed = try XCTUnwrap(golden["typed"])
        let got = TraktParsing.typed(typed["rows"]?.array)
        XCTAssertEqual(got.map(\.imdb), typed["result"]?.array?.compactMap { $0["imdb"]?.string })
        XCTAssertEqual(got.map(\.kind), typed["result"]?.array?.compactMap { $0["kind"]?.string })
    }

    func testTargetFromVideoID() {
        XCTAssertEqual(TraktTarget(videoID: "tt0944947:1:5", kind: "series"), TraktTarget(imdb: "tt0944947", season: 1, episode: 5))
        XCTAssertEqual(TraktTarget(videoID: "tt1160419", kind: "movie"), TraktTarget(imdb: "tt1160419"))
        XCTAssertNil(TraktTarget(videoID: "kitsu:1:7", kind: "series"), "sin IMDb no se puede avisar a Trakt")
        XCTAssertNil(TraktTarget(videoID: "tt1", kind: "series"))
    }

    func testDeviceCodeFlowStoresTokens() async throws {
        let http = FakeHTTP(), secrets = InMemorySecrets()
        http.json["\(api)/oauth/device/code"] = ["device_code": "DC", "user_code": "ABCD1234", "verification_url": "https://trakt.tv/activate", "interval": 5, "expires_in": 600]
        http.json["\(api)/oauth/device/token"] = ["access_token": "AT", "refresh_token": "RT", "created_at": 1_760_000_000, "expires_in": 604800]
        let trakt = makeTrakt(http, secrets: secrets, linked: false)
        XCTAssertFalse(trakt.linked)
        let code = try await trakt.deviceCode()
        XCTAssertEqual(code.userCode, "ABCD1234")
        http.statuses["\(api)/oauth/device/token"] = 400
        let waiting = try await trakt.pollDevice(code)
        XCTAssertEqual(waiting, .pending)
        http.statuses["\(api)/oauth/device/token"] = 200
        let done = try await trakt.pollDevice(code)
        XCTAssertEqual(done, .linked)
        XCTAssertTrue(trakt.linked)
        XCTAssertTrue(secrets.get(SecretKey.traktTokens)?.contains("AT") == true)
    }

    func testExpiredTokenIsRefreshedAndNewRefreshTokenSaved() async throws {
        let http = FakeHTTP(), secrets = InMemorySecrets(), clock = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"OLD","refresh_token":"R1","expires_at":\#(clock.now.timeIntervalSince1970 - 10)}"#)
        http.json["\(api)/oauth/token"] = ["access_token": "NEW", "refresh_token": "R2", "created_at": .double(clock.now.timeIntervalSince1970), "expires_in": 604800]
        http.json["\(api)/users/settings"] = ["user": ["username": "fer", "name": "Fer"]]
        let trakt = makeTrakt(http, secrets: secrets, clock: clock, linked: false)
        let name = try await trakt.username()
        XCTAssertEqual(name, "Fer")
        let tokens = try XCTUnwrap(secrets.get(SecretKey.traktTokens))
        XCTAssertTrue(tokens.contains("NEW") && tokens.contains("R2"), "se guarda el refresh token nuevo")
    }

    func testRefreshFailureUnlinksAndAsksToReconnect() async {
        let http = FakeHTTP(), secrets = InMemorySecrets(), clock = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"OLD","refresh_token":"R1","expires_at":\#(clock.now.timeIntervalSince1970 - 10)}"#)
        http.statuses["\(api)/oauth/token"] = 401
        http.json["\(api)/oauth/token"] = [:]
        let trakt = makeTrakt(http, secrets: secrets, clock: clock, linked: false)
        do { _ = try await trakt.username(); XCTFail() } catch let error as TraktError {
            guard case .auth = error else { return XCTFail("\(error)") }
        } catch { XCTFail("\(error)") }
        XCTAssertFalse(trakt.linked)
    }

    func testWatchlistIsSortedAndTyped() async throws {
        let http = FakeHTTP()
        http.json["\(api)/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = [
            ["type": "movie", "listed_at": "2025-01-01T00:00:00.000Z", "movie": ["title": "Vieja", "ids": ["imdb": "tt1"]]],
            ["type": "show", "listed_at": "2025-06-01T00:00:00.000Z", "show": ["title": "Nueva", "ids": ["imdb": "tt2"]]],
            ["type": "movie", "listed_at": "2025-07-01T00:00:00.000Z", "movie": ["title": "Sin imdb", "ids": [:]]]]
        let list = try await makeTrakt(http).watchlist()
        XCTAssertEqual(list.map(\.title), ["Nueva", "Vieja"])
        XCTAssertEqual(list.map(\.kind), ["series", "movie"])
    }

    func testScrobbleResults() async throws {
        let http = FakeHTTP()
        let trakt = makeTrakt(http)
        let target = TraktTarget(imdb: "tt0386676", season: 1, episode: 2)
        http.json["\(api)/scrobble/stop"] = [:]
        let sent = try await trakt.scrobble(.stop, target, progress: 95)
        XCTAssertEqual(sent, .sent)
        let body = try XCTUnwrap(http.bodies(for: "\(api)/scrobble/stop").first.flatMap(JSON.parse))
        XCTAssertEqual(body["episode"]?["season"]?.intValue, 1)
        XCTAssertEqual(body["show"]?["ids"]?["imdb"]?.string, "tt0386676")
        XCTAssertEqual(body["progress"]?.intValue, 95)
        http.statuses["\(api)/scrobble/stop"] = 409
        let duplicate = try await trakt.scrobble(.stop, target, progress: 95)
        XCTAssertEqual(duplicate, .duplicate)
        http.statuses["\(api)/scrobble/stop"] = 422
        let tiny = try await trakt.scrobble(.stop, target, progress: 0.2)
        XCTAssertEqual(tiny, .ignored)
        http.statuses["\(api)/scrobble/stop"] = 500
        do { _ = try await trakt.scrobble(.stop, target, progress: 90); XCTFail() } catch { XCTAssertTrue("\(error)".contains("500")) }
    }

    func testHistoryDoesNotRepeatWhatTraktAlreadyHas() async throws {
        let http = FakeHTTP(), clock = Clock()
        let trakt = makeTrakt(http, clock: clock)
        let when = clock.now.addingTimeInterval(-3600)
        let movie = TraktTarget(imdb: "tt1160419")
        http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 55]]]]
        let start = StremioLibrary.iso(when.addingTimeInterval(-12 * 3600).timeIntervalSince1970), end = StremioLibrary.iso(when.addingTimeInterval(12 * 3600).timeIntervalSince1970)
        let historyURL = "\(api)/sync/history/movies/55?start_at=\(start)&end_at=\(end)&limit=100"
        http.json[historyURL] = [["id": 1]]
        http.json["\(api)/sync/history"] = [:]
        let skipped = try await trakt.addToHistory(movie, watchedAt: when)
        XCTAssertFalse(skipped)
        XCTAssertTrue(http.bodies(for: "\(api)/sync/history").isEmpty)
        http.json[historyURL] = []
        let added = try await trakt.addToHistory(movie, watchedAt: when)
        XCTAssertTrue(added)
        let body = try XCTUnwrap(http.bodies(for: "\(api)/sync/history").first.flatMap(JSON.parse))
        XCTAssertEqual(body["movies"]?.array?.first?["watched_at"]?.string, StremioLibrary.iso(when.timeIntervalSince1970), "con la fecha real")
    }

    func testWritesAreSpacedOneSecondApart() async throws {
        let http = FakeHTTP(), clock = Clock()
        let slept = Sleeps()
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { await slept.add($0) })
        http.json["\(api)/scrobble/start"] = [:]
        try await trakt.scrobble(.start, TraktTarget(imdb: "tt1"), progress: 1)
        try await trakt.scrobble(.start, TraktTarget(imdb: "tt1"), progress: 2)
        let total = await slept.total
        XCTAssertGreaterThan(total, 0.9)
    }

    func testAuthErrorOnReadClearsSession() async {
        let http = FakeHTTP(), secrets = InMemorySecrets()
        http.statuses["\(api)/users/me/lists"] = 401
        http.json["\(api)/users/me/lists"] = [:]
        let trakt = makeTrakt(http, secrets: secrets)
        do { _ = try await trakt.lists(); XCTFail() } catch { XCTAssertFalse(trakt.linked) }
    }
}

actor Sleeps { var total = 0.0; func add(_ v: TimeInterval) { total += v } }
