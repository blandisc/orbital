import XCTest
@testable import OrbitalModels
@testable import OrbitalCore
import OrbitalAddons

/// Tus pedidos en la app con la libreta del acuerdo S2: avisa solo el aparato que lo pidió, y lo de otra cuenta se enseña
/// pero no se sigue, no se cancela y no sale como versión.
@MainActor
final class DebridRequestsModelTests: XCTestCase {
    let rd = "https://api.real-debrid.com/rest/1.0/"

    func entry(_ hash: Character, rd: String, meta: String, by: String, account: String?) -> DebridRequest {
        var e = DebridRequest(hash: String(repeating: hash, count: 40), account: account, rdID: rd, title: meta, kind: "movie", metaID: meta, videoIDs: [meta],
                              device: by, createdAt: Date(timeIntervalSince1970: 1_760_000_000), percent: 10, state: .downloading)
        e.pending = false
        return e
    }

    func testOnlyTheRequestingDeviceNotifiesAndAnotherAccountIsOnlyShown() async throws {
        let rig = try ServicesRig()
        rig.secrets.set(AddonKeys.realDebridToken, String(repeating: "K", count: 52))
        rig.http.json[rd + "user"] = ["id": 111, "username": "fer", "type": "premium", "premium": 86400]
        let model = rig.services.debridRequests
        let book = model.requester.book
        book.put(entry("a", rd: "R1", meta: "tt1", by: "iPhone", account: "111"))     // lo pediste aquí
        book.put(entry("b", rd: "R2", meta: "tt2", by: "TV", account: "111"))         // la TV, con tu cuenta
        book.put(entry("c", rd: "R3", meta: "tt3", by: "TV", account: "999"))         // la TV, con otra cuenta
        rig.http.json[rd + "torrents?limit=100"] = .array([
            ["id": "R1", "hash": .string(String(repeating: "a", count: 40)), "filename": "x", "status": "downloaded", "progress": 100],
            ["id": "R2", "hash": .string(String(repeating: "b", count: 40)), "filename": "x", "status": "downloaded", "progress": 100],
            ["id": "R3", "hash": .string(String(repeating: "c", count: 40)), "filename": "x", "status": "downloaded", "progress": 100],
        ])
        var told: [String] = []
        model.onReady = { told.append($0.metaID) }
        await model.refresh()
        XCTAssertEqual(told, ["tt1"], "avisa solo el aparato que lo pidió")
        XCTAssertEqual(model.requests.count, 3, "lo de otra cuenta se enseña")
        let theirs = try XCTUnwrap(model.requests.first { $0.metaID == "tt3" })
        XCTAssertTrue(model.isOtherAccount(theirs))
        XCTAssertEqual(theirs.state, .downloading, "no se sigue")
        XCTAssertNil(model.request(metaID: "tt3", videoID: "tt3"), "no sale como versión")
        XCTAssertNil(model.request(hash: theirs.hash))
        let cancelled = await model.cancel(theirs)
        XCTAssertFalse(cancelled, "no se cancela desde aquí")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("torrents/delete") })
    }
}
