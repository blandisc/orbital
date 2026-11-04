import XCTest

/// Las historias en el encabezado de Inicio (HE1-B): se asoman a la derecha, deslizar a la izquierda las abre en lugar del
/// encabezado, tocar lo asomado también (puntero y teclado), y la ✕ o deslizar a la derecha lo regresa.
final class HomeStoriesUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-rd", "premium"]
        app.launch()
    }

    func testSwipeLeftOpensTheStoriesAndTheCrossBringsTheHeaderBack() {
        let peek = app.buttons["home-stories-peek"]
        XCTAssertTrue(peek.waitForExistence(timeout: 20), "dos círculos se asoman a la derecha")
        XCTAssertTrue(app.buttons["home-random-simpsons"].isHittable, "sin estorbar a la cápsula")
        app.buttons["home-kind-filter"].firstMatch.exists ? app.otherElements["home-kind-filter"].swipeLeft() : peek.swipeLeft()
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'learn-ring-'")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5) && ring.isHittable, "las historias ocupan el encabezado")
        XCTAssertFalse(app.buttons["home-random-simpsons"].isHittable, "la cápsula se fue")
        app.buttons["home-stories-close"].tap()
        XCTAssertTrue(app.buttons["home-random-simpsons"].waitForExistence(timeout: 5))
        XCTAssertTrue(peek.waitForExistence(timeout: 5))
    }

    func testTappingThePeekAlsoOpensThem() {
        let peek = app.buttons["home-stories-peek"]
        XCTAssertTrue(peek.waitForExistence(timeout: 20))
        peek.tap()
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'learn-ring-'")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        XCTAssertTrue(app.otherElements["story"].waitForExistence(timeout: 5) || app.buttons["story-close"].waitForExistence(timeout: 5))
    }
}
