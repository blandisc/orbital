import XCTest
@testable import OrbitalAddons

/// A15 · el iPhone lee los errores de Real-Debrid con la misma tabla que la TV (`design/realdebrid-errors.json`): cada código,
/// cada HTTP y cada uno de sus `cases` dicen lo mismo aquí que en `orbital/library/realdebrid.py`.
final class RDErrorTableTests: XCTestCase {
    func table() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("design/realdebrid-errors.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryCodeAndHTTPMeansTheSameAsOnTheTV() throws {
        let table = try table()
        XCTAssertEqual(table["version"] as? Int, 1)
        let causes = try XCTUnwrap(table["causes"] as? [String: Any])
        XCTAssertEqual(Set(causes.keys), Set(RDErrorCause.allCases.map(\.rawValue)), "las mismas causas en las dos apps")
        let codes = try XCTUnwrap(table["codes"] as? [String: [String: Any]])
        var fromTable: [Int: String] = [:]
        for (key, entry) in codes { fromTable[try XCTUnwrap(Int(key), key)] = entry["cause"] as? String }
        XCTAssertEqual(fromTable, RDErrorCause.codes.mapValues(\.rawValue), "`codes` de design/realdebrid-errors.json")
        let http = try XCTUnwrap(table["http"] as? [String: Any])
        var httpTable: [Int: String] = [:]
        for (key, cause) in http { if let status = Int(key) { httpTable[status] = cause as? String } }
        XCTAssertEqual(httpTable, RDErrorCause.http.mapValues(\.rawValue), "`http` de design/realdebrid-errors.json")
    }

    func testEveryCaseOfTheTable() throws {
        let cases = try XCTUnwrap(try table()["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let status = c["http"] as? Int, code = c["code"] as? Int, expected = try XCTUnwrap(c["cause"] as? String)
            XCTAssertEqual(RDErrorCause.of(status: status, code: code).rawValue, expected, "http \(status.map(String.init) ?? "—") · code \(code.map(String.init) ?? "—")")
            // Lo mismo por donde entra de verdad: la respuesta de Real-Debrid.
            guard let status else { continue }
            let body = code.map { Data(#"{"error": "x", "error_code": \#($0)}"#.utf8) } ?? Data()
            XCTAssertEqual(RDRequestError.from(status: status, body: body), RDRequestError.from(try XCTUnwrap(RDErrorCause(rawValue: expected))))
        }
    }

    /// Lo que pidió el tablero (A15): el mismo error dice y hace lo mismo en la tele y en el iPhone.
    func testTheFourThatUsedToDisagree() {
        func error(_ status: Int, _ code: Int?) -> RDRequestError {
            RDRequestError.from(status: status, body: code.map { Data(#"{"error_code": \#($0)}"#.utf8) } ?? Data())
        }
        XCTAssertEqual(error(429, 34), .slowDown, "34: espera y reintenta")
        XCTAssertEqual(error(403, 36), .tooManyActive, "36: muchas descargas")
        XCTAssertEqual(error(403, 23), .tooManyActive, "23: muchas descargas")
        XCTAssertEqual(error(403, 9), .notPremium, "9: sin Premium")
        XCTAssertEqual(error(403, nil), .notPremium, "403: sin Premium")
        for code in [16, 24, 26, 27, 28, 29, 30, 35] { XCTAssertEqual(error(400, code), .refused, "\(code): rechazado") }
    }
}
