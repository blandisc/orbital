import XCTest
@testable import OrbitalCore

/// El catálogo de textos (español base, inglés) está completo y sus marcadores coinciden. Para que ningún texto de la
/// pantalla se quede sin traducir hay además `python scripts/ios_strings.py --check`.
final class LocalizationTests: XCTestCase {
    func testEveryStringHasAnEnglishTranslationWithTheSamePlaceholders() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let catalog = try XCTUnwrap(JSON.parse(try Data(contentsOf: url.appendingPathComponent("ios/App/Resources/Localizable.xcstrings"))))
        XCTAssertEqual(catalog["sourceLanguage"]?.string, "es")
        let strings = try XCTUnwrap(catalog["strings"]?.object)
        XCTAssertGreaterThan(strings.count, 100)
        func placeholders(_ s: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: "%(lld|@)")
            return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
        }
        for (key, entry) in strings {
            let english = entry["localizations"]?["en"]?["stringUnit"]?["value"]?.string
            XCTAssertNotNil(english, "falta la traducción de «\(key)»")
            XCTAssertFalse(english?.isEmpty ?? true, "«\(key)» está vacía en inglés")
            XCTAssertEqual(placeholders(english ?? "").sorted(), placeholders(key).sorted(), "los marcadores de «\(key)» no coinciden con su traducción")
        }
    }
}
