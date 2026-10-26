import XCTest
@testable import OrbitalCore

/// El scrobble a Trakt desde el iPhone (con su propia sesión): el 409, el 401, la cola sin conexión y el registro de lo último.
final class ScrobbleTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let get = "https://api.strem.io/api/datastoreGet", put = "https://api.strem.io/api/datastorePut"

    struct Rig {
        let http: FakeHTTP, service: WatchService, pending: InMemoryPendingStore, clock: Clock, log: ScrobbleLog, trakt: Trakt, secrets: InMemorySecrets
    }

    /// Un Trakt con la sesión PROPIA del iPhone (con refresh token); `borrowed`: la que antes prestaba la consola (sin él).
    func makeRig(borrowed: Bool = false, kv: KeyValueStore? = nil) -> Rig {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock(), secrets = InMemorySecrets()
        let expires = clock.now.timeIntervalSince1970 + 86400
        secrets.set(SecretKey.traktTokens, borrowed ? #"{"access_token":"OLD","expires_at":\#(expires)}"#
                                                    : #"{"access_token":"OLD","refresh_token":"RT","expires_at":\#(expires)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
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

    /// Un 401 con la sesión prestada de antes: no hay a quién pedirle otra. Se olvida (sin revocarla: es la de la consola), se
    /// avisa para conectar Trakt en este iPhone y lo visto espera en la cola.
    func testA401WithALeftoverBorrowedSessionForgetsItWithoutRevokingAndQueues() async {
        let rig = makeRig(borrowed: true)
        rig.http.json["\(api)/scrobble/stop"] = [:]; rig.http.statuses["\(api)/scrobble/stop"] = 401
        await rig.service.report(event(rig, position: 1300), phase: .stopped(finished: true))
        XCTAssertFalse(rig.trakt.linked)
        XCTAssertFalse(rig.http.calls.contains { $0.hasSuffix("/oauth/revoke") || $0.hasSuffix("/oauth/token") })
        XCTAssertTrue(rig.log.status.error?.contains("este iPhone") == true)
        XCTAssertEqual(rig.pending.load().traktWatched.count, 1, "lo visto espera para subirse cuando conectes Trakt")
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

    /// Un 401 con la sesión propia: se renueva UNA vez con el refresh token y se reintenta.
    func testA401RenewsTheOwnSessionOnceAndRetries() async throws {
        let rig = makeRig()
        rig.http.json["\(api)/scrobble/stop"] = [:]; rig.http.statuses["\(api)/scrobble/stop"] = 401
        rig.http.json["\(api)/oauth/token"] = ["access_token": "NEW", "refresh_token": "RT2", "created_at": 1_760_000_000, "expires_in": 604800]
        _ = try? await rig.trakt.scrobble(.stop, TraktTarget(imdb: "tt0386676", season: 2, episode: 5), progress: 95)
        XCTAssertEqual(rig.http.calls.filter { $0.hasSuffix("/oauth/token") }.count, 1, "una sola renovación")
        XCTAssertEqual(rig.http.calls.filter { $0.hasSuffix("/scrobble/stop") }.count, 2, "y se reintenta")
        XCTAssertFalse(rig.http.calls.contains { $0.hasSuffix("/oauth/revoke") })
    }

    /// Pausar y cerrar le dicen a Trakt el avance exacto: con menos de 80 % Trakt lo guarda como «en pausa» (sus `/sync/playback`)
    /// y el otro dispositivo sigue ahí.
    func testPauseAndStopCarryTheExactProgressSoTraktSavesThePlaybackPoint() async {
        let rig = makeRig()
        for action in ["pause", "stop"] { rig.http.json["\(api)/scrobble/\(action)"] = [:] }
        await rig.service.report(event(rig, position: 412.5, duration: 1320), phase: .paused)
        await rig.service.report(event(rig, position: 528, duration: 1320), phase: .stopped(finished: false))
        XCTAssertEqual(progress(rig.http, "pause"), [31.25]); XCTAssertEqual(progress(rig.http, "stop"), [40])
    }

    /// Infuse avisa a Trakt por su cuenta: desde aquí no se manda nada (ni pausa ni cierre).
    func testInfuseNeverScrobblesFromHere() async {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 528), phase: .stopped(finished: false), scrobbleToTrakt: false)
        XCTAssertTrue(rig.http.calls.filter { $0.contains("/scrobble/") }.isEmpty)
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

