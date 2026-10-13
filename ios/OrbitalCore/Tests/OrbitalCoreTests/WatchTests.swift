import XCTest
@testable import OrbitalCore

final class WatchTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let get = "https://api.strem.io/api/datastoreGet", put = "https://api.strem.io/api/datastorePut"

    struct Rig {
        let http: FakeHTTP, service: WatchService, pending: InMemoryPendingStore, clock: Clock
    }

    func makeRig(trakt: Trakt? = nil, remote: JSON? = nil) -> Rig {
        let http = FakeHTTP(), pending = InMemoryPendingStore(), clock = Clock()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": remote.map { [$0] } ?? []]
        http.json[put] = ["result": ["success": true]]
        let service = WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now })
        return Rig(http: http, service: service, pending: pending, clock: clock)
    }

    func event(_ rig: Rig, position: Double = 600, duration: Double = 1320, watched: Double = 120, video: String = "tt0386676:1:1", title: String = "The Office (US)") -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: title, position: position, duration: duration, watched: watched, at: rig.clock.now.timeIntervalSince1970)
    }

    func savedItem(_ rig: Rig) throws -> JSON {
        let body = try XCTUnwrap(rig.http.bodies(for: put).last.flatMap(JSON.parse))
        return try XCTUnwrap(body["changes"]?.array?.first)
    }

    func testSavesProgressToStremioWithTheOriginalTitle() async throws {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig, title: "La Oficina"), phase: .tick)  // el llamador pasó el título traducido por error
        XCTAssertTrue(outcome.savedToStremio)
        let item = try savedItem(rig)
        XCTAssertEqual(item["name"]?.string, series["name"]?.string, "el nombre sale de Cinemeta (original), no del título traducido")
        XCTAssertEqual(item["state"]?["video_id"]?.string, "tt0386676:1:1")
        XCTAssertEqual(item["state"]?["timeOffset"]?.intValue, 600_000)
    }

    func testFinishingAnEpisodeMarksItWatchedAndMovesToTheNext() async throws {
        let rig = makeRig()
        await rig.service.report(event(rig, position: 1300, duration: 1320, watched: 1300), phase: .stopped(finished: true))
        let state = try XCTUnwrap(savedItem(rig)["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt0386676:1:2")
        XCTAssertEqual(state["timeOffset"]?.intValue, 1)
        let ids = CinemetaParsing.seasonVideoIDs(series)
        XCTAssertEqual(StremioLibrary.parseWatched(state["watched"]?.string, videoIDs: ids), ["tt0386676:1:1"])
    }

    func testOpeningAndClosingWithoutWatchingDoesNotTouchTheLibrary() async {
        let rig = makeRig()
        let outcome = await rig.service.report(event(rig, position: 5, watched: 5), phase: .stopped(finished: false))
        XCTAssertFalse(outcome.savedToStremio)
        XCTAssertTrue(rig.http.bodies(for: put).isEmpty)
    }

    func testWithoutInternetProgressIsQueuedAndUploadedLater() async throws {
        let rig = makeRig()
        rig.http.statuses[put] = 500
        let outcome = await rig.service.report(event(rig), phase: .paused)
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

    func testResumeUsesStremioPositionOnlyForTheSameVideo() async {
        let remote: JSON = ["_id": "tt0386676", "state": ["video_id": "tt0386676:1:2", "timeOffset": 300_000, "duration": 1_320_000]]
        let rig = makeRig(remote: remote)
        let same = await rig.service.resumePosition(metaID: "tt0386676", videoID: "tt0386676:1:2")
        let other = await rig.service.resumePosition(metaID: "tt0386676", videoID: "tt0386676:1:3")
        XCTAssertEqual(same, 300); XCTAssertEqual(other, 0)
    }

    func testContinueWatchingSkipsBarelyOpenedTitles() async throws {
        let items: JSON = [
            ["_id": "tt1", "name": "A medias", "type": "movie", "state": ["video_id": "tt1", "timeOffset": 600_000, "duration": 6_000_000, "lastWatched": "2025-01-02T00:00:00.000Z"]],
            ["_id": "tt2", "name": "Abierta un momento", "type": "movie", "state": ["video_id": "tt2", "timeOffset": 10_000, "duration": 6_000_000]],
            ["_id": "tt3", "name": "Sigue", "type": "series", "state": ["video_id": "tt3:1:2", "timeOffset": 1, "duration": 0]]]
        let http = FakeHTTP()
        http.json[get] = ["result": items]
        let service = WatchService(stremio: StremioAPI(http: http), authKey: { "K" }, cinemeta: Cinemeta(http: http), pending: InMemoryPendingStore())
        let list = try await service.continueWatching()
        XCTAssertEqual(Set(list.map(\.name)), ["A medias", "Sigue"])
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
        XCTAssertFalse(outcome.savedToStremio)
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
        let pending = InMemoryPendingStore()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[get] = ["result": []]
        http.json[put] = ["result": ["success": true]]
        let service = WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: Cinemeta(http: http), trakt: trakt, pending: pending, clock: { clock.now })
        return Rig(http: http, service: service, pending: pending, clock: clock)
    }
}

