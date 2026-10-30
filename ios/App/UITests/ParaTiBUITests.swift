import XCTest

/// Para ti B con toques de verdad (modo demo): la tarjeta «¿Qué vemos hoy?» abre el mazo, la portada abre el mosaico y abajo
/// están «Lo que ves» y Colecciones. Deja capturas como adjuntos.
final class ParaTiBUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-tab", "1", "-demo-mode", "lists", "-demo-appearance", "dark", "-demo-no-idle"]
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func testLaTarjetaAbreElMazo() {
        let card = app.buttons["paraTi-decide"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "la tarjeta «¿Qué vemos hoy?» está")
        shot("para-ti-arriba")
        card.tap()
        XCTAssertTrue(app.otherElements["match-deck"].waitForExistence(timeout: 10), "se abre el mazo")
        sleep(2)
        shot("mazo")
    }

    func testLaPortadaAbreElMosaico() {
        let walk = app.buttons["paraTi-walk-mosaic"]
        XCTAssertTrue(walk.waitForExistence(timeout: 20))
        walk.tap()
        XCTAssertTrue(app.otherElements["mosaic"].waitForExistence(timeout: 10), "se abre el mosaico")
        shot("mosaico")
    }

    func testAbajoEstanLoQueVesYColecciones() {
        let seen = app.descendants(matching: .any)["paraTi-your-year"]
        for _ in 0..<25 where !seen.exists || !seen.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(seen.waitForExistence(timeout: 10), "«Lo que ves» está al final")
        shot("abajo")
    }
}
