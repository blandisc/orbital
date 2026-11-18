import XCTest
import CoreGraphics
@testable import OrbitalModels

/// La receta de la ficha ancha (`WideStage`).
final class WideStageTests: XCTestCase {
    private func stage(_ w: CGFloat, _ h: CGFloat) -> WideStage {
        WideStage(window: CGSize(width: w, height: h), heroHeight: h * 0.82, stageAspect: 2.4, portraitBelow: 1.15, marginShare: 0.05, minMargin: 40)
    }

    func testUltrawideCentersTheStage() {
        let s = stage(2560, 700)   // ultrawide: escenario al centro, lados con arte difuminado
        XCTAssertTrue(s.hasSides)
        XCTAssertEqual(s.x * 2 + s.width, 2560, accuracy: 1)
        XCTAssertGreaterThan(s.leading, 2560 * 0.15, "la columna ya no va clavada a la orilla")
        XCTAssertFalse(s.portrait)
    }

    func testLandscapeFillsTheWindow() {
        let s = stage(1440, 900)   // Mac o iPad horizontal: el escenario es la ventana
        XCTAssertFalse(s.hasSides)
        XCTAssertEqual(s.leading, 72)   // 5 % del ancho
    }

    func testPortraitCentersTheColumn() {
        let s = stage(1032, 1376)   // iPad 13 parado
        XCTAssertTrue(s.portrait)
        XCTAssertFalse(s.hasSides)
        XCTAssertGreaterThanOrEqual(s.margin, 40)
    }
}
