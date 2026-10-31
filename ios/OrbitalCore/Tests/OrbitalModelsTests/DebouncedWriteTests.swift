import XCTest
@testable import OrbitalModels

/// C8: lo que escribes se guarda una vez cuando dejas de teclear (y al cerrar, lo que faltaba), no en cada tecla.
@MainActor
final class DebouncedWriteTests: XCTestCase {
    func testTypingSavesOnceWithTheLastText() async throws {
        var saved: [String] = []
        let writer = DebouncedWrite<String>(delay: .milliseconds(50))
        for text in ["h", "ho", "hol", "hola"] { writer.schedule(text) { saved.append($0) } }
        XCTAssertEqual(saved, [], "nada mientras tecleas")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(saved, ["hola"])
    }

    func testClosingSavesWhatWasMissing() {
        var saved: [String] = []
        let writer = DebouncedWrite<String>(delay: .seconds(60))
        writer.schedule("nota a medias") { saved.append($0) }
        writer.flush()
        XCTAssertEqual(saved, ["nota a medias"])
        writer.flush()
        XCTAssertEqual(saved, ["nota a medias"], "no se guarda dos veces")
    }
}
