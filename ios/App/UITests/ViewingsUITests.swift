import XCTest

/// O3-B (Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): «Tus vistas» y «Tu nota» en la ficha, las estrellas de
/// la temporada y la pantalla «Historial» con sus vistas repetidas. La demo tiene Dune vista tres veces (dos el mismo día).
final class ViewingsUITests: XCTestCase {
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

    /// La hoja «¿Cuándo la viste?»: «Ahora».
    func answerWhen(_ app: XCUIApplication) {
        let now = app.buttons["watched-now"], no = app.buttons["watched-earlier-no"], done = app.buttons["watched-when-done"]
        XCTAssertTrue(now.waitForExistence(timeout: 5) || no.exists || done.exists, "la hoja de cuándo")
        if no.exists { no.tap() }
        if now.waitForExistence(timeout: 2) { now.tap() }
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    /// Lo sube poco a poco hasta que quede en la parte libre de la pantalla: ni bajo la barra de arriba ni bajo las pestañas y
    /// «¿Qué tal…?» (en una pantalla baja, como el Duo cerrado, un `swipeUp` entero lo pasaba de largo bajo la barra).
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let height = app.frame.height
        func clear() -> Bool { element.exists && element.isHittable && element.frame.minY > height * 0.15 && element.frame.maxY < height * 0.7 }
        for _ in 0..<16 where !clear() {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let up = element.exists && element.frame.maxY > 0 && element.frame.minY < height * 0.15
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: up ? 120 : -120)))
        }
    }

    func testTusVistasYTuNotaEnLaFicha() {
        let app = launch(["-demo-title", "movie:tt1160419"])
        // En la demo Dune aún no cuenta como vista aquí (Trakt ya tiene sus tres vistas): «Vista» desde el menú.
        // F1: «Vista» es su propio mosaico (en una película, un toque).
        let watched = app.buttons["title-watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 25))
        watched.tap()
        answerWhen(app)
        let viewings = app.buttons["title-your-viewings"]
        XCTAssertTrue(viewings.waitForExistence(timeout: 25), "«Tus vistas» en la ficha de una película vista")
        scrollTo(viewings, in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '3 veces'")).firstMatch.waitForExistence(timeout: 10)
                      || viewings.label.contains("3 veces"), "la viste 3 veces")
        shot(app, "ficha")
        viewings.tap()
        XCTAssertTrue(app.otherElements["viewings-sheet"].waitForExistence(timeout: 5) || app.navigationBars["Tus vistas"].waitForExistence(timeout: 5))
        let trash = app.buttons.matching(identifier: "viewing-delete")
        XCTAssertTrue(trash.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(trash.count, 3, "una fila por vista")
        shot(app, "tus-vistas")
        trash.firstMatch.tap()
        XCTAssertTrue(app.buttons["Deshacer"].waitForExistence(timeout: 5) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Borr'")).firstMatch.exists,
                      "el aviso con Deshacer")
        let fewer = NSPredicate(format: "count == 2")
        expectation(for: fewer, evaluatedWith: trash)
        waitForExpectations(timeout: 8)
        app.buttons["viewing-add"].tap()
        XCTAssertTrue(app.buttons["viewing-date-save"].waitForExistence(timeout: 5), "«La vi otra vez» pide la fecha")
        shot(app, "otra-vez")
        app.buttons["viewing-date-save"].tap()
        expectation(for: NSPredicate(format: "count == 3"), evaluatedWith: trash)
        waitForExpectations(timeout: 8)
        app.navigationBars.buttons["Listo"].tap()

        let note = app.buttons.matching(identifier: "title-your-note").firstMatch
        scrollTo(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 5), "«Tu nota» en la ficha")
        note.tap()
        let where_ = app.staticTexts["note-where"]
        XCTAssertTrue(where_.waitForExistence(timeout: 5))
        XCTAssertTrue(where_.label.contains("solo en este iPhone"), "sin VIP la nota se queda en el iPhone: \(where_.label)")
        app.textViews["note-editor"].tap()
        app.textViews["note-editor"].typeText("La vi en el cine con Ana.")
        shot(app, "nota")
        app.buttons["note-save"].tap()
        // F1 (12 nov): la nota ya no es un renglón; el botón redondo se llena y la lee en voz (su valor).
        expectation(for: NSPredicate(format: "value CONTAINS 'con Ana'"), evaluatedWith: note)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(note.label, "Tu nota", "la nota queda en la ficha: el botón se llena")
        shot(app, "ficha-con-nota")
    }

    func testLaNotaConVIPVaATrakt() {
        let app = launch(["-demo-vip", "-demo-title", "movie:tt1160419"])
        let note = app.buttons.matching(identifier: "title-your-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 25))
        scrollTo(note, in: app)
        note.tap()
        let where_ = app.staticTexts["note-where"]
        XCTAssertTrue(where_.waitForExistence(timeout: 5))
        XCTAssertTrue(where_.label.contains("Trakt (VIP)"), "con VIP la nota vive en Trakt: \(where_.label)")
        shot(app, "nota-vip")
    }

    func testEstrellasDeLaTemporada() {
        let app = launch(["-demo-title", "series:tt0386676"])
        // F1: la temporada se marca y se califica desde el mosaico «Vista».
        let mark = app.buttons["title-watched"]
        XCTAssertTrue(mark.waitForExistence(timeout: 25))
        mark.tap()
        // Dentro de un menú de iOS el identificador no llega: se busca por su nombre («Temporada 1 · 3 de 22 vistos»).
        // «Temporada 2» también es el selector de temporadas de la ficha: la del menú es la que va justo arriba de «Toda la serie».
        let whole = app.buttons.matching(NSPredicate(format: "label == 'Toda la serie'")).firstMatch
        XCTAssertTrue(whole.waitForExistence(timeout: 5), "el menú de «Vista»")
        let season = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Temporada'")).allElementsBoundByIndex
            .filter { $0.frame.maxY <= whole.frame.minY + 2 && $0.frame.minX < whole.frame.maxX && $0.frame.maxX > whole.frame.minX }
            .max { $0.frame.maxY < $1.frame.maxY } ?? whole
        XCTAssertNotEqual(season.label, whole.label, "la temporada en el menú de «Vista»")
        season.tap()
        answerWhen(app)
        mark.tap()
        let rate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Calificar la temporada'")).firstMatch
        XCTAssertTrue(rate.waitForExistence(timeout: 10), "«Calificar la temporada» en el menú de «Vista»")
        rate.tap()
        let stars = app.otherElements["season-rating"]
        XCTAssertTrue(stars.waitForExistence(timeout: 10), "la hoja con las estrellas de la temporada")
        shot(app, "temporada")
    }

    func testHistorialYRepetidas() {
        let app = launch(["-demo-tab", "3"])
        let watched = app.buttons["saved-tab-watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20), "la pestaña «Vistas» de Guardado")
        watched.tap()
        let history = app.buttons["Historial"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "«Historial» dentro de Vistas (GD2)")
        history.tap()
        let repeatRow = app.descendants(matching: .any)["history-row-repeat"]
        XCTAssertTrue(repeatRow.waitForExistence(timeout: 10), "Dune repetida el mismo día")
        shot(app, "historial")
        // GD2: el historial vive bajo las pestañas de Guardado; «Quitar … repetidas» queda al final de la lista.
        let clean = app.buttons["history-clean-repeats"]
        for _ in 0..<4 where !clean.isHittable { app.swipeUp() }
        clean.tap()
        let confirm = app.buttons["Quitar"]   // la confirmación dice «Quitar» (D7-A: limpieza, no borrar)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: repeatRow)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.descendants(matching: .any)["history-row"].exists, "las demás vistas se quedan")
        shot(app, "historial-limpio")
    }
}
