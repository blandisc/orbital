import Foundation
import XCTest
@testable import OrbitalCore

/// Los datos de ejemplo son los mismos que usan las pruebas de Python (`tests/fixtures`).
enum Fixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("tests/fixtures")
    }()

    static func json(_ path: String) throws -> JSON {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(JSON.parse(data), "JSON no válido: \(path)")
    }
}

let NOW = 1_760_000_000.0
