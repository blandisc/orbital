import XCTest
@testable import OrbitalCore
@testable import OrbitalAddons

/// F1 · las 29 respuestas reales de la TV (`tests/fixtures/contract`, las escribe `tests/test_contract_fixtures.py`) pasan por
/// las mismas funciones que usa la app. Si la TV cambia o quita un campo que el iPhone lee, una de estas falla.
final class ContractFixturesTests: XCTestCase {
    /// Una TV de mentira que contesta lo que dice un ejemplo (estado y cuerpo), solo a esa ruta y con ese método.
    final class FixtureTV: HTTPClient, @unchecked Sendable {
        let method: String, path: String, status: Int, body: Data
        private let lock = NSLock()
        private var _sent: [HTTPRequest] = []
        var sent: [HTTPRequest] { lock.withLock { _sent } }

        init(_ name: String, replacing: [String: String] = [:]) throws {
            let fixture = try Fixtures.json("contract/\(name).json")
            method = try XCTUnwrap(fixture["request"]?["method"]?.string)
            path = try XCTUnwrap(fixture["request"]?["path"]?.string)
            status = try XCTUnwrap(fixture["status"]?.intValue)
            var text = String(decoding: try XCTUnwrap(fixture["response"]).serialized(), as: UTF8.self)
            for (from, to) in replacing { text = text.replacingOccurrences(of: from, with: to) }
            body = Data(text.utf8)
        }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.withLock { _sent.append(request) }
            guard request.method == method, request.url.path == path else {
                return HTTPResponse(status: 599, data: Data("pidió \(request.method) \(request.url.path), el ejemplo es \(method) \(path)".utf8))
            }
            return HTTPResponse(status: status, data: body)
        }
    }

    /// La llave de un aparato con la forma acordada: los ejemplos la guardan como «<key>» (cambia en cada corrida).
    static let deviceID = String(repeating: "ab", count: 16)
    static let key = "od1.\(deviceID).\(String(repeating: "S3cr3t_-", count: 5))"

    func remote(_ tv: FixtureTV, key: String? = ContractFixturesTests.key, book: TVContractBook = TVContractBook()) -> OrbitalRemote {
        Self.remote(tv, key: key, book: book)
    }

    static func remote(_ tv: FixtureTV, key: String? = ContractFixturesTests.key, book: TVContractBook = TVContractBook()) -> OrbitalRemote {
        var remote = OrbitalRemote(http: tv, address: "tv.example", token: "x", deviceKey: key)
        remote.contracts = book
        return remote
    }

    /// Todos los ejemplos que hay en la carpeta tienen su prueba aquí (uno nuevo sin prueba también falla).
    func testEveryFixtureIsCovered() throws {
        let folder = Fixtures.root.appendingPathComponent("contract")
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        let covered: Set<String> = [
            "addons", "companion", "companion_choices", "companion_console", "companion_game_409", "companion_inbox_ack", "companion_input",
            "companion_now", "companion_now_episode", "companion_now_movie", "companion_player_409", "companion_player_toggle",
            "companion_resume", "companion_text", "devices", "devices_invite", "devices_key_required", "devices_pair", "foryou",
            "foryou_details", "foryou_dismiss", "foryou_list", "foryou_list_continue", "ping", "realdebrid", "realdebrid_requests",
            "stremio_play", "voice", "voice_hints",
        ]
        XCTAssertEqual(names.count, 29)
        XCTAssertEqual(names, covered, "ejemplo nuevo o quitado en tests/fixtures/contract: súmale (o quítale) su prueba")
    }

    // MARK: lo que la TV dice de sí misma

    func testPingSaysTheContractAndEveryCapabilityTheIPhoneUses() async throws {
        let tv = try FixtureTV("ping"), book = TVContractBook()
        let contract = try await remote(tv, book: book).check()
        XCTAssertEqual(contract.api, 1)
        XCTAssertTrue(contract.isKnown)
        XCTAssertEqual(book.contract(for: URL(string: "https://tv.example")), contract, "se guarda con la TV conectada")
        // Cada ruta del iPhone apunta a una capacidad que la TV anuncia con ese mismo nombre.
        let paths = ["api/stremio/play", "api/voice", "api/voice/hints", "api/companion/now", "api/companion/input", "api/companion/text",
                     "api/companion/player", "api/companion/game", "api/companion/console", "api/companion/choices", "api/companion/resume",
                     "api/companion/inbox/ack", "api/devices", "api/devices/abc", "api/devices/invite", "api/devices/upgrade",
                     "api/devices/upgrade/x", "api/realdebrid", "api/realdebrid/requests", "api/opensubtitles", "api/addons", "api/foryou",
                     "api/foryou/list", "api/foryou/details", "api/foryou/dismiss", "api/art/tt1"]
        for path in paths {
            let capability = try XCTUnwrap(TVContract.capability(for: path), path)
            XCTAssertTrue(contract.capabilities?.contains(capability) == true, "«\(capability)» (\(path)) ya no está en /api/ping")
        }
        XCTAssertNil(TVContract.capability(for: "api/ping"))
        XCTAssertNil(TVContract.capability(for: "api/companion"))
    }

    func testCompanionBringsKeysPairingTVAndContract() async throws {
        let tv = try FixtureTV("companion"), book = TVContractBook()
        let keys = try await remote(tv, book: book).keys()
        XCTAssertEqual(keys.region, "MX")
        XCTAssertEqual(keys.tmdbKey, "")
        XCTAssertEqual(keys.traktClientID, "")
        XCTAssertEqual(keys.pairing, 2)
        XCTAssertEqual(keys.tvID, "<tv_id>")
        XCTAssertEqual(keys.contract.api, 1)
        XCTAssertTrue(keys.contract.supports("remote_input"))
        XCTAssertTrue(book.contract(for: URL(string: "https://tv.example")).isKnown)
    }

    /// Lo que la TV no anuncia no se pide: se dice que hay que actualizarla (sin un «Not Found» crudo).
    func testWhatTheTVDoesNotAnnounceIsNotAskedFor() async throws {
        let tv = try FixtureTV("ping"), book = TVContractBook()
        let remote = remote(tv, book: book)
        book.record(TVContract(api: 1, capabilities: ["now_playing"]), for: remote.base)
        do { _ = try await remote.foryouOverview(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused(OrbitalRemote.updateLine)) }
        do { try await remote.input(.select); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .outdated, "el pad se esconde") }
        do { _ = try await remote.devices(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused(OrbitalRemote.updateLine)) }
        let addons = await AddonListRemote(remote: { remote }).get()
        XCTAssertEqual(addons, .outdated)
        XCTAssertTrue(tv.sent.isEmpty, "nada viajó a la TV")
        // Una TV de antes (sin `api`) se intenta como siempre, y su 404 «Not Found» tampoco se muestra crudo.
        book.record(.unknown, for: remote.base)
        let old = FakeHTTP()
        var oldRemote = OrbitalRemote(http: old, address: "tv.example", token: "x")
        oldRemote.contracts = book
        old.statuses["https://tv.example/api/foryou"] = 404
        old.json["https://tv.example/api/foryou"] = ["detail": "Not Found"]
        do { _ = try await oldRemote.foryouOverview(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused(OrbitalRemote.updateLine)) }
        old.statuses["https://tv.example/api/devices"] = 404
        old.json["https://tv.example/api/devices"] = ["detail": "Not Found"]
        do { _ = try await oldRemote.devices(); XCTFail() } catch { XCTAssertEqual((error as? OrbitalRemote.Failure)?.description, OrbitalRemote.updateLine) }
        XCTAssertEqual(old.calls.count, 2)
    }

    func testAnOldTVWithoutApiKeepsWorking() async throws {
        let http = FakeHTTP(), book = TVContractBook()
        http.json["https://tv.example/api/ping"] = ["ok": true]
        var remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        remote.contracts = book
        let contract = try await remote.check()
        XCTAssertEqual(contract, .unknown)
        XCTAssertTrue(remote.supports("foryou"))
        XCTAssertTrue(remote.supports("remote_input"))
    }

    // MARK: lo que se ve en la TV

    func testNowWithNothingPlaying() async throws {
        let snapshot = try await remote(try FixtureTV("companion_now")).snapshot()
        XCTAssertNil(snapshot.playing)
        XCTAssertNil(snapshot.game)
        XCTAssertEqual(snapshot.inbox, [])
        XCTAssertEqual(snapshot.screen, "home")
        XCTAssertEqual(snapshot.textField, false)
        XCTAssertEqual(snapshot.volume, OrbitalRemote.Volume(level: 50, muted: false, extra: nil, extraMax: 200))
    }

    func testNowWithAnEpisode() async throws {
        let snapshot = try await remote(try FixtureTV("companion_now_episode")).snapshot()
        let playing = try XCTUnwrap(snapshot.playing)
        XCTAssertEqual(playing.kind, "series")
        XCTAssertEqual(playing.title, "The Office")
        XCTAssertEqual(playing.metaID, "s1")
        XCTAssertEqual(playing.season, 1)
        XCTAssertEqual(playing.episode, 1)
        XCTAssertEqual(playing.episodeLabel, "T1 · E1")
        XCTAssertEqual(playing.position, 50)
        XCTAssertEqual(playing.duration, 1200)
        XCTAssertFalse(playing.paused)
        XCTAssertEqual(playing.audioTracks.count, 2)
        XCTAssertEqual(playing.audioTracks.first, .init(id: "1", label: "Inglés · 5.1 · E-AC3", selected: true))
        XCTAssertFalse(playing.subtitleTracks.isEmpty)
        XCTAssertEqual(snapshot.screen, "player")
        XCTAssertEqual(snapshot.legend["select"], "Pausa")
        XCTAssertEqual(snapshot.volume?.extra, 100)
    }

    func testNowWithAMovie() async throws {
        let snapshot = try await remote(try FixtureTV("companion_now_movie")).snapshot()
        let playing = try XCTUnwrap(snapshot.playing)
        XCTAssertEqual(playing.kind, "movie")
        XCTAssertEqual(playing.metaID, "tt1")
        XCTAssertNil(playing.season)
        XCTAssertNil(playing.episode)
        XCTAssertGreaterThan(playing.duration, 0)
        XCTAssertFalse(playing.title.isEmpty)
    }

    func testPlayerToggleAndNothingPlaying() async throws {
        let now = try await remote(try FixtureTV("companion_player_toggle")).control(action: "toggle")
        XCTAssertEqual(now?.title, "Interstellar")
        XCTAssertEqual(now?.paused, true)
        XCTAssertEqual(now?.position, 100)
        XCTAssertEqual(now?.poster, "https://img/x.jpg")
        do { _ = try await remote(try FixtureTV("companion_player_409")).control(action: "toggle"); XCTFail() }
        catch { XCTAssertEqual((error as? OrbitalRemote.Failure)?.description, "No hay nada en la TV ahora mismo") }
    }

    func testGameWithNothingOpen() async throws {
        do { _ = try await remote(try FixtureTV("companion_game_409")).game(action: "resume"); XCTFail() }
        catch { XCTAssertEqual((error as? OrbitalRemote.Failure)?.description, "No hay ningún juego abierto") }
    }

    func testConsoleState() async throws {
        let console = try await remote(try FixtureTV("companion_console")).console()
        let state = try XCTUnwrap(console)
        XCTAssertEqual(state.powerMode, "balanced")
        XCTAssertEqual(state.brightness, 50)
        XCTAssertEqual(state.freeGB, 4.0)
        XCTAssertNil(state.batteryPercent)
        XCTAssertNil(state.wifiSSID)
        XCTAssertEqual(state.controllers, [])
    }

    func testRemoteKeysTextAckAndPlay() async throws {
        let input = try FixtureTV("companion_input")
        try await remote(input).input(.select)
        XCTAssertEqual(JSON.parse(try XCTUnwrap(input.sent.first?.body))?["action"]?.string, "select")
        let text = try FixtureTV("companion_text")
        try await remote(text).type("hola", submit: false)
        XCTAssertEqual(JSON.parse(try XCTUnwrap(text.sent.first?.body))?["text"]?.string, "hola")
        let ack = try FixtureTV("companion_inbox_ack")
        try await remote(ack).ack(ids: ["nada"])
        XCTAssertEqual(ack.sent.count, 1)
        let play = try FixtureTV("stremio_play")
        try await remote(play).play(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", title: "The Office")
        let body = try XCTUnwrap(JSON.parse(try XCTUnwrap(play.sent.first?.body)))
        XCTAssertEqual(body["id"]?.string, "tt0386676")
        XCTAssertEqual(body["video_id"]?.string, "tt0386676:2:5")
        XCTAssertEqual(body["kind"]?.string, "series")
    }

    func testChoicesAndResumeSync() async throws {
        let reply = try await remote(try FixtureTV("companion_choices")).syncChoices(since: 0, changes: ["tt0386676": .init(audio: "es")])
        XCTAssertEqual(reply?.rev, 1)
        XCTAssertEqual(reply?.changed["tt0386676"], OrbitalRemote.TitleChoice(audio: "es", rev: 1))
        XCTAssertEqual(reply?.rejected, [])
        let resume = try await remote(try FixtureTV("companion_resume")).syncResume([:], want: ["tt0386676"])
        XCTAssertEqual(resume, [:], "una TV nueva sin nada guardado contesta vacío (no nil: nil es «TV de antes»)")
    }

    // MARK: aparatos y Real-Debrid

    func testDevicesInvitePairAndKeyRequired() async throws {
        let devices = try await remote(try FixtureTV("devices")).devices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "<device_id>")
        XCTAssertEqual(devices.first?.name, "iPhone de Fernando")
        XCTAssertEqual(devices.first?.platform, "iphone")
        XCTAssertEqual(devices.first?.isThis, true)
        XCTAssertEqual(devices.first?.pairedAt, Date(timeIntervalSince1970: 1_700_000_000))
        let invite = try await remote(try FixtureTV("devices_invite")).invite(platform: "ipad")
        XCTAssertEqual(invite.code, "<code>")
        XCTAssertEqual(invite.expires, Date(timeIntervalSince1970: 1_700_000_000))
        // La llave viaja normalizada («<key>»): se pone una con la forma acordada para que el iPhone la acepte.
        let pair = try await remote(try FixtureTV("devices_pair", replacing: ["<key>": Self.key, "<device_id>": Self.deviceID]), key: nil)
            .pair(code: "<code>", name: "iPhone de Fernando", platform: "iphone")
        XCTAssertEqual(pair.deviceID, Self.deviceID)
        XCTAssertEqual(pair.key, Self.key)
        XCTAssertEqual(pair.tvName, "Orbital")
        XCTAssertEqual(pair.tvID, "<tv_id>")
        let tv = try FixtureTV("devices_key_required")
        let refused = await AddonListRemote(remote: { Self.remote(tv, key: nil) }).get()
        XCTAssertEqual(refused, .refused(OrbitalRemote.rescanLine))
    }

    func testRealDebridAccountAndRequests() async throws {
        let account = try await remote(try FixtureTV("realdebrid")).realDebridAccount()
        XCTAssertEqual(account, OrbitalTVDebrid(user: "fer", premium: true, expires: Date(timeIntervalSince1970: 1_700_000_000), tail: "3F2A"))
        let tv = try FixtureTV("realdebrid_requests")
        let pull = await OrbitalRemoteDebridRequestSync(remote: { Self.remote(tv) }).pull()
        XCTAssertEqual(pull, DebridRequestPull(version: 1, account: nil, requests: []))
    }

    func testSharedAddonList() async throws {
        let tv = try FixtureTV("addons")
        let reply = await AddonListRemote(remote: { Self.remote(tv) }).get()
        guard case .list(let list) = reply else { return XCTFail("la lista de la TV no se leyó") }
        XCTAssertEqual(list.addons.count, 3)
        XCTAssertEqual(list.addons.first?.id, "torrentio")
        XCTAssertEqual(list.addons.first?.template, "torrentio")
        XCTAssertEqual(list.addons.first?.origin, "orbital")
        XCTAssertEqual(list.addons.map(\.order), list.addons.map(\.order).sorted())
    }

    // MARK: voz

    func testVoiceAndHints() async throws {
        let reply = try await remote(try FixtureTV("voice")).voice("abre hades")
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.speech, "Abriendo Hades.")
        XCTAssertEqual(reply.heard, "abre hades")
        XCTAssertEqual(reply.hints, ["pon The Office", "sigue viendo", "qué sale hoy"])
        let hints = try await remote(try FixtureTV("voice_hints")).voiceHints()
        XCTAssertEqual(hints, OrbitalRemote.VoiceHints(moment: "home", hints: ["pon The Office", "sigue viendo", "qué sale hoy"]))
    }

    // MARK: Para ti

    func testForYouOverviewListsAndMosaic() async throws {
        let tv = try FixtureTV("foryou")
        let foryou = RemoteForYou(remote: { Self.remote(tv) })
        let lists = try await foryou.lists()
        XCTAssertFalse(lists.isEmpty)
        XCTAssertEqual(lists.first?.id, "continue")
        XCTAssertEqual(lists.first?.title, "Seguir viendo")
        XCTAssertEqual(lists.first?.group, .mine)
        let mosaic = try await foryou.mosaic()
        XCTAssertEqual(mosaic.count, 6)
        XCTAssertEqual(mosaic.first?.imdb, "tt0903747")
        XCTAssertEqual(mosaic.first?.kind, "series")
        XCTAssertFalse(mosaic.first?.poster.isEmpty ?? true)
        XCTAssertFalse(mosaic.first?.wide.isEmpty ?? true)
    }

    func testForYouListAndContinue() async throws {
        let list = try FixtureTV("foryou_list")
        let items = try await RemoteForYou(remote: { Self.remote(list) }).items(listID: "cinemeta", kind: "series")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.imdb, "tt901")
        XCTAssertEqual(items.first?.overview, "Sinopsis")
        let continuing = try FixtureTV("foryou_list_continue")
        // `continue` siempre se pide como serie en el iPhone (`items` sin `kind`): el ejemplo va sin `kind`.
        let next = try await RemoteForYou(remote: { Self.remote(continuing) }).items(listID: "continue")
        XCTAssertEqual(next.first?.imdb, "tt0903747")
        XCTAssertEqual(next.first?.next?.season, 2)
        XCTAssertEqual(next.first?.next?.episode, 6)
    }

    func testForYouDetailsAndDismiss() async throws {
        let details = try await remote(try FixtureTV("foryou_details")).foryouDetails(key: "video:tt0386676", kind: nil)
        XCTAssertEqual(details?["overview"]?.string, "")
        let dismiss = try FixtureTV("foryou_dismiss")
        try await remote(dismiss).foryouDismiss(key: "video:tt0386676")
        XCTAssertEqual(JSON.parse(try XCTUnwrap(dismiss.sent.first?.body))?["key"]?.string, "video:tt0386676")
    }
}
