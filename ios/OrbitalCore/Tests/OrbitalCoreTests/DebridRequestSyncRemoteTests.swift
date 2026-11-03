import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// `GET/POST /api/realdebrid/requests` contra tu Orbital (contrato › `requests` › `routes`). Todavía apagada en la app
/// (`NoDebridRequestSync`) hasta que el corte S2 de la TV esté en main.
final class DebridRequestSyncRemoteTests: XCTestCase {
    let url = "https://orbital.example.com/api/realdebrid/requests"
    let infoHash = "0123456789abcdef0123456789abcdef01234567"

    func sync(_ http: FakeHTTP, address: String = "https://orbital.example.com") -> OrbitalRemoteDebridRequestSync {
        let device = OrbitalRemote.Device(name: "iPhone de Fernando", kind: "iphone", id: "ABC")
        return OrbitalRemoteDebridRequestSync { OrbitalRemote(http: http, address: address, token: "TOKEN", device: device) }
    }

    func testPullReadsEachEntryAndTheTVsAccount() async throws {
        let http = FakeHTTP()
        http.raw[url] = Data(#"{"version": 1, "account": "999", "requests": [{"hash": "\#(infoHash)", "by": "TV", "state": "ready", "percent": 100}, {"hash": null}]}"#.utf8)
        let maybe = await sync(http).pull()
        let pulled = try XCTUnwrap(maybe)
        XCTAssertEqual(pulled.account, "999")
        XCTAssertEqual(pulled.requests.map(\.hash), [infoHash])
        XCTAssertEqual(http.headers.first?["Authorization"], "Bearer TOKEN")
        XCTAssertEqual(http.headers.first?["X-Orbital-Device-Id"], "ABC")
    }

    func testPushSendsTheEntryWithoutWhatStaysHereAndReadsWhatTheTVSaved() async throws {
        let http = FakeHTTP()
        http.raw[url] = Data(#"{"hash": "\#(infoHash)", "rd_id": "RD1", "by": "iPhone de Fernando", "state": "downloading", "percent": 12, "updated": 1800000100}"#.utf8)
        var entry = DebridRequest(hash: infoHash, fileIdx: 1, account: "111", rdID: "RD1", title: "The Office", kind: "series", metaID: "tt0386676",
                                  videoIDs: ["tt0386676:1:2"], season: 1, episode: 2, device: "iPhone de Fernando", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        entry.notified = true; entry.nudged = true
        let saved = await sync(http).push(entry)
        XCTAssertEqual(saved?.percent, 12)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.bodies(for: url).first)) as? [String: Any])
        XCTAssertNil(body["notified"]); XCTAssertNil(body["nudged"]); XCTAssertNil(body["updated"]); XCTAssertNil(body["url"])
        XCTAssertEqual(body["files"] as? [String: Int], ["tt0386676:1:2": 1])
        XCTAssertEqual(http.headers.first?["Content-Type"], "application/json")
    }

    func testOnlyOverHttpsOrTailscale() async {
        let http = FakeHTTP()
        let plain = sync(http, address: "http://orbital.example.com")
        let pulled = await plain.pull()
        XCTAssertNil(pulled)
        XCTAssertTrue(http.calls.isEmpty, "por http a la vista no sale nada")
        http.raw["http://100.100.1.2:8710/api/realdebrid/requests"] = Data(#"{"version": 1, "account": null, "requests": []}"#.utf8)
        let tailscale = await sync(http, address: "http://100.100.1.2:8710").pull()
        XCTAssertEqual(tailscale?.requests, [])
    }

    func testAnOldTVWithoutTheRouteIsNothing() async {
        let http = FakeHTTP()   // 404: la TV todavía no tiene su corte S2
        let pulled = await sync(http).pull()
        XCTAssertNil(pulled)
        let entry = DebridRequest(hash: infoHash, title: "x", kind: "movie", metaID: "tt1", videoIDs: ["tt1"], device: "iPhone", createdAt: Date())
        let saved = await sync(http).push(entry)
        XCTAssertNil(saved)
    }
}
