import XCTest
@testable import OrbitalCore

/// Una fila de tarjetas no repite los pósters de la de al lado (revisión de la Mac, 22 nov 2026: Acción, Aventura y
/// Animación enseñaban los mismos tres). Regla en `docs/ios-interfaz.md`.
final class CoverSpreadTests: XCTestCase {
    func testLaterCardsSkipPostersAlreadyShown() {
        let rows = [["a", "b", "c", "d"], ["a", "b", "c", "e", "f", "g"], ["a", "e", "h", "i"]]
        let picked = CoverSpread.pick(rows, count: 3, id: { $0 })
        XCTAssertEqual(picked, [["a", "b", "c"], ["e", "f", "g"], ["h", "i", "a"]])
        XCTAssertEqual(Set(picked[0]).intersection(picked[1]), [], "dos tarjetas seguidas con los mismos pósters")
    }

    func testShortRowsKeepTheirOwnPosters() {
        XCTAssertEqual(CoverSpread.pick([["a", "b"], ["a", "b"]], count: 3, id: { $0 }), [["a", "b"], ["a", "b"]])
        XCTAssertEqual(CoverSpread.pick([[String]](), count: 3, id: { $0 }), [])
    }

    /// Las filas de tarjetas de Explorar (Estudios, Temporadas, Géneros) piden sus portadas a `CoverSpread`.
    func testExploreCardRowsUseCoverSpread() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("App/Sources/Screens/ListsView.swift")
        let code = try String(contentsOf: file, encoding: .utf8)
        for map in ["studioItems[", "seasonItems[", "genreCharts["] {
            XCTAssertFalse(code.contains("\(map)") && code.contains(".prefix(3).map { Optional($0.poster) }"),
                           "una fila de tarjetas toma sus pósters sin CoverSpread (\(map))")
        }
        XCTAssertGreaterThanOrEqual(code.components(separatedBy: "Self.spread(").count - 1, 3)
    }
}
