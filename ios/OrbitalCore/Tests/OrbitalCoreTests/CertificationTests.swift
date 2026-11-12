import XCTest
@testable import OrbitalCore

/// Una sola escala de clasificación por idioma (Fernando, 12 nov 2026): en español latino, la mexicana; en cualquier otro, la
/// de EE. UU.; nunca el dato crudo de otro país. La tabla de `Certification` es la de `design/clasificaciones.json` (la que lee
/// la TV) y los `cases` del archivo son los mismos que corre la TV (`tests/test_certification.py`).
final class CertificationTests: XCTestCase {
    func table() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("design/clasificaciones.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testVersionIsTheOneTheIPhoneKnows() throws {
        XCTAssertEqual(try table()["version"] as? Int, 1, "una versión nueva de la tabla: revisar el iPhone")
    }

    func testTheIPhoneCopiesTheSharedTable() throws {
        let t = try table()
        XCTAssertEqual(Set(try XCTUnwrap(t["mexican_languages"] as? [String])), Certification.mexicanLanguages, "`mexican_languages`")
        let scales = try XCTUnwrap(t["scales"] as? [String: Any])
        XCTAssertEqual(scales["mexico"] as? [String], Certification.mexico, "`scales.mexico`")
        XCTAssertEqual(scales["us"] as? [String: [String]], Certification.us, "`scales.us`")
        XCTAssertEqual(t["to_mexico"] as? [String: [String: String]], Certification.toMexico, "`to_mexico`")
        XCTAssertEqual(t["to_us"] as? [String: [String: String]], Certification.toUS, "`to_us`")
    }

    func testTheSharedCases() throws {
        let cases = try XCTUnwrap(try table()["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let got = Certification.resolve(mx: c["mx"] as? String, us: c["us"] as? String, kind: c["kind"] as? String ?? "?",
                                            language: c["language"] as? String)
            XCTAssertEqual(got, c["expect"] as? String, c["why"] as? String ?? "?")
        }
    }
}
