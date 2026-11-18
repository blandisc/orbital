import XCTest
@testable import OrbitalAddons

/// DN1 · Tu nube: Real-Debrid, TorBox o AllDebrid, igual que la TV (`design/debrid-services.json`, `design/torbox-errors.json`,
/// `design/alldebrid-errors.json`; la TV los prueba en `tests/test_debrid_services.py`). Sin cuentas de verdad: respuestas falsas.
final class DebridServicesTests: XCTestCase {
    static func design(_ name: String) throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("design/\(name)"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: El contrato

    func testTheThreeCloudsAreTheContractOnes() throws {
        let contract = try Self.design("debrid-services.json")
        let services = try XCTUnwrap(contract["services"] as? [String: [String: String]])
        XCTAssertEqual(Set(services.keys), Set(DebridService.allCases.map(\.rawValue)), "solo esos tres")
        XCTAssertEqual(contract["default"] as? String, DebridService.fallback.rawValue)
        for service in DebridService.allCases {
            let entry = try XCTUnwrap(services[service.rawValue])
            XCTAssertEqual(entry["name"], service.name)
            XCTAssertEqual(entry["tag"], service.tag)
            XCTAssertEqual(entry["site"], service.site)
            XCTAssertEqual(entry["key_url"], service.keyURL.absoluteString)
            XCTAssertEqual(entry["renew_url"], service.renewURL.absoluteString)
            XCTAssertEqual(entry["torrentio_param"], service.torrentioParam)
            XCTAssertEqual(entry["comet_service"], service.cometService)
            XCTAssertEqual(entry["key_store"], service.keyStore, "la clave de cada una aparte, con el mismo nombre que en la TV")
        }
        let signup = try XCTUnwrap((contract["words"] as? [String: Any])?["signup_urls"] as? [String: String])
        for service in DebridService.allCases { XCTAssertEqual(signup[service.rawValue], service.signupURL.absoluteString) }
    }

    func testErrorTablesAreTheTVOnes() throws {
        for (file, table) in [("torbox-errors.json", DebridErrorTable.torBox), ("alldebrid-errors.json", DebridErrorTable.allDebrid)] {
            let json = try Self.design(file)
            let codes = try XCTUnwrap(json["codes"] as? [String: [String: Any]])
            XCTAssertEqual(codes.mapValues { $0["cause"] as? String ?? "" }, table.codes.mapValues(\.rawValue), file)
            let http = try XCTUnwrap(json["http"] as? [String: String])
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: http.map { (Int($0.key)!, $0.value) }), table.http.mapValues(\.rawValue), file)
            for c in try XCTUnwrap(json["cases"] as? [[String: Any]]) {
                XCTAssertEqual(table.cause(status: c["http"] as? Int, code: c["code"] as? String).rawValue, c["cause"] as? String, "\(file) \(c)")
            }
        }
    }

    // MARK: Torrentio y Comet (punto 1: antes se tiraban las claves de TorBox y AllDebrid)

    func testTorrentioKeepsTheKeyOfEachCloud() throws {
        let tb = try XCTUnwrap(TorrentioConfig.parse("https://torrentio.strem.fun/language=latino|torbox=1a2b3c4d-1111-2222-3333-444455556666/manifest.json"))
        XCTAssertEqual(tb.key, "1a2b3c4d-1111-2222-3333-444455556666")
        XCTAssertEqual(tb.service, .torBox)
        let ad = try XCTUnwrap(TorrentioConfig.parse("https://torrentio.strem.fun/alldebrid=ABCDEFGHIJ1234567890/manifest.json"))
        XCTAssertEqual(ad.service, .allDebrid)
        XCTAssertEqual(TorrentioConfig.manifestURL(options: AddonOptions(excludedQualities: [], languages: []), token: "1a2b3c4d-1111", service: .torBox),
                       "https://torrentio.strem.fun/torbox=1a2b3c4d-1111/manifest.json")
    }

    func testCometAsksForYourCloud() throws {
        let url = try XCTUnwrap(AddonCatalog.comet.manifestURL(token: "ABCDEFGHIJ1234567890", service: .allDebrid))
        let segment = try XCTUnwrap(url.split(separator: "/").dropLast().last)
        let json = try XCTUnwrap(String(data: try XCTUnwrap(Data(base64Encoded: String(segment))), encoding: .utf8))
        XCTAssertTrue(json.contains(#""service":"alldebrid""#), json)
    }

    // MARK: El archivo del episodio

    func testEpisodeFileIsPickedByItsName() {
        let files = [RDFile(id: 1, path: "Show/Show.S01E01.mkv", bytes: 900, selected: true),
                     RDFile(id: 2, path: "Show/Show.S01E03.1080p.mkv", bytes: 800, selected: true),
                     RDFile(id: 3, path: "Show/Show.1x02.mkv", bytes: 700, selected: true)]
        XCTAssertEqual(DebridFilePick.pick(files, fileIdx: 0, season: 1, episode: 3)?.id, 2, "el nombre manda")
        XCTAssertEqual(DebridFilePick.pick(files, fileIdx: nil, season: 1, episode: 2)?.id, 3, "también «1x02»")
        XCTAssertEqual(DebridFilePick.pick(files, fileIdx: 0, season: 1, episode: 9)?.id, 1, "sin nombre, el fileIdx")
        XCTAssertEqual(DebridFilePick.pick(files, fileIdx: nil, season: nil, episode: nil)?.id, 1, "sin nada, el más grande")
        XCTAssertNil(DebridFilePick.episode(of: "tt1"))
        XCTAssertEqual(DebridFilePick.episode(of: "tt1:2:5")?.episode, 5)
    }

    // MARK: TorBox

    func testTorBoxAnswersInRealDebridShape() async throws {
        let fake = FakeCloud()
        fake.answers["GET torrents/mylist"] = (200, #"{"success": true, "data": {"id": 77, "hash": "ABC", "name": "Show", "download_state": "completed", "download_finished": true, "progress": 1, "files": [{"id": 5, "name": "Show/S01E01.mkv", "size": 10}, {"id": 6, "name": "Show/S01E02.mkv", "size": 20}]}}"#)
        fake.answers["GET torrents/requestdl"] = (200, #"{"success": true, "data": "https://tb.example/file.mkv"}"#)
        let api = TorBoxTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000))
        let info = try await api.info(id: "77", token: "KEY")
        XCTAssertEqual(info.status, "downloaded")
        XCTAssertEqual(info.progress, 100)
        XCTAssertEqual(info.hash, "abc")
        let link = try XCTUnwrap(info.link(fileIdx: nil, episode: (1, 2)))
        XCTAssertEqual(link, "torbox:77:6", "el archivo del episodio por su nombre")
        let url = try await api.unrestrict(link: link, token: "KEY")
        XCTAssertEqual(url.absoluteString, "https://tb.example/file.mkv")
        XCTAssertTrue(fake.asked.last?.contains("file_id=6") == true)
    }

    func testTorBoxStatesAndErrors() async throws {
        XCTAssertEqual(TorBoxTorrents.status(["download_state": "metaDL"]), "queued")
        XCTAssertEqual(TorBoxTorrents.status(["download_state": "stalled (no seeds)"]), "downloading")
        XCTAssertEqual(TorBoxTorrents.status(["download_state": "error"]), "error")
        XCTAssertEqual(TorBoxTorrents.status(["download_present": true]), "downloaded")
        let fake = FakeCloud()
        fake.answers["POST torrents/createtorrent"] = (200, #"{"success": false, "error": "ACTIVE_LIMIT", "detail": "x"}"#)
        let api = TorBoxTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000))
        do { _ = try await api.addMagnet(hash: "abc", token: "KEY"); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .tooManyActive) }
        do { _ = try await api.activeCount(token: "KEY"); XCTFail("TorBox no dice su límite") } catch {}
    }

    // MARK: AllDebrid

    func testAllDebridAnswersInRealDebridShape() async throws {
        let fake = FakeCloud()
        fake.answers["POST v4.1/magnet/status"] = (200, #"{"status": "success", "data": {"magnets": {"id": 9, "hash": "DEF", "filename": "Movie", "statusCode": 4, "size": 100, "downloaded": 100}}}"#)
        fake.answers["POST v4/magnet/files"] = (200, #"{"status": "success", "data": {"magnets": [{"id": "9", "files": [{"n": "Movie", "e": [{"n": "movie.mkv", "s": 100, "l": "https://alldebrid.com/f/abc"}, {"n": "info.nfo", "s": 1, "l": "https://alldebrid.com/f/nfo"}]}]}]}}"#)
        fake.answers["POST v4/link/unlock"] = (200, #"{"status": "success", "data": {"link": "https://ad.example/movie.mkv", "filename": "movie.mkv"}}"#)
        let api = AllDebridTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000), pause: {})
        let info = try await api.info(id: "9", token: "KEY")
        XCTAssertEqual(info.status, "downloaded")
        XCTAssertEqual(info.files.map(\.path), ["Movie/movie.mkv", "Movie/info.nfo"])
        let link = try XCTUnwrap(info.link(fileIdx: nil))
        XCTAssertEqual(link, "https://alldebrid.com/f/abc", "el video más grande")
        let url = try await api.unrestrict(link: link, token: "KEY")
        XCTAssertEqual(url.absoluteString, "https://ad.example/movie.mkv")
    }

    func testAllDebridErrorsComeWithHTTP200() async throws {
        XCTAssertEqual(AllDebridTorrents.status(1), "downloading")
        XCTAssertEqual(AllDebridTorrents.status(7), "dead")
        XCTAssertEqual(AllDebridTorrents.status(9), "error")
        let fake = FakeCloud()
        fake.answers["POST v4/magnet/upload"] = (200, #"{"status": "success", "data": {"magnets": [{"magnet": "abc", "error": {"code": "MAGNET_TOO_MANY_ACTIVE", "message": "x"}}]}}"#)
        fake.answers["POST v4.1/magnet/status"] = (200, #"{"status": "error", "error": {"code": "AUTH_BAD_APIKEY", "message": "x"}}"#)
        let api = AllDebridTorrents(fetch: fake.fetch, gate: RDGate(perMinute: 1000), pause: {})
        do { _ = try await api.addMagnet(hash: "abc", token: "KEY"); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .tooManyActive) }
        do { _ = try await api.list(limit: 10, token: "KEY"); XCTFail() } catch { XCTAssertEqual(error as? RDRequestError, .invalidKey) }
    }

    func testAllDebridAccountUsesTheUsernameAsID() async throws {
        let fake = FakeCloud()
        fake.answers["GET v4/user"] = (200, #"{"status": "success", "data": {"user": {"username": "fer", "isPremium": true, "premiumUntil": 1900000000}}}"#)
        let status = try await AllDebrid(fetch: fake.fetch).status(token: "ABCDEFGHIJ1234567890")
        XCTAssertEqual(status.userID, "fer")
        XCTAssertTrue(status.isPremium)
        XCTAssertEqual(status.service, "AllDebrid")
    }

    // MARK: Tu nube y la libreta

    func testOneCloudAtATimeAndAKeyForEach() async throws {
        let vault = InMemoryAddonVault()
        XCTAssertEqual(vault.debridService, .realDebrid, "sin elegir nunca, Real-Debrid")
        let fake = FakeCloud()
        fake.answers["GET user/me"] = (200, #"{"success": true, "data": {"id": 42, "email": "a@b.c", "plan": 2}}"#)
        let account = DebridAccount(providers: DebridClients.live(fetch: fake.fetch).providers, vault: vault)
        let key = "1a2b3c4d-1111-2222-3333-444455556666"
        let status = try await account.verify(key, service: .torBox)
        _ = await account.save(token: key, status: status, service: .torBox)
        XCTAssertEqual(vault.debridService, .torBox)
        XCTAssertEqual(vault.debridToken(), key)
        XCTAssertNil(vault.secret(AddonKeys.realDebridToken), "la de Real-Debrid es otra")
        XCTAssertEqual(account.savedOwner, "torbox:42")
        await account.use(.realDebrid)
        XCTAssertFalse(account.hasToken)
        XCTAssertTrue(account.hasKey(.torBox), "cambiarse y volver no pide la clave otra vez")
    }

    func testAKeyInYourTorrentioBecomesYourCloud() async throws {
        let vault = InMemoryAddonVault()
        let fake = FakeCloud()
        fake.answers["GET v4/user"] = (200, #"{"status": "success", "data": {"user": {"username": "fer", "isPremium": true}}}"#)
        let account = DebridAccount(providers: DebridClients.live(fetch: fake.fetch).providers, vault: vault)
        let adopted = await account.adoptKey(fromAddonURLs: ["https://torrentio.strem.fun/alldebrid=ABCDEFGHIJ1234567890/manifest.json"])
        XCTAssertTrue(adopted)
        XCTAssertEqual(vault.debridService, .allDebrid)
        XCTAssertEqual(vault.debridToken(.allDebrid), "ABCDEFGHIJ1234567890")
    }

    func testARequestIsYoursOnlyInYourCloudAndAccount() throws {
        var request = DebridRequest(hash: "abc", account: "42", title: "X", kind: "movie", metaID: "tt1", videoIDs: ["tt1"], device: "TV", createdAt: Date())
        request.service = .torBox
        XCTAssertFalse(request.isOther(account: "torbox:42"))
        XCTAssertTrue(request.isOther(account: "torbox:7"), "otra cuenta de TorBox")
        XCTAssertTrue(request.isOther(account: "42"), "es de TorBox y usas Real-Debrid")
        XCTAssertTrue(request.isOther(account: nil))
        request.service = nil
        XCTAssertFalse(request.isOther(account: nil), "sin «service» es de Real-Debrid, como antes")
        XCTAssertTrue(request.isOther(account: "torbox:"), "lo de Real-Debrid no es tuyo si usas TorBox")

        request.service = .allDebrid
        let wire = try DebridRequestBook.wireEncoder.encode(request)
        XCTAssertTrue(String(data: wire, encoding: .utf8)!.contains(#""service":"alldebrid""#))
        XCTAssertEqual(try DebridRequestBook.decoder.decode(DebridRequest.self, from: wire).service, .allDebrid)
        let legacy = Data(#"{"hash": "abc", "by": "TV"}"#.utf8)
        XCTAssertNil(try DebridRequestBook.decoder.decode(DebridRequest.self, from: legacy).service)
        XCTAssertThrowsError(try DebridRequestBook.decoder.decode(DebridRequest.self, from: Data(#"{"hash": "abc", "service": "premiumize"}"#.utf8)),
                             "otra nube no se anota")
    }

    func testWhatOneCloudRefusedDoesNotCountForAnother() {
        let vault = InMemoryAddonVault()
        let book = DebridRequestBook(vault: vault)
        var refused = DebridRequest(hash: "abc", title: "X", kind: "movie", metaID: "tt1", videoIDs: ["tt1"], device: "iPhone", createdAt: Date(), state: .refused)
        refused.pending = false
        book.put(refused)
        let requester = DebridRequester(book: book, api: RealDebridTorrents(fetch: FakeCloud().fetch), token: { "K" }, device: { "iPhone" },
                                        currentOwner: { "torbox:42" })
        XCTAssertTrue(requester.refused(metaID: "tt1").isEmpty, "con TorBox, lo que Real-Debrid rechazó se vuelve a ofrecer")
    }
}

/// Una nube falsa: contesta por «MÉTODO ruta» (sin la parte de `?…`) y anota lo que se le pidió.
final class FakeCloud: @unchecked Sendable {
    var answers: [String: (Int, String)] = [:]
    var asked: [String] = []
    var fetch: DebridFetch {
        { [self] request in
            let url = request.url!.absoluteString
            asked.append(url)
            let path = url.replacingOccurrences(of: TorBoxTorrents.api + "/", with: "").replacingOccurrences(of: AllDebridTorrents.api + "/", with: "")
                .split(separator: "?").first.map(String.init) ?? ""
            let answer = answers["\(request.httpMethod ?? "GET") \(path)"] ?? (404, "{}")
            return (answer.0, Data(answer.1.utf8))
        }
    }
}
