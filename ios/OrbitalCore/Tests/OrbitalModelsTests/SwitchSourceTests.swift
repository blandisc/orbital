import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Cambiar de versión a mano: el aviso de Real-Debrid no se toma por la película, si la nueva no llega a sonar se vuelve a la
/// tuya en el mismo segundo, el español elegido sigue en el título y la sincronía pregunta.
@MainActor
final class SwitchSourceTests: XCTestCase {
    let eng = MediaTrack(id: 1, kind: .audio, language: "eng")
    let subEn = MediaTrack(id: 10, kind: .subtitle, language: "eng")

    func rig() async throws -> (Rig, english: Source, latino: Source) {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.WEB-DL\n💾 2 GB", "url": "https://rd.example/english.mkv"]),
            .object(["name": "T\n1080p [RD download]", "title": "Show.S01E01.1080p.LATINO\n💾 2 GB", "url": "https://rd.example/latino.mkv"]),
        ]]
        rig.settings.update { $0.audio = "en"; $0.subtitles = "en" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(300, audio: [eng], subs: [subEn], selectedAudio: 1, selectedSubtitle: 10))
        let english = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("WEB-DL") })
        let latino = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("LATINO") })
        XCTAssertEqual(rig.model.source?.index, english.index, "precondición: suena la inglesa")
        return (rig, english, latino)
    }

    func testTheRealDebridNoticeVideoIsNotTheMovieAndGoesBack() async throws {
        let (rig, english, latino) = try await rig()
        await rig.model.switchSource(to: latino.index, language: "es-419")
        // Real-Debrid aún no la tiene: manda su video de 30 s de «descargando».
        await rig.model.handle(rig.playing(0, duration: 30))
        XCTAssertEqual(rig.model.notice, .notReadyOnRealDebrid)
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/english.mkv", "vuelve a la tuya")
        XCTAssertEqual(rig.engine.loads.last?.start ?? 0, 300, accuracy: 1, "en el mismo segundo")
        XCTAssertEqual(rig.model.source?.index, english.index)
        XCTAssertNotEqual(rig.model.phase, .closed, "nunca se toma como terminado (ni pasa al siguiente)")
    }

    func testIfTheNewOneFailsAfterOpeningYouGoBackToYours() async throws {
        let (rig, english, latino) = try await rig()
        await rig.model.switchSource(to: latino.index)
        await rig.model.handle(rig.playing(0, state: .failed("se cortó")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.source?.index, english.index, "a la tuya, no a cualquiera")
        XCTAssertEqual(rig.model.notice, .switchFailedBack)
    }

    func testTheChosenSpanishFollowsTheTitleAndSyncAsks() async throws {
        let (rig, _, latino) = try await rig()
        await rig.model.switchSource(to: latino.index, language: "es-419")
        XCTAssertTrue(rig.model.askInSync, "otro archivo con subtítulos: «¿Va a tiempo?»")
        let langs = rig.titlePrefs.languages(for: "tt0386676", settings: rig.settings.value)
        XCTAssertEqual(langs.prefs.audio, "es")
        XCTAssertEqual(langs.prefs.spanish, "es-419", "los siguientes episodios, en latino (aunque en Ajustes no tengas la variante)")
    }
}
