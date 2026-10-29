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
        /// El texto plano o, si varía por aparato (iPhone, iPad, Mac), cada una de sus variaciones.
        func values(_ localization: JSON?) -> [String: String] {
            if let plain = localization?["stringUnit"]?["value"]?.string { return ["": plain] }
            let devices = localization?["variations"]?["device"]?.object ?? [:]
            return devices.compactMapValues { $0["stringUnit"]?["value"]?.string }
        }
        for (key, entry) in strings {
            let english = values(entry["localizations"]?["en"])
            XCTAssertFalse(english.isEmpty, "falta la traducción de «\(key)»")
            for (device, text) in english {
                XCTAssertFalse(text.isEmpty, "«\(key)» está vacía en inglés \(device)")
                XCTAssertEqual(placeholders(text).sorted(), placeholders(key).sorted(), "los marcadores de «\(key)» (\(device)) no coinciden con su traducción")
            }
            // Las variaciones por aparato (`scripts/ios_strings.py`): en el iPhone se lee el texto de siempre.
            let spanish = values(entry["localizations"]?["es"])
            if !spanish.isEmpty {
                XCTAssertEqual(spanish["iphone"], key, "«\(key)»: en el iPhone debe leerse igual")
                XCTAssertEqual(Set(spanish.keys), Set(english.keys), "«\(key)»: los mismos aparatos en español e inglés")
                for (device, text) in spanish { XCTAssertEqual(placeholders(text).sorted(), placeholders(key).sorted(), "«\(key)» (\(device))") }
            }
        }
    }
}
