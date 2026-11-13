import XCTest

/// Pasada de prueba y pulido de O3-B (Fernando, 10 nov 2026: «Prueba y da una pulida a lo que acabas de construir»): lo que
/// la primera prueba no tocaba. «Tus vistas» de un capítulo, borrar la nota, «Agregar» del Historial y sin internet.
final class ViewingsPolishUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark"] + extra
        app.launch()
        return app
    }

    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func answerWhen(_ app: XCUIApplication) {
        let now = app.buttons["watched-now"], no = app.buttons["watched-earlier-no"], done = app.buttons["watched-when-done"]
        XCTAssertTrue(now.waitForExistence(timeout: 5) || no.exists || done.exists, "la hoja de cuándo")
        if no.exists { no.tap() }
        if now.waitForExistence(timeout: 2) { now.tap() }
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    func testTusVistasDeUnCapitulo() {
        let app = launch(["-demo-title", "series:tt0386676"])
        let mark = app.buttons["title-watched"]   // F1: la temporada se marca desde el mosaico «Vista»
        XCTAssertTrue(mark.waitForExistence(timeout: 25))
        mark.tap()
        // Si otra prueba ya la dejó vista, se cierra el menú y se sigue.
        let season = app.buttons["title-watched-season"]
        if season.waitForExistence(timeout: 5), !app.staticTexts.containing(NSPredicate(format: "label CONTAINS '22 de 22'")).firstMatch.exists {
            season.tap(); answerWhen(app)
        } else if season.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
        // Mantener el dedo sobre el capítulo (en el SE no cabe el «···»).
        let episode = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Los Dundies'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 10))
        scrollTo(episode, in: app)
        episode.press(forDuration: 1.2)
        let item = app.buttons["Tus vistas…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "el capítulo visto ofrece «Tus vistas…»")
        item.tap()
        XCTAssertTrue(app.navigationBars["Tus vistas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["viewing-add"].waitForExistence(timeout: 10))
        shot(app, "capitulo-tus-vistas")
    }

    func testBorrarLaNota() {
        let app = launch(["-demo-title", "movie:tt1160419"])
        let note = app.buttons.matching(identifier: "title-your-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 25))
        scrollTo(note, in: app)
        note.tap()
        let editor = app.textViews["note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Para borrar")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["Para borrar"].waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()   // el cursor al final
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        shot(app, "nota-vacia")
        app.buttons["note-save"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Para borrar"])
        waitForExpectations(timeout: 5)
        shot(app, "ficha-sin-nota")
    }

    func testAgregarAlHistorial() {
        let app = launch(["-demo-tab", "3"])
        let watched = app.buttons["saved-tab-watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        watched.tap()
        app.buttons["Historial"].tap()
        let add = app.buttons["history-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let field = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "buscar qué agregar")
        field.tap(); field.typeText("Interstellar")
        let found = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Interstellar'")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 10))
        shot(app, "historial-buscar")
        found.tap()
        let save = app.buttons["viewing-date-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "una película pide la fecha")
        shot(app, "historial-fecha")
        save.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Interstellar'")).firstMatch.waitForExistence(timeout: 10), "entra al historial")
        shot(app, "historial-agregada")
    }

    /// Sin internet «Tus vistas» abre con lo que espera en la cola y lo dice; «La vi otra vez» sigue a mano (la TV lo encontró).
    func testTusVistasSinInternet() {
        let app = launch(["-demo-offline", "-demo-title", "movie:tt1160419"])
        let watched = app.buttons["title-watched"]   // F1: «Vista» es su propio mosaico
        XCTAssertTrue(watched.waitForExistence(timeout: 25))
        watched.tap()
        answerWhen(app)
        let viewings = app.buttons["title-your-viewings"]
        XCTAssertTrue(viewings.waitForExistence(timeout: 10))
        scrollTo(viewings, in: app)
        viewings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["viewings-offline"].waitForExistence(timeout: 10), "lo dice")
        XCTAssertTrue(app.buttons["viewing-add"].exists, "«La vi otra vez» sigue a mano")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "viewing-delete").count, 1, "la que se acaba de marcar, en la cola")
        shot(app, "tus-vistas-sin-internet")
    }

    func testSinInternet() {
        let app = launch(["-demo-offline", "-demo-tab", "3"])
        let watched = app.buttons["saved-tab-watched"]
        if watched.waitForExistence(timeout: 20) {
            watched.tap()
            if app.buttons["Historial"].waitForExistence(timeout: 5) {
                app.buttons["Historial"].tap()
                XCTAssertTrue(app.staticTexts["No pude traer tu historial"].waitForExistence(timeout: 10), "lo dice, no un vacío")
                XCTAssertTrue(app.buttons["Reintentar"].exists)
            }
        }
        shot(app, "historial-sin-internet")
    }
}
