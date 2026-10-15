import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La aritmética de los gestos del reproductor (CEN-16): brillo, volumen, buscar arrastrando y 2×. Sin UIKit:
/// solo números, con los mismos tipos que usa `PlayerScreen` al traducir el arrastre de la pantalla.
final class PlayerGesturesTests: XCTestCase {

    // MARK: eje dominante

    func testBelowThresholdHasNoAxisYet() {
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: 3, dy: 3), .undecided)
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: 0, dy: 0), .undecided)
    }

    func testAtTheThresholdTheBiggerDeltaWins() {
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: 20, dy: 2), .horizontal)
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: 2, dy: 20), .vertical)
        // Empate: gana horizontal (buscar), como pide la especificación («cualquier zona»).
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: 15, dy: 15), .horizontal)
    }

    func testAxisThresholdMatchesTheToken() {
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: DesignTokens.Gesture.axisThreshold - 1, dy: 0), .undecided)
        XCTAssertEqual(PlayerGestures.dominantAxis(dx: DesignTokens.Gesture.axisThreshold, dy: 0), .horizontal)
    }

    // MARK: qué mitad

    func testLeftHalfIsBrightnessRightHalfIsVolume() {
        XCTAssertEqual(PlayerGestures.verticalGesture(startX: 0, screenWidth: 400), .brightness)
        XCTAssertEqual(PlayerGestures.verticalGesture(startX: 199, screenWidth: 400), .brightness)
        XCTAssertEqual(PlayerGestures.verticalGesture(startX: 200, screenWidth: 400), .volume)
        XCTAssertEqual(PlayerGestures.verticalGesture(startX: 399, screenWidth: 400), .volume)
    }

    // MARK: brillo y volumen

    func testDraggingUpIncreasesValue() {
        // Toda la altura hacia arriba: del mínimo al máximo.
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0, dragHeight: -800, screenHeight: 800), 1, accuracy: 1e-9)
        // La mitad de la altura: medio camino.
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0, dragHeight: -400, screenHeight: 800), 0.5, accuracy: 1e-9)
    }

    func testDraggingDownDecreasesValue() {
        XCTAssertEqual(PlayerGestures.verticalValue(start: 1, dragHeight: 800, screenHeight: 800), 0, accuracy: 1e-9)
    }

    func testVerticalValueClampsAt0And1() {
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0.9, dragHeight: -1000, screenHeight: 800), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0.1, dragHeight: 1000, screenHeight: 800), 0, accuracy: 1e-9)
    }

    func testVerticalValueStartsFromWhereYouGrabbedItNotFromTheCenter() {
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0.3, dragHeight: 0, screenHeight: 800), 0.3, accuracy: 1e-9)
    }

    func testZeroHeightKeepsTheStartingValue() {
        XCTAssertEqual(PlayerGestures.verticalValue(start: 0.4, dragHeight: -200, screenHeight: 0), 0.4)
    }

    // MARK: buscar arrastrando

    func testSeekLimitIsTenPercentOfDurationWhenThatIsSmaller() {
        // 600 s de duración: 10 % son 60 s, menos que el tope de 180 s.
        XCTAssertEqual(PlayerGestures.seekLimitSeconds(duration: 600), 60, accuracy: 1e-9)
    }

    func testSeekLimitCapsAt180SecondsOnLongVideos() {
        // Una película de 3 h: 10 % serían 1080 s, pero el tope manda.
        XCTAssertEqual(PlayerGestures.seekLimitSeconds(duration: 3 * 3600), DesignTokens.Gesture.seekMaxSeconds, accuracy: 1e-9)
    }

    func testSeekLimitFallsBackToTheCapWithoutKnownDuration() {
        XCTAssertEqual(PlayerGestures.seekLimitSeconds(duration: 0), DesignTokens.Gesture.seekMaxSeconds, accuracy: 1e-9)
    }

    func testDraggingFullWidthRightAddsTheWholeLimit() {
        // Video de 600 s (tope 60 s), ancho de pantalla 400 pt, arrastre de 400 pt a la derecha.
        let target = PlayerGestures.seekTarget(startPosition: 100, duration: 600, dragWidth: 400, screenWidth: 400)
        XCTAssertEqual(target, 160, accuracy: 1e-9)
    }

    func testDraggingHalfWidthLeftSubtractsHalfTheLimit() {
        let target = PlayerGestures.seekTarget(startPosition: 100, duration: 600, dragWidth: -200, screenWidth: 400)
        XCTAssertEqual(target, 70, accuracy: 1e-9)
    }

    func testSeekTargetNeverGoesBelowZero() {
        let target = PlayerGestures.seekTarget(startPosition: 5, duration: 600, dragWidth: -400, screenWidth: 400)
        XCTAssertEqual(target, 0, accuracy: 1e-9)
    }

    func testSeekTargetNeverPassesTheEnd() {
        let target = PlayerGestures.seekTarget(startPosition: 590, duration: 600, dragWidth: 400, screenWidth: 400)
        XCTAssertEqual(target, 600, accuracy: 1e-9)
    }

    func testSeekTargetWithoutKnownDurationStillClampsAtZero() {
        let target = PlayerGestures.seekTarget(startPosition: 10, duration: 0, dragWidth: -400, screenWidth: 400)
        XCTAssertEqual(target, 0, accuracy: 1e-9)
    }

    func testZeroWidthKeepsTheStartingPosition() {
        XCTAssertEqual(PlayerGestures.seekTarget(startPosition: 42, duration: 600, dragWidth: 100, screenWidth: 0), 42)
    }
}
