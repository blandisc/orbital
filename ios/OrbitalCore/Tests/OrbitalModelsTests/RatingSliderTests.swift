import XCTest
@testable import OrbitalModels

/// El deslizador de Calificación: qué mínimo sale según el dedo, dónde se dibuja y cómo se mueve con VoiceOver.
final class RatingSliderTests: XCTestCase {
    func testTheFingerGivesTenthsAndTheStartIsNoMinimum() {
        let s = RatingSlider.tmdb
        XCTAssertNil(s.value(atFraction: 0), "del todo a la izquierda, sin mínimo")
        XCTAssertNil(s.value(atFraction: -0.3), "fuera de la regla, también")
        XCTAssertEqual(s.value(atFraction: 0.625), 7.5)
        XCTAssertEqual(s.value(atFraction: 0.63), 7.5, "de décima en décima")
        XCTAssertEqual(s.value(atFraction: 1.4), 9, "no pasa del tope")
        XCTAssertNil(RatingSlider.letterboxd.value(atFraction: 0.04), "un toquecito en la primera estrella no cuenta")
        XCTAssertEqual(RatingSlider.letterboxd.value(atFraction: 0.76), 3.8)
    }

    func testValuesAreDrawnInsideTheScale() {
        XCTAssertEqual(RatingSlider.tmdb.fraction(of: nil), 0)
        XCTAssertEqual(RatingSlider.tmdb.fraction(of: 6), 0.25)
        XCTAssertEqual(RatingSlider.tmdb.fraction(of: 3), 0, "un mínimo viejo abajo de 5 se dibuja al inicio")
        XCTAssertEqual(RatingSlider.letterboxd.fraction(of: 5), 1)
    }

    func testLevels() {
        let s = RatingSlider.letterboxd
        XCTAssertNil(s.level(nil)); XCTAssertNil(s.level(3.4))
        XCTAssertEqual(s.level(3.5), 0); XCTAssertEqual(s.level(3.9), 1); XCTAssertEqual(s.level(4.2), 2); XCTAssertEqual(s.level(5), 2)
    }

    func testVoiceOverStepsThroughTheLevelsThenByHalves() {
        let s = RatingSlider.tmdb
        XCTAssertEqual(s.step(nil, up: true), 7)
        XCTAssertEqual(s.step(7, up: true), 7.5)
        XCTAssertEqual(s.step(7.2, up: true), 7.5, "un valor fino sube al siguiente nivel")
        XCTAssertEqual(s.step(8, up: true), 8.5)
        XCTAssertEqual(s.step(9, up: true), 9, "en el tope se queda")
        XCTAssertEqual(s.step(7.5, up: false), 7)
        XCTAssertNil(s.step(7, up: false), "abajo de Buena, sin mínimo")
        XCTAssertNil(s.step(nil, up: false))
    }
}
