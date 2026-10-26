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

    /// Un 401 al leer primero intenta renovar la sesión (como al escribir); si Trakt también rechaza la renovación, se desconecta.
    func testAuthErrorOnReadClearsSession() async {
        let http = FakeHTTP(), secrets = InMemorySecrets()
        http.statuses["\(api)/users/me/lists"] = 401
        http.json["\(api)/users/me/lists"] = [:]
        http.statuses["\(api)/oauth/token"] = 401
        http.json["\(api)/oauth/token"] = ["error": "invalid_grant"]
        let trakt = makeTrakt(http, secrets: secrets)
        do { _ = try await trakt.lists(); XCTFail() } catch { XCTAssertFalse(trakt.linked) }
    }

    // MARK: revisión de robustez

    func testTwoCallsWithAnExpiredTokenRefreshOnlyOnce() async throws {
        let http = FakeHTTP(), secrets = InMemorySecrets(), clock = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"OLD","refresh_token":"R1","expires_at":\#(clock.now.timeIntervalSince1970 - 10)}"#)
        http.json["\(api)/oauth/token"] = ["access_token": "NEW", "refresh_token": "R2", "created_at": .double(clock.now.timeIntervalSince1970), "expires_in": 604800]
        http.delays["\(api)/oauth/token"] = 60
        http.json["\(api)/users/settings"] = ["user": ["username": "fer"]]
        http.json["\(api)/users/me/lists"] = []
        let trakt = makeTrakt(http, secrets: secrets, clock: clock, linked: false)
        async let a = trakt.username(), b = trakt.lists()
        _ = try await (a, b)
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/oauth/token") }.count, 1, "un solo refresh: el refresh token es de un solo uso")
        XCTAssertTrue(trakt.linked)
    }

    func testAServerErrorOnRefreshDoesNotDisconnectTheAccount() async {
        let http = FakeHTTP(), secrets = InMemorySecrets(), clock = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"OLD","refresh_token":"R1","expires_at":\#(clock.now.timeIntervalSince1970 - 10)}"#)
        http.statuses["\(api)/oauth/token"] = 503
        http.json["\(api)/oauth/token"] = [:]
        let trakt = makeTrakt(http, secrets: secrets, clock: clock, linked: false)
        do { _ = try await trakt.username(); XCTFail() } catch {}
        XCTAssertTrue(trakt.linked, "un 503 es pasajero: la sesión sigue")
    }

    func testEpisodeHistoryCheckUsesTheShowEndpointAndFindsAnAlreadyWatchedEpisode() async throws {
        let http = FakeHTTP(), clock = Clock()
        let trakt = makeTrakt(http, clock: clock)
        let when = clock.now
        let target = TraktTarget(imdb: "tt0386676", season: 1, episode: 2)
        http.json["\(api)/search/imdb/tt0386676?type=show"] = [["show": ["ids": ["trakt": 1388]]]]
        let start = StremioLibrary.iso(when.addingTimeInterval(-12 * 3600).timeIntervalSince1970), end = StremioLibrary.iso(when.addingTimeInterval(12 * 3600).timeIntervalSince1970)
        http.json["\(api)/sync/history/shows/1388?start_at=\(start)&end_at=\(end)&limit=100"] = [["episode": ["season": 1, "number": 2]], ["episode": ["season": 1, "number": 3]]]
        http.json["\(api)/sync/history"] = [:]
        let already = try await trakt.addToHistory(target, watchedAt: when)
        XCTAssertFalse(already, "ese episodio ya está en el historial: no se repite")
        XCTAssertFalse(http.calls.contains { $0.contains("/sync/history/episodes/") })
        let other = try await trakt.addToHistory(TraktTarget(imdb: "tt0386676", season: 1, episode: 9), watchedAt: when)
        XCTAssertTrue(other)
    }

    func testTwoSimultaneousWritesAreSpacedAndOrdered() async throws {
        let http = FakeHTTP(), clock = Clock(), secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let sleeps = Sleeps()
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { await sleeps.add($0) })
        http.json["\(api)/scrobble/pause"] = [:]; http.json["\(api)/scrobble/stop"] = [:]
        async let a = trakt.scrobble(.pause, TraktTarget(imdb: "tt1"), progress: 50)
        async let b = trakt.scrobble(.stop, TraktTarget(imdb: "tt1"), progress: 95)
        _ = try await (a, b)
        let total = await sleeps.total
        XCTAssertGreaterThanOrEqual(total, 1.0, "la segunda escritura espera su turno aunque la primera siga en vuelo")
    }

    func testInvalidIMDbIdsNeverReachThePath() async throws {
        let http = FakeHTTP()
        let trakt = makeTrakt(http)
        do { try await trakt.setWatchlist(imdb: "../users/me", series: false, add: true); XCTFail() } catch {}
        XCTAssertTrue(http.calls.isEmpty)
        do { _ = try await trakt.addToHistory(TraktTarget(imdb: "tt1/../x"), watchedAt: Date()); XCTFail() } catch {}
        do { _ = try await trakt.scrobble(.start, TraktTarget(imdb: "x"), progress: 1); XCTFail() } catch {}
        XCTAssertTrue(http.calls.isEmpty)
    }

    /// La sesión que antes prestaba tu Orbital (sin refresh token): se olvida aquí sin revocarla; una propia no se toca.
    func testABorrowedSessionIsForgottenLocallyAndNeverRevoked() async throws {
        let http = FakeHTTP(), clock = Clock(), secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"PRESTADA","expires_at":\#(clock.now.timeIntervalSince1970 + 600)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        XCTAssertTrue(trakt.linked); XCTAssertTrue(trakt.borrowed)
        XCTAssertTrue(trakt.forgetBorrowedSession())
        XCTAssertFalse(trakt.linked)
        XCTAssertTrue(http.calls.isEmpty, "ni /oauth/revoke: revocarla desconectaría también la consola")
        let own = makeTrakt(http)
        XCTAssertFalse(own.forgetBorrowedSession(), "la sesión propia del iPhone se queda")
        XCTAssertTrue(own.linked)
    }

    /// Las apps nuevas de Trakt (PKCE) solo tienen Client ID: el código y la sesión van sin `client_secret`; una antigua lo manda.
    func testDeviceLinkWithoutASecretSendsNoClientSecret() async throws {
        let http = FakeHTTP(), secrets = InMemorySecrets()
        http.json["\(api)/oauth/device/code"] = ["device_code": "DC", "user_code": "ABCD1234", "interval": 5, "expires_in": 600]
        http.json["\(api)/oauth/device/token"] = ["access_token": "AT", "refresh_token": "RT", "created_at": 1_760_000_000, "expires_in": 604800]
        let trakt = makeTrakt(http, secrets: secrets, linked: false)
        let code = try await trakt.deviceCode()
        XCTAssertEqual(code.verificationURL, "https://trakt.tv/activate")
        let status = try await trakt.pollDevice(code)
        XCTAssertEqual(status, .linked)
        let body = try XCTUnwrap(JSON.parse(try XCTUnwrap(http.bodies(for: "\(api)/oauth/device/token").first)))
        XCTAssertEqual(body["client_id"]?.string, "CID")
        XCTAssertNil(body["client_secret"])
        let legacy = Trakt(http: http, secrets: InMemorySecrets(), clientID: "CID", clientSecret: "S", pause: { _ in })
        _ = try await legacy.pollDevice(code)
        XCTAssertEqual(JSON.parse(http.bodies(for: "\(api)/oauth/device/token").last!)?["client_secret"]?.string, "S")
    }

    static let playbackRows: JSON = [
        ["progress": .double(31.5), "paused_at": "2026-10-25T20:00:00.000Z", "id": 11, "type": "movie",
         "movie": ["title": "Dune", "ids": ["trakt": 1, "imdb": "tt1160419"]]],
        ["progress": 12, "paused_at": "2026-10-24T20:00:00.000Z", "id": 12, "type": "episode",
         "episode": ["season": 2, "number": 5, "title": "x", "ids": ["trakt": 9]],
         "show": ["title": "The Office", "ids": ["trakt": 2, "imdb": "tt0386676"]]],
        ["progress": 50, "paused_at": "2026-10-26T20:00:00Z", "id": 13, "type": "episode",
         "episode": ["season": 2, "number": 5], "show": ["title": "The Office", "ids": ["trakt": 2, "imdb": "tt0386676"]]],
        ["progress": 40, "paused_at": "2026-10-24T20:00:00Z", "id": 14, "type": "movie", "movie": ["title": "Sin IMDb", "ids": ["trakt": 3]]],
    ]

    func testPlaybackParsesMoviesAndEpisodesByIMDb() throws {
        let rows = try XCTUnwrap(Self.playbackRows.array).compactMap(TraktParsing.playback)
        XCTAssertEqual(rows.map(\.id), [11, 12, 13], "sin IMDb no sirve para seguir")
        XCTAssertEqual(rows[0].target, TraktTarget(imdb: "tt1160419"))
        XCTAssertEqual(rows[0].progress, 31.5)
        XCTAssertEqual(rows[0].pausedAt, TraktParsing.date("2026-10-25T20:00:00.000Z"))
        XCTAssertEqual(rows[1].target, TraktTarget(imdb: "tt0386676", season: 2, episode: 5))
    }

    /// La pausa más reciente de ESE episodio; se guarda un minuto (abrir varios títulos no pregunta cada vez) y una pausa propia
    /// la renueva.
    func testPausedPicksTheMostRecentAndIsCachedBriefly() async throws {
        let http = FakeHTTP(), clock = Clock()
        http.json["\(api)/sync/playback"] = Self.playbackRows
        let trakt = makeTrakt(http, clock: clock)
        let episode = await trakt.paused(TraktTarget(imdb: "tt0386676", season: 2, episode: 5))
        XCTAssertEqual(episode?.id, 13)
        let none = await trakt.paused(TraktTarget(imdb: "tt0386676", season: 1, episode: 1))
        XCTAssertNil(none)
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/sync/playback") }.count, 1, "la segunda pregunta sale de lo guardado")
        clock.now = clock.now.addingTimeInterval(61)
        _ = await trakt.paused(TraktTarget(imdb: "tt1160419"))
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/sync/playback") }.count, 2, "pasado el minuto se vuelve a preguntar")
        http.json["\(api)/scrobble/pause"] = [:]
        try await trakt.scrobble(.pause, TraktTarget(imdb: "tt1160419"), progress: 40)
        _ = await trakt.paused(TraktTarget(imdb: "tt1160419"))
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/sync/playback") }.count, 3, "tras tu propia pausa, lo nuevo")
    }

    func testPausedWithoutASessionAsksNothing() async {
        let http = FakeHTTP()
        let trakt = makeTrakt(http, linked: false)
        let found = await trakt.paused(TraktTarget(imdb: "tt1160419"))
        XCTAssertNil(found)
        XCTAssertTrue(http.calls.isEmpty)
    }
}

actor Sleeps { var total = 0.0; func add(_ v: TimeInterval) { total += v } }

