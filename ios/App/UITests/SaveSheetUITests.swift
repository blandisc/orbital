import XCTest

/// «Guardar en…»: Fernando tocaba la lista equivocada porque todo se recorría al llegar las listas. Con `-demo-trakt` las
/// listas tardan ~1,5 s: la fija (Mi lista) y «Nueva lista…» tienen que estar en el mismo lugar antes y después.
final class SaveSheetUITests: XCTestCase {
    func testFixedRowsDoNotMoveWhenTheListsArrive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-title", "series:tt0386676", "-demo-open", "save"]
        app.launch()

        let watchlist = app.buttons["save-fixed-myList"]
        XCTAssertTrue(watchlist.waitForExistence(timeout: 20), "Mi lista, fija")
        XCTAssertTrue(app.descendants(matching: .any)["save-lists-loading"].exists, "las listas todavía no llegan: esqueletos en su lugar")
        let before = (watchlist.frame, app.buttons["save-new-list"].frame)

        let recent = app.buttons["save-list-105"]   // «Fin de semana», la que cambió más reciente
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "llegaron las listas")
        XCTAssertFalse(app.descendants(matching: .any)["save-lists-loading"].exists)
        XCTAssertEqual(watchlist.frame, before.0, "Mi lista no se movió")
        XCTAssertEqual(app.buttons["save-new-list"].frame, before.1, "«Nueva lista…» no se movió")
        XCTAssertLessThan(recent.frame.minY, app.buttons["save-list-101"].exists ? app.buttons["save-list-101"].frame.minY : .infinity,
                          "las recientes van arriba")
        XCTAssertLessThan(recent.frame.maxY, watchlist.frame.minY, "tus listas arriba, las fijas abajo")
        XCTAssertGreaterThanOrEqual(watchlist.frame.height, 44, "objetivo táctil de al menos 44 pt")

        // Una lista nueva entra arriba sin mover las fijas.
        app.buttons["save-new-list"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Recién hecha")
        app.alerts.buttons["Crear"].tap()
        let made = app.buttons["save-list-106"]
        XCTAssertTrue(made.waitForExistence(timeout: 10), "la lista nueva")
        XCTAssertLessThan(made.frame.minY, recent.frame.minY, "arriba de las demás")
        XCTAssertEqual(watchlist.frame, before.0, "y las fijas siguen donde estaban")
    }
}
