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

    /// Desde Mi media: tu copia de OneDrive primero; si falla, Real-Debrid en el mismo punto.
    func testMiMediaPlaysYourOwnCopyFirstAndFallsBackToRealDebrid() async throws {
        let rig = try twoSources()
        let own = OneDriveLibrary.source(OneDriveFile(id: "f1", name: "Show.S01E01.2160p.mkv", path: "Series/Show.S01E01.2160p.mkv", size: 5_000_000_000,
                                                      info: OneDriveName(kind: "series", title: "Show", season: 1, episode: 1)),
                                         url: URL(string: "https://onedrive.example/own.mkv")!)
        rig.model.ownSource = { _, _ in own }
        var request = rig.request()
        request.ownCopy = true
        await rig.model.begin(request)
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://onedrive.example/own.mkv"])
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://onedrive.example/own.mkv", "su enlace dura ~1 h: primero se pide otro de tu copia")
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/best.mkv", "tu copia volvió a fallar: la de Real-Debrid")
    }

    func testWithoutMiMediaYourCopyIsNotUsed() async throws {
        let rig = try twoSources()
        rig.model.ownSource = { _, _ in XCTFail("solo desde Mi media"); return nil }
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.first?.url.absoluteString, "https://rd.example/best.mkv")
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
        XCTAssertEqual(rig.model.phase, .failed("No hay versiones en Real-Debrid para este título."))
        XCTAssertTrue(rig.engine.loads.isEmpty)
    }

    func testStartupTimeoutTriesTheNextSourceAtTheSamePoint() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        rig.clock.advance(PlaybackRules.startupTimeout + 1)
        await rig.model.tick()
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://rd.example/best.mkv", "https://rd.example/second.mkv"])
        XCTAssertEqual(rig.model.notice, .triedAnotherSource(attempt: 1))
        XCTAssertTrue(rig.engine.calls.contains("stop"))
    }

    func testAFailureBeforeOrAfterPlayingTriesAnotherSourceAtTheSamePoint() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.count, 2)
        await rig.model.handle(rig.playing(0))
        XCTAssertEqual(rig.model.phase, .playing)
        // Se corta a mitad: como en Orbital, se cambia de fuente y se sigue donde ibas.
        rig.clock.advance(5)
        await rig.model.handle(rig.playing(100))
        await rig.model.handle(rig.playing(100, state: .failed("se cortó")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.phase, .failed("Ninguna versión funcionó."), "ya no quedan más fuentes")
        XCTAssertEqual(rig.engine.loads.count, 2)
    }

    func testARepeatedFailureNotificationDoesNotBurnTheNextSource() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": .array((1...4).map { rig.stream("s\($0)", size: "💾 \($0) GB") })]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("a")))
        await rig.model.waitForTransition()
        await rig.model.handle(rig.playing(0, state: .failed("a")))      // el motor avisa dos veces del mismo fallo
        XCTAssertEqual(rig.engine.loads.count, 2, "el segundo aviso es del video que ya se descartó")
    }

    func testSnapshotsFromThePreviousVideoAreIgnoredWhileTheNextOneLoads() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        rig.clock.advance(PlaybackRules.upNextCountdown + 1)
        await rig.model.handle(rig.playing(1304)); await rig.model.tick()
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.request?.videoID, "tt0386676:1:2")
        XCTAssertFalse(rig.model.snapshot.state == .playing && rig.model.phase == .playing, "el nuevo episodio todavía no empezó: lo del anterior no cuenta")
        await rig.model.handle(rig.playing(1320, state: .ended))   // el motor aún entrega el final del episodio viejo… ya con el nuevo cargando
        XCTAssertEqual(rig.engine.loads.count, 2)
    }

    func testTheNextEpisodeShowsItsOwnName() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        rig.clock.advance(PlaybackRules.upNextCountdown + 1)
        await rig.model.handle(rig.playing(1304)); await rig.model.tick()
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.request?.videoID, "tt0386676:1:2")
        XCTAssertTrue(rig.model.request?.episodeLabel.contains("E2") == true, "no el «T1 · E1» del anterior: \(rig.model.request?.episodeLabel ?? "")")
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/e2.mkv")
    }

    func testGivesUpAfterFourRetries() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": .array((1...8).map { rig.stream("s\($0)", size: "💾 \($0) GB") })]
        for n in 1...8 { rig.engine.failing.insert("https://rd.example/s\(n).mkv") }
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.phase, .failed("Ninguna versión funcionó."))
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

    /// La regla de la TV: «Continuar» vuelve con la misma fuente y la misma pista de subtítulos con que lo dejaste.
    func testContinueUsesTheSourceAndSubtitlesYouLeftItWith() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "en"; $0.subtitles = "en" }
        await rig.model.begin(rig.request())
        let second = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("second") == true })
        let latino = MediaTrack(id: 12, kind: .subtitle, language: "spa", title: "Latinoamérica")
        rig.titlePrefs.remember(metaID: "tt0386676", choice: ResumeChoice(videoID: "tt0386676:1:1", source: second.key,
                                                                          subtitle: .init(language: "spa", title: "Latinoamérica")))
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/second.mkv", "la fuente con la que lo dejaste")
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn, subEs, latino], selectedAudio: 1))
        XCTAssertTrue(rig.engine.calls.contains("sub 12"), "la misma pista (Latinoamérica, no la otra en español)")
        XCTAssertFalse(rig.engine.calls.contains("sub 10"), "no la de Ajustes")
        await rig.model.begin(rig.request(fromStart: true))
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/best.mkv", "«Desde el principio» elige como siempre")
    }

    func testClosingRemembersTheSourceAndTracksYouHad() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(120, audio: [eng, spa], subs: [subEn, subEs], selectedAudio: 2, selectedSubtitle: 11))
        await rig.model.close()
        let choice = try XCTUnwrap(rig.titlePrefs.resumeChoice(metaID: "tt0386676", videoID: "tt0386676:1:1"))
        XCTAssertEqual(choice.source, rig.model.sourceChoices.first?.key ?? choice.source)
        XCTAssertEqual(choice.audio?.language, "spa")
        XCTAssertEqual(choice.subtitle?.language, "spa")
        XCTAssertNil(rig.titlePrefs.resumeChoice(metaID: "tt0386676", videoID: "tt0386676:1:2"), "es de ese episodio, no del siguiente")
    }

    /// IntroDB: sin capítulos en el archivo, «Saltar resumen» y «Saltar intro» salen de las marcas de la comunidad, y los
    /// créditos marcados adelantan «Siguiente episodio».
    func testCommunityMarksSkipTheRecapAndIntro() async throws {
        let rig = try twoSources()
        let model = PlayerModel(engine: rig.engine, finder: rig.finder, watch: rig.watch, titlePrefs: rig.titlePrefs, settings: rig.settings, clock: { rig.clock.now },
                                skipSegments: { _ in SkipSegments(intro: 60...120, recap: 0...45, credits: 1200...1320) })
        await model.begin(rig.request())
        await model.handle(rig.playing(10))
        try await Task.sleep(nanoseconds: 50_000_000)   // las marcas llegan aparte
        await model.handle(rig.playing(11))
        XCTAssertEqual(model.skipKind, .recap)
        XCTAssertEqual(model.skipIntroTo, 45)
        await model.handle(rig.playing(70))
        XCTAssertEqual(model.skipKind, .intro)
        XCTAssertEqual(model.skipIntroTo, 120)
        await model.handle(rig.playing(300))
        XCTAssertNil(model.skipIntroTo)
    }

    /// IntroDB que no responde a la primera: se reintenta, y el botón sale en cuanto llegan las marcas (sin otro aviso del motor).
    func testCommunityMarksAreRetriedAndShowTheButtonAsSoonAsTheyArrive() async throws {
        let rig = try twoSources()
        final class Calls: @unchecked Sendable { var n = 0 }
        let calls = Calls()
        let model = PlayerModel(engine: rig.engine, finder: rig.finder, watch: rig.watch, titlePrefs: rig.titlePrefs, settings: rig.settings, clock: { rig.clock.now },
                                skipSegments: { _ in calls.n += 1; return calls.n == 1 ? nil : SkipSegments(intro: 0...31) })
        model.segmentRetryDelays = [0.01]
        await model.begin(rig.request())
        await model.handle(rig.playing(5))
        XCTAssertNil(model.skipIntroTo)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.n, 2, "la primera falla y se pide otra vez")
        XCTAssertEqual(model.skipIntroTo, 31, "sin esperar el siguiente aviso del motor")
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

    /// «Este va bien» en una serie: en el siguiente episodio se pone el de la misma copia (grupo), aunque el video traiga uno.
    func testThisOneWorksPicksTheSameReleaseNextEpisode() async throws {
        let rig = try twoSources()
        rig.model.subtitlePicks = SubtitlePicks(rig.kv)
        rig.settings.update { $0.audio = "en"; $0.subtitles = "es" }
        let subs: JSON = ["subtitles": [["url": "https://s.example/a.srt", "lang": "spa", "release": "Show.HDTV-LOL", "downloads": 900],
                                        ["url": "https://s.example/b.srt", "lang": "spa", "release": "Show.WEB-DL-NTb", "downloads": 5],
                                        ["url": "https://s.example/sdh.srt", "lang": "spa", "release": "Show.WEB-DL-NTb", "hearing_impaired": true]]]
        rig.http.json["https://a.example/subtitles/series/tt0386676%3A1%3A1.json"] = subs
        rig.http.json["https://a.example/subtitles/series/tt0386676%3A1%3A2.json"] = subs
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn, subEs], selectedAudio: 1))
        await rig.model.ensureSubtitleSearch()
        let versions = rig.model.subtitleVersions(language: "es")
        XCTAssertEqual(versions.count, 3, "la del video y dos de internet (sin la de sordos)")
        await rig.model.selectVersion(versions[2], trying: true)   // Show.WEB-DL-NTb
        XCTAssertEqual(rig.model.tryingSubtitles, "es")
        await rig.model.handle(rig.playing(1, audio: [eng], subs: [subEn, subEs, MediaTrack(id: 20, kind: .subtitle, language: "spa")], selectedAudio: 1, selectedSubtitle: 20))
        XCTAssertEqual(rig.model.selectedVersionID, "https://s.example/b.srt")
        rig.model.confirmSubtitle()
        XCTAssertNil(rig.model.tryingSubtitles)
        XCTAssertEqual(SubtitlePicks(rig.kv).pick(metaID: "tt0386676")?.group, "ntb")
        await rig.model.begin(rig.request(video: "tt0386676:1:2"))
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn, subEs], selectedAudio: 1))
        XCTAssertEqual(rig.engine.subs.last?.absoluteString, "https://s.example/b.srt", "la misma copia, no la del video")
    }

    /// El ajuste de tiempo se recuerda por versión: cambias a otra (se pregunta «¿Va a tiempo?») y al volver se pone solo.
    func testSubtitleOffsetIsRememberedPerVersionAndTriedOnesAreMarked() async throws {
        let rig = try twoSources()
        rig.model.subtitleOffsets = SubtitleOffsets(rig.kv)
        rig.settings.update { $0.audio = "en"; $0.subtitles = "es" }
        let subEs2 = MediaTrack(id: 12, kind: .subtitle, language: "spa", title: "Castellano")
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn, subEs, subEs2], selectedAudio: 1, selectedSubtitle: 11))
        rig.model.nudgeSubtitles(by: 1.5)
        XCTAssertEqual(SubtitleOffsets(rig.kv).offset(metaID: "tt0386676", versionID: rig.model.offsetKey("track-11")), 1.5)
        XCTAssertTrue(rig.model.offsetKey("track-11").hasSuffix("|track-11"), "por subtítulo y por archivo (la misma pista es otra en otro archivo)")
        let other = try XCTUnwrap(rig.model.subtitleVersions(language: "es").first { $0.id == "track-12" })
        await rig.model.selectVersion(other)
        XCTAssertEqual(rig.model.subtitleDelay, 0, "otra versión, sin ajuste")
        XCTAssertTrue(rig.model.askInSync)
        XCTAssertEqual(rig.model.triedVersionIDs, ["track-11"])
        await rig.model.handle(rig.playing(1, audio: [eng], subs: [subEn, subEs, subEs2], selectedAudio: 1, selectedSubtitle: 12))
        await rig.model.tryAnotherVersion()   // la única sin probar ya es la 11: vuelve, con su ajuste
        XCTAssertTrue(rig.engine.calls.contains("sub 11"))
        XCTAssertEqual(rig.model.subtitleDelay, 1.5)
        XCTAssertEqual(rig.model.restoredDelay, 1.5)
        rig.model.confirmInSync()
        XCTAssertFalse(rig.model.askInSync)
        // Otro día: arranca con esa versión y el ajuste se pone solo.
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.subtitleDelay, 0)
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn, subEs, subEs2], selectedAudio: 1, selectedSubtitle: 11))
        XCTAssertEqual(rig.model.subtitleDelay, 1.5)
    }

    /// Regresar 10 s con los subtítulos apagados los enseña un momento (sin recordarlos como elegidos).
    func testSkipBackShowsSubtitlesBriefly() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "en"; $0.subtitles = "" ; $0.uiLanguage = "es" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(100, audio: [eng], subs: [subEn, subEs], selectedAudio: 1))
        XCTAssertFalse(rig.engine.calls.contains("sub 11"))
        await rig.model.skip(-10)
        XCTAssertTrue(rig.engine.calls.contains("sub 11"), "se ven al regresar")
        rig.settings.update { $0.subtitlesOnSkipBack = false }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(100, audio: [eng], subs: [subEn, subEs], selectedAudio: 1))
        let before = rig.engine.calls.filter { $0 == "sub 11" }.count
        await rig.model.skip(-10)
        XCTAssertEqual(rig.engine.calls.filter { $0 == "sub 11" }.count, before, "apagado en Ajustes")
    }

    func testDoesNotFetchSubtitlesWhenAudioAlreadyInYourLanguage() async throws {
        let rig = try twoSources()
        rig.settings.update { $0.audio = "es"; $0.subtitles = "es" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [spa], subs: [], selectedAudio: 2))
        XCTAssertTrue(rig.engine.subs.isEmpty)
    }

    /// Quieres latino y cambias A MANO a la que dice castellano: trae inglés y castellano (comprobado por sus pistas). La
    /// elegiste tú: no se insiste con «cambiar a latino». Y las pistas quedan «comprobadas» para la próxima vez.
    func testOffersTheVersionInYourSpanishWhenThisOneDoesNotHaveIt() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.LATINO\n💾 2 GB", "url": "https://rd.example/latino.mkv"]),
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.ENG.CASTELLANO\n💾 2 GB", "url": "https://rd.example/castellano.mkv"]),
        ]]
        rig.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.first?.url.absoluteString, "https://rd.example/latino.mkv", "la latina primero")
        let castilian = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("CASTELLANO") })
        let latino = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("LATINO") })
        await rig.model.switchSource(to: castilian.index)
        let spain = MediaTrack(id: 2, kind: .audio, language: "spa", title: "Castellano")
        await rig.model.handle(rig.playing(0, audio: [eng, spain], subs: [], selectedAudio: 2))
        XCTAssertNil(rig.model.notice, "la elegiste tú: no se ofrece volver a cambiar")
        XCTAssertEqual(rig.model.request?.sourceIndex, castilian.index)
        _ = latino
        XCTAssertEqual(rig.titlePrefs.checkedAudio(castilian.key), [AudioLanguage("en", .checked), AudioLanguage("es-ES", .checked)], "quedó comprobada")
    }

    /// «Continuar» en el siguiente episodio: la misma versión (su familia `bingeGroup`), no la que se recomendaría de cero.
    func testNextEpisodeKeepsTheVersionFamilyYouWereWatching() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A2.json"] = ["streams": [
            rig.stream("best", size: "💾 2 GB", binge: "group-b"), rig.stream("mine", size: "💾 2.2 GB", name: "T\n1080p [RD+]", binge: "group-a")]]
        rig.titlePrefs.remember(metaID: "tt0386676", choice: ResumeChoice(videoID: "tt0386676:1:1", source: "Torrentio|old|1", binge: "group-a"))
        await rig.model.begin(rig.request(video: "tt0386676:1:2"))
        XCTAssertEqual(rig.engine.loads.first?.url.absoluteString, "https://rd.example/mine.mkv", "la misma familia que el episodio anterior")
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

    /// «Episodios» y «Siguiente» en el reproductor: el siguiente ya se sabe al abrir, y elegir otro lo pone desde el principio.
    func testPickingAnEpisodePlaysItFromTheStart() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.nextUp?.videoID, "tt0386676:1:2")
        XCTAssertEqual(rig.model.nextUp?.label, "T1 · E2")
        await rig.model.handle(rig.playing(300))
        await rig.model.playEpisode("tt0386676:1:2")
        XCTAssertEqual(rig.model.request?.videoID, "tt0386676:1:2")
        XCTAssertTrue(rig.model.request?.episodeLabel.contains("E2") == true)
        XCTAssertEqual(rig.engine.loads.last?.start, 0, "desde el principio")
        let loads = rig.engine.loads.count
        await rig.model.playEpisode("tt0386676:1:2")
        XCTAssertEqual(rig.engine.loads.count, loads, "el que ya suena no se vuelve a abrir")
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

    func testTraktHearsAboutABigJumpSoWatchingNowStaysRight() async throws {
        let api = "https://api.trakt.tv"
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(1_760_000_000 + 86400)}"#)
        let probe = FakeHTTP()
        let trakt = Trakt(http: probe, secrets: secrets, clientID: "CID", clock: { Date(timeIntervalSince1970: 1_760_000_000) }, pause: { _ in })
        let rig = try Rig(trakt: trakt)
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("a")]]
        probe.json["\(api)/scrobble/start"] = [:]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(100))
        XCTAssertEqual(probe.calls.filter { $0.hasSuffix("/scrobble/start") }.count, 1)
        await rig.model.seek(to: 105)                                    // un saltito no se avisa
        await rig.model.handle(rig.playing(105))
        XCTAssertEqual(probe.calls.filter { $0.hasSuffix("/scrobble/start") }.count, 1)
        await rig.model.seek(to: 700)
        await rig.model.handle(rig.playing(700))
        let starts = probe.bodies("\(api)/scrobble/start")
        XCTAssertEqual(starts.count, 2, "Trakt recibe el avance nuevo")
        guard case .double(let progress)? = JSON.parse(starts[1])?["progress"] else { return XCTFail("sin progreso") }
        XCTAssertEqual(progress, 700.0 / 1320 * 100, accuracy: 0.5)
    }

    /// Un Trakt con sesión propia en su propia red falsa (`probe`), y lo que dejaste en pausa en otro dispositivo.
    func traktRig(remote: JSON? = nil, paused: JSON = []) throws -> (Rig, FakeHTTP) {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(1_760_000_000 + 86400)}"#)
        let probe = FakeHTTP()
        let trakt = Trakt(http: probe, secrets: secrets, clientID: "CID", clock: { Date(timeIntervalSince1970: 1_760_000_000) }, pause: { _ in })
        let rig = try Rig(remote: remote, trakt: trakt)
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("a")]]
        probe.json["https://api.trakt.tv/sync/playback"] = paused
        for action in ["start", "pause", "stop"] { probe.json["https://api.trakt.tv/scrobble/\(action)"] = [:] }
        return (rig, probe)
    }

    static let pausedOnTheTV: JSON = [["progress": 50, "paused_at": "2025-10-09T08:00:00.000Z", "id": 7, "type": "episode",
                                       "episode": ["season": 1, "number": 1], "show": ["ids": ["imdb": "tt0386676"]]]]

    /// Lo dejaste en la TV después que en el iPhone: se sigue donde dice Trakt, con la duración que Stremio ya conoce.
    func testResumesFromTraktWhenItsPauseIsNewerThanStremio() async throws {
        let (rig, _) = try traktRig(remote: ["_id": "tt0386676", "state": ["video_id": "tt0386676:1:1", "timeOffset": 300_000, "duration": 1_320_000,
                                                                          "lastWatched": "2025-10-08T08:00:00.000Z"]],
                                    paused: Self.pausedOnTheTV)
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.first?.start, 660, "50 % de 1320 s (Trakt es más reciente)")
    }

    func testStremioStillWinsWhenItIsNewer() async throws {
        let (rig, _) = try traktRig(remote: ["_id": "tt0386676", "state": ["video_id": "tt0386676:1:1", "timeOffset": 300_000, "duration": 1_320_000,
                                                                          "lastWatched": "2025-10-09T09:00:00.000Z"]],
                                    paused: Self.pausedOnTheTV)
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.first?.start, 300)
    }

    /// Solo el porcentaje (Stremio no tiene ese episodio): se empieza y, en cuanto el motor dice cuánto dura, se va a ese punto;
    /// Trakt recibe el «Viendo» ya con ese avance.
    func testATraktPercentWithoutDurationSeeksOnceTheEngineKnowsIt() async throws {
        let (rig, probe) = try traktRig(paused: Self.pausedOnTheTV)
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.first?.start, 0)
        await rig.model.handle(rig.playing(0, duration: 2000))
        XCTAssertTrue(rig.engine.calls.contains("seek 1000"))
        await rig.model.handle(rig.playing(1000, duration: 2000))
        XCTAssertEqual(rig.engine.calls.filter { $0.hasPrefix("seek") }.count, 1, "una sola vez")
        let progress = try XCTUnwrap(JSON.parse(try XCTUnwrap(probe.bodies("https://api.trakt.tv/scrobble/start").first))?["progress"]?.doubleValue)
        XCTAssertEqual(progress, 50, accuracy: 0.5)
    }

    func testFromStartIgnoresTrakt() async throws {
        let (rig, probe) = try traktRig(paused: Self.pausedOnTheTV)
        await rig.model.begin(rig.request(fromStart: true))
        await rig.model.handle(rig.playing(0, duration: 2000))
        XCTAssertFalse(rig.engine.calls.contains { $0.hasPrefix("seek") })
        XCTAssertFalse(probe.calls.contains { $0.hasSuffix("/sync/playback") })
    }

    /// Pausar manda `pause` con el avance exacto (una vez por pausa) y cerrar manda `stop`: Trakt guarda ese punto para el otro
    /// dispositivo.
    func testPauseAndCloseSendTheExactProgressToTrakt() async throws {
        let (rig, probe) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(330))
        await rig.model.handle(rig.playing(660, state: .paused))
        await rig.model.handle(rig.playing(660, state: .paused))
        await rig.model.close()
        func progress(_ action: String) -> [Double] {
            probe.bodies("https://api.trakt.tv/scrobble/\(action)").compactMap { JSON.parse($0)?["progress"]?.doubleValue }
        }
        XCTAssertEqual(progress("pause"), [50], "una pausa, un aviso")
        XCTAssertEqual(progress("stop"), [50])
    }

    func testTheChosenSpeedSurvivesAnotherSource() async throws {
        let rig = try twoSources()
        await rig.model.begin(rig.request())
        XCTAssertFalse(rig.engine.calls.contains { $0.hasPrefix("rate") }, "a velocidad normal no se toca el motor")
        await rig.model.setRate(1.5)
        XCTAssertEqual(rig.engine.calls.last, "rate 1.5")
        let other = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("second") == true })
        await rig.model.switchSource(to: other.index)
        XCTAssertEqual(rig.engine.calls.filter { $0 == "rate 1.5" }.count, 2, "el video nuevo empieza en 1x: se vuelve a poner")
        XCTAssertEqual(rig.model.rate, 1.5)
    }

    func testOfflinePlaybackUsesTheLocalFileWithoutAskingForSources() async throws {
        let rig = try Rig()
        var request = rig.request()
        request.localFile = URL(fileURLWithPath: "/tmp/video.mkv")
        await rig.model.begin(request)
        XCTAssertEqual(rig.engine.loads.map(\.url.path), ["/tmp/video.mkv"])
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/stream/") })
    }

    func testScrubThenReleaseSeeksOnceToTheLastPointInOrder() async throws {
        let rig = try Rig()
        await rig.model.begin(rig.request())
        let before = rig.engine.calls.count
        rig.model.scrub(to: 100); rig.model.scrub(to: 200); rig.model.scrub(to: 300)
        await rig.model.seek(to: 320)
        try await Task.sleep(nanoseconds: 2 * PlaybackRules.streamScrubInterval)
        XCTAssertEqual(Array(rig.engine.calls.dropFirst(before)), ["seek 320"], "solo el último punto, una vez, y nada viejo después")
    }

    func testScrubKeepsTheLatestPointWhileASeekIsInFlight() async throws {
        let rig = try Rig()
        await rig.model.begin(rig.request())
        let before = rig.engine.calls.count
        rig.model.scrub(to: 100)
        await Task.yield(); await Task.yield()
        rig.model.scrub(to: 150); rig.model.scrub(to: 180)
        try await Task.sleep(nanoseconds: 3 * PlaybackRules.streamScrubInterval)
        XCTAssertEqual(rig.engine.calls.dropFirst(before).last, "seek 180", "el punto final del arrastre no se pierde")
    }
}

@MainActor
final class PlayerModelRobustnessTests: XCTestCase {
    func nextEpisodeRig() throws -> Rig {
        let rig = try Rig()
        for n in 1...5 { rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A\(n).json"] = ["streams": [rig.stream("e\(n)", binge: "grp")]] }
        return rig
    }

    func testClosingTwiceSavesOnce() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        for sec in 1...30 { rig.clock.advance(1); await rig.model.handle(rig.playing(10 + Double(sec))) }
        async let a: Void = rig.model.close(), b: Void = rig.model.close()
        _ = await (a, b)
        XCTAssertEqual(try rig.saved().count, 1)
    }

    func testClosingWhileMovingToTheNextEpisodeDoesNotReopenThePlayer() async throws {
        let rig = try nextEpisodeRig()
        rig.http.delays[stremioPut] = 80                           // guardar el episodio terminado tarda
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        await rig.model.playNextNow()                              // «Ver ahora»… y a media transición…
        let moving = Task { await rig.model.playNextNow() }
        try await Task.sleep(nanoseconds: 20_000_000)
        await rig.model.close()                                    // …el usuario cierra
        await moving.value
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.phase, .closed)
        XCTAssertLessThanOrEqual(rig.engine.loads.count, 2)
        let loadsAfterClose = rig.engine.loads.count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(rig.engine.loads.count, loadsAfterClose, "tras cerrar no se vuelve a cargar nada")
    }

    func testWatchNowAndTheCountdownDoNotMoveTwice() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        rig.clock.advance(PlaybackRules.upNextCountdown + 1)
        async let a: Void = rig.model.playNextNow(), b: Void = rig.model.tick()
        _ = await (a, b)
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://rd.example/e1.mkv", "https://rd.example/e2.mkv"])
    }

    func testEndedMovesToTheNextEpisodeWithoutBeingCancelledByItself() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1320, state: .ended))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/e2.mkv")
        XCTAssertEqual(rig.model.request?.videoID, "tt0386676:1:2")
    }

    func testWatchedSecondsDuringASlowSaveAreNotLost() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        for sec in 1...59 { rig.clock.advance(1); await rig.model.handle(rig.playing(10 + Double(sec))) }
        rig.clock.advance(1); await rig.model.handle(rig.playing(70))
        rig.http.delays[stremioPut] = 80
        async let saving: Void = rig.model.tick()                  // el guardado de las 60 s tarda…
        try await Task.sleep(nanoseconds: 20_000_000)
        for sec in 1...20 { rig.clock.advance(1); await rig.model.handle(rig.playing(70 + Double(sec))) }   // …y se sigue viendo
        await saving
        rig.http.delays[stremioPut] = nil
        await rig.model.close()
        let total = try rig.saved().compactMap { $0["state"]?["timeWatched"]?.intValue }.reduce(0, +)
        XCTAssertTrue((78_000...82_000).contains(total), "los ~80 s vistos se reparten entre los guardados, sin perder ni repetir: \(total)")
    }

    func testTheExternalSubtitleIsActivatedEvenForAMovie() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [rig.stream("m")]]
        rig.http.json["https://a.example/subtitles/movie/tt1.json"] = ["subtitles": [["url": "https://s.example/es.srt", "lang": "spa"]]]
        rig.settings.update { $0.audio = "en"; $0.subtitles = "es" }
        let eng = MediaTrack(id: 1, kind: .audio, language: "eng"), subEn = MediaTrack(id: 10, kind: .subtitle, language: "eng")
        await rig.model.begin(PlayRequest(kind: "movie", metaID: "tt1", videoID: "tt1", originalTitle: "Peli", displayTitle: "Peli"))
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [subEn], selectedAudio: 1))
        await rig.model.handle(rig.playing(1, audio: [eng], subs: [subEn, MediaTrack(id: 11, kind: .subtitle, language: "spa")], selectedAudio: 1))
        XCTAssertTrue(rig.engine.calls.contains("sub 11"), "en una película (sin siguiente episodio) el subtítulo también se activa")
    }

    func testTracksLabelledWithUnderscoresMatchYourLanguage() async throws {
        XCTAssertTrue(TrackChooser.matches(MediaTrack(id: 1, kind: .audio, language: "es_MX"), "es"))
        XCTAssertTrue(TrackChooser.matches(MediaTrack(id: 1, kind: .audio, language: "es_419"), "es"))
        XCTAssertFalse(TrackChooser.matches(MediaTrack(id: 1, kind: .audio, language: "esperanto"), "es"))
    }

    func testPickingASubtitleTrackWithoutALanguageDoesNotSwitchSubtitlesOffForTheShow() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("a")]]
        await rig.model.begin(rig.request())
        let unlabeled = MediaTrack(id: 7, kind: .subtitle, language: nil)
        await rig.model.handle(rig.playing(0, subs: [unlabeled]))
        await rig.model.selectSubtitle(7)
        XCTAssertEqual(rig.titlePrefs.languages(for: "tt0386676", settings: rig.settings.value).subtitles, "es", "sigue como estaba en Ajustes")
    }

    func testOpeningCreditsAtTheStartDoNotTriggerNextEpisode() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10, chapters: [Chapter(title: "Opening Credits", time: 0), Chapter(title: "Capítulo 1", time: 60)]))
        XCTAssertNil(rig.model.upNext)
    }

    func testTheNextEpisodeCardGoesAwayIfYouSeekBackFarFromTheEnd() async throws {
        let rig = try nextEpisodeRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        XCTAssertNotNil(rig.model.upNext)
        rig.clock.advance(1); await rig.model.handle(rig.playing(600))
        XCTAssertNil(rig.model.upNext)
    }

    func testEngineErrorsDoNotLeakTheVideoURL() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("only", url: "https://rd.example/realdebrid=SECRET/a.mkv")]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("Failed to open https://rd.example/realdebrid=SECRET/a.mkv: 403")))
        await rig.model.waitForTransition()
        if case .failed(let message) = rig.model.phase { XCTAssertFalse(message.contains("SECRET")) } else { XCTFail("debía fallar") }
    }

    func testNonFiniteEngineValuesDoNotBreakSaving() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("a")]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(.nan, duration: .infinity))
        rig.clock.advance(30); await rig.model.handle(rig.playing(.infinity, duration: .infinity))
        await rig.model.close()
        XCTAssertEqual(rig.model.phase, .closed)
    }

    func testOfflineEpisodePlaysTheNextDownloadedOneNotTheSameFileAgain() async throws {
        let rig = try Rig()
        let next = LocalEpisode(file: URL(fileURLWithPath: "/tmp/ep2.mkv"), subtitles: [])
        let model = PlayerModel(engine: rig.engine, finder: rig.finder, watch: rig.watch, titlePrefs: rig.titlePrefs, settings: rig.settings, clock: { rig.clock.now },
                                localEpisode: { _, video in video == "tt0386676:1:2" ? next : nil })
        var request = rig.request()
        request.localFile = URL(fileURLWithPath: "/tmp/ep1.mkv")
        var finished: [String] = []
        model.onFinishedLocal = { finished.append($0.videoID) }
        await model.begin(request)
        await model.handle(rig.playing(10))
        rig.clock.advance(1); await model.handle(rig.playing(1295))
        XCTAssertEqual(model.upNext?.videoID, "tt0386676:1:2")
        rig.clock.advance(PlaybackRules.upNextCountdown + 1)
        await model.handle(rig.playing(1304)); await model.tick()
        await model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.map(\.url.path), ["/tmp/ep1.mkv", "/tmp/ep2.mkv"], "el siguiente episodio descargado, no el mismo archivo con otro id")
        XCTAssertEqual(finished, ["tt0386676:1:1"], "el episodio descargado que se terminó se avisa (para «Borrar al terminar de verlo»)")
    }

    func testOfflineWithoutTheNextEpisodeDownloadedShowsNoNextCard() async throws {
        let rig = try Rig()
        var request = rig.request()
        request.localFile = URL(fileURLWithPath: "/tmp/ep1.mkv")
        await rig.model.begin(request)
        await rig.model.handle(rig.playing(10))
        rig.clock.advance(1); await rig.model.handle(rig.playing(1295))
        XCTAssertNil(rig.model.upNext)
    }

    func testStaleSourceListIsRefreshedBeforeSwitching() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("old1"), rig.stream("old2", size: "💾 3 GB", name: "T\n1080p")]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(500))
        let old2 = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("old2") == true })
        rig.clock.advance(StreamFinder.cacheSeconds + 60)                // pasó más de lo que dura un enlace de Real-Debrid
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("old1"), rig.stream("old2", size: "💾 3 GB", name: "T\n1080p")]]
        await rig.model.switchSource(to: old2.index)
        XCTAssertEqual(rig.http.calls.filter { $0.contains("/stream/series/") }.count, 2, "se volvió a pedir la lista antes de cambiar")
        XCTAssertEqual(rig.engine.loads.last?.start, 500)
    }

    // MARK: scrobble a Trakt (CEN-46)

    /// Un reproductor con Trakt conectado y su red falsa aparte, para contar lo que se le avisa.
    func traktRig(request: Bool = true) throws -> (rig: Rig, probe: FakeHTTP, log: ScrobbleLog) {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(1_760_000_000 + 86400)}"#)
        let probe = FakeHTTP()
        let trakt = Trakt(http: probe, secrets: secrets, clientID: "CID", clock: { Date(timeIntervalSince1970: 1_760_000_000) }, pause: { _ in })
        let log = ScrobbleLog()
        let rig = try Rig(trakt: trakt, scrobbleLog: log)
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("a"), rig.stream("b", size: "💾 3 GB", name: "T\n1080p")]]
        for action in ["start", "pause", "stop"] { probe.json["https://api.trakt.tv/scrobble/\(action)"] = [:] }
        return (rig, probe, log)
    }

    /// El `progress` del primer aviso de esa acción (Trakt lo recibe como número: 50 o 50.5).
    func percent(_ probe: FakeHTTP, _ action: String) -> Double? {
        switch JSON.parse(probe.bodies("https://api.trakt.tv/scrobble/\(action)")[0])?["progress"] {
        case .double(let d)?: return d
        case .int(let i)?: return Double(i)
        default: return nil
        }
    }

    func scrobbles(_ probe: FakeHTTP) -> [String] { probe.calls.filter { $0.contains("/scrobble/") }.map { String($0.split(separator: "/").last!) } }

    func testStartIsNotSentUntilTheEngineActuallyPlays() async throws {
        let (rig, probe, _) = try traktRig()
        await rig.model.begin(rig.request())
        XCTAssertTrue(scrobbles(probe).isEmpty, "pedir el video no es verlo")
        await rig.model.handle(rig.playing(0, state: .loading))
        await rig.model.handle(rig.playing(0, state: .buffering))
        XCTAssertTrue(scrobbles(probe).isEmpty, "cargando o armando buffer tampoco")
        await rig.model.handle(rig.playing(12))
        XCTAssertEqual(scrobbles(probe), ["start"])
    }

    func testStartWaitsForTheDurationWhenTheEngineDoesNotKnowItYet() async throws {
        let (rig, probe, _) = try traktRig()
        var request = rig.request()
        request.meta = nil                              // sin ficha tampoco hay duración de respaldo
        await rig.model.begin(request)
        await rig.model.handle(rig.playing(5, duration: 0))
        XCTAssertTrue(scrobbles(probe).isEmpty, "sin duración no hay porcentaje")
        await rig.model.handle(rig.playing(9, duration: 1320))
        XCTAssertEqual(scrobbles(probe), ["start"], "en cuanto se sabe, se avisa")
        await rig.model.handle(rig.playing(10, duration: 1320))
        XCTAssertEqual(scrobbles(probe), ["start"], "una sola vez")
    }

    func testPausingSendsPauseAndResumingEvenThroughBufferingSendsStartAgain() async throws {
        let (rig, probe, _) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(100))
        rig.clock.advance(1)
        await rig.model.handle(rig.playing(101, state: .paused))
        XCTAssertEqual(scrobbles(probe), ["start", "pause"])
        await rig.model.handle(rig.playing(101, state: .paused))             // el motor repite lo mismo: no se repite el aviso
        XCTAssertEqual(scrobbles(probe), ["start", "pause"])
        await rig.model.handle(rig.playing(101, state: .buffering))          // al reanudar un stream pasa por «cargando»
        await rig.model.handle(rig.playing(102))
        XCTAssertEqual(scrobbles(probe), ["start", "pause", "start"], "antes Trakt se quedaba en pausa")
    }

    func testClosingSendsStopWithTheRealPercentageOnlyOnce() async throws {
        let (rig, probe, log) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(660))
        await rig.model.close()
        await rig.model.close()
        XCTAssertEqual(scrobbles(probe), ["start", "stop"])
        let progress = try XCTUnwrap(percent(probe, "stop"))
        XCTAssertEqual(progress, 50, accuracy: 0.1)
        XCTAssertEqual(log.status.last?.action, .stop)
        XCTAssertEqual(log.status.last?.title, "The Office T1 · E1")
    }

    func testFinishingAnEpisodeSendsStopNearOneHundredBeforeTheNextOnesStart() async throws {
        let (rig, probe, _) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(100))
        rig.clock.advance(1)
        await rig.model.handle(rig.playing(1320, state: .ended))
        await rig.model.waitForTransition()
        XCTAssertEqual(scrobbles(probe).prefix(2), ["start", "stop"])
        let progress = try XCTUnwrap(percent(probe, "stop"))
        XCTAssertEqual(progress, 100, accuracy: 0.1)
    }

    func testAnotherSourceAnnouncesStartAgainWhereYouWere() async throws {
        let (rig, probe, _) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(600))
        let other = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("/b.mkv") == true })
        await rig.model.switchSource(to: other.index)
        await rig.model.handle(rig.playing(600, state: .loading))
        XCTAssertEqual(scrobbles(probe), ["start"])
        await rig.model.handle(rig.playing(601))
        XCTAssertEqual(scrobbles(probe), ["start", "start"], "la fuente nueva suena: Trakt recibe el avance donde va")
    }

    func testGoingToTheBackgroundSavesProgressButDoesNotClaimThatYouStopped() async throws {
        // El audio sigue sonando en segundo plano (UIBackgroundModes: audio), así que NO es un `stop`: Trakt lo marcaría visto a ≥ 80 %.
        let (rig, probe, _) = try traktRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(1200))
        await rig.model.appDidEnterBackground()
        XCTAssertEqual(scrobbles(probe), ["start"])
        XCTAssertFalse(try rig.saved().isEmpty, "el avance sí se guarda en Stremio (iOS puede suspender la app)")
    }
}
