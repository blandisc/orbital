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

    /// Dos modos: el botón cambia al otro; pellizcar va entre los dos; los modos viejos caen en el más parecido; se recuerda.
    func testVideoZoomTwoModesPinchesAndPersists() {
        XCTAssertEqual(VideoZoom.allCases, [.fit, .fill])
        XCTAssertEqual(VideoZoom.fit.next, .fill)
        XCTAssertEqual(VideoZoom.fill.next, .fit)
        XCTAssertEqual(VideoZoom.pinched(magnification: 1.4), .fill)
        XCTAssertEqual(VideoZoom.pinched(magnification: 0.7), .fit)
        XCTAssertNil(VideoZoom.pinched(magnification: 1.05), "dos dedos que apenas se mueven no son un pellizco")
        XCTAssertNil(VideoZoom.pinched(magnification: 0.9))
        XCTAssertEqual(VideoZoom(stored: "???"), .fit)
        XCTAssertEqual(VideoZoom(stored: "fitSafeArea"), .fit, "«Ajuste de aspecto» era la imagen completa")
        XCTAssertEqual(VideoZoom(stored: "stretch"), .fill, "«Estirar» llenaba la pantalla")
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(kv)
        XCTAssertEqual(VideoZoom(stored: store.value.videoZoom), .fit)
        store.update { $0.videoZoom = VideoZoom.fill.rawValue }
        XCTAssertEqual(VideoZoom(stored: SettingsStore(kv).value.videoZoom), .fill)
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

    /// El país sale de la zona horaria antes que del idioma: una Mac en inglés de EE. UU. en Monterrey es México.
    func testRegionFollowsTimeZone() {
        XCTAssertEqual(AppSettings.zoneRegion("America/Monterrey"), "MX")
        XCTAssertEqual(AppSettings.zoneRegion("America/Mexico_City"), "MX")
        XCTAssertEqual(AppSettings.zoneRegion("America/Argentina/Buenos_Aires"), "AR")
        XCTAssertEqual(AppSettings.zoneRegion("Europe/Madrid"), "ES")
        XCTAssertNil(AppSettings.zoneRegion("America/New_York"))
        XCTAssertNil(AppSettings.zoneRegion("Asia/Tokyo"))
    }

    /// Un país elegido en Ajustes se queda; uno sin elegir sigue a donde estás.
    func testChosenRegionStays() throws {
        let chosen = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"region":"JP","regionChosen":true}"#.utf8))
        XCTAssertEqual(chosen.region, "JP")
        let followed = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"region":"JP","regionChosen":false}"#.utf8))
        XCTAssertEqual(followed.region, AppSettings.phoneRegion)
    }
}

/// ID-A: el idioma de los títulos y sinopsis es aparte del de la app; si nunca lo elegiste, es el mismo (nada cambia al
/// actualizar).
final class TitleLanguageTests: XCTestCase {
    func testTitleLanguageFollowsTheAppUntilChosen() throws {
        var s = AppSettings()
        s.uiLanguage = "en"
        XCTAssertEqual(s.titleLanguage, "en")
        s.metadataLanguage = "es"
        XCTAssertEqual(s.titleLanguage, "es")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"uiLanguage":"en"}"#.utf8))
        XCTAssertNil(old.metadataLanguage); XCTAssertEqual(old.titleLanguage, "en")
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again.metadataLanguage, "es")
    }
}
