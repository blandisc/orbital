import XCTest
@testable import OrbitalCore

/// Desacoplar Stremio, corte A: lo tuyo vive en el teléfono y viaja por Trakt. Las pruebas de la propuesta (§4): fusión,
/// visto que se suma, desmarcar que viaja, avance viejo descartado al volver la red, solo lo que cambió, importar de Stremio.
final class LibrarySyncTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")

    struct Rig {
        let http: FakeHTTP, clock: Clock, library: LocalLibrary, pending: InMemoryPendingStore, kv: InMemoryKeyValueStore
        let trakt: Trakt, watch: WatchService, sync: LibrarySync, outbox: TraktOutbox
        let sleeps: SleepLog
    }
    final class SleepLog: @unchecked Sendable {
        private let lock = NSLock(); private var _all: [TimeInterval] = []
        var all: [TimeInterval] { lock.withLock { _all } }
        func add(_ s: TimeInterval) { lock.withLock { _all.append(s) } }
    }

    func rig(stremio: Bool = false) -> Rig {
        let http = FakeHTTP(), clock = Clock(), library = LocalLibrary(), pending = InMemoryPendingStore(), kv = InMemoryKeyValueStore(), secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        let sleeps = SleepLog()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        for action in ["start", "pause", "stop"] { http.json["\(api)/scrobble/\(action)"] = [:] }
        let watch = WatchService(library: library, stremio: StremioAPI(http: http), authKey: { stremio ? "KEY" : nil }, cinemeta: Cinemeta(http: http),
                                 trakt: trakt, pending: pending, clock: { clock.now }, sleep: { sleeps.add($0) })
        let outbox = TraktOutbox(kv)
        let sync = LibrarySync(trakt: trakt, library: library, kv: kv, outbox: outbox, pending: pending, clock: { clock.now })
        return Rig(http: http, clock: clock, library: library, pending: pending, kv: kv, trakt: trakt, watch: watch, sync: sync, outbox: outbox, sleeps: sleeps)
    }

    func event(_ r: Rig, position: Double, duration: Double = 1320, video: String = "tt0386676:1:1", finished: Bool = false) -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: "The Office", position: position, duration: duration,
                      watched: 60, at: r.clock.now.timeIntervalSince1970, finished: finished)
    }
    func scrobbles(_ r: Rig) -> [String] { r.http.calls.filter { $0.contains("/scrobble/") }.map { $0.components(separatedBy: "/").last! } }
    func percents(_ r: Rig, _ action: String) -> [Double] {
        r.http.bodies(for: "\(api)/scrobble/\(action)").compactMap { JSON.parse($0)?["progress"]?.doubleValue }
    }

    // MARK: lo que se le manda a Trakt (§5, las mismas reglas que la consola)
    func testTheProgressRule() {
        func p(_ a: ScrobbleAction, _ pos: Double, _ dur: Double = 1000, kind: String = "movie", finished: Bool = false) -> Double? {
            TraktProgressRule.percent(a, position: pos, duration: dur, kind: kind, finished: finished)
        }
        XCTAssertNil(p(.pause, 5), "menos de 1 %: Trakt contesta 422, no se manda")
        XCTAssertNil(p(.stop, 5))
        XCTAssertEqual(p(.start, 5), 0.5, "un `start` no guarda nada: sí se manda")
        XCTAssertEqual(p(.pause, 500), 50)
        XCTAssertEqual(p(.stop, 850), 79.9, "al 85 % todavía no está visto: como mucho 79.9 %")
        XCTAssertEqual(p(.stop, 920), 92, "película al 92 %: visto, el avance real")
        XCTAssertEqual(p(.stop, 700, finished: true), 80, "créditos al 70 %: al menos 80 para que Trakt lo marque")
        // Episodio de 45 min al 92 %: aún faltan 3.6 min (el tramo final es de 90 s): no está visto.
        XCTAssertEqual(p(.stop, 2484, 2700, kind: "series"), 79.9)
        XCTAssertEqual(p(.stop, 2650, 2700, kind: "series") ?? 0, 2650.0 / 27, accuracy: 0.01)
        XCTAssertNil(p(.pause, 500, 0), "sin duración no se manda")
    }

    func testBackupEveryFiveMinutesIsStartThenPauseAndTheNextPauseStartsAgain() async {
        let r = rig()
        await r.watch.report(event(r, position: 100), phase: .started)
        r.clock.now = r.clock.now.addingTimeInterval(60); await r.watch.report(event(r, position: 160), phase: .tick)
        XCTAssertEqual(scrobbles(r), ["start"], "al minuto no hay respaldo")
        r.clock.now = r.clock.now.addingTimeInterval(250); await r.watch.report(event(r, position: 410), phase: .tick)
        XCTAssertEqual(scrobbles(r), ["start", "start", "pause"])
        XCTAssertEqual(r.sleeps.all, [2], "2 s entre `start` y `pause`")
        r.clock.now = r.clock.now.addingTimeInterval(30); await r.watch.report(event(r, position: 440), phase: .paused)
        XCTAssertEqual(scrobbles(r), ["start", "start", "pause", "start", "pause"], "tras un respaldo, la pausa lleva antes un `start`")
    }

    func testGoingToTheBackgroundSendsAPauseNotAStop() async {
        let r = rig()
        await r.watch.report(event(r, position: 100), phase: .started)
        await r.watch.report(event(r, position: 600), phase: .background)
        XCTAssertEqual(scrobbles(r), ["start", "pause"])
        XCTAssertEqual(r.library.entry("tt0386676")?.position, 600)
    }

    func testClosingAtEightyFivePercentKeepsYourSpotOnTrakt() async {
        let r = rig()
        await r.watch.report(event(r, position: 1122), phase: .stopped(finished: false))   // 85 % de un episodio
        XCTAssertEqual(percents(r, "stop"), [79.9])
        XCTAssertEqual(r.library.entry("tt0386676")?.position, 1122, "el teléfono guarda el segundo exacto")
    }

    // MARK: fusión
    func entry(video: String = "tt0386676:2:5", position: Double = 300, duration: Double = 1320, at: Double) -> LibraryEntry {
        var e = LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office")
        e.videoID = video; e.position = position; e.duration = duration; e.updatedAt = at
        return e
    }
    func playback(_ progress: Double, at: Double, season: Int = 2, episode: Int = 5) -> TraktPlayback {
        TraktPlayback(id: 9, progress: progress, pausedAt: Date(timeIntervalSince1970: at), target: TraktTarget(imdb: "tt0386676", season: season, episode: episode),
                      title: "The Office", runtime: 22)
    }

    func testProgressMergeNewestWinsAndATieKeepsThePhone() {
        XCTAssertNil(LibraryMerge.playback(entry(at: 2000), playback(50, at: 1000)), "lo del teléfono es más nuevo")
        XCTAssertNil(LibraryMerge.playback(entry(at: 1000), playback(50, at: 1000)), "empate: el teléfono (segundos exactos)")
        let won = LibraryMerge.playback(entry(at: 1000), playback(50, at: 2000))
        XCTAssertEqual(won?.position, 660, "50 % con la duración que el teléfono conoce de ese episodio")
        XCTAssertNil(won?.fraction)
        // Otro episodio: la duración de Trakt (22 min) y la fracción para buscar con la del archivo.
        let other = LibraryMerge.playback(entry(at: 1000), playback(25, at: 2000, episode: 6))
        XCTAssertEqual(other?.videoID, "tt0386676:2:6"); XCTAssertEqual(other?.fraction, 0.25); XCTAssertEqual(other?.duration, 1320)
        // Nuevo en el teléfono (lo empezaste en la TV): entra a «Seguir viendo».
        XCTAssertEqual(LibraryMerge.playback(nil, playback(40, at: 2000))?.inContinue, true)
    }

    func testWatchedAddsUpAndANewerEpisodeElsewhereMovesToTheNext() {
        var mine = entry(video: "tt0386676:1:3", at: 1000)
        mine.seen = ["tt0386676:1:1"]
        let progress = TraktShowProgress(imdb: "tt0386676", lastWatchedAt: Date(timeIntervalSince1970: 2000),
                                         completed: [(1, 2), (1, 3)], next: (1, 4), last: (1, 3))
        let merged = LibraryMerge.show(mine, progress, name: "The Office", unmarked: ["tt0386676:1:2"])
        XCTAssertEqual(merged.seen, ["tt0386676:1:1", "tt0386676:1:3"], "se suma; lo que desmarcaste aquí no regresa")
        XCTAssertEqual(merged.videoID, "tt0386676:1:4"); XCTAssertTrue(merged.nextUp)
        // Lo de aquí es más nuevo: lo visto se suma pero tu punto no se mueve.
        let older = TraktShowProgress(imdb: "tt0386676", lastWatchedAt: Date(timeIntervalSince1970: 500), completed: [(1, 5)], next: (1, 6), last: (1, 5))
        let kept = LibraryMerge.show(mine, older, name: "The Office")
        XCTAssertEqual(kept.videoID, "tt0386676:1:3"); XCTAssertTrue(kept.seen.contains("tt0386676:1:5"))
    }

    func testMyListMirrorsTheWatchlistExceptWhatIsStillWaitingHere() {
        var entries: [String: LibraryEntry] = [:]
        var a = LibraryEntry(metaID: "tt1", kind: "movie", name: "A"); a.inList = true
        var b = LibraryEntry(metaID: "tt2", kind: "movie", name: "B"); b.inList = true
        entries["tt1"] = a; entries["tt2"] = b
        let onTrakt = [TraktEntry(kind: "movie", imdb: "tt3", title: "C", year: nil, runtime: nil, episodes: nil, overview: "", traktID: nil),
                       TraktEntry(kind: "movie", imdb: "tt1", title: "A", year: nil, runtime: nil, episodes: nil, overview: "", traktID: nil)]
        LibraryMerge.watchlist(&entries, trakt: onTrakt, pending: ["tt2": true], now: 100)
        XCTAssertEqual(entries["tt1"]?.inList, true)
        XCTAssertEqual(entries["tt2"]?.inList, true, "lo guardaste aquí sin red: no se borra porque Trakt aún no lo tenga")
        XCTAssertEqual(entries["tt3"]?.inList, true, "lo guardado en otro aparato llega")
        LibraryMerge.watchlist(&entries, trakt: onTrakt, pending: [:], now: 200)
        XCTAssertEqual(entries["tt2"]?.inList, false, "ya sin nada pendiente, manda Trakt")
    }

    // MARK: viajes
    func testOldProgressIsDiscardedWhenTheNetworkReturnsIfTraktHasNewer() async throws {
        let r = rig()
        r.http.failing = ["\(api)/scrobble/pause"]
        await r.watch.report(event(r, position: 600), phase: .paused)
        XCTAssertEqual(r.pending.load().traktProgress.count, 1, "sin red: tu avance espera")
        // Mientras, lo viste en la TV (una pausa más nueva en Trakt).
        r.http.failing = []
        let later = StremioLibrary.iso(r.clock.now.timeIntervalSince1970 + 600)
        r.http.json["\(api)/sync/playback?extended=full"] = [["progress": 70, "paused_at": .string(later), "id": 5, "type": "episode",
                                                             "episode": ["season": 1, "number": 1], "show": ["ids": ["imdb": "tt0386676"]]]]
        let before = scrobbles(r).count
        await r.watch.flushPending()
        XCTAssertEqual(scrobbles(r).count, before, "el viejo no se manda: retrocedería tu avance")
        XCTAssertTrue(r.pending.load().traktProgress.isEmpty)
    }

    func testQueuedProgressIsSentAsStartAndPauseWhenTraktHasNothingNewer() async throws {
        let r = rig()
        r.http.failing = ["\(api)/scrobble/pause"]
        await r.watch.report(event(r, position: 600), phase: .paused)
        r.http.failing = []
        r.http.json["\(api)/sync/playback?extended=full"] = []
        await r.watch.flushPending()
        XCTAssertEqual(Array(scrobbles(r).suffix(2)), ["start", "pause"])
        XCTAssertTrue(r.pending.load().traktProgress.isEmpty)
    }

    func testDismissingRemovesThePausedEntryOnTrakt() async throws {
        let r = rig()
        r.library.update("tt0386676", make: { self.entry(at: r.clock.now.timeIntervalSince1970 - 60) }) { _ in }
        r.http.json["\(api)/sync/playback?extended=full"] = [["progress": 20, "paused_at": .string(StremioLibrary.iso(r.clock.now.timeIntervalSince1970 - 60)),
                                                             "id": 77, "type": "episode", "episode": ["season": 2, "number": 5], "show": ["ids": ["imdb": "tt0386676"]]]]
        r.http.json["\(api)/sync/playback/77"] = [:]; r.http.statuses["\(api)/sync/playback/77"] = 204
        await r.watch.dismissContinue(metaID: "tt0386676")
        XCTAssertEqual(r.library.entry("tt0386676")?.inContinue, false, "sale al instante")
        XCTAssertTrue(r.http.calls.contains("\(api)/sync/playback/77"), "y se borra de Trakt")
        XCTAssertTrue(r.pending.load().playbackRemovals.isEmpty)
    }

    func testUnmarkingTravelsToTraktAndASyncDoesNotBringItBack() async throws {
        let r = rig()
        r.http.failing = ["\(api)/sync/history/remove"]
        r.library.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) { $0.seen = ["tt0386676:1:1"] }
        await r.watch.unmarkWatched(kind: "series", metaID: "tt0386676", videoID: "tt0386676:1:1")
        XCTAssertEqual(r.library.entry("tt0386676")?.seen, [])
        XCTAssertEqual(r.pending.load().traktUnwatched, [TraktTarget(imdb: "tt0386676", season: 1, episode: 1)], "sin red: espera")
        // Trakt todavía dice que lo viste: la sincronización no lo regresa.
        r.http.json["\(api)/shows/tt0386676/progress/watched?hidden=false&specials=false"] = [
            "last_watched_at": "2020-01-01T00:00:00.000Z", "seasons": [["number": 1, "episodes": [["number": 1, "completed": true]]]],
            "last_episode": ["season": 1, "number": 1]]
        await r.sync.pullShow(imdb: "tt0386676", name: "The Office")
        XCTAssertEqual(r.library.entry("tt0386676")?.seen, [])
        r.http.failing = []
        r.http.json["\(api)/sync/history/remove"] = [:]
        await r.watch.flushPending()
        let body = try XCTUnwrap(r.http.bodies(for: "\(api)/sync/history/remove").last.flatMap(JSON.parse))
        XCTAssertEqual(body["shows"]?.array?.first?["seasons"]?.array?.first?["episodes"]?.array?.first?["number"]?.intValue, 1)
        XCTAssertTrue(r.pending.load().traktUnwatched.isEmpty)
    }

    func testOnlyWhatChangedIsDownloaded() async throws {
        let r = rig()
        r.http.json["\(api)/sync/last_activities"] = ["movies": ["paused_at": "2026-10-29T10:00:00.000Z", "watched_at": "2026-10-01T00:00:00.000Z"],
                                                      "episodes": ["paused_at": "2026-10-28T10:00:00.000Z", "watched_at": "2026-10-01T00:00:00.000Z"],
                                                      "watchlist": ["updated_at": "2026-10-20T00:00:00.000Z"]]
        r.http.json["\(api)/sync/watched/shows?extended=noseasons"] = []
        r.http.json["\(api)/sync/watched/movies"] = []
        r.http.json["\(api)/sync/playback?extended=full"] = [["progress": .double(37.5), "paused_at": "2026-10-29T10:00:00.000Z", "id": 3, "type": "movie",
                                                              "movie": ["title": "Night of the Living Dead", "runtime": 96, "ids": ["imdb": "tt0063350"]]]]
        r.http.json["\(api)/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = []
        let changed = await r.sync.pull()
        XCTAssertTrue(changed)
        let movie = try XCTUnwrap(r.library.entry("tt0063350"))
        XCTAssertTrue(movie.inContinue, "lo que dejaste en la consola aparece en «Seguir viendo» del iPhone (la prueba del 29 oct)")
        XCTAssertEqual(movie.progress ?? 0, 0.375, accuracy: 0.0001)
        let calls = r.http.calls.count
        await r.sync.pull()
        XCTAssertEqual(r.http.calls.count, calls + 1, "nada cambió: solo la pregunta chiquita")
    }

    func testStremioIsImportedOnceIntoThePhone() async throws {
        let r = rig(stremio: true)
        r.http.json["https://api.strem.io/api/datastoreGet"] = ["result": [
            ["_id": "tt0386676", "name": "The Office", "type": "series", "removed": false, "temp": false,
             "state": ["video_id": "tt0386676:2:5", "timeOffset": 600_000, "duration": 1_320_000, "lastWatched": "2026-10-20T00:00:00.000Z",
                       "watched": .string(StremioLibrary.encodeWatched(["tt0386676:1:1"], videoIDs: CinemetaParsing.seasonVideoIDs(series)) ?? "")]]]]
        let kv = InMemoryKeyValueStore()
        let first = await r.watch.importFromStremio(kv: kv)
        XCTAssertEqual(first, 1)
        let mine = try XCTUnwrap(r.library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:2:5"); XCTAssertEqual(mine.position, 600); XCTAssertEqual(mine.seen, ["tt0386676:1:1"])
        XCTAssertFalse(mine.inList, "Mi lista de Stremio no se trae: Mi lista es tu watchlist de Trakt")
        let again = await r.watch.importFromStremio(kv: kv)
        XCTAssertEqual(again, 0, "una sola vez")
    }
}
