import XCTest
@testable import OrbitalCore

final class SettingsTests: XCTestCase {
    func testSettingsPersist() {
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(kv)
        XCTAssertEqual(store.value.uiLanguage, "es")
        store.update { $0.uiLanguage = "en"; $0.audio = "es"; $0.subtitles = "en" }
        let again = SettingsStore(kv)
        XCTAssertEqual(again.value.uiLanguage, "en"); XCTAssertEqual(again.value.subtitles, "en")
        XCTAssertEqual(again.value.audio, "es", "idioma de la app, de audio y de subtítulos son independientes")
    }

    func testCellularCapsQualityButNeverRaisesIt() {
        var settings = AppSettings()
        settings.quality = "4K"; settings.cellularQuality = "1080p"
        XCTAssertEqual(settings.preferences(onCellular: false).quality, "4K")
        XCTAssertEqual(settings.preferences(onCellular: true).quality, "1080p")
        settings.quality = "720p"
        XCTAssertEqual(settings.preferences(onCellular: true).quality, "720p")
    }

    func testEachTitleRemembersItsOwnLanguages() {
        let kv = InMemoryKeyValueStore()
        let prefs = TitlePreferences(kv)
        var settings = AppSettings(); settings.audio = "es"; settings.subtitles = "es"
        prefs.remember(metaID: "tt1", audioTrack: "eng", subtitleTrack: "")   // inglés con subtítulos apagados
        prefs.remember(metaID: "tt2", subtitleTrack: "spa")
        let a = TitlePreferences(kv).languages(for: "tt1", settings: settings)
        XCTAssertEqual(a.prefs.audio, "en"); XCTAssertEqual(a.subtitles, "")
        let b = prefs.languages(for: "tt2", settings: settings)
        XCTAssertEqual(b.prefs.audio, "es"); XCTAssertEqual(b.subtitles, "es")
        let other = prefs.languages(for: "tt3", settings: settings)
        XCTAssertEqual(other.prefs.audio, "es")
    }

    func testUnknownTrackLanguagesAreNotRemembered() {
        let prefs = TitlePreferences(InMemoryKeyValueStore())
        prefs.remember(metaID: "tt1", audioTrack: "fra")
        XCTAssertEqual(prefs.languages(for: "tt1", settings: AppSettings()).prefs.audio, "es")
    }
}
