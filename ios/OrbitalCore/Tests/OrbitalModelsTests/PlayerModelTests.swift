import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

@MainActor
final class PlayerModelTests: XCTestCase {
    func twoSources(_ rig: Rig? = nil) throws -> Rig {
        let r = try rig ?? Rig()
        r.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            r.stream("best", size: "💾 2 GB"), r.stream("second", size: "💾 2.2 GB", name: "T\n1080p")]]
        return r
    }

    func testBeginPicksTheBestSourceAndResumesWhereYouLeftOff() async throws {
        let rig = try Rig(remote: ["_id": "tt0386676", "state": ["video_id": "tt0386676:1:1", "timeOffset": 300_000, "duration": 1_320_000]])
        _ = try twoSources(rig)
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.count, 1)
        XCTAssertEqual(rig.engine.loads[0].url.absoluteString, "https://rd.example/best.mkv", "la que ya está en Real-Debrid primero")
        XCTAssertEqual(rig.engine.loads[0].start, 300, "continúa donde ibas según Stremio")
        XCTAssertEqual(rig.model.phase, .preparing)
        await rig.model.handle(rig.playing(300))
        XCTAssertEqual(rig.model.phase, .playing)
    }

    func testFromStartIgnoresSavedPosition() async throws {
        let rig = try Rig(remote: ["_id": "tt0386676", "state": ["video_id": "tt0386676:1:1", "timeOffset": 300_000, "duration": 1_320_000]])
        _ = try twoSources(rig)
        await rig.model.begin(rig.request(fromStart: true))
        XCTAssertEqual(rig.engine.loads[0].start, 0)
    }

    func testNoSourcesShowsAClearError() async throws {
        let rig = try Rig()
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.phase, .failed("No hay fuentes de Real-Debrid para este título."))
        XCTAssertTrue(rig.engine.loads.isEmpty)
    }

    func testStartupTimeoutTriesTheNextSourceAtTheSamePoint() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        rig.clock.advance(PlaybackRules.startupTimeout + 1)
        await rig.model.tick()
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://rd.example/best.mkv", "https://rd.example/second.mkv"])
        XCTAssertEqual(rig.model.notice, .triedAnotherSource(attempt: 1))
        XCTAssertTrue(rig.engine.calls.contains("stop"))
    }

    func testAFailureBeforePlayingTriesAnotherSourceButAfterPlayingItStops() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        XCTAssertEqual(rig.engine.loads.count, 2)
        await rig.model.handle(rig.playing(0))
        XCTAssertEqual(rig.model.phase, .playing)
        await rig.model.handle(rig.playing(100, state: .failed("se cortó")))
        XCTAssertEqual(rig.model.phase, .failed("se cortó"))
        XCTAssertEqual(rig.engine.loads.count, 2, "ya estaba reproduciendo: no se cambia de fuente solo")
    }

    func testGivesUpAfterFourRetries() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": .array((1...8).map { rig.stream("s\($0)", size: "💾 \($0) GB") })]
        for n in 1...8 { rig.engine.failing.insert("https://rd.example/s\(n).mkv") }
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.phase, .failed("Ninguna fuente funcionó."))
        XCTAssertEqual(rig.engine.loads.count, PlaybackRules.maxSourceRetries + 1)
    }

    func testProgressIsSavedEveryMinuteOnPauseAndOnClose() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        for second in 1...59 { rig.clock.advance(1); await rig.model.handle(rig.playing(10 + Double(second))); await rig.model.tick() }
        XCTAssertTrue(try rig.saved().isEmpty, "antes del minuto no se guarda")
        rig.clock.advance(1); await rig.model.handle(rig.playing(70)); await rig.model.tick()
        XCTAssertEqual(try rig.saved().count, 1)
        XCTAssertEqual(try rig.saved()[0]["state"]?["timeOffset"]?.intValue, 70_000)
        // Pausar guarda
        rig.clock.advance(2); await rig.model.handle(rig.playing(72, state: .paused))
        XCTAssertEqual(try rig.saved().count, 2)
        // Cerrar guarda dónde te quedaste y lo visto
        await rig.model.close()
        XCTAssertEqual(try rig.saved().count, 3)
        XCTAssertEqual(rig.model.phase, .closed)
        let state = try XCTUnwrap(rig.saved().last?["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt0386676:1:1")
        let watchedAtFirstSave = try XCTUnwrap(rig.saved().first?["state"]?["timeWatched"]?.intValue)
        XCTAssertTrue((58_000...62_000).contains(watchedAtFirstSave), "se sumaron los ~60 s que de verdad viste: \(watchedAtFirstSave)")
    }

    func testPausedTimeDoesNotCountAsWatched() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(3); await rig.model.handle(rig.playing(13, state: .paused))   // guarda: ya vio 3 s
        rig.clock.advance(600); await rig.model.handle(rig.playing(13, state: .paused)) // 10 minutos en pausa
        rig.clock.advance(30); await rig.model.handle(rig.playing(13))
        rig.clock.advance(5); await rig.model.handle(rig.playing(18))
        await rig.model.close()
        let state = try XCTUnwrap(rig.saved().last?["state"])
        XCTAssertLessThan(state["timeWatched"]?.intValue ?? 0, 20_000)
    }

    func testOpeningAndClosingWithoutWatchingDoesNotTouchTheLibrary() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(3))
        await rig.model.close()
        XCTAssertTrue(try rig.saved().isEmpty)
    }

    func testBackgroundSavesImmediately() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(30); await rig.model.handle(rig.playing(40))
        await rig.model.appDidEnterBackground()
        XCTAssertEqual(try rig.saved().count, 1)
    }

    // MARK: pistas
    let eng = MediaTrack(id: 1, kind: .audio, language: "eng", codec: "EAC3", channels: "5.1", isDefault: true)
    let spa = MediaTrack(id: 2, kind: .audio, language: "spa", codec: "AC3", channels: "5.1")
    let subEn = MediaTrack(id: 10, kind: .subtitle, language: "eng")
    let subEs = MediaTrack(id: 11, kind: .subtitle, language: "spa")

    func testChoosesYourAudioAndSubtitlesAndRemembersWhatYouChange() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "es"; $0.subtitles = "en" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng, spa], subs: [subEn, subEs], selectedAudio: 1))
        XCTAssertTrue(rig.engine.calls.contains("audio 2"))
        XCTAssertTrue(rig.engine.calls.contains("sub 10"), "subtítulos en el idioma de Ajustes (distinto del audio)")
        await rig.model.selectAudio(1)   // cambias al inglés viendo esta serie
        let remembered = rig.titlePrefs.languages(for: "tt0386676", settings: rig.settings.value)
        XCTAssertEqual(remembered.prefs.audio, "en")
        await rig.model.selectSubtitle(nil)
        XCTAssertEqual(rig.titlePrefs.languages(for: "tt0386676", settings: rig.settings.value).subtitles, "")
    }

    func testAsksYourAddonsForSubtitlesWhenTheVideoHasNone() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "en"; $0.subtitles = "es" }
        rig.http.json["https://a.example/subtitles/series/tt0386676%3A1%3A1.json"] = ["subtitles": [["url": "https://s.example/es.srt", "lang": "spa"]]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn], selectedAudio: 1))
        XCTAssertEqual(rig.engine.subs.map(\.absoluteString), ["https://s.example/es.srt"])
        await rig.model.handle(rig.playing(1, audio: [eng], subs: [subEn, MediaTrack(id: 12, kind: .subtitle, language: "spa")], selectedAudio: 1))
        XCTAssertTrue(rig.engine.calls.contains("sub 12"), "el subtítulo nuevo se activa")
    }

    func testDoesNotFetchSubtitlesWhenAudioAlreadyInYourLanguage() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "es"; $0.subtitles = "es" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [spa], subs: [], selectedAudio: 2))
        XCTAssertTrue(rig.engine.subs.isEmpty)
    }

    func testWarnsWhenNoAudioTrackIsYourLanguage() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "es" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEs], selectedAudio: 1))
        XCTAssertEqual(rig.model.notice, .audioNotInYourLanguage)
    }

    // MARK: intro y siguiente episodio
    func testIntroCanBeSkippedOnlyInsideTheIntroChapter() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        let chapters = [Chapter(title: "Intro", time: 0), Chapter(title: "Capítulo 2", time: 90), Chapter(title: "Credits", time: 1250)]
        await rig.model.handle(rig.playing(10, chapters: chapters))
        XCTAssertEqual(rig.model.skipIntroTo, 90)
        await rig.model.skipIntro()
        XCTAssertTrue(rig.engine.calls.contains("seek 90"))
        await rig.model.handle(rig.playing(300, chapters: chapters))
        XCTAssertNil(rig.model.skipIntroTo)
    }

    func nextEpisodeRig() throws -> Rig {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("e1", binge: "grp")]]
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A2.json"] = ["streams": [rig.stream("e2", binge: "grp")]]
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A3.json"] = ["streams": [rig.stream("e3", binge: "grp")]]
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A4.json"] = ["streams": [rig.stream("e4", binge: "grp")]]
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A5.json"] = ["streams": [rig.stream("e5", binge: "grp")]]
        return rig
    }

    func testUpNextAppearsBeforeTheEndPreloadsAndAdvancesAfterTheCountdown() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1150))   // a 170 s del final: se busca ya el siguiente
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(rig.http.calls.contains { $0.contains("tt0386676%3A1%3A2") }, "la fuente del siguiente ya está buscada")
        XCTAssertNil(rig.model.upNext)
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))   // a 25 s del final
        XCTAssertEqual(rig.model.upNext?.videoID, "tt0386676:1:2")
        XCTAssertEqual(rig.model.upNext?.label, "T1 · E2")
        rig.clock.advance(PlaybackRules.upNextCountdown + 1)
        await rig.model.handle(rig.playing(1304)); await rig.model.tick()
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/e2.mkv", "la misma calidad (bingeGroup) en el siguiente")
        XCTAssertEqual(rig.engine.loads.last?.start, 0, "el siguiente empieza desde el principio")
        let state = try XCTUnwrap(rig.saved().last?["state"])
        XCTAssertEqual(state["video_id"]?.string, "tt0386676:1:2", "Stremio ya apunta al siguiente")
    }

    func testCancelingUpNextKeepsWatchingTheCurrentEpisode() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        XCTAssertNotNil(rig.model.upNext)
        rig.model.cancelUpNext()
        rig.clock.advance(20); await rig.model.handle(rig.playing(1310)); await rig.model.tick()
        XCTAssertEqual(rig.engine.loads.count, 1)
        XCTAssertNil(rig.model.upNext)
    }

    func testStillWatchingPromptAfterThreeAutoAdvances() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        for episode in 1...4 {
            await rig.model.handle(rig.playing(10))
            rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
            rig.clock.advance(PlaybackRules.upNextCountdown + 1)
            await rig.model.handle(rig.playing(1304)); await rig.model.tick()
            if episode < 4 { XCTAssertFalse(rig.model.stillWatchingPrompt, "episodio \(episode)") }
        }
        XCTAssertTrue(rig.model.stillWatchingPrompt)
        XCTAssertTrue(rig.engine.calls.contains("pause"))
        XCTAssertEqual(rig.engine.loads.count, 4, "tres saltos solos y el cuarto espera")
        await rig.model.confirmStillWatching()
        XCTAssertFalse(rig.model.stillWatchingPrompt)
        XCTAssertEqual(rig.engine.loads.count, 5)
    }

    func testTouchingTheScreenResetsTheStillWatchingCounter() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        for _ in 1...2 {
            await rig.model.handle(rig.playing(10))
            rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
            rig.clock.advance(PlaybackRules.upNextCountdown + 1)
            await rig.model.handle(rig.playing(1304)); await rig.model.tick()
        }
        await rig.model.seek(to: 5)   // tocaste la pantalla
        for _ in 1...3 {
            await rig.model.handle(rig.playing(10))
            rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
            rig.clock.advance(PlaybackRules.upNextCountdown + 1)
            await rig.model.handle(rig.playing(1304)); await rig.model.tick()
        }
        XCTAssertFalse(rig.model.stillWatchingPrompt)
    }

    func testEndOfTheLastEpisodeClosesAndMarksItWatched() async throws {
        let rig = try Rig()
        let last = "tt0386676:2:21"
        rig.http.json["https://a.example/stream/series/tt0386676%3A2%3A21.json"] = ["streams": [rig.stream("last")]]
        await rig.model.begin(rig.request(video: last))
        await rig.model.handle(rig.playing(1300))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1320, state: .ended))
        XCTAssertEqual(rig.model.phase, .closed)
        let state = try XCTUnwrap(rig.saved().last?["state"])
        XCTAssertEqual(state["timeOffset"]?.intValue, 0, "terminada: sale de Seguir viendo")
    }

    func testSwitchSourceKeepsThePosition() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(600))
        let other = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("second") == true })
        await rig.model.switchSource(to: other.index)
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/second.mkv")
        XCTAssertEqual(rig.engine.loads.last?.start, 600)
    }

    func testOfflinePlaybackUsesTheLocalFileWithoutAskingForSources() async throws {
        let rig = try Rig()
        var request = rig.request()
        request.localFile = URL(fileURLWithPath: "/tmp/video.mkv")
        await rig.model.begin(request)
        XCTAssertEqual(rig.engine.loads.map(\.url.path), ["/tmp/video.mkv"])
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/stream/") })
    }
}
