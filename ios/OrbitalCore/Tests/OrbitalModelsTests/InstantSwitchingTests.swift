import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Cambiar algo dentro del reproductor se siente al instante y nunca truena (23 nov 2026, «que se sienta instantáneo el
/// cambio»): lo que eliges se ve elegido al tocar, el último toque gana aunque el anterior siga cargando, y cambiar de episodio
/// no espera a que se guarde el anterior. La regla está en `docs/ios-interfaz.md` («Lo que eliges en el reproductor se ve al tocar»).
@MainActor
final class InstantSwitchingTests: XCTestCase {
    let eng = MediaTrack(id: 1, kind: .audio, language: "eng"), spa = MediaTrack(id: 2, kind: .audio, language: "spa")
    let subEn = MediaTrack(id: 10, kind: .subtitle, language: "eng")

    /// Suena la primera de tres versiones en el segundo 300.
    func threeVersions() async throws -> (Rig, [Source]) {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            rig.stream("a", title: "Show.S01E01.1080p.WEB-DL"), rig.stream("b", title: "Show.S01E01.1080p.BluRay"), rig.stream("c", title: "Show.S01E01.720p.HDTV"),
        ]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(300, audio: [eng, spa], subs: [subEn], selectedAudio: 1, selectedSubtitle: 10))
        let playing = try XCTUnwrap(rig.model.source)
        let others = rig.model.sourceChoices.filter { $0.index != playing.index }
        XCTAssertEqual(others.count, 2, "precondición: hay otras dos")
        return (rig, [playing] + others)
    }

    func testSwitchingTwiceQuicklyKeepsYourSecondAndYourWayBack() async throws {
        let (rig, v) = try await threeVersions()
        rig.engine.hangLoads = true                                    // la segunda se queda abriendo…
        let first = Task { await rig.model.switchSource(to: v[1].index) }
        for _ in 0..<200 where rig.engine.loads.count < 2 { await Task.yield() }
        XCTAssertEqual(rig.engine.loads.count, 2)
        XCTAssertEqual(rig.model.phase, .preparing, "la carga se ve al tocar")
        // …y mientras, el motor dice 0 (abriendo). Antes, el segundo toque tomaba ese 0 y el video empezaba desde el principio.
        await rig.model.handle(rig.playing(0, state: .loading))
        rig.engine.hangLoads = false
        await rig.model.switchSource(to: v[2].index)                    // …y tocas otra
        await first.value
        XCTAssertEqual(rig.engine.loads.last?.url, v[2].playbackURL)
        XCTAssertEqual(rig.engine.loads.last?.start ?? 0, 300, accuracy: 1, "en el mismo segundo, no desde el principio")
        XCTAssertEqual(rig.model.switchBack?.source.index, v[0].index, "si no abre, se vuelve a la que de verdad veías")
        XCTAssertEqual(rig.model.source?.index, v[2].index, "el último toque gana")
    }

    func testAVersionThatIsGoneLeavesYouWatchingAsBefore() async throws {
        let (rig, v) = try await threeVersions()
        await rig.model.switchSource(to: 999)
        XCTAssertEqual(rig.model.phase, .playing, "sin carga colgada")
        XCTAssertEqual(rig.model.source?.index, v[0].index)
        XCTAssertEqual(rig.engine.calls.suffix(2), ["pause", "play"], "sigue sonando")
    }

    func testTheAudioYouTapIsCheckedAtOnce() async throws {
        let (rig, _) = try await threeVersions()
        await rig.model.selectAudio(2)
        XCTAssertEqual(rig.model.snapshot.selectedAudio, 1, "el motor todavía no la pone (rearma el video)")
        XCTAssertEqual(rig.model.shownAudio, 2, "pero la palomita ya está donde tocaste")
        await rig.model.handle(rig.playing(301, audio: [eng, spa], subs: [subEn], selectedAudio: 2, selectedSubtitle: 10))
        XCTAssertNil(rig.model.pendingAudio, "el motor la confirmó")
        XCTAssertEqual(rig.model.shownAudio, 2)
    }

    func testAnAudioTheEngineNeverSetsDoesNotStayChecked() async throws {
        let (rig, _) = try await threeVersions()
        await rig.model.selectAudio(2)
        rig.clock.advance(PlayerModel.pendingAudioWait + 1)
        await rig.model.tick()
        XCTAssertEqual(rig.model.shownAudio, 1, "la palomita vuelve a la que de verdad suena")
    }

    func testAnInternetSubtitleArrivingLateDoesNotReplaceTheOneYouPickedAfter() async throws {
        let (rig, _) = try await threeVersions()
        let url = try XCTUnwrap(URL(string: "https://subs.example/es.srt"))
        await rig.model.selectVersion(SubtitleVersion(origin: .internet(SubtitleOption(url: url, language: "es")), language: "es", match: 0))
        XCTAssertTrue(rig.model.loadingSubtitle)
        await rig.model.selectSubtitle(10)                               // te arrepientes: el inglés del video
        XCTAssertFalse(rig.model.loadingSubtitle, "el botón ya no carga el que dejaste")
        let arrived = MediaTrack(id: 11, kind: .subtitle, language: "spa")
        await rig.model.handle(rig.playing(302, audio: [eng, spa], subs: [subEn, arrived], selectedAudio: 1, selectedSubtitle: 10))
        XCTAssertEqual(rig.model.addedTracks[url], 11, "queda en la lista como «de internet»")
        XCTAssertEqual(rig.engine.calls.last, "sub 10", "no se pone encima del que elegiste")
    }

    func testASubtitleThatCannotBeFetchedLeavesNothingLoading() async throws {
        let (rig, _) = try await threeVersions()
        let url = try XCTUnwrap(URL(string: "\(OpenSubtitlesAPI.scheme)://file/1"))   // sin cuenta de OpenSubtitles: no se puede pedir
        await rig.model.selectVersion(SubtitleVersion(origin: .internet(SubtitleOption(url: url, language: "es")), language: "es", match: 0))
        XCTAssertFalse(rig.model.loadingSubtitle)
        XCTAssertTrue(rig.model.addedSubtitleURLs.isEmpty)
        XCTAssertNotNil(rig.model.notice, "se dice por qué")
    }

    func testPickingAnEpisodeDoesNotWaitForTheSave() async throws {
        let rig = try Rig()
        for n in 1...3 { rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A\(n).json"] = ["streams": [rig.stream("e\(n)", binge: "grp")]] }
        rig.saves.delay = 0.3                                            // guardar en la red tarda
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        for sec in 1...30 { rig.clock.advance(1); await rig.model.handle(rig.playing(10 + Double(sec))) }
        await rig.model.playEpisode("tt0386676:1:3")
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/e3.mkv", "el elegido ya está abriendo")
        XCTAssertTrue(rig.saved().isEmpty, "sin esperar a que se guarde el anterior")
        XCTAssertTrue(rig.engine.calls.contains("pause"), "el que dejas se calla al tocar")
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.saved().map(\.videoID), ["tt0386676:1:1"], "y el anterior sí quedó guardado")
    }
}
