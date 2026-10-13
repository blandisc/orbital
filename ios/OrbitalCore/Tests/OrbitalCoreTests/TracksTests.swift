import XCTest
@testable import OrbitalCore

final class TracksTests: XCTestCase {
    let tracks: [MediaTrack] = [
        .init(id: 1, kind: .audio, language: "eng", codec: "EAC3", channels: "5.1", isDefault: true),
        .init(id: 2, kind: .audio, language: "spa", codec: "AC3", channels: "5.1"),
        .init(id: 3, kind: .audio, language: "es-419", codec: "AAC", channels: "2.0"),
        .init(id: 10, kind: .subtitle, language: "eng"),
        .init(id: 11, kind: .subtitle, language: "spa", isForced: true),
        .init(id: 12, kind: .subtitle, language: "spa"),
        .init(id: 13, kind: .subtitle, language: "es-419", title: "Latino"),
    ]

    func testAudioPrefersYourLanguageThenDefault() {
        XCTAssertEqual(TrackChooser.audio(tracks, language: "es")?.id, 2)
        XCTAssertEqual(TrackChooser.audio(tracks, language: "en")?.id, 1)
        XCTAssertEqual(TrackChooser.audio(tracks, language: "fr")?.id, 1, "sin tu idioma: el marcado por defecto")
        XCTAssertNil(TrackChooser.audio([], language: "es"))
    }

    func testSubtitleModes() {
        XCTAssertNil(TrackChooser.subtitle(tracks, mode: .off, audioLanguage: "es"))
        XCTAssertEqual(TrackChooser.subtitle(tracks, mode: .language("es"), audioLanguage: "en")?.id, 12, "completos antes que forzados")
        XCTAssertEqual(TrackChooser.subtitle(tracks, mode: .forced, audioLanguage: "es")?.id, 11)
        XCTAssertNil(TrackChooser.subtitle(tracks, mode: .forced, audioLanguage: "en"), "sin forzados en ese idioma: ninguno")
        XCTAssertEqual(TrackChooser.subtitle(tracks, mode: .language("fr"), audioLanguage: "es")?.id, 11, "sin tu idioma: el forzado")
        let onlyEnglish = tracks.filter { $0.id == 10 }
        XCTAssertNil(TrackChooser.subtitle(onlyEnglish, mode: .language("es"), audioLanguage: "en"))
    }

    func testSubtitleModeFromSettings() {
        XCTAssertEqual(SubtitleMode(settings: "es", onlyForced: false), .language("es"))
        XCTAssertEqual(SubtitleMode(settings: "es", onlyForced: true), .forced)
        XCTAssertEqual(SubtitleMode(settings: "", onlyForced: false), .off)
    }

    func testWrongAudioOnlyWhenTracksAreTaggedAndNoneIsYours() {
        XCTAssertFalse(TrackChooser.wrongAudio(tracks, language: "es"))
        XCTAssertTrue(TrackChooser.wrongAudio(tracks.filter { $0.id == 1 }, language: "es"))
        XCTAssertFalse(TrackChooser.wrongAudio([.init(id: 1, kind: .audio, language: "und")], language: "es"), "sin etiquetas no se sabe: no avisa")
    }

    func testLabels() {
        XCTAssertEqual(TrackChooser.label(tracks[1]), "Español · AC3 5.1")
        XCTAssertEqual(TrackChooser.label(tracks[2]), "Español latino · AAC 2.0")
        XCTAssertEqual(TrackChooser.label(tracks[4]), "Español · forzados")
        XCTAssertEqual(TrackChooser.label(tracks[0], locale: Locale(identifier: "en")), "English · EAC3 5.1")
    }
}
