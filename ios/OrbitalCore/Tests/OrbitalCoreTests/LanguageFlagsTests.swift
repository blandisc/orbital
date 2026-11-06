import XCTest
@testable import OrbitalCore

/// Las mismas banderas que la TV y la computadora (`orbital/flags.py`).
final class LanguageFlagsTests: XCTestCase {
    func testSpanishEnglishAndPortugueseFollowTheDesktopRules() {
        XCTAssertEqual(LanguageFlags.flag("es-419"), "🇲🇽")
        XCTAssertEqual(LanguageFlags.flag("es"), LanguageFlags.mixedSpanish, "el español que no dice cuál: mitad y mitad")
        XCTAssertEqual(LanguageFlags.flag("es-ES"), "🇪🇸")
        XCTAssertEqual(LanguageFlags.flag("en"), "🇺🇸")
        XCTAssertEqual(LanguageFlags.flag("en-GB"), "🇬🇧")
        XCTAssertEqual(LanguageFlags.flag("pt"), "🇧🇷")
        XCTAssertEqual(LanguageFlags.flag("pt-PT"), "🇵🇹")
        XCTAssertEqual(LanguageFlags.flag("spa"), LanguageFlags.mixedSpanish, "las pistas dicen «spa»: no dicen cuál")
        XCTAssertEqual(LanguageFlags.flag("jpn"), "🇯🇵")
        XCTAssertNil(LanguageFlags.flag("ar"), "sin un país claro, sin bandera")
        XCTAssertNil(LanguageFlags.flag(nil))
    }

    func testTwoAudiosCarryBothFlagsAndVoiceOverReadsOnlyTheName() {
        let both = LanguageFlags.flagged("Inglés + latino", ["en", "es-419"])
        XCTAssertEqual(both, "🇺🇸🇲🇽 Inglés + latino")
        XCTAssertEqual(LanguageFlags.flagged("Árabe", "ar"), "Árabe")
        XCTAssertEqual(LanguageFlags.withoutFlags(both), "Inglés + latino")
    }

    func testTheVersionLineKeepsOnlyTheFlagAndFallsBackToTheName() {
        XCTAssertEqual(LanguageFlags.flagOnly("Latino", "es-419"), "🇲🇽")
        XCTAssertEqual(LanguageFlags.flagOnly("Castellano", "es-ES"), "🇪🇸")
        XCTAssertEqual(LanguageFlags.flagOnly("Árabe", "ar"), "Árabe", "sin bandera, el nombre: algo tiene que decir el idioma")
    }
}
