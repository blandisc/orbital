import XCTest

/// G3-A (Fernando, 10 nov 2026: «Vamos con tus sugerencias»): en Mi lista, «Editar» elige varios y la barra de abajo los quita
/// juntos, con un solo aviso y «Deshacer».
final class SavedSelectionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testElegirVariosYQuitarlosDeUnaVez() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
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

    /// Revisión del 28 nov: con «Todas» elegidas, cambiar a Películas suelta las series (ya no se ven): la barra solo actúa
    /// sobre lo que tienes enfrente.
    func testCambiarElFiltroSueltaLoQueYaNoSeVe() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let edit = app.buttons["list-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 10))
        edit.tap()
        let all = app.buttons["select-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        let count = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'elegidas de'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let before = count.label
        let pill = app.buttons["kind-all"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "la pastilla del tipo de la lista")
        pill.tap()
        let movies = app.buttons["kind-movie"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5))
        movies.tap()
        sleep(1)
        let after = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'elegidas de'")).firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        XCTAssertNotEqual(after.label, before, "las series escondidas dejan de contar")
        let parts = after.label.components(separatedBy: " elegidas de ")
        XCTAssertEqual(parts.first, parts.last, "quedan elegidas justo las que se ven: \(after.label)")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "solo-peliculas"; a.lifetime = .keepAlways; add(a)
    }
}
