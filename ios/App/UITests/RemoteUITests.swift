import XCTest

/// El control completo de tu Orbital: la hoja estirada, con el pad y las teclas, usado con gestos de verdad (demo).
final class RemoteUITests: XCTestCase {
    func testTheStretchedSheetHasThePadAndKeysAndTheyWork() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-tv-now", "-demo-open", "remote-full", "-demo-appearance", "dark"]
        app.launch()
        let pad = app.descendants(matching: .any)["Pad de la TV"]
        XCTAssertTrue(pad.waitForExistence(timeout: 20), "estirada, la hoja trae el pad")
        pad.swipeRight(); pad.swipeDown(); pad.tap()          // flechas y A: la demo las acepta sin error
        // Todos los botones del mando (los mismos de `input.js`): LB/RB, B, X, Y, LT/RT, Inicio, ☰ y ⧉; A es tocar el pad.
        for action in ["prevsection", "nextsection", "back", "alt", "options", "pageleft", "pageright", "home", "menu", "search"] {
            XCTAssertTrue(app.buttons["remote-\(action)"].exists, "la tecla de \(action)")
        }
        app.buttons["remote-back"].tap()
        XCTAssertTrue(app.buttons["remote-alt"].label.contains("Mi lista"), "rotulada con la leyenda de la TV")
        XCTAssertTrue(app.buttons["Dile a Orbital"].exists, "y el micrófono")
        // Junto al micrófono, lo que puedes decir: dónde hablarle, lo del iPhone y las frases de la consola.
        app.buttons["remote-voice-guide"].tap()
        XCTAssertTrue(app.navigationBars["Lo que puedes decir"].waitForExistence(timeout: 5), "abre la guía de voz")
        XCTAssertTrue(app.staticTexts["Con Siri"].exists)
        XCTAssertTrue(app.staticTexts["«descárgalo»"].exists, "con lo que solo hace el iPhone")
        app.navigationBars["Lo que puedes decir"].buttons["Listo"].tap()
        XCTAssertTrue(app.buttons["Dile a Orbital"].waitForExistence(timeout: 5), "y regresa al control")
        XCTAssertFalse(app.staticTexts["Actualiza tu Orbital para usar el control completo."].exists, "la consola (demo) sí tiene el control completo")
        XCTAssertTrue(app.textFields["Escribir en la TV"].exists, "y se puede escribir en la TV")
    }

    /// Sin nada en la TV, bajar el control lo cierra (antes se quedaba atorado en una hoja corta vacía).
    func testWithNothingOnTheTVPullingDownClosesTheRemote() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-open", "remote-idle", "-demo-appearance", "dark"]
        app.launch()
        let pad = app.descendants(matching: .any)["Pad de la TV"]
        XCTAssertTrue(pad.waitForExistence(timeout: 20), "sin nada en la TV abre el control completo")
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        top.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        sleep(2)
        XCTAssertFalse(pad.exists, "se cerró")
        XCTAssertFalse(app.staticTexts["Estira hacia arriba para el control completo"].exists, "y no quedó la hoja corta vacía")
    }

    /// Sin nada en la TV no hay accesorio abajo (ni doble fila): el control se abre desde el botón junto al avatar.
    func testWithNothingOnTheTVTheRemoteLivesNextToTheAvatar() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark"]
        app.launch()
        let button = app.buttons["home-remote"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "el botón del control, en la barra de Inicio")
        XCTAssertFalse(app.staticTexts["Nada en la TV ahora"].exists, "y abajo ya no hay accesorio vacío")
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Pad de la TV"].waitForExistence(timeout: 10), "abre el control completo")
    }
}
