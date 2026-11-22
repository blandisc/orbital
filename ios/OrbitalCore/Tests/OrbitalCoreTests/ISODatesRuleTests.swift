import XCTest
import OrbitalAddons

/// Regla (21 nov 2026, cierre de la 2436): las fechas ISO se leen con `ISODates`, nunca con un `ISO8601DateFormatter()` nuevo
/// por llamada. Crear uno arranca ICU y gasta mucha pila; la ficha armaba dos en cada dibujo y, al girar a horizontal, la app
/// se cerró. Solo `ISODates.swift` los crea; las pruebas y la demostración pueden.
final class ISODatesRuleTests: XCTestCase {
    var ios: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    func testNobodyBuildsAnISOFormatterPerCall() throws {
        var found: [String] = []
        for folder in ["App/Sources", "App/Widgets", "OrbitalCore/Sources"] {
            let base = ios.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)).allObjects
            for case let file as URL in files where file.pathExtension == "swift" {
                let name = file.lastPathComponent
                if name == "ISODates.swift" || name.hasPrefix("Demo") { continue }
                for (i, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated()
                where line.contains("ISO8601DateFormatter()") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    found.append("\(name):\(i + 1)")
                }
            }
        }
        XCTAssertEqual(found, [], "usa ISODates.parse / ISODates.string en lugar de un ISO8601DateFormatter() nuevo")
    }

    func testReadsWithAndWithoutMilliseconds() {
        XCTAssertEqual(ISODates.parse("2026-10-23T02:00:00.000Z"), ISODates.parse("2026-10-23T02:00:00Z"))
        XCTAssertNotNil(ISODates.parse("2026-10-23T02:00:00Z"))
        XCTAssertNil(ISODates.parse("mañana"))
        XCTAssertNotNil(ISODates.day.date(from: "2026-10-23"))
    }
}
