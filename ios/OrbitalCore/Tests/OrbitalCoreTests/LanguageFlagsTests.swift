import XCTest
@testable import OrbitalCore

/// Las mismas banderas que la TV y la computadora (`orbital/flags.py`).
final class LanguageFlagsTests: XCTestCase {
    func testSpanishEnglishAndPortugueseFollowTheDesktopRules() {
        XCTAssertEqual(LanguageFlags.flag("es-419"), "🇲🇽")
        XCTAssertEqual(LanguageFlags.flag("es"), "🇲🇽", "el español que no dice cuál: México")
        XCTAssertEqual(LanguageFlags.flag("es-ES"), "🇪🇸")
        XCTAssertEqual(LanguageFlags.flag("en"), "🇺🇸")
        XCTAssertEqual(LanguageFlags.flag("en-GB"), "🇬🇧")
        XCTAssertEqual(LanguageFlags.flag("pt"), "🇧🇷")
        XCTAssertEqual(LanguageFlags.flag("pt-PT"), "🇵🇹")
        XCTAssertEqual(LanguageFlags.flag("spa"), "🇲🇽", "las pistas dicen «spa»")
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
}

