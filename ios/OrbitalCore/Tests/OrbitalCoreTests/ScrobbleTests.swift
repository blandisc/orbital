import XCTest
@testable import OrbitalCore

/// El scrobble a Trakt desde el iPhone: la sesión prestada por la consola, el 409, el 401, la cola sin conexión y el registro de lo último.
final class ScrobbleTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let get = "https://api.strem.io/api/datastoreGet", put = "https://api.strem.io/api/datastorePut"

    struct Rig {
        let http: FakeHTTP, service: WatchService, pending: InMemoryPendingStore, clock: Clock, log: ScrobbleLog, trakt: Trakt, secrets: InMemorySecrets
    }

    /// Un Trakt con la sesión PRESTADA por la consola (sin refresh token); `borrow` es lo que contesta la consola.
    func makeRig(borrow: (@Sendable () async -> BorrowedSession?)? = nil, kv: KeyValueStore? = nil) -> Rig {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock(), secrets = InMemorySecrets()
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in }, borrow: borrow)
        trakt.adopt(BorrowedSession(accessToken: "OLD", expiresAt: clock.now.timeIntervalSince1970 + 86400))
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": []]; http.json[put] = ["result": ["success": true]]
        let log = ScrobbleLog(kv: kv)
        let service = WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending,
                                   clock: { clock.now }, scrobbleLog: log)
        return Rig(http: http, service: service, pending: pending, clock: clock, log: log, trakt: trakt, secrets: secrets)
    }

    func event(_ rig: Rig, position: Double, duration: Double = 1320, video: String = "tt0386676:2:5") -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: "The Office", position: position, duration: duration, watched: 0, at: rig.clock.now.timeIntervalSince1970)
    }

    func progress(_ http: FakeHTTP, _ action: String) -> [Double] {
        http.bodies(for: "\(api)/scrobble/\(action)").compactMap { data in
            switch JSON.parse(data)?["progress"] { case .double(let p)?: return p; case .int(let i)?: return Double(i); default: return nil }
        }
    }

    func testEachActionGoesToItsEndpointWithTheRealPercentageAndIsLogged() async {
        let rig = makeRig()
        for action in ["start", "pause", "stop"] { rig.http.json["\(api)/scrobble/\(action)"] = [:] }
        await rig.service.report(event(rig, position: 330), phase: .started)
        await rig.service.report(event(rig, position: 660), phase: .paused)
        await rig.service.report(event(rig, position: 1320), phase: .stopped(finished: true))
        XCTAssertEqual(progress(rig.http, "start"), [25]); XCTAssertEqual(progress(rig.http, "pause"), [50]); XCTAssertEqual(progress(rig.http, "stop"), [100])
        let body = JSON.parse(rig.http.bodies(for: "\(api)/scrobble/start")[0])
        XCTAssertEqual(body?["show"]?["ids"]?["imdb"]?.string, "tt0386676")
        XCTAssertEqual(body?["episode"]?["season"]?.intValue, 2); XCTAssertEqual(body?["episode"]?["number"]?.intValue, 5)
        XCTAssertEqual(rig.log.status.last?.title, "The Office T2 · E5")
        XCTAssertEqual(rig.log.status.last?.action, .stop)
        XCTAssertNil(rig.log.status.error)
    }

    /// Un 401 al LEER (p. ej. al subir lo visto sin conexión) ya no borra la sesión prestada: le pide otra a tu Orbital, y si la
    /// consola no contesta, la sesión se queda (antes el scrobble se apagaba sin avisar).
    func testA401OnAReadAsksTheConsoleAndKeepsTheSessionIfItCannotAnswer() async {
        let asked = Counter()
        let rig = makeRig(borrow: { asked.bump(); return nil })
        rig.http.json["\(api)/users/me/lists"] = [:]; rig.http.statuses["\(api)/users/me/lists"] = 401
        do { _ = try await rig.trakt.lists(); XCTFail("debe avisar del error") } catch {}
        XCTAssertEqual(asked.value, 1, "se le pidió una sesión nueva a la consola")
        XCTAssertTrue(rig.trakt.linked, "la sesión prestada sigue ahí")
    }

    /// Un título sin IMDb no se puede registrar en Trakt: se dice (una vez, al empezar) en vez de callar.
    func testATitleWithoutIMDbSaysSoInsteadOfStayingQuiet() async {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 10, video: "kitsu:123:1"), phase: .started)
        XCTAssertTrue(rig.http.calls.filter { $0.contains("/scrobble/") }.isEmpty)
        XCTAssertTrue(rig.log.status.error?.contains("IMDb") == true)
    }

    func testTicksNeverScrobble() async {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 100), phase: .tick)
        XCTAssertTrue(rig.http.calls.filter { $0.contains("/scrobble/") }.isEmpty, "el guardado de cada minuto no le habla a Trakt")
    }

    func testA409IsNotAnErrorNorQueued() async {
        let rig = makeRig()
        rig.http.json["\(api)/scrobble/stop"] = [:]; rig.http.statuses["\(api)/scrobble/stop"] = 409
        await rig.service.report(event(rig, position: 1300), phase: .stopped(finished: true))
        XCTAssertNil(rig.log.status.error, "409 = ya estaba registrado")
        XCTAssertEqual(rig.log.status.last?.action, .stop)
        XCTAssertTrue(rig.pending.load().traktWatched.isEmpty)
    }

    func testA401AsksTheConsoleForANewSessionOnceAndRetries() async throws {
        let asked = AskCounter()
        let http = FakeHTTPBox()
        let rig = makeRig(borrow: {
            await asked.add()
            http.value?.statuses["https://api.trakt.tv/scrobble/stop"] = nil      // la consola ya tiene la sesión buena
            return BorrowedSession(accessToken: "NEW", expiresAt: 1_760_000_000 + 2 * 86400)
        })
        http.value = rig.http
        rig.http.json["\(api)/scrobble/stop"] = [:]; rig.http.statuses["\(api)/scrobble/stop"] = 401
        let sent = try await rig.trakt.scrobble(.stop, TraktTarget(imdb: "tt0386676", season: 2, episode: 5), progress: 95)
        XCTAssertEqual(sent, .sent)
        let count = await asked.value
        XCTAssertEqual(count, 1, "se le pide una sesión nueva a la consola, una sola vez")
        XCTAssertEqual(rig.http.calls.filter { $0.hasSuffix("/scrobble/stop") }.count, 2, "y se reintenta")
        XCTAssertTrue(rig.trakt.linked)
        XCTAssertTrue(rig.secrets.get(SecretKey.traktTokens)?.contains("NEW") == true, "la sesión nueva se guardó")
    }

    func testA401WhenTheConsoleHasNothingNewKeepsTheSessionAndQueuesWhatWasWatched() async {
        let asked = AskCounter()
        let rig = makeRig(borrow: { await asked.add(); return nil })       // la TV está apagada
        rig.http.json["\(api)/scrobble/stop"] = [:]; rig.http.statuses["\(api)/scrobble/stop"] = 401
        await rig.service.report(event(rig, position: 1300), phase: .stopped(finished: true))
        let count = await asked.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(rig.http.calls.filter { $0.hasSuffix("/scrobble/stop") }.count, 1, "sin sesión nueva no se insiste")
        XCTAssertTrue(rig.trakt.linked, "la TV apagada no desconecta Trakt del iPhone")
        XCTAssertNotNil(rig.log.status.error)
        XCTAssertEqual(rig.pending.load().traktWatched.count, 1, "lo visto espera para subirse luego")
    }

    func testAFailureIsSaidInWordsAndTheNextSuccessClearsIt() async {
        let rig = makeRig()
        rig.http.json["\(api)/scrobble/pause"] = [:]; rig.http.statuses["\(api)/scrobble/pause"] = 503
        await rig.service.report(event(rig, position: 100), phase: .paused)
        XCTAssertEqual(rig.log.status.error, "Trakt respondió HTTP 503")
        XCTAssertNil(rig.log.status.last)
        rig.http.statuses["\(api)/scrobble/pause"] = nil
        await rig.service.report(event(rig, position: 100), phase: .paused)
        XCTAssertNil(rig.log.status.error)
        XCTAssertEqual(rig.log.status.last?.action, .pause)
    }

    func testTheSameWatchedTitleClosedTwiceOfflineIsQueuedOnce() async {
        let rig = makeRig()
        rig.http.failing = ["\(api)/scrobble/stop"]
        await rig.service.report(event(rig, position: 1300), phase: .stopped(finished: true))
        rig.clock.now = rig.clock.now.addingTimeInterval(600)
        await rig.service.report(event(rig, position: 1310), phase: .stopped(finished: true))
        XCTAssertEqual(rig.pending.load().traktWatched.count, 1)
        // Al volver la red se sube UNA vez.
        rig.http.failing = []
        rig.http.json["\(api)/search/imdb/tt0386676?type=show"] = []
        rig.http.json["\(api)/sync/history"] = [:]
        await rig.service.flushPending()
        XCTAssertEqual(rig.http.bodies(for: "\(api)/sync/history").count, 1)
    }

    func testTheLogSurvivesRestartingTheApp() {
        let kv = InMemoryKeyValueStore()
        let log = ScrobbleLog(kv: kv)
        log.recordSent(title: "Dune", action: .start, at: Date(timeIntervalSince1970: 1_760_000_000))
        log.recordFailure("Trakt respondió HTTP 500")
        let again = ScrobbleLog(kv: kv).status
        XCTAssertEqual(again.last, .init(title: "Dune", action: .start, at: Date(timeIntervalSince1970: 1_760_000_000)))
        XCTAssertEqual(again.error, "Trakt respondió HTTP 500")
        log.clear()
        XCTAssertEqual(ScrobbleLog(kv: kv).status, ScrobbleStatus())
    }
}

/// Para que la consola falsa (que corre dentro de `borrow`) pueda tocar la red falsa creada después.
final class FakeHTTPBox: @unchecked Sendable { var value: FakeHTTP? }

