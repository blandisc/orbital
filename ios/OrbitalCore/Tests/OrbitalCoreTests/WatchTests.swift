import XCTest
@testable import OrbitalCore

final class WatchTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let get = "https://api.strem.io/api/datastoreGet", put = "https://api.strem.io/api/datastorePut"

    struct Rig {
        let http: FakeHTTP, service: WatchService, pending: InMemoryPendingStore, clock: Clock, library: LocalLibrary
    }

    func makeRig(trakt: Trakt? = nil, remote: JSON? = nil, signedIn: Bool = true) -> Rig {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock(), library = LocalLibrary()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": remote.map { [$0] } ?? []]
        http.json[put] = ["result": ["success": true]]
        let service = WatchService(library: library, stremio: StremioAPI(http: http), authKey: { signedIn ? "KEY" : nil }, cinemeta: Cinemeta(http: http),
                                   trakt: trakt, pending: pending, clock: { clock.now })
        return Rig(http: http, service: service, pending: pending, clock: clock, library: library)
    }

    func event(_ rig: Rig, position: Double = 600, duration: Double = 1320, watched: Double = 120, video: String = "tt0386676:1:1", title: String = "The Office (US)") -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: title, position: position, duration: duration, watched: watched, at: rig.clock.now.timeIntervalSince1970)
    }

    func savedItem(_ rig: Rig) throws -> JSON {
        let body = try XCTUnwrap(rig.http.bodies(for: put).last.flatMap(JSON.parse))
        return try XCTUnwrap(body["changes"]?.array?.first)
    }

    func testSavesOnThePhoneAndCopiesToStremioWithTheOriginalTitle() async throws {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig, title: "La Oficina"), phase: .tick)  // el llamador pasó el título traducido por error
        XCTAssertTrue(outcome.saved)
        let mine = try XCTUnwrap(rig.library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:1:1"); XCTAssertEqual(mine.position, 600); XCTAssertEqual(mine.duration, 1320)
        let item = try savedItem(rig)
        XCTAssertEqual(item["name"]?.string, series["name"]?.string, "el nombre sale de Cinemeta (original), no del título traducido")
        XCTAssertEqual(item["state"]?["video_id"]?.string, "tt0386676:1:1")
        XCTAssertEqual(item["state"]?["timeOffset"]?.intValue, 600_000)
    }

    func testFinishingAnEpisodeMarksItWatchedAndMovesToTheNext() async throws {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 1300, duration: 1320, watched: 1300), phase: .stopped(finished: true))
        let mine = try XCTUnwrap(rig.library.entry("tt0386676"))
        XCTAssertEqual(mine.videoID, "tt0386676:1:2"); XCTAssertTrue(mine.nextUp); XCTAssertEqual(mine.seen, ["tt0386676:1:1"])
        XCTAssertTrue(mine.inContinue, "sigue en «Seguir viendo» con el siguiente")
        let state = try XCTUnwrap(savedItem(rig)["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt0386676:1:2")
        XCTAssertEqual(state["timeOffset"]?.intValue, 1)
        let ids = CinemetaParsing.seasonVideoIDs(series)
        XCTAssertEqual(StremioLibrary.parseWatched(state["watched"]?.string, videoIDs: ids), ["tt0386676:1:1"])
    }

    func testOpeningAndClosingWithoutWatchingDoesNotTouchTheLibrary() async {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig, position: 5, watched: 5), phase: .stopped(finished: false))
        XCTAssertFalse(outcome.saved)
        XCTAssertNil(rig.library.entry("tt0386676"))
        XCTAssertTrue(rig.http.bodies(for: put).isEmpty)
    }

    /// Sin Stremio conectado (cualquiera que no sea Fernando) todo queda en el teléfono y a Stremio no se le pregunta nada.
    func testWithoutStremioNothingIsCopied() async throws {
        let rig = makeRig(signedIn: false)
        let outcome = await rig.service.report(event(rig), phase: .paused)
        XCTAssertTrue(outcome.saved); XCTAssertFalse(outcome.queued)
        XCTAssertEqual(rig.library.entry("tt0386676")?.position, 600)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.strem.io") })
    }

    func testWithoutInternetTheStremioCopyIsQueuedAndUploadedLater() async throws {
        let rig = makeRig()
        rig.http.statuses[put] = 500
        let outcome = await rig.service.report(event(rig), phase: .paused)
        XCTAssertTrue(outcome.saved, "en el teléfono sí quedó")
        XCTAssertTrue(outcome.queued)
        XCTAssertEqual(rig.pending.load().progress.count, 1)
        rig.http.statuses[put] = 200
        let left = await rig.service.flushPending()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(try savedItem(rig)["state"]?["timeOffset"]?.intValue, 600_000)
        XCTAssertTrue(rig.pending.load().isEmpty)
    }

    func testQueuedProgressDoesNotOverwriteANewerChangeFromAnotherDevice() async throws {
        let when = Clock().now.timeIntervalSince1970
        let remote: JSON = ["_id": "tt0386676", "name": "x", "type": "series", "_mtime": .string(StremioLibrary.iso(when + 3600)), "state": ["video_id": "tt0386676:1:5", "timeOffset": 99]]
        let rig = makeRig(remote: remote)
        var work = PendingWork()
        work.progress = [event(rig)]
        rig.pending.save(work)
        await rig.service.flushPending()
        XCTAssertTrue(rig.http.bodies(for: put).isEmpty, "lo viste en Orbital después: no se pisa")
        XCTAssertTrue(rig.pending.load().isEmpty)
    }

    func testStillOfflineKeepsTheQueue() async {
        let rig = makeRig()
        rig.http.fail = true
        var work = PendingWork()
        work.progress = [event(rig)]
        rig.pending.save(work)
        let left = await rig.service.flushPending()
        XCTAssertEqual(left.progress.count, 1)
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
                       StremioLibrary.iso(queued[0].at))
    }

    func testStartedDoesNotWriteToStremio() async {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig), phase: .started)
        XCTAssertFalse(outcome.saved)
        XCTAssertTrue(rig.http.bodies(for: put).isEmpty)
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
        http.json[get] = ["result": []]
        http.json[put] = ["result": ["success": true]]
        let service = WatchService(library: library, stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt,
                                   pending: pending, clock: { clock.now }, sleep: { _ in })
        return Rig(http: http, service: service, pending: pending, clock: clock, library: library)
    }
}


// MARK: - revisión de robustez

final class WatchRobustnessTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let get = "https://api.strem.io/api/datastoreGet", put = "https://api.strem.io/api/datastorePut"

    func make(trakt: Trakt? = nil, remote: JSON? = nil, gate: FlushGate = FlushGate()) -> (WatchService, FakeHTTP, InMemoryPendingStore, Clock) {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": remote.map { [$0] } ?? []]
        http.json[put] = ["result": ["success": true]]
        return (WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now }, gate: gate), http, pending, clock)
    }

    func event(_ clock: Clock, video: String = "tt0386676:1:1", position: Double = 600, duration: Double = 1320, watched: Double = 120, title: String = "The Office", finished: Bool = false) -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: title, position: position, duration: duration, watched: watched, at: clock.now.timeIntervalSince1970, finished: finished)
    }

    func testAnEventQueuedDuringAFlushIsNotLost() async throws {
        let (service, http, pending, clock) = make()
        var work = PendingWork(); work.progress = [event(clock, video: "tt0386676:1:1")]
        pending.save(work)
        http.delays[put] = 80                                   // la subida tarda: da tiempo a que llegue otro evento
        let flush = Task { await service.flushPending() }
        try await Task.sleep(nanoseconds: 30_000_000)
        // Este evento llega durante el vaciado y no se puede guardar (sin título original y sin Cinemeta): se encola.
        let late = ProgressEvent(kind: "movie", metaID: "tt999", videoID: "tt999", originalTitle: "", position: 900, duration: 6000, watched: 100, at: clock.now.timeIntervalSince1970)
        await service.report(late, phase: .paused)
        _ = await flush.value
        XCTAssertEqual(pending.load().progress.map(\.videoID), ["tt999"], "el evento nuevo sobrevive al vaciado y el viejo ya se subió")
        XCTAssertEqual(http.bodies(for: put).count, 1)
    }

    func testTwoFlushesAtOnceUploadOnlyOnce() async throws {
        let (service, http, pending, clock) = make()
        var work = PendingWork(); work.progress = [event(clock)]
        pending.save(work)
        http.delays[put] = 60
        async let a = service.flushPending(), b = service.flushPending()
        _ = await (a, b)
        XCTAssertEqual(http.bodies(for: put).count, 1)
        XCTAssertTrue(pending.load().isEmpty)
    }

    func testUserSaysTheyFinishedSoItIsMarkedWatchedEvenWithoutAKnownDuration() async throws {
        let (service, http, _, clock) = make()
        let outcome = await service.report(event(clock, position: 1, duration: 1, watched: 0, finished: false), phase: .stopped(finished: true))
        XCTAssertTrue(outcome.saved, "«Sí, lo terminé» no se descarta por el umbral de segundos vistos")
        let item = try XCTUnwrap(http.bodies(for: put).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        XCTAssertEqual(item["state"]?["video_id"]?.string, "tt0386676:1:2")
        let ids = CinemetaParsing.seasonVideoIDs(series)
        XCTAssertEqual(StremioLibrary.parseWatched(item["state"]?["watched"]?.string, videoIDs: ids), ["tt0386676:1:1"])
    }

    func testMovingToTheNextEpisodeBeforeNinetyPercentStillMarksThePreviousWatched() async throws {
        let (service, http, _, clock) = make()
        await service.report(event(clock, position: 1120, duration: 1320, watched: 1100), phase: .stopped(finished: true))   // créditos al 85 %
        let item = try XCTUnwrap(http.bodies(for: put).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        XCTAssertEqual(item["state"]?["video_id"]?.string, "tt0386676:1:2")
    }

    func testNoTitleNoNewItem() async throws {
        let (service, http, pending, clock) = make()
        http.statuses["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = 500      // Cinemeta caído
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = nil
        let outcome = await service.report(event(clock, title: ""), phase: .paused)
        XCTAssertTrue(outcome.queued, "sin el nombre original no se crea el item: se reintenta cuando haya Cinemeta")
        XCTAssertTrue(http.bodies(for: put).isEmpty)
        XCTAssertEqual(pending.load().progress.count, 1)
    }

    func testMyListWithoutCinemetaDoesNotWriteATranslatedTitleToStremio() async throws {
        let (service, http, _, _) = make()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = nil
        http.statuses["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = 500
        await service.setInLibrary(kind: "series", metaID: "tt0386676", title: "La Oficina", poster: nil, add: true)
        XCTAssertTrue(http.bodies(for: put).isEmpty, "a Stremio no se le escribe un nombre traducido")
        let mine = await service.entry(metaID: "tt0386676")
        XCTAssertEqual(mine?.inList, true, "en el teléfono sí queda")
        // Con Cinemeta, el nombre es el original aunque el que se muestre sea otro.
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.statuses["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = nil
        await service.setInLibrary(kind: "series", metaID: "tt0386676", title: "La Oficina", poster: nil, add: true)
        let item = try XCTUnwrap(http.bodies(for: put).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        XCTAssertEqual(item["name"]?.string, series["name"]?.string)
    }

    func testTraktWatchedIsQueuedAgainOnServerErrorsNotJustOnNetworkErrors() async throws {
        let secrets = InMemorySecrets(), clock = Clock(), http = FakeHTTP(), pending = InMemoryPendingStore()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": []]; http.json[put] = ["result": ["success": true]]
        http.json["https://api.trakt.tv/scrobble/stop"] = [:]; http.statuses["https://api.trakt.tv/scrobble/stop"] = 503
        let service = WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now })
        await service.report(event(clock, position: 1300, watched: 1300), phase: .stopped(finished: true))
        XCTAssertEqual(pending.load().traktWatched.count, 1, "un 503 de Trakt no pierde lo visto")
    }
}

final class StremioRobustnessTests: XCTestCase {
    func testMarkWatchedOnlyTouchesTheBitfieldWhenItIsNotTheCurrentVideo() throws {
        let ids = ["tt1:1:1", "tt1:1:2", "tt1:1:3", "tt1:1:8"]
        let raw: JSON = ["_id": "tt1", "name": "S", "type": "series", "state": ["video_id": "tt1:1:8", "timeOffset": 300_000, "duration": 1_000_000, "timeWatched": 300_000]]
        let item = StremioLibrary.markWatched(raw, metaID: "tt1", kind: "series", name: "S", poster: nil, videoID: "tt1:1:3", videoIDs: ids, nextVideo: "tt1:1:8", now: 1_760_000_000)
        let state = try XCTUnwrap(item["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt1:1:8", "tu punto de Seguir viendo no se mueve")
        XCTAssertEqual(state["timeOffset"]?.intValue, 300_000)
        XCTAssertEqual(StremioLibrary.parseWatched(state["watched"]?.string, videoIDs: ids), ["tt1:1:3"])
    }

    func testMarkWatchedOnTheCurrentVideoMovesToTheNext() throws {
        let ids = ["tt1:1:1", "tt1:1:2"]
        let raw: JSON = ["_id": "tt1", "name": "S", "type": "series", "state": ["video_id": "tt1:1:1", "timeOffset": 100_000, "duration": 1_000_000]]
        let state = try XCTUnwrap(StremioLibrary.markWatched(raw, metaID: "tt1", kind: "series", name: "S", poster: nil, videoID: "tt1:1:1", videoIDs: ids, nextVideo: "tt1:1:2", now: 1_760_000_000)["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt1:1:2"); XCTAssertEqual(state["timeOffset"]?.intValue, 1)
    }

    func testKitsuEpisodeNumbers() {
        XCTAssertEqual(StremioLibrary.episodeNumbers(videoID: "kitsu:7442:3", metaID: "kitsu:7442").episode, 3)
        XCTAssertNil(StremioLibrary.episodeNumbers(videoID: "kitsu:7442:3", metaID: "kitsu:7442").season)
        let s = StremioLibrary.episodeNumbers(videoID: "tt0944947:1:5", metaID: "tt0944947")
        XCTAssertEqual(s.season, 1); XCTAssertEqual(s.episode, 5)
    }

    func testAbsurdNumbersDoNotCrash() throws {
        let weird: Double = .infinity
        let item = StremioLibrary.withProgress(nil, metaID: "tt1", kind: "movie", name: "x", poster: nil, videoID: "tt1", position: .nan, duration: weird, watched: -5, nextVideo: nil, now: 1_760_000_000)
        XCTAssertEqual(item["state"]?["timeOffset"]?.intValue, 0)
        _ = StremioLibrary.withProgress(nil, metaID: "tt1", kind: "movie", name: "x", poster: nil, videoID: "tt1", position: 1e300, duration: 1e300, watched: 1e300, nextVideo: nil, now: 1_760_000_000)
        XCTAssertNotNil(StremioLibrary.parseItem(["_id": "tt1", "name": .double(1e300), "type": "movie"]))
        XCTAssertEqual(StremioLibrary.parseWatched("tt1:\(Int.max):AAAA", videoIDs: ["tt1"]), [])
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
        XCTAssertEqual(work.progress.count, 1)
        XCTAssertFalse(work.progress[0].finished)
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
        XCTAssertEqual(point, ResumePoint(seconds: 650), "50 % de 1320 s, 10 s antes (otro aparato)")
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
        XCTAssertEqual(point.seconds(duration: 2000), 490, "en cuanto el reproductor sabe cuánto dura (10 s antes)")
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
        return WatchService(library: library, stremio: StremioAPI(http: http), authKey: { nil }, cinemeta: Cinemeta(http: http), trakt: trakt,
                            pending: InMemoryPendingStore(), clock: { clock.now })
    }

    func testResumePointAsksTraktForThatEpisodeAndInfuseGetsSeconds() async throws {
        let both = service(local: local(at: "2026-10-25T10:00:00.000Z"))
        let point = await both.resumePoint(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(point, ResumePoint(seconds: 650))
        let seconds = await both.resumePosition(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(seconds, 650)
        // Solo el porcentaje (sin la duración en el teléfono): Infuse recibe lo del teléfono, que sí son segundos.
        let onlyTrakt = service(local: nil)
        let fraction = await onlyTrakt.resumePoint(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(fraction.fraction, 0.5)
        let infuse = await onlyTrakt.resumePosition(metaID: "tt0386676", videoID: "tt0386676:2:5", kind: "series")
        XCTAssertEqual(infuse, 0)
    }
}
