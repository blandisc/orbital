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
        XCTAssertFalse(app.staticTexts["Actualiza tu Orbital para usar el control completo."].exists, "la consola (demo) sí tiene el control completo")
        XCTAssertTrue(app.textFields["Escribir en la TV"].exists, "y se puede escribir en la TV")
    }
}
