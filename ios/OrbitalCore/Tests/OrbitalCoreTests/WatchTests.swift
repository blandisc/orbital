import XCTest
@testable import OrbitalCore

final class WatchTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")

    struct Rig {
        let http: FakeHTTP, service: WatchService, pending: InMemoryPendingStore, clock: Clock, library: LocalLibrary
    }

    func makeRig(trakt: Trakt? = nil) -> Rig {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock(), library = LocalLibrary()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        let service = WatchService(library: library, cinemeta: Cinemeta(http: http),
                                   trakt: trakt, pending: pending, clock: { clock.now })
        return Rig(http: http, service: service, pending: pending, clock: clock, library: library)
    }

    func event(_ rig: Rig, position: Double = 600, duration: Double = 1320, watched: Double = 120, video: String = "tt0386676:1:1", title: String = "The Office (US)") -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: title, position: position, duration: duration, watched: watched, at: rig.clock.now.timeIntervalSince1970)
    }


    func testSavesOnThePhone() async throws {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig), phase: .tick)
        XCTAssertTrue(outcome.saved)
        let mine = try XCTUnwrap(rig.library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:1:1"); XCTAssertEqual(mine.position, 600); XCTAssertEqual(mine.duration, 1320)
    }

    func testFinishingAnEpisodeMarksItWatchedAndMovesToTheNext() async throws {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 1300, duration: 1320, watched: 1300), phase: .stopped(finished: true))
        let mine = try XCTUnwrap(rig.library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:1:2"); XCTAssertTrue(mine.nextUp); XCTAssertEqual(mine.seen, ["tt0386676:1:1"])
        XCTAssertTrue(mine.inContinue, "sigue en «Seguir viendo» con el siguiente")
    }

    func testOpeningAndClosingWithoutWatchingDoesNotTouchTheLibrary() async {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig, position: 5, watched: 5), phase: .stopped(finished: false))
        XCTAssertFalse(outcome.saved)
        XCTAssertNil(rig.library.entry("tt0386676"))
    }

    /// Todo queda en el teléfono y a Stremio no se le pregunta nada (F8: ya no hay copia a Stremio).
    func testNothingGoesToStremio() async throws {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig), phase: .paused)
        XCTAssertTrue(outcome.saved)
        XCTAssertEqual(rig.library.entry("tt0386676")?.position, 600)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.strem.io") })
    }




    func testResumeUsesThePhonePositionOnlyForTheSameVideo() async {
        let rig = makeRig()
        rig.library.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) {
            $0.videoID = "tt0386676:1:2"; $0.position = 300; $0.duration = 1320; $0.updatedAt = 1
        }
        let same = await rig.service.resumePosition(metaID: "tt0386676", videoID: "tt0386676:1:2")
        let other = await rig.service.resumePosition(metaID: "tt0386676", videoID: "tt0386676:1:3")
        XCTAssertEqual(same, 300); XCTAssertEqual(other, 0)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.strem.io") }, "dónde ibas ya no se le pregunta a Stremio")
    }

    func testContinueWatchingSkipsBarelyOpenedTitles() async throws {
        let rig = makeRig()
        func add(_ id: String, _ kind: String, _ name: String, _ change: (inout LibraryEntry) -> Void) {
            rig.library.update(id, make: { LibraryEntry(metaID: id, kind: kind, name: name) }, change)
        }
        add("tt1", "movie", "A medias") { $0.videoID = "tt1"; $0.position = 600; $0.duration = 6000; $0.updatedAt = 3 }
        add("tt2", "movie", "Abierta un momento") { $0.videoID = "tt2"; $0.position = 10; $0.duration = 6000; $0.updatedAt = 2 }
        add("tt3", "series", "Sigue") { $0.videoID = "tt3:1:2"; $0.nextUp = true; $0.updatedAt = 1 }
        add("tt4", "movie", "Quitada") { $0.videoID = "tt4"; $0.position = 600; $0.duration = 6000; $0.hiddenAt = 5 }
        let list = await rig.service.continueWatching()
        XCTAssertEqual(list.map(\.name), ["A medias", "Sigue"])
    }

    func testScrobbleFollowsPlaybackAndQueuesWatchedWhenOffline() async throws {
        let secrets = InMemorySecrets()
        let clockForTrakt = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clockForTrakt.now.timeIntervalSince1970 + 86400)}"#)
        let http = FakeHTTP()
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clockForTrakt.now }, pause: { _ in })
        let rig = makeRigSharing(http: http, trakt: trakt, clock: clockForTrakt)
        for action in ["start", "pause", "stop"] { http.json["https://api.trakt.tv/scrobble/\(action)"] = [:] }
        await rig.service.report(event(rig, position: 30, duration: 1320), phase: .started)
        await rig.service.report(event(rig, position: 600), phase: .paused)
        await rig.service.report(event(rig, position: 1300, watched: 1300), phase: .stopped(finished: true))
        let calls = http.calls.filter { $0.contains("/scrobble/") }.map { $0.components(separatedBy: "/").last! }
        XCTAssertEqual(calls, ["start", "pause", "stop"])
    }

    func testWatchedIsQueuedForTraktWhenTheNetworkFailsAtTheEnd() async throws {
        let secrets = InMemorySecrets(), clock = Clock()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let http = FakeHTTP()
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        let rig = makeRigSharing(http: http, trakt: trakt, clock: clock)
        http.failing = ["https://api.trakt.tv/scrobble/stop"]
        await rig.service.report(event(rig, position: 1300, watched: 1300), phase: .stopped(finished: true))
        let queued = rig.pending.load().traktWatched
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.target, TraktTarget(imdb: "tt0386676", season: 1, episode: 1))
        // Vuelve la red: se sube con la fecha real (y se comprueba antes que no esté ya).
        http.failing = []
        http.json["https://api.trakt.tv/search/imdb/tt0386676?type=show"] = []
        http.json["https://api.trakt.tv/sync/history"] = [:]
        let left = await rig.service.flushPending()
        XCTAssertTrue(left.traktWatched.isEmpty)
        let body = try XCTUnwrap(http.bodies(for: "https://api.trakt.tv/sync/history").first.flatMap(JSON.parse))
        XCTAssertEqual(body["shows"]?.array?.first?["seasons"]?.array?.first?["episodes"]?.array?.first?["watched_at"]?.string,
                       LibraryRules.iso(queued[0].at))
    }

    func testStartedDoesNotSaveYet() async {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig), phase: .started)
        XCTAssertFalse(outcome.saved)
        XCTAssertNil(rig.library.entry("tt0386676"))
    }

    func testChapterAndLanguageRules() {
        XCTAssertEqual(PlaybackRules.chapterKind("Opening"), .intro)
        XCTAssertEqual(PlaybackRules.chapterKind("Créditos"), .credits)
        XCTAssertEqual(PlaybackRules.chapterKind("Credits"), .credits)
        XCTAssertNil(PlaybackRules.chapterKind("Capítulo 3"))
        XCTAssertEqual(PlaybackRules.languageCode("spa"), "es"); XCTAssertEqual(PlaybackRules.languageCode("es-MX"), "es")
        XCTAssertEqual(PlaybackRules.languageCode("eng"), "en"); XCTAssertEqual(PlaybackRules.languageCode(""), ""); XCTAssertNil(PlaybackRules.languageCode("fra"))
        XCTAssertEqual(PlaybackRules.timeLeft(3000), "quedan 50 min"); XCTAssertEqual(PlaybackRules.timeLeft(6000 + 600), "quedan 1 h 50 min")
        XCTAssertEqual(PlaybackRules.timeLeft(7200), "quedan 2 h"); XCTAssertEqual(PlaybackRules.timeLeft(30), "")
        XCTAssertTrue(PlaybackRules.shouldShowUpNext(position: 1300, duration: 1320))
        XCTAssertFalse(PlaybackRules.shouldShowUpNext(position: 600, duration: 1320))
        XCTAssertTrue(PlaybackRules.shouldShowUpNext(position: 600, duration: 1320, inCredits: true))
    }

    func makeRigSharing(http: FakeHTTP, trakt: Trakt?, clock: Clock) -> Rig {
        let pending = InMemoryPendingStore(), library = LocalLibrary()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        let service = WatchService(library: library, cinemeta: Cinemeta(http: http), trakt: trakt,
                                   pending: pending, clock: { clock.now }, sleep: { _ in })
        return Rig(http: http, service: service, pending: pending, clock: clock, library: library)
    }
}


// MARK: - revisión de robustez

final class WatchRobustnessTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let api = "https://api.trakt.tv"

    func make(trakt: Trakt? = nil) -> (WatchService, FakeHTTP, InMemoryPendingStore, Clock, LocalLibrary) {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock(), library = LocalLibrary()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        return (WatchService(library: library, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now }), http, pending, clock, library)
    }

    func event(_ clock: Clock, video: String = "tt0386676:1:1", position: Double = 600, duration: Double = 1320, watched: Double = 120, title: String = "The Office", finished: Bool = false) -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: title, position: position, duration: duration, watched: watched, at: clock.now.timeIntervalSince1970, finished: finished)
    }


    func testTwoFlushesAtOnceUploadOnlyOnce() async throws {
        let http = FakeHTTP(), clock = Clock(), pending = InMemoryPendingStore(), secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": "tt1160419"]]]]
        http.prefix["\(api)/sync/history/movies/42"] = []
        http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
        http.delays["\(api)/sync/history"] = 60
        let service = WatchService(cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now }, sleep: { _ in })
        pending.update { $0.traktWatched = [.init(target: TraktTarget(videoID: "tt1160419", kind: "movie")!, at: clock.now.timeIntervalSince1970)] }
        async let a = service.flushPending(), b = service.flushPending()
        _ = await (a, b)
        XCTAssertEqual(http.bodies(for: "\(api)/sync/history").count, 1)
        XCTAssertTrue(pending.load().isEmpty)
    }

    func testUserSaysTheyFinishedSoItIsMarkedWatchedEvenWithoutAKnownDuration() async throws {
        let (service, _, _, clock, library) = make()
        let outcome = await service.report(event(clock, position: 1, duration: 1, watched: 0, finished: false), phase: .stopped(finished: true))
        XCTAssertTrue(outcome.saved, "«Sí, lo terminé» no se descarta por el umbral de segundos vistos")
        let mine = try XCTUnwrap(library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:1:2")
        XCTAssertEqual(mine.seen, ["tt0386676:1:1"])
    }

    func testMovingToTheNextEpisodeBeforeNinetyPercentStillMarksThePreviousWatched() async throws {
        let (service, _, _, clock, library) = make()
        await service.report(event(clock, position: 1120, duration: 1320, watched: 1100), phase: .stopped(finished: true))   // créditos al 85 %
        XCTAssertEqual(library.entry("tt0386676")?.videoID, "tt0386676:1:2")
    }


    func testMyListWithoutCinemetaStillSavesOnThePhone() async throws {
        let (service, http, _, _, _) = make()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = nil
        http.statuses["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = 500
        await service.setInLibrary(kind: "series", metaID: "tt0386676", title: "La Oficina", poster: nil, add: true)
        let mine = await service.entry(metaID: "tt0386676")
        XCTAssertEqual(mine?.inList, true, "en el teléfono sí queda")
    }

    func testTraktWatchedIsQueuedAgainOnServerErrorsNotJustOnNetworkErrors() async throws {
        let secrets = InMemorySecrets(), clock = Clock(), http = FakeHTTP(), pending = InMemoryPendingStore()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json["https://api.trakt.tv/scrobble/stop"] = [:]; http.statuses["https://api.trakt.tv/scrobble/stop"] = 503
        let service = WatchService(cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now })
        await service.report(event(clock, position: 1300, watched: 1300), phase: .stopped(finished: true))
        XCTAssertEqual(pending.load().traktWatched.count, 1, "un 503 de Trakt no pierde lo visto")
    }
}

final class LibraryRobustnessTests: XCTestCase {


    func testKitsuEpisodeNumbers() {
        XCTAssertEqual(LibraryRules.episodeNumbers(videoID: "kitsu:7442:3", metaID: "kitsu:7442").episode, 3)
        XCTAssertNil(LibraryRules.episodeNumbers(videoID: "kitsu:7442:3", metaID: "kitsu:7442").season)
        let s = LibraryRules.episodeNumbers(videoID: "tt0944947:1:5", metaID: "tt0944947")
        XCTAssertEqual(s.season, 1); XCTAssertEqual(s.episode, 5)
    }

    func testAbsurdNumbersDoNotCrash() throws {
        XCTAssertEqual(LibraryRules.finite(.nan), 0); XCTAssertEqual(LibraryRules.finite(.infinity), 0)
        XCTAssertEqual(LibraryRules.parseWatched("tt1:\(Int.max):AAAA", videoIDs: ["tt1"]), [])
    }

    func testOneOutOfRangeNumberDoesNotDiscardTheWholeResponse() throws {
        let parsed = try XCTUnwrap(JSON.parse(Data(#"{"result":[{"_id":"tt1","name":"x","state":{"timeOffset":1e999}}]}"#.utf8)))
        XCTAssertEqual(parsed["result"]?.array?.first?["_id"]?.string, "tt1")
    }

    func testHugeSourceSizeDoesNotCrashAndCRLFTextsParse() {
        let big = Streams.parse(["name": "T\n1080p", "title": "Peli 1080p\n💾 99999999 TB", "url": "https://x/a"], addon: "T", transportURL: "u", index: 1)
        XCTAssertEqual(big.size, 0)
        let giant = Streams.parse(["name": "T", "title": .string("Peli\n💾 \(String(repeating: "9", count: 400)) GB"), "url": "https://x/a"], addon: "T", transportURL: "u", index: 2)
        XCTAssertEqual(giant.size, 0)
        let crlf = Streams.parse(["name": "T\r\n1080p [RD+]", "title": "Peli.2024.1080p\r\n👤 10 💾 2 GB ⚙️ YTS\r\n🇲🇽", "url": "https://x/a"], addon: "T", transportURL: "u", index: 3)
        XCTAssertEqual(crlf.release, "Peli.2024.1080p")
        XCTAssertEqual(crlf.site, "YTS")
        XCTAssertEqual(crlf.size, 2_000_000_000)
    }

    func testInfuseIgnoresNonFiniteAndNegativePositions() throws {
        let nan = try XCTUnwrap(Infuse.parseCallback(URL(string: "orbital-ios://infuse-done?position=nan")!))
        XCTAssertEqual(nan, .closed(lastPlayed: nil, position: nil, progress: nil))
        let inf = try XCTUnwrap(Infuse.parseCallback(URL(string: "orbital-ios://infuse-done?position=inf&progress=-1")!))
        XCTAssertEqual(inf, .closed(lastPlayed: nil, position: nil, progress: nil))
    }

    func testRedactCutsAtQueryAndUserInfo() {
        XCTAssertEqual(redact("https://host?apikey=SECRET"), "host")
        XCTAssertEqual(redact("https://user:pass@host/KEY/x"), "host")
        XCTAssertEqual(redact("https://host/KEY/a://b/c"), "host")
        XCTAssertEqual(redact("host#frag"), "host")
        XCTAssertEqual(redact(""), "?")
    }

    func testLegacySettingsAndPendingFilesStillLoad() throws {
        let kv = InMemoryKeyValueStore()
        kv.set("settings", data: Data(#"{"uiLanguage":"en","audio":"en"}"#.utf8))      // un archivo viejo sin los demás campos
        let store = SettingsStore(kv)
        XCTAssertEqual(store.value.uiLanguage, "en")
        XCTAssertEqual(store.value.quality, "1080p", "lo que falta toma su valor por omisión; no se pierde todo")
        let old = Data(#"{"progress":[{"kind":"movie","metaID":"tt1","videoID":"tt1","position":5,"duration":10,"watched":5,"at":1}]}"#.utf8)
        let work = try JSONDecoder().decode(PendingWork.self, from: old)
        XCTAssertTrue(work.isEmpty, "el avance que esperaba para Stremio (ya no se copia) se ignora sin romper el archivo")
    }
}

/// Dónde seguir: lo más reciente entre este teléfono y Trakt.
final class ResumeTests: XCTestCase {
    func local(video: String = "tt0386676:2:5", position: Double = 300, duration: Double = 1320, at: String) -> LibraryEntry {
        var e = LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office")
        e.videoID = video; e.position = position; e.duration = duration; e.updatedAt = TraktParsing.date(at)!.timeIntervalSince1970
        return e
    }
    func pause(_ progress: Double, at: String) -> TraktPlayback {
        TraktPlayback(id: 1, progress: progress, pausedAt: TraktParsing.date(at)!, target: TraktTarget(imdb: "tt0386676", season: 2, episode: 5))
    }

    func testTraktWinsWhenItsPauseIsNewerAndItsPercentBecomesSecondsWithThePhonesDuration() {
        let mine = local(at: "2026-10-25T10:00:00.000Z")                       // en el iPhone, 300 s
        let point = ResumePoint.latest(local: mine, videoID: "tt0386676:2:5", trakt: pause(50, at: "2026-10-25T21:00:00.000Z"))  // en la TV, después
        XCTAssertEqual(point, ResumePoint(seconds: 660), "50 % de 1320 s, en el punto exacto (D6-A, como la TV)")
    }

    func testThePhoneWinsWhenItIsNewerOrTied() {
        let newer = local(at: "2026-10-26T10:00:00.000Z")
        XCTAssertEqual(ResumePoint.latest(local: newer, videoID: "tt0386676:2:5", trakt: pause(50, at: "2026-10-25T21:00:00.000Z")), ResumePoint(seconds: 300))
        let tied = local(at: "2026-10-25T21:00:00.000Z")
        XCTAssertEqual(ResumePoint.latest(local: tied, videoID: "tt0386676:2:5", trakt: pause(50, at: "2026-10-25T21:00:00.000Z")), ResumePoint(seconds: 300), "empate: el del teléfono (segundos exactos)")
    }

    func testTheEchoOfWhatThisPhoneSentDoesNotWin() {
        var mine = local(at: "2026-10-25T10:00:00.000Z")
        mine.pushedAt = TraktParsing.date("2026-10-25T10:00:05.000Z")!.timeIntervalSince1970
        let echo = pause(22.7, at: "2026-10-25T10:00:06.000Z")    // Trakt guardó lo que mandó este teléfono, con su propia hora
        XCTAssertEqual(ResumePoint.latest(local: mine, videoID: "tt0386676:2:5", trakt: echo), ResumePoint(seconds: 300))
    }

    func testWithoutThePhoneTheTraktPercentWaitsForTheDuration() {
        let point = ResumePoint.latest(local: nil, videoID: "tt0386676:2:5", trakt: pause(25, at: "2026-10-25T21:00:00.000Z"))
        XCTAssertEqual(point.fraction, 0.25)
        XCTAssertEqual(point.seconds(duration: 2000), 500, "en cuanto el reproductor sabe cuánto dura (el punto exacto)")
        XCTAssertEqual(point.seconds(duration: 0), 0)
        // Otro episodio en el teléfono: su duración no sirve para este.
        let other = ResumePoint.latest(local: local(video: "tt0386676:2:4", at: "2026-10-20T10:00:00Z"), videoID: "tt0386676:2:5",
                                       trakt: pause(25, at: "2026-10-25T21:00:00.000Z"))
        XCTAssertEqual(other.fraction, 0.25)
    }

    func testWithoutTraktItIsExactlyThePhone() {
        XCTAssertEqual(ResumePoint.latest(local: local(at: "2026-10-25T10:00:00Z"), videoID: "tt0386676:2:5", trakt: nil), ResumePoint(seconds: 300))
    }

    func service(local entry: LibraryEntry?) -> WatchService {
        let http = FakeHTTP(), clock = Clock(), secrets = InMemorySecrets(), library = LocalLibrary()
        if let entry { library.update(entry.metaID, make: { entry }) { _ in } }
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        http.json["https://api.trakt.tv/sync/playback?extended=full"] = [["progress": 50, "paused_at": "2026-10-25T21:00:00.000Z", "id": 7, "type": "episode",
                                                                          "episode": ["season": 2, "number": 5], "show": ["ids": ["imdb": "tt0386676"]]]]
        return WatchService(library: library, cinemeta: Cinemeta(http: http), trakt: trakt,
                            pending: InMemoryPendingStore(), clock: { clock.now })
    }

    func testResumePointAsksTraktForThatEpisodeAndInfuseGetsSeconds() async throws {
        let both = service(local: local(at: "2026-10-25T10:00:00.000Z"))
        let point = await both.resumePoint(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(point, ResumePoint(seconds: 660))
        let seconds = await both.resumePosition(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(seconds, 660)
        // Solo el porcentaje (sin la duración en el teléfono): Infuse recibe lo del teléfono, que sí son segundos.
        let onlyTrakt = service(local: nil)
        let fraction = await onlyTrakt.resumePoint(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(fraction.fraction, 0.5)
        let infuse = await onlyTrakt.resumePosition(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(infuse, 0)
    }
}
