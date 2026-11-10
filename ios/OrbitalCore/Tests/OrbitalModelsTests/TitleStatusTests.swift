import XCTest
@testable import OrbitalModels

/// G1-A: el botón de estado de la ficha dice una sola respuesta.
final class TitleStatusTests: XCTestCase {
    func movie(inList: Bool = false, watched: Bool = false) -> TitleStatus {
        .decide(isSeries: false, inList: inList, watchedCount: watched ? 1 : 0, releasedCount: 1, upcoming: false, dropped: false)
    }
    func series(inList: Bool = false, watched: Int = 0, released: Int = 10, upcoming: Bool = false, dropped: Bool = false) -> TitleStatus {
        .decide(isSeries: true, inList: inList, watchedCount: watched, releasedCount: released, upcoming: upcoming, dropped: dropped)
    }

    func testPeliculaSinNadaGuardadaYVista() {
        XCTAssertEqual(movie(), .none)
        XCTAssertEqual(movie(inList: true), .inList)
        XCTAssertEqual(movie(watched: true), .watched)
        // Vista y otra vez en Mi lista: la guardaste para verla de nuevo.
        XCTAssertEqual(movie(inList: true, watched: true), .inList)
    }

    func testSerieEmpezadaAlDiaTerminadaYDejada() {
        XCTAssertEqual(series(), .none)
        XCTAssertEqual(series(inList: true), .inList)
        XCTAssertEqual(series(inList: true, watched: 3), .watching)
        XCTAssertEqual(series(watched: 10), .watched)
        XCTAssertEqual(series(watched: 10, upcoming: true), .watching, "al día, pero le faltan episodios por salir")
        XCTAssertEqual(series(watched: 3, dropped: true), .dropped)
        XCTAssertEqual(series(inList: true, dropped: true), .dropped)
    }
}
