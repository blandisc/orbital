import XCTest

/// Las lecciones de Aprende (AF1-B…AF4-B, 19 nov 2026): se avanza a tu ritmo con «Siguiente» y la última pantalla,
/// «Pruébalo», se toca de verdad y dice «¡Eso es!» al lograrlo.
final class LessonsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() { app.terminate() }

    private func open(_ route: String) {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-free-tabs", "-demo-lesson", route]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testTheCloudLessonGoesAtYourPaceAndEndsInPractice() {
        open("nube")
        XCTAssertTrue(element("lesson-nube").waitForExistence(timeout: 20))
        XCTAssertFalse(element("lesson-back").isHittable, "en la primera pantalla no hay «Atrás»")
        for _ in 0..<5 {
            XCTAssertTrue(app.buttons["lesson-next"].waitForExistence(timeout: 5))
            app.buttons["lesson-next"].tap()
        }
        XCTAssertTrue(element("lesson-try-ask").waitForExistence(timeout: 5), "la última es «Pruébalo»")
        element("lesson-try-ask").tap()
        XCTAssertTrue(element("lesson-tried").waitForExistence(timeout: 8), "al pedirla de práctica, «¡Eso es!»")
    }

    func testTodayPracticeDecidesForYou() {
        open("hoy:4")
        XCTAssertTrue(element("lesson-try-decide").waitForExistence(timeout: 20))
        element("lesson-try-decide").tap()
        XCTAssertTrue(element("lesson-try-pick-1").waitForExistence(timeout: 5))
        element("lesson-try-pick-1").tap()
        XCTAssertTrue(element("lesson-tried").waitForExistence(timeout: 5))
        app.buttons["lesson-done"].tap()
        XCTAssertTrue(element("lesson-hoy").waitForNonExistence(timeout: 5), "«Listo» cierra la lección")
    }

    func testYoursPracticeMarksAndFollows() {
        open("tuyo:4")
        XCTAssertTrue(element("lesson-try-episode-3").waitForExistence(timeout: 20))
        element("lesson-try-episode-3").tap()
        XCTAssertFalse(element("lesson-tried").exists, "falta seguir la serie")
        element("lesson-try-follow").switches.firstMatch.tap()
        XCTAssertTrue(element("lesson-tried").waitForExistence(timeout: 5))
    }

    func testTVPracticeSendsAndAnyArrowCounts() {
        open("tv:4")
        XCTAssertTrue(element("lesson-try-send").waitForExistence(timeout: 20))
        element("lesson-try-send").tap()
        element("lesson-try-left").tap()
        XCTAssertTrue(element("lesson-tried").waitForExistence(timeout: 5), "«Izquierda» también cuenta")
    }

    func testCloseLeavesTheLesson() {
        open("idioma:2")
        XCTAssertTrue(element("lesson-idioma").waitForExistence(timeout: 20))
        app.buttons["lesson-close"].tap()
        XCTAssertTrue(element("lesson-idioma").waitForNonExistence(timeout: 5))
    }
}
