import XCTest
@testable import OrbitalCore

/// Revisión 2 del 11 nov: «Бархан» entre los resultados de «dune».
final class OtherScriptTests: XCTestCase {
    func testOtherAlphabetsGoAfterWhatYouCanRead() {
        XCTAssertTrue(OtherScript.isOther("Бархан"))
        XCTAssertTrue(OtherScript.isOther("君の名は。"))
        XCTAssertFalse(OtherScript.isOther("Duna: Parte dos"))
        XCTAssertFalse(OtherScript.isOther("Amélie"))
        XCTAssertFalse(OtherScript.isOther("2001"))
        XCTAssertEqual(OtherScript.readableFirst(["Бархан", "Dune", "Duna", "Дюна 2"]) { $0 }, ["Dune", "Duna", "Бархан", "Дюна 2"])
    }
}
