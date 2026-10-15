import XCTest
@testable import OrbitalCore

final class OrbitalRemoteTests: XCTestCase {
    func testAddressesAreForgivingAndAlwaysHTTPS() {
        XCTAssertEqual(OrbitalRemote.normalize("orbital.casa.mx")?.absoluteString, "https://orbital.casa.mx")
        XCTAssertEqual(OrbitalRemote.normalize(" https://orbital.casa.mx/// ")?.absoluteString, "https://orbital.casa.mx")
        XCTAssertNil(OrbitalRemote.normalize(""))
        XCTAssertNil(OrbitalRemote.normalize("ftp://x"))
    }

    func testPlaySendsTheEpisodeWithTheToken() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/stremio/play"] = ["ok": true]
        let remote = OrbitalRemote(http: http, address: "tv.example", token: " secreto ")
        try await remote.play(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", title: "The Office")
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(http.bodies(for: "https://tv.example/api/stremio/play").first)))
        XCTAssertEqual(sent["video_id"]?.string, "tt0386676:2:5")
        XCTAssertEqual(sent["kind"]?.string, "series")
    }

    func testFailuresSayWhatToDo() async {
        let http = FakeHTTP()
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        http.statuses["https://tv.example/api/ping"] = 401
        http.json["https://tv.example/api/ping"] = ["detail": "Token inválido"]
        do { try await remote.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .badToken) }
        http.fail = true
        do { try await remote.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .unreachable) }
        let empty = OrbitalRemote(http: http, address: "", token: "")
        XCTAssertFalse(empty.isConfigured)
        do { try await empty.play(kind: "movie", metaID: "tt1", videoID: nil, title: "x"); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .notConfigured) }
    }

    func testTheTVsQRCodeConnectsWithoutTyping() {
        let pair = OrbitalRemote.pairing(URL(string: "orbital-ios://pair?u=https%3A%2F%2Flegion.tail1.ts.net&t=abc%2B1")!)
        XCTAssertEqual(pair?.address, "https://legion.tail1.ts.net")
        XCTAssertEqual(pair?.token, "abc+1")
        XCTAssertNil(OrbitalRemote.pairing(URL(string: "orbital-ios://infuse-done?x=1")!))
        XCTAssertNil(OrbitalRemote.pairing(URL(string: "orbital-ios://pair?u=&t=x")!))
    }

    func testKeysCarryTheConsolesTraktSession() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion"] = ["tmdb_key": "k", "trakt_client_id": "c", "region": "MX",
                                                         "trakt_session": ["access_token": "AT", "expires_at": 1_760_100_000]]
        let keys = try await OrbitalRemote(http: http, address: "tv.example", token: "x").keys()
        XCTAssertEqual(keys.traktSession, BorrowedSession(accessToken: "AT", expiresAt: 1_760_100_000))
    }
}
