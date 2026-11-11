import XCTest
@testable import OrbitalAddons

/// Real-Debrid de mentira: contesta por ruta y apunta lo que se le pidió (nunca sale a la red).
final class FakeRealDebrid: @unchecked Sendable {
    private let lock = NSLock()
    var torrents: [[String: Any]] = []
    var answers: [String: (Int, Data)] = [:]
    private(set) var calls: [String] = []
    private(set) var bodies: [String: String] = [:]
    private var nextID = 1

    var fetch: DebridFetch {
        { [self] request in
            let path = request.url!.absoluteString.replacingOccurrences(of: RealDebrid.api.absoluteString + "/", with: "")
            let method = request.httpMethod ?? "GET"
            return lock.withLock {
                calls.append("\(method) \(path)")
                if let body = request.httpBody { bodies[path] = String(data: body, encoding: .utf8) }
                if let answer = answers[path] { return answer }
                switch (method, path) {
                case ("POST", "torrents/addMagnet"):
                    let id = "RD\(nextID)"; nextID += 1
                    torrents.append(["id": id, "hash": "", "filename": "x", "status": "waiting_files_selection", "progress": 0,
                                     "files": [["id": 1, "path": "/Show.S01E01.mkv", "bytes": 100, "selected": 0],
                                               ["id": 2, "path": "/Show.S01E02.mkv", "bytes": 100, "selected": 0],
                                               ["id": 3, "path": "/info.nfo", "bytes": 1, "selected": 0]]])
                    return (201, try! JSONSerialization.data(withJSONObject: ["id": id, "uri": "x"]))
                case ("GET", let p) where p.hasPrefix("torrents?"):
                    return (200, try! JSONSerialization.data(withJSONObject: torrents))
                case ("GET", let p) where p.hasPrefix("torrents/info/"):
                    let id = String(p.dropFirst("torrents/info/".count))
                    guard let found = torrents.first(where: { $0["id"] as? String == id }) else { return (404, Data(#"{"error_code":7}"#.utf8)) }
                    return (200, try! JSONSerialization.data(withJSONObject: found))
                case ("POST", let p) where p.hasPrefix("torrents/selectFiles/"): return (204, Data())
                case ("DELETE", _): return (204, Data())
                case ("GET", "torrents/activeCount"): return (200, Data(#"{"nb": 3, "limit": 25}"#.utf8))
                default: return (404, Data())
                }
            }
        }
    }

    func set(_ id: String, status: String, progress: Int, seeders: Int? = nil, hash: String? = nil) {
        lock.withLock {
            guard let i = torrents.firstIndex(where: { $0["id"] as? String == id }) else { return }
            torrents[i]["status"] = status; torrents[i]["progress"] = progress
            if let seeders { torrents[i]["seeders"] = seeders }
            if let hash { torrents[i]["hash"] = hash }
        }
    }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class DebridRequestsTests: XCTestCase {
    let infoHash = "0123456789ABCDEF0123456789ABCDEF01234567"

    func make(token: String? = "KEY", fake: FakeRealDebrid = FakeRealDebrid(), clock: Clock = Clock(), vault: InMemoryAddonVault = InMemoryAddonVault())
        -> (DebridRequester, FakeRealDebrid, Clock, InMemoryAddonVault) {
        let requester = DebridRequester(book: DebridRequestBook(vault: vault), api: RealDebridTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000)),
                                        token: { token }, device: { "iPhone de prueba" }, clock: { clock.now })
        return (requester, fake, clock, vault)
    }

    func wish(_ episode: Int = 2) -> DebridWish {
        DebridWish(hash: infoHash, fileIdx: episode - 1, title: "The Office", kind: "series", metaID: "tt0386676", videoID: "tt0386676:1:\(episode)",
                   season: 1, episode: episode, language: "es-419", release: "The.Office.S01E0\(episode)")
    }

    // MARK: la máquina de estados (R13)

    func testRealDebridStatusesBecomeTheSixStates() {
        XCTAssertEqual(DebridRequest.state(rdStatus: "magnet_conversion", progress: 0, seeders: 4), .queued)
        XCTAssertEqual(DebridRequest.state(rdStatus: "waiting_files_selection", progress: 0, seeders: nil), .queued)
        XCTAssertEqual(DebridRequest.state(rdStatus: "queued", progress: 0, seeders: nil), .queued)
        XCTAssertEqual(DebridRequest.state(rdStatus: "downloading", progress: 42, seeders: 12), .downloading)
        XCTAssertEqual(DebridRequest.state(rdStatus: "downloading", progress: 3, seeders: 0), .noPeers, "bajando sin nadie que lo comparta")
        XCTAssertEqual(DebridRequest.state(rdStatus: "compressing", progress: 100, seeders: nil), .downloading)
        XCTAssertEqual(DebridRequest.state(rdStatus: "downloaded", progress: 100, seeders: nil), .ready)
        for failed in ["magnet_error", "error", "virus", "dead"] { XCTAssertEqual(DebridRequest.state(rdStatus: failed, progress: 0, seeders: nil), .refused) }
        XCTAssertEqual(DebridRequest.state(after: .refused), .refused)
        XCTAssertEqual(DebridRequest.state(after: .tooManyActive), .tooMany)
        XCTAssertNil(DebridRequest.state(after: .invalidKey), "tu clave no es un estado del pedido: es una causa")
        XCTAssertNil(DebridRequest.state(after: .network))
    }

    func testStallsAfterADayWithoutProgress() {
        let start = Date(timeIntervalSince1970: 0)
        var request = DebridRequest(hash: infoHash, title: "x", kind: "movie", metaID: "tt1", videoIDs: ["tt1"], device: "iPhone", createdAt: start)
        request.apply(RDTorrent(id: "A", hash: infoHash, filename: "x", status: "downloading", progress: 5, seeders: 0), now: start.addingTimeInterval(60))
        XCTAssertFalse(request.isStalled(now: start.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(request.isStalled(now: start.addingTimeInterval(25 * 3600)))
        request.apply(RDTorrent(id: "A", hash: infoHash, filename: "x", status: "downloading", progress: 6, seeders: 1), now: start.addingTimeInterval(25 * 3600))
        XCTAssertFalse(request.isStalled(now: start.addingTimeInterval(26 * 3600)), "avanzó: se vuelve a contar")
        request.apply(RDTorrent(id: "A", hash: infoHash, filename: "x", status: "downloaded", progress: 100), now: start.addingTimeInterval(90 * 3600))
        XCTAssertFalse(request.isStalled(now: start.addingTimeInterval(200 * 3600)), "un pedido listo nunca está atorado")
    }

    // MARK: lo que dice Real-Debrid al decir que no

    func testRealDebridErrorsMapToWords() {
        func error(_ status: Int, _ code: Int?) -> RDRequestError {
            RDRequestError.from(status: status, body: code.map { Data(#"{"error": "x", "error_code": \#($0)}"#.utf8) } ?? Data())
        }
        XCTAssertEqual(error(451, 35), .refused, "Infringing file: Real-Debrid no lo dejó bajar")
        XCTAssertEqual(error(503, 21), .tooManyActive, "Too many active downloads")
        XCTAssertEqual(error(503, 23), .tooManyActive, "Traffic exhausted")
        XCTAssertEqual(error(401, 8), .invalidKey)
        XCTAssertEqual(error(403, 20), .notPremium)
        XCTAssertEqual(error(429, 34), .slowDown)
        XCTAssertEqual(error(429, nil), .slowDown)
        XCTAssertEqual(error(401, nil), .invalidKey)
        XCTAssertEqual(error(403, nil), .notPremium)
        XCTAssertEqual(error(404, 7), .notFound)
        XCTAssertEqual(error(502, nil), .slowDown, "otro 5xx: se espera y se reintenta, como en la TV (design/realdebrid-errors.json)")
    }

    // MARK: la libreta (R12)

    func testTheBookSurvivesARestartAndKeepsTheTVShape() throws {
        let vault = InMemoryAddonVault()
        let book = DebridRequestBook(vault: vault)
        var request = DebridRequest(hash: infoHash, fileIdx: 1, rdID: "RD9", title: "The Office", kind: "series", metaID: "tt0386676", videoIDs: ["tt0386676:1:2"],
                                    season: 1, episode: 2, language: "es-419", device: "iPhone de Fernando", createdAt: Date(timeIntervalSince1970: 100))
        request.percent = 42; request.state = .downloading; request.rdStatus = "downloading"
        book.put(request)
        let again = DebridRequestBook(vault: vault)   // la app se cerró y volvió a abrir
        XCTAssertEqual(again.find(hash: infoHash), request)
        XCTAssertEqual(again.find(metaID: "tt0386676", videoID: "tt0386676:1:2")?.percent, 42)
        // La forma acordada con la TV (A6): la huella como clave, sus videos, quién lo pidió, el estado de Real-Debrid.
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(vault.data(DebridRequestBook.key))) as? [[String: Any]]).first
        for key in ["hash", "rd_id", "title", "meta_id", "video_ids", "episode", "season", "by", "since", "rd_status", "percent", "state"] {
            XCTAssertNotNil(json?[key], "falta «\(key)» en la libreta")
        }
        XCTAssertEqual(json?["hash"] as? String, infoHash.lowercased())
        XCTAssertEqual(json?["by"] as? String, "iPhone de Fernando")
        XCTAssertEqual(json?["state"] as? String, "downloading")
        XCTAssertNil(json?["url"], "nunca un enlace de Real-Debrid (van atados a quien los pidió)")
    }

    func testReadsAnEntryFromTheTVWithMissingFieldsAndAnUnknownState() throws {
        let tv = #"[{"hash": "ABC", "video_ids": ["tt1"], "meta_id": "tt1", "title": "Nocturne", "by": "TV", "state": "paused_by_tv", "percent": 7}]"#
        let vault = InMemoryAddonVault()
        vault.setData(DebridRequestBook.key, Data(tv.utf8))
        let entry = try XCTUnwrap(DebridRequestBook(vault: vault).find(hash: "abc"))
        XCTAssertEqual(entry.state, .queued, "un estado que no se conoce se vuelve a preguntar")
        XCTAssertEqual(entry.device, "TV"); XCTAssertEqual(entry.percent, 7); XCTAssertNil(entry.rdID)
    }

    func testForgetsFinishedAfterAWeekButNeverOneInFlight() {
        let book = DebridRequestBook(vault: InMemoryAddonVault())
        let old = Date(timeIntervalSince1970: 0)
        var ready = DebridRequest(hash: "aa", title: "a", kind: "movie", metaID: "tt1", videoIDs: ["tt1"], device: "iPhone", createdAt: old, state: .ready)
        ready.updatedAt = old
        let slow = DebridRequest(hash: "bb", title: "b", kind: "movie", metaID: "tt2", videoIDs: ["tt2"], device: "iPhone", createdAt: old, state: .noPeers)
        book.put(ready); book.put(slow)
        book.prune(now: old.addingTimeInterval(8 * 24 * 3600))
        XCTAssertNil(book.find(hash: "aa"))
        XCTAssertNotNil(book.find(hash: "bb"), "puede tardar días: no se olvida mientras sigue en camino")
    }

    // MARK: pedir (R12, R13)

    func testRequestAddsSelectsTheEpisodeFileAndIsNeverAddedTwice() async throws {
        let (requester, fake, _, _) = make()
        let made = try await requester.request(wish(2))
        XCTAssertEqual(made.rdID, "RD1")
        XCTAssertEqual(made.device, "iPhone de prueba")
        XCTAssertEqual(fake.bodies["torrents/selectFiles/RD1"], "files=1%2C2", "un paquete: todos sus videos (Real-Debrid solo deja elegir una vez)")
        XCTAssertEqual(made.files, ["tt0386676:1:2": 1]); XCTAssertTrue(made.pack)
        XCTAssertEqual(fake.bodies["torrents/addMagnet"], "magnet=magnet%3A%3Fxt%3Durn%3Abtih%3A\(infoHash.lowercased())")
        _ = try await requester.request(wish(2))
        XCTAssertEqual(fake.calls.filter { $0 == "POST torrents/addMagnet" }.count, 1, "nunca se agrega dos veces")
        // Otro episodio del mismo paquete: el mismo pedido, con ese video sumado, sin preguntarle nada a Real-Debrid.
        let calls = fake.calls.count
        let pack = try await requester.request(wish(3))
        XCTAssertEqual(pack.videoIDs, ["tt0386676:1:2", "tt0386676:1:3"])
        XCTAssertEqual(pack.files, ["tt0386676:1:2": 1, "tt0386676:1:3": 2])
        XCTAssertEqual(fake.calls.count, calls, "otro episodio de un paquete ya pedido: ninguna llamada a Real-Debrid")
    }

    func testTwoTapsAtOnceAddTheTorrentOnlyOnce() async throws {
        let (requester, fake, _, _) = make()
        let two = wish(2), three = wish(3)
        async let first = requester.request(two)
        async let second = requester.request(two)
        async let other = requester.request(three)
        let (a, b, _) = try await (first, second, other)
        XCTAssertEqual(fake.calls.filter { $0 == "POST torrents/addMagnet" }.count, 1, "dos toques seguidos: un solo torrent en tu Real-Debrid")
        XCTAssertEqual(a.rdID, b.rdID)
        XCTAssertEqual(Set(requester.book.find(hash: infoHash)?.videoIDs ?? []), ["tt0386676:1:2", "tt0386676:1:3"],
                       "el otro episodio del paquete se suma al mismo pedido")
    }

    func testWithoutAKnownFileItSelectsOnlyTheVideos() async throws {
        let (requester, fake, _, _) = make()
        var w = wish(2); w.fileIdx = nil
        _ = try await requester.request(w)
        XCTAssertEqual(fake.bodies["torrents/selectFiles/RD1"], "files=1%2C2", "los videos, no el .nfo")
    }

    func testTakesTheTorrentTorrentioAlreadyAddedInsteadOfAddingAnother() async throws {
        let fake = FakeRealDebrid()
        fake.torrents = [["id": "TORRENTIO", "hash": infoHash.lowercased(), "filename": "x", "status": "downloading", "progress": 30, "seeders": 8]]
        let (requester, _, _, _) = make(fake: fake)
        let made = try await requester.request(wish())
        XCTAssertEqual(made.rdID, "TORRENTIO"); XCTAssertEqual(made.state, .downloading); XCTAssertEqual(made.percent, 30)
        XCTAssertFalse(fake.calls.contains("POST torrents/addMagnet"))
    }

    func testRefusedAndTooManyAreStatesButAccountProblemsAreThrown() async throws {
        let fake = FakeRealDebrid()
        fake.answers["torrents/addMagnet"] = (451, Data(#"{"error": "infringing_file", "error_code": 35}"#.utf8))
        let (requester, _, _, _) = make(fake: fake)
        let refused = try await requester.request(wish())
        XCTAssertEqual(refused.state, .refused)
        fake.answers["torrents/addMagnet"] = (503, Data(#"{"error_code": 21}"#.utf8))
        let again = try await requester.request(wish())   // rechazado: se puede volver a intentar
        XCTAssertEqual(again.state, .tooMany)
        fake.answers["torrents/addMagnet"] = (403, Data(#"{"error_code": 20}"#.utf8))
        let other = DebridWish(hash: "ff" + String(infoHash.dropFirst(2)), fileIdx: nil, title: "x", kind: "movie", metaID: "tt9", videoID: "tt9")
        do { _ = try await requester.request(other); XCTFail("sin Premium es de tu cuenta: se dice como causa") }
        catch let error as RDRequestError { XCTAssertEqual(error, .notPremium) }
        XCTAssertNil(requester.book.find(hash: other.hash), "lo que no llegó a Real-Debrid no se anota")
    }

    func testNoKeyNeverCallsRealDebrid() async {
        let (requester, fake, _, _) = make(token: nil)
        do { _ = try await requester.request(wish()); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .noKey) }
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testRefreshUsesOneCallAndReportsWhatChanged() async throws {
        let (requester, fake, clock, _) = make()
        _ = try await requester.request(wish())
        let before = fake.calls.count
        fake.set("RD1", status: "downloading", progress: 63, seeders: 5)
        let changed = await requester.refresh()
        XCTAssertEqual(fake.calls.count - before, 1, "una sola consulta (GET /torrents) para todos")
        XCTAssertEqual(changed.first?.percent, 63); XCTAssertEqual(changed.first?.state, .downloading)
        let same = await requester.refresh()
        XCTAssertTrue(same.isEmpty, "nada cambió: no hay nada que avisar")
        clock.now += 600
        fake.set("RD1", status: "downloaded", progress: 100)
        let done = await requester.refresh()
        XCTAssertEqual(done.first?.state, .ready)
        let idle = fake.calls.count
        _ = await requester.refresh()
        XCTAssertEqual(fake.calls.count, idle, "sin pedidos en camino no se le pregunta nada a Real-Debrid")
    }

    func testRefreshFindsWhatTorrentioAddedByItsHash() async {
        let fake = FakeRealDebrid()
        let (requester, _, _, _) = make(fake: fake)
        await requester.noteOpened(wish())
        XCTAssertNil(requester.book.find(hash: infoHash)?.rdID)
        fake.torrents = [["id": "T7", "hash": infoHash.lowercased(), "filename": "x", "status": "queued", "progress": 0]]
        let changed = await requester.refresh()
        XCTAssertEqual(changed.first?.rdID, "T7")
    }

    func testDeletedOnTheWebsiteBecomesATombstone() async throws {
        let (requester, fake, clock, _) = make()
        _ = try await requester.request(wish())
        fake.torrents = []   // lo borraste en real-debrid.com (o en la TV): 404 a su rd_id
        clock.now += 60
        let changed = await requester.refresh()
        XCTAssertEqual(changed.first?.state, .gone)
        XCTAssertEqual(requester.book.find(hash: infoHash)?.state, .gone, "lápida, no se borra: así la TV no lo vuelve a anotar")
        XCTAssertNil(requester.book.find(metaID: "tt0386676", videoID: "tt0386676:1:2"), "la lápida no se enseña ni sale como versión")
        XCTAssertTrue(requester.book.all.isEmpty)
        let calls = fake.calls.count
        _ = await requester.refresh()
        XCTAssertEqual(fake.calls.count, calls, "a una lápida nunca se le pregunta")
        // Se guarda 7 días desde su último cambio.
        requester.book.prune(now: clock.now.addingTimeInterval(6 * 24 * 3600))
        XCTAssertNotNil(requester.book.find(hash: infoHash))
        requester.book.prune(now: clock.now.addingTimeInterval(7 * 24 * 3600 + 1))
        XCTAssertNil(requester.book.find(hash: infoHash))
    }

    func testCancelDeletesItFromRealDebridAndLeavesATombstone() async throws {
        let (requester, fake, _, _) = make()
        _ = try await requester.request(wish())
        try await requester.cancel(hash: infoHash)
        XCTAssertTrue(fake.calls.contains("DELETE torrents/delete/RD1"))
        XCTAssertEqual(requester.book.find(hash: infoHash)?.state, .gone, "cancelado: lápida")
        XCTAssertTrue(requester.book.all.isEmpty)
        let count = await requester.activeCount()
        XCTAssertEqual(count?.active, 3); XCTAssertEqual(count?.limit, 25)
    }

    func testRespectsRealDebridsSlowDown() async throws {
        let fake = FakeRealDebrid()
        let clock = Clock()
        let gate = RDGate(perMinute: 1000, clock: { clock.now })
        let requester = DebridRequester(book: DebridRequestBook(vault: InMemoryAddonVault()), api: RealDebridTorrents(fetch: fake.fetch, gate: gate),
                                        token: { "KEY" }, device: { "iPhone" }, clock: { clock.now })
        fake.answers["torrents?limit=100"] = (429, Data(#"{"error_code": 34}"#.utf8))
        do { _ = try await requester.request(wish()); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .slowDown) }
        let calls = fake.calls.count
        do { _ = try await requester.request(wish()); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .slowDown) }
        XCTAssertEqual(fake.calls.count, calls, "un minuto sin preguntarle")
        clock.now += 61
        fake.answers["torrents?limit=100"] = nil
        _ = try await requester.request(wish())
        XCTAssertGreaterThan(fake.calls.count, calls)
    }

    // MARK: Torrentio sin Real-Debrid (R4)

    func testTorrentioWithoutDebridKeepsYourOptionsAndDropsTheKey() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("tests/fixtures/torrentio-config.json"))) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 3)
        for item in cases {
            let withKey = try XCTUnwrap(item["url"] as? String).replacingOccurrences(of: "{CLAVE}", with: "SECRETKEY123456")
            let keyless = try XCTUnwrap(AddonCatalog.torrentioWithoutDebrid(withKey))
            XCTAssertFalse(keyless.contains("SECRETKEY"), "nunca lleva tu clave: \(item["name"] ?? "")")
            XCTAssertFalse(keyless.contains("realdebrid") || keyless.contains("debridoptions"))
            XCTAssertFalse(keyless.hasSuffix("manifest.json"))
            let base = "https://torrentio.strem.fun"
            let config = withKey.replacingOccurrences(of: "/manifest.json", with: "").dropFirst(base.count + 1)
            let kept = config.split(separator: "|").filter { !$0.hasPrefix("realdebrid=") && !$0.hasPrefix("debridoptions=") }.joined(separator: "|")
            XCTAssertEqual(keyless, kept.isEmpty ? base : "\(base)/\(kept)", "\(item["name"] ?? "")")
        }
        XCTAssertEqual(AddonCatalog.torrentioWithoutDebrid("https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=brremux,cam,scr|realdebrid=ABC/manifest.json"),
                       "https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=brremux,cam,scr")
        XCTAssertEqual(AddonCatalog.torrentioWithoutDebrid("https://torrentio.strem.fun/alldebrid=ABC|language=spanish/manifest.json"),
                       "https://torrentio.strem.fun/language=spanish")
        XCTAssertNil(AddonCatalog.torrentioWithoutDebrid("https://comet.elfhosted.com/abc/manifest.json"), "solo Torrentio")
    }
}
