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

    /// El botón de zoom recorre los cuatro modos y vuelve al primero; pellizcar va entre Ajustar y Recortar; se recuerda.
    func testVideoZoomCyclesPinchesAndPersists() {
        XCTAssertEqual(VideoZoom.fit.next, .fitSafeArea)
        XCTAssertEqual(VideoZoom.fitSafeArea.next, .fill)
        XCTAssertEqual(VideoZoom.fill.next, .stretch)
        XCTAssertEqual(VideoZoom.stretch.next, .fit)
        XCTAssertEqual(VideoZoom.pinched(magnification: 1.4), .fill)
        XCTAssertEqual(VideoZoom.pinched(magnification: 0.7), .fit)
        XCTAssertEqual(VideoZoom(stored: "???"), .fit)
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(kv)
        XCTAssertEqual(VideoZoom(stored: store.value.videoZoom), .fit)
        store.update { $0.videoZoom = VideoZoom.stretch.rawValue }
        XCTAssertEqual(VideoZoom(stored: SettingsStore(kv).value.videoZoom), .stretch)
    }

    /// «Un Simpson al azar»: por omisión las clásicas (5–15); lo elegido se guarda, y un ajuste guardado antes de existir no se pierde.
    func testSimpsonsSeasonsDefaultPersistAndOldData() throws {
        XCTAssertEqual(AppSettings().simpsonsSeasons, Array(5...15))
        let kv = InMemoryKeyValueStore()
        SettingsStore(kv).update { $0.simpsonsSeasons = [1, 2, 30] }
        XCTAssertEqual(SettingsStore(kv).value.simpsonsSeasons, [1, 2, 30])
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"audio":"en"}"#.utf8))
        XCTAssertEqual(old.audio, "en")
        XCTAssertEqual(old.simpsonsSeasons, Array(5...15))
    }
}
