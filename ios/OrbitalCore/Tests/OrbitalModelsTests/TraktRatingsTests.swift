import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Revisión del 11 nov: 79 % en el destacado de Inicio y 84 % en la ficha de la misma película. Una sola calificación por
/// título en la sesión (la primera que se conoce) y un solo redondeo.
@MainActor
final class TraktRatingsTests: XCTestCase {
    func testTheFirstKnownRatingWinsEverywhere() {
        XCTAssertEqual(TraktRatings.shown("tt7000001", fallback: 7.9), 7.9, "la de la lista de Inicio")
        XCTAssertEqual(TraktRatings.shown("tt7000001", fallback: 8.4), 7.9, "la ficha (u otra lista) enseña la misma")
        XCTAssertNil(TraktRatings.shown("tt7000002", fallback: 0), "cero no es una calificación")
        XCTAssertEqual(TraktRatings.percent(7.94), 79)
        XCTAssertEqual(TraktRatings.percent(8.45), 85)
    }

    func testTheTitlePageUsesTheRatingAlreadyShown() async throws {
        let rig = try ServicesRig()
        TraktRatings.note("tt7000003", 7.9)
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt7000003")
        await title.loadExtras()
        XCTAssertEqual(title.traktRating, 7.9)
    }
}
