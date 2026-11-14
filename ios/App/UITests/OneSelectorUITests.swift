import XCTest

/// SG1 + SL1 + KT1 (Fernando, 13 nov 2026): Guardado con sus cuatro partes en el selector de Orbital; el renglón de controles
/// (R1); Vistas sin tercer renglón (VS2: ⊜ elige «Las dejé», el reloj abre el Historial); Listas con ＋; la pastilla de tipo
/// dice «Series». Las capturas quedan en `ORBITAL_SHOTS` (si se da) para revisarlas.
final class OneSelectorUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Nada empuja la página fuera de la pantalla: el selector, la pastilla y elegir varios quedan adentro (antes, con el nombre
    /// en la pastilla, el renglón crecía y los pósters se salían por los lados).
    private func assertFits(_ app: XCUIApplication, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        for id in ["saved-tabs", "kind-all", "kind-movie", "kind-series", "list-edit", "list-sort"] {
            let e = app.descendants(matching: .any)[id].firstMatch
            guard e.exists else { continue }
            XCTAssertGreaterThanOrEqual(e.frame.minX, screen.minX - 0.5, "\(id) se sale por la izquierda \(when)", file: file, line: line)
            XCTAssertLessThanOrEqual(e.frame.maxX, screen.maxX + 0.5, "\(id) se sale por la derecha \(when)", file: file, line: line)
        }
    }

    func testGuardadoConElSelectorDeOrbital() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let myList = app.buttons["saved-tab-mylist"]
        XCTAssertTrue(myList.waitForExistence(timeout: 20), "Mi lista en el selector")
        XCTAssertTrue(myList.isSelected, "Mi lista, elegida al entrar")
        XCTAssertTrue(app.buttons["list-sort"].waitForExistence(timeout: 10), "el orden a la izquierda del renglón")
        XCTAssertTrue(app.buttons["list-add"].exists, "＋ en Mi lista")
        shot(app, "1-mi-lista")

        // KT1: elegir Series y que la pastilla lo diga con letras.
        let series = app.buttons["kind-series"].firstMatch
        XCTAssertTrue(series.exists)
        let before = series.frame
        series.tap()
        let name = app.descendants(matching: .any)["kind-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3), "dice «Series»")
        XCTAssertEqual(name.label, "Series")
        sleep(1)
        XCTAssertEqual(series.frame.minX, before.minX, accuracy: 1, "el ícono no se mueve al elegirlo")
        XCTAssertEqual(series.frame.minY, before.minY, accuracy: 1, "el ícono no se mueve al elegirlo")
        XCTAssertLessThanOrEqual(name.frame.maxX, app.buttons["kind-all"].firstMatch.frame.minX, "el nombre, a la izquierda de la pastilla")
        let tabs = app.descendants(matching: .any)["saved-tabs"]
        XCTAssertGreaterThan(series.frame.minY, tabs.frame.maxY - 1, "la pastilla, bajo el selector")
        assertFits(app, "con «Series»")
        shot(app, "2-solo-series")
        app.buttons["kind-movie"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["kind-name"].firstMatch.label, "Películas", "dice «Películas»")
        XCTAssertEqual(series.frame.minX, before.minX, accuracy: 1, "los íconos siguen en su lugar")
        assertFits(app, "con «Películas»")
        shot(app, "2b-solo-peliculas")
        app.buttons["kind-all"].firstMatch.tap()

        // VS2: Vistas sin tercer renglón; el reloj abre el Historial y se regresa.
        app.buttons["saved-tab-watched"].tap()
        XCTAssertTrue(app.buttons["saved-tab-watched"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["saved-watched-views"].exists, "Vistas ya no trae su renglón de pestañas")
        let history = app.buttons["saved-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "el reloj del Historial en el renglón")
        shot(app, "3-vistas")
        history.tap()
        XCTAssertTrue(app.navigationBars["Historial"].waitForExistence(timeout: 10), "el Historial en su pantalla")
        shot(app, "4-historial")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["saved-tab-watched"].waitForExistence(timeout: 10), "de vuelta en Vistas")

        // Listas: ＋ en el renglón.
        app.buttons["saved-tab-lists"].tap()
        XCTAssertTrue(app.buttons["saved-new-list"].waitForExistence(timeout: 10), "＋ crea una lista nueva")
        shot(app, "5-listas")
    }
}
