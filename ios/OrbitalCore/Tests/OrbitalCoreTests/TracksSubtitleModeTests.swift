import XCTest
@testable import OrbitalCore

/// Regla (26 nov 2026): con el audio en tu idioma, o en el de los subtítulos que pediste, solo los forzados. Igual en la TV
/// (`tests/test_player.py::test_audio_in_your_language_starts_without_subtitles`).
final class TracksSubtitleModeTests: XCTestCase {
    func testAudioInYourLanguageNeedsOnlyForced() {
        XCTAssertEqual(TrackChooser.modeFor(.language("en"), audioLanguage: "es", home: "es"), .forced, "Mario en español, subtítulos en inglés")
        XCTAssertEqual(TrackChooser.modeFor(.language("es"), audioLanguage: "spa", home: "es"), .forced, "español con subtítulos en español")
        XCTAssertEqual(TrackChooser.modeFor(.language("es"), audioLanguage: "en", home: "es"), .language("es"), "inglés: sí")
        XCTAssertEqual(TrackChooser.modeFor(.language("en"), audioLanguage: "en", home: "es"), .forced, "lo pedido es lo que suena")
        XCTAssertEqual(TrackChooser.modeFor(.off, audioLanguage: "ja", home: "es"), .off)
    }
}
