import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «No puedo buscar subtítulos»: cerrar el panel a media búsqueda ya no la deja marcada como fallida para siempre, y elegir un
/// idioma mientras busca (o después de no encontrar nada) espera y vuelve a buscar en vez de no hacer nada.
@MainActor
final class SubtitleSearchTests: XCTestCase {
    let subtitlesURL = "https://a.example/subtitles/series/tt0386676%3A1%3A1.json"
    let eng = MediaTrack(id: 1, kind: .audio, language: "eng")

    func rig() async throws -> Rig {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("best", size: "💾 2 GB")]]
        rig.settings.update { $0.audio = "en"; $0.subtitles = "" }
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [], selectedAudio: 1))
        return rig
    }

    func testClosingThePanelMidSearchDoesNotBlockSearchingAgain() async throws {
        let rig = try await rig()
        rig.http.json[subtitlesURL] = ["subtitles": [["url": "https://s.example/fr.srt", "lang": "fre"]]]
        rig.http.delays[subtitlesURL] = 200
        let fromPanel = Task { await rig.model.ensureSubtitleSearch() }
        try await Task.sleep(nanoseconds: 20_000_000)
        fromPanel.cancel()   // cerraste el panel
        await fromPanel.value
        await rig.model.ensureSubtitleSearch()
        XCTAssertFalse(rig.model.subtitleSearchFailed, "cerrar el panel no es «no hay nada»")
        XCTAssertFalse(rig.model.subtitleVersions(language: "fr").isEmpty, "la búsqueda terminó y encontró el francés")
    }

    func testChoosingALanguageWhileSearchingWaitsForTheSearch() async throws {
        let rig = try await rig()
        rig.http.json[subtitlesURL] = ["subtitles": [["url": "https://s.example/fr.srt", "lang": "fre"]]]
        rig.http.delays[subtitlesURL] = 200
        let auto = Task { await rig.model.ensureSubtitleSearch() }   // la que arranca sola
        try await Task.sleep(nanoseconds: 20_000_000)
        let chose = await rig.model.chooseLanguage("fr")
        await auto.value
        XCTAssertTrue(chose, "antes salía al momento (ya había una búsqueda) y no ponía nada")
    }

    func testChoosingALanguageAfterAnEmptySearchSearchesAgain() async throws {
        let rig = try await rig()
        rig.http.json[subtitlesURL] = ["subtitles": []]
        await rig.model.ensureSubtitleSearch()
        XCTAssertTrue(rig.model.subtitleSearchFailed)
        rig.http.json[subtitlesURL] = ["subtitles": [["url": "https://s.example/fr.srt", "lang": "fre"]]]
        let chose = await rig.model.chooseLanguage("fr")
        XCTAssertTrue(chose, "lo pediste tú: se vuelve a buscar")
    }
}
