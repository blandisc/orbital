import XCTest

/// G4-A (Fernando, 10 nov 2026: «Vamos con tus sugerencias»): el «···» de una lista tuya cambia su nombre y la borra; Mi lista
/// se ordena a mano desde su orden; la pestaña «Listas» (GD2, 13 nov 2026) suma «Nueva lista».
final class SavedListMenuUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testElMenuDeUnaListaTuya() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let lists = app.buttons["saved-tab-lists"]
        XCTAssertTrue(lists.waitForExistence(timeout: 20), "la pestaña «Listas»")
        lists.tap()
        let newList = app.buttons["saved-new-list"]
        XCTAssertTrue(newList.waitForExistence(timeout: 10), "«Nueva lista» al final de las listas")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Para ver con Ana'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let more = app.buttons["saved-list-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "el «···» de la lista")
        more.tap()
        for item in ["Cambiar nombre", "Quién la ve", "Ordenar a mano", "Duplicar", "Compartir enlace", "Borrar lista"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 3), item)
        }
        shot(app, "menu")
        app.buttons["Cambiar nombre"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        field.typeText("Con Ana")
        app.alerts.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Con Ana'")).firstMatch.waitForExistence(timeout: 5)
                      || app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Con Ana'")).firstMatch.exists, "el nombre nuevo")
        more.tap()
        app.buttons["Ordenar a mano"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Guardar"].waitForExistence(timeout: 5), "la hoja con agarraderas")
        shot(app, "ordenar")
        app.navigationBars.buttons["Guardar"].tap()
        more.tap()
        app.buttons["Borrar lista"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Borrar lista'")).element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot(app, "borrar")
        app.sheets.buttons["Borrar lista"].exists ? app.sheets.buttons["Borrar lista"].tap() : confirm.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Borraste'")).firstMatch.waitForExistence(timeout: 5), "el aviso")
        XCTAssertTrue(newList.waitForExistence(timeout: 5), "de vuelta a «Listas»")
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Con Ana'")).firstMatch.exists, "la lista ya no está")
        shot(app, "listas")
        app.buttons["saved-tab-mylist"].tap()
        let sort = app.buttons["list-sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10), "el orden, a la izquierda del renglón")
        XCTAssertFalse(more.exists, "Mi lista no lleva «···»")
        sort.tap()
        XCTAssertTrue(app.buttons["A mano…"].waitForExistence(timeout: 3), "Mi lista se ordena a mano desde su orden")
        shot(app, "mi-lista-a-mano")
    }
}
