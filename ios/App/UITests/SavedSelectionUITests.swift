import XCTest

/// G3-A (Fernando, 10 nov 2026: «Vamos con tus sugerencias»): en Mi lista, «Editar» elige varios y la barra de abajo los quita
/// juntos, con un solo aviso y «Deshacer».
final class SavedSelectionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testElegirVariosYQuitarlosDeUnaVez() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let edit = app.buttons["list-edit"]   // GD2: Guardado abre en Mi lista
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 10))
        let before = app.buttons.matching(identifier: "title-link").count
        edit.tap()
        let marks = app.buttons.matching(identifier: "poster-select")
        XCTAssertTrue(marks.firstMatch.waitForExistence(timeout: 5), "cada póster se puede elegir")
        marks.element(boundBy: 0).tap()
        marks.element(boundBy: 1).tap()
        XCTAssertTrue(app.otherElements["selection-bar"].exists || app.buttons["Quitar"].exists, "sale la barra de abajo")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '2 elegidas'")).firstMatch.exists, "dice cuántas")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "elegidas"; a.lifetime = .keepAlways; add(a)
        app.buttons["Quitar"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Quitadas de'")).firstMatch.waitForExistence(timeout: 5), "un solo aviso")
        sleep(1)
        XCTAssertEqual(app.buttons.matching(identifier: "title-link").count, before - 2, "salen las dos")
        let b = XCTAttachment(screenshot: app.screenshot()); b.name = "quitadas"; b.lifetime = .keepAlways; add(b)
    }
}
