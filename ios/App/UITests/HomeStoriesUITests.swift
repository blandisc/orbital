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

    /// Fernando, 4 nov: «cuando bajas y le picas X, truenan». Abiertas, ya abajo, la ✕ regresa el encabezado sin trabarse.
    func testClosingAfterScrollingDownDoesNotHang() {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-rd", "premium", "-demo-stories-open"]
        app.launch()
        XCTAssertTrue(app.buttons["home-stories-close"].waitForExistence(timeout: 20))
        for _ in 0..<3 { app.swipeUp() }
        app.buttons["home-stories-close"].tap()
        XCTAssertTrue(app.buttons["home-random-simpsons"].waitForExistence(timeout: 5), "regresa el encabezado")
        for _ in 0..<3 { app.swipeDown() }
        XCTAssertTrue(app.buttons["home-random-simpsons"].isHittable, "y la app sigue viva")
    }

    /// Como Instagram: al deslizar a la izquierda dentro de una historia, sigue la próxima.
    func testSwipingLeftInsideAStoryGoesToTheNextOne() {
        let peek = app.buttons["home-stories-peek"]
        XCTAssertTrue(peek.waitForExistence(timeout: 20))
        peek.tap()
        let ring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'learn-ring-'")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        let deck = app.otherElements["story-deck"].firstMatch
        XCTAssertTrue(app.buttons["story-close"].firstMatch.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        let visible: () -> [String] = { self.app.staticTexts.allElementsBoundByIndex.filter { screen.contains($0.frame) }.map(\.label) }
        let before = visible()
        (deck.exists ? deck : app.windows.firstMatch).swipeLeft()
        sleep(2)
        XCTAssertNotEqual(visible(), before, "otra historia a la vista")
    }
}
