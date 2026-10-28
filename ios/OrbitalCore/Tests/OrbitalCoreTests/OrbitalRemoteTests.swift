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

    func testEachRequestSaysWhichDevice() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = ["now": .null]
        let device = OrbitalRemote.Device(name: "iPad de Fernando", kind: "ipad", id: "ABC-123")
        _ = try? await OrbitalRemote(http: http, address: "tv.example", token: "x", device: device).snapshot()
        let headers = try XCTUnwrap(http.headers.last)
        XCTAssertEqual(headers["X-Orbital-Device"], "iPad%20de%20Fernando")
        XCTAssertEqual(headers["X-Orbital-Device-Kind"], "ipad")
        XCTAssertEqual(headers["X-Orbital-Device-Id"], "ABC-123")
        XCTAssertEqual(headers["Authorization"], "Bearer x")
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

    /// La consola presta la app de Trakt (su Client ID), nunca su sesión: el iPhone conecta la suya con un código.
    func testKeysCarryTheTraktAppButNoSession() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion"] = ["tmdb_key": "k", "trakt_client_id": "c", "region": "MX"]
        let keys = try await OrbitalRemote(http: http, address: "tv.example", token: "x").keys()
        XCTAssertEqual(keys, OrbitalRemote.Keys(tmdbKey: "k", traktClientID: "c", region: "MX"))
    }

    func testNowParsesAMovieOrNilWhenNothingPlays() async throws {
        let http = FakeHTTP()
        let playing: JSON = .object(["kind": .string("movie"), "live": .bool(false), "meta_id": .string("tt1"),
                                     "video_id": .string("tt1"), "title": .string("Interstellar"), "episode_label": .string(""),
                                     "poster": .string("https://p"), "position": .int(100), "duration": .double(6000.5),
                                     "paused": .bool(false)])
        http.json["https://tv.example/api/companion/now"] = .object(["playing": playing])
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        let now = try await remote.now()
        XCTAssertEqual(now?.title, "Interstellar")
        XCTAssertEqual(now?.duration, 6000.5)
        XCTAssertEqual(now?.poster, "https://p")

        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null])
        let empty = try await remote.now()
        XCTAssertNil(empty)
    }

    func testControlSendsTheActionAndDelta() async throws {
        let http = FakeHTTP()
        let playing: JSON = .object(["kind": .string("movie"), "live": .bool(false), "title": .string("x"),
                                     "position": .int(40), "duration": .int(100), "paused": .bool(true)])
        http.json["https://tv.example/api/companion/player"] = .object(["playing": playing])
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        let now = try await remote.control(action: "skip", delta: 30)
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(http.bodies(for: "https://tv.example/api/companion/player").first)))
        XCTAssertEqual(sent["action"]?.string, "skip")
        XCTAssertEqual(sent["delta"]?.intValue, 30)
        XCTAssertEqual(now?.paused, true)
    }

    func testControlWithNothingPlayingSaysSoInWords() async {
        let http = FakeHTTP()
        http.statuses["https://tv.example/api/companion/player"] = 409
        http.json["https://tv.example/api/companion/player"] = ["detail": "No hay nada en la TV ahora mismo"]
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        do { _ = try await remote.control(action: "toggle"); XCTFail() }
        catch { XCTAssertEqual((error as? OrbitalRemote.Failure)?.description, "No hay nada en la TV ahora mismo") }
    }

    func testAClosedGameArrivesAsASessionSummary() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null, "inbox": .array([
            .object(["id": "g1", "action": "played", "meta_id": "steam:1145360", "video_id": "1760000000", "title": "Hades", "seconds": .int(4320),
                     "total_seconds": .int(123_000), "crashed": false, "low_memory": true, "captures": .int(3), "at": .int(1_760_000_000)]),
        ])])
        let snapshot = try await OrbitalRemote(http: http, address: "tv.example", token: "x").snapshot()
        let item = try XCTUnwrap(snapshot.inbox.first)
        XCTAssertEqual(item.action, .played)
        XCTAssertEqual(item.played?.seconds, 4320)
        XCTAssertEqual(item.played?.totalSeconds, 123_000)
        XCTAssertEqual(item.played?.lowMemory, true)
        XCTAssertEqual(item.played?.captures, 3)
        XCTAssertEqual(item.played?.art?.hasSuffix("/api/art/steam%3A1145360?kind=hero"), true, "\(item.played?.art ?? "")")
    }

    func testNowBringsTheInboxTheTVLeftForTheIPhone() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null, "inbox": .array([
            .object(["id": "a1", "kind": "series", "meta_id": "tt1", "video_id": "tt1:2:5", "title": "The Office", "episode_label": "T2 · E5",
                     "season": 2, "episode": 5, "poster": "https://p", "action": "download", "at": .int(1_760_000_000)]),
            .object(["id": "b2", "kind": "movie", "meta_id": "tt9", "video_id": "tt9", "title": "Dune", "episode_label": "", "poster": .null,
                     "action": "open", "at": .double(1_760_000_001.5), "position": .double(845.4)]),
            .object(["id": "x", "kind": "movie", "meta_id": "tt3", "action": "bailar"]),  // una acción que esta versión no conoce: se ignora
        ])])
        let snapshot = try await OrbitalRemote(http: http, address: "tv.example", token: "x").snapshot()
        XCTAssertNil(snapshot.playing)
        XCTAssertEqual(snapshot.inbox.map(\.id), ["a1", "b2"])
        XCTAssertEqual(snapshot.inbox[0].action, .download)
        XCTAssertEqual(snapshot.inbox[0].displayName, "The Office T2 · E5")
        XCTAssertEqual(snapshot.inbox[1].displayName, "Dune")
        XCTAssertEqual(snapshot.inbox[0].season, 2, "los números, para armar el episodio en el idioma de la app")
        XCTAssertEqual(snapshot.inbox[0].episode, 5)
        XCTAssertNil(snapshot.inbox[1].season, "película: sin números")
        XCTAssertEqual(snapshot.inbox[1].poster, nil)
        XCTAssertEqual(snapshot.inbox[1].position, 845.4, "«Seguir en el iPhone»: el segundo exacto de la TV")
        XCTAssertNil(snapshot.inbox[0].position, "«Enviar al iPhone»: donde te quedaste")
        // Una consola de una versión anterior no manda `inbox`: bandeja vacía, sin error.
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null])
        let old = try await OrbitalRemote(http: http, address: "tv.example", token: "x").snapshot()
        XCTAssertTrue(old.inbox.isEmpty)
    }

    func testContinueOnIPhoneBringsTheSourceAndTracksOfTheTV() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null, "inbox": .array([
            .object(["id": "c3", "kind": "movie", "meta_id": "tt9", "video_id": "tt9", "title": "Dune", "action": "open",
                     "at": .int(1_760_000_000), "position": .double(845.4), "source": "Torrentio|abc|0",
                     "audio": .object(["lang": "eng", "title": ""]),
                     "subtitle": .object(["off": false, "lang": "spa", "title": "Latino", "url": "https://subs/x.srt"])]),
        ])])
        let snapshot = try await OrbitalRemote(http: http, address: "tv.example", token: "x").snapshot()
        let item = try XCTUnwrap(snapshot.inbox.first)
        XCTAssertEqual(item.choice?.videoID, "tt9")
        XCTAssertEqual(item.choice?.source, "Torrentio|abc|0", "la misma huella de fuente que el iPhone")
        XCTAssertEqual(item.choice?.audio, ResumeChoice.Track(language: "eng"))
        XCTAssertEqual(item.choice?.subtitle, ResumeChoice.Track(language: "spa", title: "Latino", url: "https://subs/x.srt"))
    }

    func testSendingToTheTVCarriesTheSecondSourceAndTracks() throws {
        let track = ResumeChoice.Track(off: false, language: "es", title: "Forzados", url: nil)
        XCTAssertEqual(track.json, .object(["off": .bool(false), "lang": "es", "title": "Forzados", "url": ""]))
        XCTAssertEqual(ResumeChoice.Track.parse(track.json), ResumeChoice.Track(language: "es", title: "Forzados"))
        XCTAssertNil(ResumeChoice.Track.parse(.null))
    }

    func testNowBringsTheRunningGameAndTheConsoleState() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null, "inbox": .array([]), "game": .object([
            "id": "steam:1245620", "title": "Elden Ring", "system": "steam", "art": .object(["cover": "/api/art/steam:1245620?kind=cover", "hero": "https://cdn/hero.jpg"]),
            "started": .int(1_760_000_000), "paused": true, "closes_at": .null])])
        http.json["https://tv.example/api/companion/console"] = .object([
            "battery": .object(["percent": 58, "plugged": false, "minutes_left": 130]), "power_mode": "balanced",
            "wifi": .object(["ssid": "Casa", "signal": 82]), "controllers": .array([.object(["kind": "legion", "battery": "full"])]),
            "memory": .object(["free_gb": .double(6.1), "apps": .array([.object(["name": "Chrome", "gb": .double(2.3), "closable": true])])])])
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        let snapshot = try await remote.snapshot()
        let game = try XCTUnwrap(snapshot.game)
        XCTAssertEqual(game.title, "Elden Ring")
        XCTAssertTrue(game.paused)
        XCTAssertEqual(game.cover, "https://tv.example/api/art/steam:1245620?kind=cover", "el arte de la consola, a su dirección")
        XCTAssertEqual(game.hero, "https://cdn/hero.jpg")
        XCTAssertEqual(game.started, Date(timeIntervalSince1970: 1_760_000_000))
        let state = try await remote.console()
        let console = try XCTUnwrap(state)
        XCTAssertEqual(console.batteryPercent, 58); XCTAssertEqual(console.minutesLeft, 130)
        XCTAssertEqual(console.powerMode, "balanced"); XCTAssertEqual(console.controllers.first?.battery, "full")
        XCTAssertEqual(console.apps.first?.name, "Chrome"); XCTAssertEqual(console.freeGB, 6.1)
        // Una consola de antes: sin juego, sin error.
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null])
        let old = try await remote.snapshot()
        XCTAssertNil(old.game)
    }

    func testAckSendsTheIDs() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/inbox/ack"] = .object(["removed": .int(2)])
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        try await remote.ack(ids: ["a1", "b2"])
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(http.bodies(for: "https://tv.example/api/companion/inbox/ack").first)))
        XCTAssertEqual((sent["ids"]?.array ?? []).compactMap(\.string), ["a1", "b2"])
        try await remote.ack(ids: [])  // nada que avisar: ni una petición
        XCTAssertEqual(http.bodies(for: "https://tv.example/api/companion/inbox/ack").count, 1)
    }

    /// La pantalla de la TV ahora (para rotular el control) y las órdenes de voz, como a Alexa.
    func testTheTVsLegendAndVoiceCommands() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/companion/now"] = .object(["playing": .null, "ui": ["screen": "games", "text_field": false, "section": "Juegos",
                                                                                          "legend": ["back": "Inicio", "page": "Otra consola", "menu": "Menú"]]])
        http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Poniendo The Office."]
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        let snapshot = try await remote.snapshot()
        XCTAssertEqual(snapshot.section, "Juegos")
        XCTAssertEqual(snapshot.legend["page"], "Otra consola")
        XCTAssertEqual(snapshot.textField, false)
        let reply = try await remote.voice("pon The Office")
        XCTAssertEqual(reply, OrbitalRemote.VoiceReply(ok: true, speech: "Poniendo The Office."))
        XCTAssertEqual(http.bodies(for: "https://tv.example/api/voice").first.flatMap { JSON.parse($0)?["text"]?.string }, "pon The Office")
    }

    func testTypingSendsOnlyWhatChanged() {
        XCTAssertEqual(RemoteTyping.delta(from: "", to: "hola"), "hola")
        XCTAssertEqual(RemoteTyping.delta(from: "hola", to: "hola mundo"), " mundo")
        XCTAssertEqual(RemoteTyping.delta(from: "hola", to: "ho"), "\u{8}\u{8}")
        XCTAssertEqual(RemoteTyping.delta(from: "dune", to: "duna"), "\u{8}a")
        XCTAssertEqual(RemoteTyping.delta(from: "dune", to: "dune"), "")
    }
}
