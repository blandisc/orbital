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
}
