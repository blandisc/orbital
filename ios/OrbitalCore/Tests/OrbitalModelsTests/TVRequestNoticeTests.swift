import XCTest
@testable import OrbitalModels
@testable import OrbitalCore
import OrbitalAddons

/// R14-B (Fernando, 3 nov): el iPhone también avisa «Ya está…» de lo que pidió la TV con tu misma cuenta de Real-Debrid, al
/// notarlo en su propio vistazo (la libreta de la TV y Real-Debrid). Una vez, nunca de otra cuenta, nunca de lo que ya llegó
/// listo, y solo en el iPhone (el iPad y la Mac no, para que no suene en todos).
@MainActor
final class TVRequestNoticeTests: XCTestCase {
    let rd = "https://api.real-debrid.com/rest/1.0/"
    let infoHash = String(repeating: "d", count: 40)

    /// La libreta de la TV, a mano.
    final class TVBook: DebridRequestSync, @unchecked Sendable {
        var pulled: DebridRequestPull?
        func pull() async -> DebridRequestPull? { pulled }
        func push(_ request: DebridRequest) async -> DebridRequest? { request }
    }

    func tvEntry(_ state: DebridRequest.State, account: String? = "111", percent: Int = 40) -> DebridRequest {
        var e = DebridRequest(hash: infoHash, account: account, rdID: "RT", title: "Nocturne", kind: "series", metaID: "tt9", videoIDs: ["tt9:1:2"],
                              season: 1, episode: 2, device: "TV", createdAt: Date().addingTimeInterval(-3600), percent: percent, state: state)
        e.pending = false
        return e
    }

    func torrents(_ status: String, progress: Int) -> JSON {
        .array([["id": "RT", "hash": .string(infoHash), "filename": "x", "status": .string(status), "progress": .int(progress)]])
    }

    /// El modelo de pedidos de ese aparato, con la libreta de la TV de mentira y tu cuenta «111».
    func make(_ rig: ServicesRig, tv: TVBook, notifiesTV: Bool) -> DebridRequestsModel {
        let http = rig.http
        let requester = DebridRequester(book: rig.services.debridRequests.requester.book, api: RealDebridTorrents(http: http), token: { "KEY" },
                                        device: { "iPhone de Fernando" }, account: { "111" }, sync: tv)
        let services = rig.services
        let model = DebridRequestsModel(requester: requester, lookup: TorrentLookup(http: http), addonList: services.addonList,
                                        finder: { services.finder }, hasKey: { true }, clock: { Date() })
        model.notifiesTVRequests = notifiesTV
        return model
    }

    func testATVRequestThatTurnsReadyNotifiesOnce() async throws {
        let rig = try ServicesRig()
        let tv = TVBook()
        let model = make(rig, tv: tv, notifiesTV: true)
        var told: [DebridRequest] = []
        model.onReady = { told.append($0) }
        tv.pulled = DebridRequestPull(account: "111", requests: [tvEntry(.downloading)])
        rig.http.json[rd + "torrents?limit=100"] = torrents("downloading", progress: 40)
        await model.refresh()
        XCTAssertTrue(told.isEmpty, "en camino: nada todavía")
        tv.pulled = DebridRequestPull(account: "111", requests: [tvEntry(.ready, percent: 100)])
        rig.http.json[rd + "torrents?limit=100"] = torrents("downloaded", progress: 100)
        await model.refresh()
        XCTAssertEqual(told.map(\.metaID), ["tt9"], "quedó listo: «Ya está T1 E2 · Nocturne · Lo pediste desde la TV»")
        XCTAssertEqual(told.first?.device, DebridRequestsModel.tvDevice)
        await model.refresh()
        XCTAssertEqual(told.count, 1, "nunca dos veces (`notified`, de este aparato)")
    }

    func testNeverForAnotherAccount() async throws {
        let rig = try ServicesRig()
        let tv = TVBook()
        let model = make(rig, tv: tv, notifiesTV: true)
        var told: [DebridRequest] = []
        model.onReady = { told.append($0) }
        tv.pulled = DebridRequestPull(account: "999", requests: [tvEntry(.downloading, account: "999")])
        await model.refresh()
        tv.pulled = DebridRequestPull(account: "999", requests: [tvEntry(.ready, account: "999", percent: 100)])
        await model.refresh()
        XCTAssertTrue(told.isEmpty, "lo que la TV pide con otra cuenta no suena aquí")
    }

    func testNeverForWhatIsAlreadyReadyWhenFirstSeen() async throws {
        let rig = try ServicesRig()
        let tv = TVBook()
        let model = make(rig, tv: tv, notifiesTV: true)
        var told: [DebridRequest] = []
        model.onReady = { told.append($0) }
        tv.pulled = DebridRequestPull(account: "111", requests: [tvEntry(.ready, percent: 100)])   // p. ej., recién conectada
        await model.refresh()
        await model.refresh()
        XCTAssertTrue(told.isEmpty, "lo que ya llegó listo se marca avisado en silencio")
        XCTAssertEqual(model.requester.book.find(hash: infoHash)?.notified, true)
    }

    func testOnlyTheIPhone() async throws {
        XCTAssertTrue(try ServicesRig().services.debridRequests.notifiesTVRequests, "el iPhone avisa")
        XCTAssertFalse(try ServicesRig(platform: "ipad").services.debridRequests.notifiesTVRequests, "el iPad no (no suena en todos)")
        XCTAssertFalse(try ServicesRig(platform: "mac", allowsOrbital: false).services.debridRequests.notifiesTVRequests, "la Mac nunca habla con la TV")
        // Y sin la bandera (iPad o Mac), una de la TV que queda lista no suena.
        let rig = try ServicesRig(platform: "ipad")
        let tv = TVBook()
        let model = make(rig, tv: tv, notifiesTV: false)
        var told: [DebridRequest] = []
        model.onReady = { told.append($0) }
        tv.pulled = DebridRequestPull(account: "111", requests: [tvEntry(.downloading)])
        rig.http.json[rd + "torrents?limit=100"] = torrents("downloading", progress: 40)
        await model.refresh()
        tv.pulled = DebridRequestPull(account: "111", requests: [tvEntry(.ready, percent: 100)])
        rig.http.json[rd + "torrents?limit=100"] = torrents("downloaded", progress: 100)
        await model.refresh()
        XCTAssertTrue(told.isEmpty)
    }
}
