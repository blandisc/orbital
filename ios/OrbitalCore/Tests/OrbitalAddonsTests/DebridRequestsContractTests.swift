import XCTest
@testable import OrbitalAddons

/// La TV de mentira para la libreta: lo que tiene y lo que se le mandó (tal como viajaría).
final class FakeRequestSync: DebridRequestSync, @unchecked Sendable {
    private let lock = NSLock()
    private var _pulled: DebridRequestPull?
    private var _pushed: [Data] = []
    private var _accepts = true
    var pulled: DebridRequestPull? { get { lock.withLock { _pulled } } set { lock.withLock { _pulled = newValue } } }
    var accepts: Bool { get { lock.withLock { _accepts } } set { lock.withLock { _accepts = newValue } } }
    var pushed: [[String: Any]] { lock.withLock { _pushed.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } } }

    func pull() async -> DebridRequestPull? { pulled }
    func push(_ request: DebridRequest) async -> DebridRequest? {
        let data = try! DebridRequestBook.wireEncoder.encode(request)
        return lock.withLock {
            _pushed.append(data)
            return _accepts ? DebridRequestBook.decodeEach(Data("[".utf8) + data + Data("]".utf8)).first : nil
        }
    }
}

/// El acuerdo S2 con la TV (`design/addons-contract.json` › `requests`, RQ-1 a RQ-12): paquetes con todos sus videos,
/// juntar por campo sin relojes, lápidas, cada entrada por separado, lo que nunca viaja y lo de otra cuenta.
final class DebridRequestsContractTests: XCTestCase {
    let infoHash = "0123456789abcdef0123456789abcdef01234567"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func make(account: String? = "111", fake: FakeRealDebrid = FakeRealDebrid(), sync: FakeRequestSync = FakeRequestSync(), clock: Clock = Clock(),
              vault: InMemoryAddonVault = InMemoryAddonVault()) -> DebridRequester {
        DebridRequester(book: DebridRequestBook(vault: vault), api: RealDebridTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000)),
                        token: { "KEY" }, device: { "iPhone de Fernando" }, account: { account }, clock: { clock.now }, sync: sync)
    }

    func wish(_ episode: Int) -> DebridWish {
        DebridWish(hash: infoHash, fileIdx: episode - 1, title: "The Office", kind: "series", metaID: "tt0386676", videoID: "tt0386676:1:\(episode)",
                   season: 1, episode: episode, language: "es-419", release: "The.Office.S01")
    }

    func entry(_ state: DebridRequest.State, rd: String? = "RD1", percent: Int = 0, videos: [String] = ["tt1:1:1"], files: [String: Int] = [:],
               by: String = "iPhone", account: String? = nil, at: TimeInterval = 0) -> DebridRequest {
        var e = DebridRequest(hash: infoHash, files: files, account: account, rdID: rd, title: "x", kind: "series", metaID: "tt1", videoIDs: videos,
                              device: by, createdAt: t0.addingTimeInterval(at), percent: percent, state: state)
        e.updatedAt = t0.addingTimeInterval(at)
        return e
    }

    // MARK: paquetes (A)

    func testAnOldSingleFileEntryDoesNotCoverAnotherEpisode() async throws {
        // La libreta de antes: un solo `file_idx`, sin marca de paquete; Real-Debrid tiene ese torrent con un archivo elegido.
        let vault = InMemoryAddonVault()
        let old = #"[{"hash": "\#(infoHash)", "file_idx": 1, "rd_id": "OLD", "title": "The Office", "kind": "series", "meta_id": "tt0386676", "video_ids": ["tt0386676:1:2"], "by": "iPhone", "since": 1800000000, "state": "ready", "percent": 100}]"#
        vault.setData(DebridRequestBook.key, Data(old.utf8))
        let fake = FakeRealDebrid()
        fake.torrents = [["id": "OLD", "hash": infoHash, "filename": "x", "status": "downloaded", "progress": 100]]
        let requester = make(fake: fake, vault: vault)
        XCTAssertEqual(requester.book.find(hash: infoHash)?.files, ["tt0386676:1:2": 1], "el `file_idx` de antes es el del primer video")
        let again = try await requester.request(wish(2))
        XCTAssertEqual(again.rdID, "OLD", "el mismo episodio: el mismo pedido")
        let other = try await requester.request(wish(1))
        XCTAssertTrue(fake.calls.contains("POST torrents/addMagnet"), "otro episodio de un paquete viejo con un archivo: se pide como torrent nuevo")
        XCTAssertNotEqual(other.rdID, "OLD")
        XCTAssertEqual(other.videoIDs, ["tt0386676:1:2", "tt0386676:1:1"], "con los videos unidos")
        XCTAssertEqual(other.files, ["tt0386676:1:2": 1, "tt0386676:1:1": 0])
        XCTAssertEqual(fake.bodies["torrents/selectFiles/\(other.rdID!)"], "files=1%2C2", "esta vez, todos los videos")
        XCTAssertTrue(other.coversWholeTorrent)
    }

    // MARK: juntar (B)

    func testMergeTakesTheStrongestStateWithoutClocks() {
        func merged(_ a: DebridRequest.State, _ b: DebridRequest.State) -> DebridRequest.State {
            DebridRequest.merge(entry(a, at: 0), entry(b, at: 999)).state
        }
        XCTAssertEqual(merged(.downloading, .ready), .ready)
        XCTAssertEqual(merged(.ready, .downloading), .ready, "lo más nuevo no gana por ser nuevo: gana la precedencia")
        XCTAssertEqual(merged(.ready, .gone), .gone)
        XCTAssertEqual(merged(.refused, .noPeers), .refused)
        XCTAssertEqual(merged(.noPeers, .downloading), .noPeers)
        XCTAssertEqual(merged(.queued, .downloading), .downloading)
        XCTAssertEqual(merged(.tooMany, .queued), .queued, "too_many se reintenta: cualquier otro le gana")
        let order: [DebridRequest.State] = [.gone, .ready, .refused, .noPeers, .downloading, .queued, .tooMany]
        XCTAssertEqual(DebridRequest.State.allCases.sorted { $0.precedence > $1.precedence }, order, "la precedencia del contrato")
    }

    func testMergeJoinsFieldByField() {
        let mine = entry(.downloading, rd: "RD1", percent: 40, videos: ["tt1:1:1"], files: ["tt1:1:1": 0], by: "iPhone", account: "111")
        var tv = entry(.downloading, rd: nil, percent: 63, videos: ["tt1:1:2"], files: ["tt1:1:2": 1], by: "TV", at: 500)
        tv.rdStatus = "downloading"; tv.seeders = 9; tv.title = "otro"
        let out = DebridRequest.merge(mine, tv)
        XCTAssertEqual(out.videoIDs, ["tt1:1:1", "tt1:1:2"]); XCTAssertEqual(out.files, ["tt1:1:1": 0, "tt1:1:2": 1])
        XCTAssertEqual(out.percent, 63); XCTAssertEqual(out.seeders, 9, "lo de Real-Debrid, de la que lleva más")
        XCTAssertEqual(out.rdID, "RD1", "el primer rd_id no vacío"); XCTAssertEqual(out.account, "111")
        XCTAssertEqual(out.device, "iPhone"); XCTAssertEqual(out.title, "x"); XCTAssertEqual(out.createdAt, mine.createdAt, "quien lo anotó primero")
    }

    func testANewRdIDIsANewRequestEvenOverATombstone() {
        var stored = entry(.gone, rd: "RD1", percent: 30, videos: ["tt1:1:1"], files: ["tt1:1:1": 0])
        stored.notified = true
        let fresh = entry(.queued, rd: "RD2", percent: 0, videos: ["tt1:1:2"], files: ["tt1:1:2": 1], at: 10)
        let out = DebridRequest.merge(stored, fresh)
        XCTAssertEqual(out.state, .queued, "volver a pedir da otro rd_id: la lápida no lo atora")
        XCTAssertEqual(out.rdID, "RD2"); XCTAssertEqual(out.percent, 0)
        XCTAssertEqual(out.videoIDs, ["tt1:1:1", "tt1:1:2"]); XCTAssertEqual(out.files, ["tt1:1:1": 0, "tt1:1:2": 1])
        XCTAssertEqual(DebridRequest.merge(entry(.ready, rd: nil), entry(.queued, rd: "RD9")).state, .ready, "llenar un rd_id vacío no es un pedido nuevo")
    }

    // MARK: lápidas

    func testCancelWhenRealDebridNoLongerHasItCountsAsDone() async throws {
        let fake = FakeRealDebrid()
        let sync = FakeRequestSync()
        let requester = make(fake: fake, sync: sync)
        _ = try await requester.request(wish(2))
        fake.answers["torrents/delete/RD1"] = (404, Data(#"{"error_code": 7}"#.utf8))
        try await requester.cancel(hash: infoHash)
        XCTAssertEqual(requester.book.find(hash: infoHash)?.state, .gone)
        XCTAssertEqual(sync.pushed.last?["state"] as? String, "gone", "la lápida se le manda a la TV")
    }

    // MARK: leer

    func testEachEntryIsReadOnItsOwn() throws {
        let body = #"""
        {"version": 1, "account": 111, "requests": [
          {"hash": "\#(infoHash)", "video_ids": ["tt1"], "meta_id": "tt1", "by": "TV", "state": "failed", "files": {"tt1": 0}},
          {"video_ids": ["sin huella"]},
          {"hash": 42},
          "basura",
          {"hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "state": "paused_by_tv", "percent": "mucho", "season": "uno"}
        ]}
        """#
        let pull = try XCTUnwrap(DebridRequestPull.parse(Data(body.utf8)))
        XCTAssertEqual(pull.account, "111")
        XCTAssertEqual(pull.requests.map(\.hash), [infoHash, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"], "una mala se salta, no tira la lista")
        XCTAssertEqual(pull.requests[0].state, .refused, "«failed» de la TV de antes es «refused»")
        XCTAssertEqual(pull.requests[1].state, .queued, "un estado desconocido se vuelve a preguntar")
        XCTAssertEqual(pull.requests[1].percent, 0); XCTAssertNil(pull.requests[1].season)
        // La libreta guardada también: una entrada mala no borra las demás.
        let vault = InMemoryAddonVault()
        vault.setData(DebridRequestBook.key, Data(#"[{"hash": "aa", "state": "ready"}, {"nada": 1}]"#.utf8))
        XCTAssertEqual(DebridRequestBook(vault: vault).stored.map(\.hash), ["aa"])
    }

    // MARK: lo que viaja

    func testThePushIsTheFullEntryWithoutWhatStaysHere() async throws {
        let sync = FakeRequestSync()
        let requester = make(sync: sync)
        _ = try await requester.request(wish(2))
        let sent = try XCTUnwrap(sync.pushed.last)
        for key in ["hash", "title", "kind", "meta_id", "video_ids", "season", "episode", "files", "rd_id", "language", "release", "rd_status", "percent",
                    "seeders", "progress_at", "state", "since", "account", "by"] {
            XCTAssertTrue(sent.keys.contains(key), "falta «\(key)» en lo que se manda")
        }
        for key in ["notified", "nudged", "url", "filename", "linked", "updated", "pack", "pending"] {
            XCTAssertNil(sent[key], "«\(key)» nunca viaja")
        }
        XCTAssertEqual(sent["account"] as? String, "111"); XCTAssertEqual(sent["by"] as? String, "iPhone de Fernando")
        XCTAssertEqual(sent["files"] as? [String: Int], ["tt0386676:1:2": 1])
        XCTAssertFalse(requester.book.find(hash: infoHash)!.pending, "la TV lo recibió")
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: sent), encoding: .utf8)!.contains("KEY"), "nunca la clave")
    }

    func testWhatTheTVDidNotGetIsSentOnTheNextLook() async throws {
        let sync = FakeRequestSync()
        sync.accepts = false   // la TV no contesta
        let requester = make(sync: sync)
        _ = try await requester.request(wish(2))
        XCTAssertTrue(requester.book.find(hash: infoHash)!.pending)
        sync.accepts = true
        sync.pulled = DebridRequestPull(account: "111", requests: [])
        await requester.syncWithTV()
        XCTAssertEqual(sync.pushed.count, 2)
        XCTAssertFalse(requester.book.find(hash: infoHash)!.pending)
    }

    func testWhatComesFromTheTVNeverNotifiesHere() async {
        let sync = FakeRequestSync()
        var tv = entry(.downloading, rd: "TV1", percent: 20, videos: ["tt1:1:1"], by: "TV")
        tv.hash = "cccccccccccccccccccccccccccccccccccccccc"
        sync.pulled = DebridRequestPull(account: "111", requests: [tv])
        let requester = make(sync: sync)
        await requester.syncWithTV()
        let stored = requester.book.find(hash: tv.hash)
        XCTAssertEqual(stored?.notified, true); XCTAssertEqual(stored?.nudged, true)
        XCTAssertEqual(stored?.account, "111", "sin `account`: la de la TV que lo guarda")
        XCTAssertEqual(stored?.pending, false)
        XCTAssertTrue(sync.pushed.isEmpty, "lo que llega no se devuelve")
    }

    // MARK: otra cuenta

    func testAnotherAccountIsShownButNotFollowedCancelledOrAVersion() async throws {
        let fake = FakeRealDebrid()
        let requester = make(account: "111", fake: fake)
        var theirs = entry(.downloading, rd: "THEIRS", videos: ["tt1:1:1"], by: "TV", account: "999")
        theirs.pending = false
        requester.book.put(theirs)
        _ = await requester.refresh()
        XCTAssertTrue(fake.calls.isEmpty, "no se sigue: ese torrent no existe en tu cuenta")
        try await requester.cancel(hash: infoHash)
        XCTAssertFalse(fake.calls.contains { $0.hasPrefix("DELETE") }, "no se cancela desde aquí")
        XCTAssertEqual(requester.book.all.count, 1, "se enseña")
        XCTAssertNil(requester.book.find(metaID: "tt1", videoID: "tt1:1:1", account: "111"), "no sale como versión")
        XCTAssertTrue(requester.book.active(account: "111").isEmpty)
    }

    func testAnotherAccountIsForgottenAWeekAfterItsLastChangeEvenInFlight() {
        let book = DebridRequestBook(vault: InMemoryAddonVault())
        var theirs = entry(.downloading, by: "TV", account: "999")
        theirs.hash = "dddddddddddddddddddddddddddddddddddddddd"
        let mine = entry(.downloading, account: "111")
        book.put(theirs); book.put(mine)
        book.prune(now: t0.addingTimeInterval(6 * 24 * 3600), account: "111")
        XCTAssertEqual(book.stored.count, 2)
        book.prune(now: t0.addingTimeInterval(8 * 24 * 3600), account: "111")
        XCTAssertEqual(book.stored.map(\.hash), [infoHash], "lo tuyo en camino nunca se olvida; lo de otra cuenta, a la semana")
    }

    func testTheAccountComesFromRealDebridsUserAndNeverTheKey() throws {
        let body = Data(#"{"id": 4242, "username": "fer", "type": "premium", "premium": 86400, "expiration": "2027-03-21T12:00:00.000Z"}"#.utf8)
        XCTAssertEqual(try RealDebrid.parse(body, checkedAt: t0).userID, "4242")
    }
}
