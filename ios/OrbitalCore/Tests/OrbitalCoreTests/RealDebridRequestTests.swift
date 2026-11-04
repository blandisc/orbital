import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// Fase 2 de Real-Debrid en el núcleo: el torrent de cada versión, Torrentio sin Real-Debrid (R4), cómo se dice cada estado
/// (R13) y la regla del siguiente episodio (R8, R9-B).
final class RealDebridRequestTests: XCTestCase {
    let infoHash = "0123456789abcdef0123456789abcdef01234567"

    func source(_ stream: String) -> Source {
        Streams.parse(JSON.parse(Data(stream.utf8))!, addon: "Torrentio", transportURL: "https://torrentio.strem.fun", index: 0)
    }

    func testTheSameTorrentWithAndWithoutRealDebrid() {
        // Con Real-Debrid, Torrentio solo da la dirección (con tu clave adentro); sin Real-Debrid, su `infoHash` y `fileIdx`.
        let rd = source(#"{"name": "Torrentio\n[RD download] 1080p", "title": "Show.S01E02.1080p", "url": "https://torrentio.strem.fun/resolve/realdebrid/SECRETKEY/\#(infoHash)/null/1/Show.S01E02.mkv"}"#)
        let raw = source(#"{"name": "Torrentio\n1080p", "title": "Show.S01E02.1080p", "infoHash": "\#(infoHash.uppercased())", "fileIdx": 1}"#)
        XCTAssertEqual(rd.torrent, TorrentID(hash: infoHash, fileIdx: 1))
        XCTAssertEqual(raw.torrent, rd.torrent, "la misma clave en las dos listas (B-P2-2)")
        let old = source(#"{"name": "Torrentio\n[RD download]", "url": "https://x.example/resolve/realdebrid/KEY/\#(infoHash)/3/Movie.mkv"}"#)
        XCTAssertEqual(old.torrent, TorrentID(hash: infoHash, fileIdx: 3))
        XCTAssertNil(source(#"{"name": "Comet", "url": "https://cdn.example/video.mkv"}"#).torrent)
        XCTAssertNil(source(#"{"name": "Torrentio", "url": "https://torrentio.strem.fun/resolve/realdebrid/KEY/abc/null/0/x.mkv"}"#).torrent, "no es una huella")
    }

    func testTorrentLookupAsksTorrentioWithoutTheKeyAndRanksByYourLanguage() async {
        let http = FakeHTTP()
        http.prefix["https://torrentio.strem.fun/"] = JSON.parse(Data(#"""
        {"streams": [
          {"name": "Torrentio\n720p", "title": "Show.S01E02.720p.ENG\n👤 3", "infoHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "fileIdx": 1},
          {"name": "Torrentio\n1080p", "title": "Show.S01E02.1080p.Latino\n🇲🇽 👤 40", "infoHash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "fileIdx": 1},
          {"name": "Torrentio\nCAM", "title": "Show.S01E02.HDCAM", "infoHash": "cccccccccccccccccccccccccccccccccccccccc"},
          {"name": "Torrentio\n1080p", "title": "sin huella", "url": "https://x/y.mkv"}
        ]}
        """#.utf8))
        let base = AddonCatalog.torrentioWithoutDebrid("https://torrentio.strem.fun/language=latino|realdebrid=SECRETKEY/manifest.json")!
        let found = await TorrentLookup(http: http).torrents(base: base, kind: "series", videoID: "tt1:1:2",
                                                             prefs: Preferences(audio: "es", quality: "1080p", spanish: "es-419"))
        XCTAssertEqual(found?.map { $0.torrent?.hash }, ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], "latino primero; sin CAM ni las que no son torrent")
        XCTAssertFalse(http.calls.contains { $0.contains("SECRETKEY") || $0.contains("realdebrid") }, "nunca con tu clave")
        XCTAssertTrue(http.calls.first?.contains("/stream/series/tt1") ?? false, http.calls.first ?? "")
    }

    func testTorrentLookupTellsNobodyHasItFromNoAnswer() async {
        let http = FakeHTTP()
        http.prefix["https://torrentio.strem.fun/"] = JSON.parse(Data(#"{"streams": []}"#.utf8))
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        let empty = await TorrentLookup(http: http).torrents(base: "https://torrentio.strem.fun", kind: "movie", videoID: "tt1", prefs: prefs)
        XCTAssertEqual(empty?.count, 0, "contestó y no hay: nadie lo tiene (causa 11)")
        http.fail = true
        let offline = await TorrentLookup(http: http).torrents(base: "https://torrentio.strem.fun", kind: "movie", videoID: "tt1", prefs: prefs)
        XCTAssertNil(offline, "sin red no se puede decir «nadie lo tiene»")
    }

    /// RX2-A · cuánto falta, honesto: del avance desde que se pidió; sin avance que medir, «de minutos a horas».
    func testThePaceComesFromTheProgressRateOrSaysMinutesToHours() {
        var request = DebridRequest(hash: infoHash, title: "Hasta el viento tiene miedo", kind: "movie", metaID: "tt0061752", videoIDs: ["tt0061752"],
                                    device: "iPhone", createdAt: Date(timeIntervalSince1970: 0), percent: 42, state: .downloading)
        request.progressAt = Date(timeIntervalSince1970: 600)
        // 42 % en 10 min: faltan ~14 min.
        XCTAssertEqual(DebridRequestWords.pace(request, now: Date(timeIntervalSince1970: 600)), .minutes)
        XCTAssertEqual(DebridRequestWords.paceLine(request, now: Date(timeIntervalSince1970: 600), notifies: true), "A este paso, faltan unos minutos. Te aviso.")
        // 42 % en 30 min: faltan ~41 min.
        request.progressAt = Date(timeIntervalSince1970: 1800)
        XCTAssertEqual(DebridRequestWords.paceLine(request, now: Date(timeIntervalSince1970: 1800), notifies: false), "A este paso, falta menos de una hora.")
        // 42 % en 5 h: faltan ~7 h; 10 % en 10 h: faltan 90 h.
        request.progressAt = Date(timeIntervalSince1970: 5 * 3600)
        XCTAssertEqual(DebridRequestWords.pace(request, now: Date(timeIntervalSince1970: 5 * 3600)), .hours)
        request.percent = 10; request.progressAt = Date(timeIntervalSince1970: 10 * 3600)
        XCTAssertEqual(DebridRequestWords.pace(request, now: Date(timeIntervalSince1970: 10 * 3600)), .overADay)
        // Sin qué medir: recién pedido, casi sin avance, o en cola.
        request.percent = 1
        XCTAssertEqual(DebridRequestWords.paceLine(request, now: Date(timeIntervalSince1970: 10 * 3600), notifies: true), "Suele tardar de minutos a horas. Te aviso.")
        request.percent = 42; request.state = .queued
        XCTAssertEqual(DebridRequestWords.pace(request, now: Date(timeIntervalSince1970: 600)), .unknown)
        // Atorado (24 h sin avanzar): lo de siempre, no una promesa.
        request.state = .downloading; request.progressAt = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(DebridRequestWords.paceLine(request, now: Date(timeIntervalSince1970: 30 * 3600), notifies: true), "Sigue sin bajar · ¿probar otra versión?")
    }

    func testEachStateHasWordsAndAnIcon() {
        var request = DebridRequest(hash: infoHash, title: "The Office", kind: "series", metaID: "tt1", videoIDs: ["tt1:1:2"], device: "iPhone",
                                    createdAt: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 3600)
        var titles = Set<String>(), symbols = Set<String>()
        for state in DebridRequest.State.allCases where state != .gone {   // la lápida no se enseña
            request.state = state; request.percent = 42
            titles.insert(DebridRequestWords.title(request)); symbols.insert(DebridRequestWords.symbol(state))
            XCTAssertFalse(DebridRequestWords.detail(request, now: now).isEmpty)
        }
        XCTAssertEqual(titles.count, 6); XCTAssertEqual(symbols.count, 6, "cada estado con su ícono, no solo color (A1)")
        request.state = .downloading
        XCTAssertEqual(DebridRequestWords.title(request), "Bajando en la nube · 42 %", "el texto de design/vocabulario.json › causas (RX4-A: la nube)")
        XCTAssertEqual(DebridRequestWords.short(request), "Bajando · 42 %")
        // IOS-8: sin permiso de avisos (o pedido desde otro aparato) no se promete avisar.
        XCTAssertEqual(DebridRequestWords.detail(request, now: now), "Te aviso cuando esté listo")
        XCTAssertEqual(DebridRequestWords.detail(request, now: now, notifies: false), "Ábrelo aquí para ver cuánto lleva")
        request.state = .refused
        XCTAssertEqual(DebridRequestWords.title(request), "Real-Debrid no lo dejó bajar")
        // Lo de otra cuenta de Real-Debrid nunca es «lo pediste» (contrato › other_account).
        request.device = "TV"
        XCTAssertEqual(DebridRequestWords.since(request, now: now, otherAccount: true), "Lo pidió la TV · hace 1 h · con otra cuenta de Real-Debrid")
        request.device = "iPad"
        XCTAssertEqual(DebridRequestWords.since(request, now: now, otherAccount: true), "Lo pidió iPad · hace 1 h · con otra cuenta de Real-Debrid")
        XCTAssertEqual(DebridRequestWords.since(request, now: now), "Lo pediste en iPad · hace 1 h")
        request.state = .noPeers
        XCTAssertEqual(DebridRequestWords.detail(request, now: Date(timeIntervalSince1970: 25 * 3600)), "Sigue sin bajar · ¿probar otra versión?")
    }

    /// P1-A: «Tus pedidos» en dos grupos, lo que falta y lo que ya terminó, sin grupos vacíos; P2-B: «Probar otra versión»
    /// solo cuando ayuda.
    func testRequestsSplitIntoPendingAndFinished() {
        func make(_ hash: Character, _ state: DebridRequest.State) -> DebridRequest {
            var r = DebridRequest(hash: String(repeating: hash, count: 40), title: "X", kind: "movie", metaID: "tt\(hash)", videoIDs: ["tt\(hash)"],
                                  device: "iPhone", createdAt: Date(timeIntervalSince1970: 0))
            r.state = state; r.progressAt = Date(timeIntervalSince1970: 0)
            return r
        }
        let all = [make("a", .ready), make("b", .downloading), make("c", .refused), make("d", .queued), make("e", .noPeers), make("f", .tooMany)]
        let groups = DebridRequestWords.grouped(all)
        XCTAssertEqual(groups.map(\.group), [.pending, .finished])
        XCTAssertEqual(groups[0].requests.map(\.state), [.downloading, .queued, .noPeers, .tooMany], "en el orden de la lista")
        XCTAssertEqual(groups[1].requests.map(\.state), [.ready, .refused])
        XCTAssertEqual(DebridRequestWords.grouped([make("a", .ready)]).map(\.group), [.finished], "un grupo vacío no sale")
        XCTAssertTrue(DebridRequestWords.grouped([]).isEmpty)
        let soon = Date(timeIntervalSince1970: 60)
        XCTAssertTrue(DebridRequestWords.suggestsOtherVersion(make("c", .refused), now: soon))
        XCTAssertTrue(DebridRequestWords.suggestsOtherVersion(make("e", .noPeers), now: soon))
        XCTAssertFalse(DebridRequestWords.suggestsOtherVersion(make("b", .downloading), now: soon))
        XCTAssertTrue(DebridRequestWords.suggestsOtherVersion(make("b", .downloading), now: Date(timeIntervalSince1970: 25 * 3600)), "atorado 24 h")
        XCTAssertFalse(DebridRequestWords.suggestsOtherVersion(make("a", .ready), now: soon))
    }

    func testRealDebridAnswersBecomeCauses() {
        XCTAssertEqual(UnavailableCause.from(.refused), .debridRefused)
        XCTAssertEqual(UnavailableCause.from(.invalidKey), .reconnectDebrid)
        XCTAssertEqual(UnavailableCause.from(.noKey), .reconnectDebrid)
        XCTAssertEqual(UnavailableCause.from(.notPremium), .noPremium)
        XCTAssertNil(UnavailableCause.from(.tooManyActive), "es un estado del pedido, no una causa")
        XCTAssertEqual(RDRequestError.tooManyActive.words(), "Muchas descargas activas")
        // La 10 dice «La nube lo puede bajar por ti»: ahora el botón existe.
        XCTAssertEqual(UnavailableCause.notInDebrid(language: "es-419").action, .request)
        XCTAssertEqual(UnavailableCause.label(.request), "Pedir a la nube")
        XCTAssertNil(UnavailableCause.nobodyHasIt.action)
    }

    func testNextEpisodeIsRequestedThreeMinutesBeforeTheEndOnlyIfNeeded() {
        XCTAssertEqual(PlaybackRules.upNextLookahead, 180, "R9-B: 3 min antes del final, como la TV")
        XCTAssertTrue(PlaybackRules.shouldRequestNext(remaining: 170, enabled: true, nextHasInstant: false, alreadyRequested: false))
        XCTAssertFalse(PlaybackRules.shouldRequestNext(remaining: 600, enabled: true, nextHasInstant: false, alreadyRequested: false), "todavía no")
        XCTAssertFalse(PlaybackRules.shouldRequestNext(remaining: 170, enabled: false, nextHasInstant: false, alreadyRequested: false), "el ajuste apagado")
        XCTAssertFalse(PlaybackRules.shouldRequestNext(remaining: 170, enabled: true, nextHasInstant: true, alreadyRequested: false), "ya arranca al instante")
        XCTAssertFalse(PlaybackRules.shouldRequestNext(remaining: 170, enabled: true, nextHasInstant: false, alreadyRequested: true), "nunca dos veces")
        XCTAssertTrue(AppSettings().autoRequestNextEpisode, "prendido por omisión, igual que la TV")
    }
}
