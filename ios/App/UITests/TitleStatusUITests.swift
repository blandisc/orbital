import XCTest

/// G1-A (Fernando, 9 nov 2026): el botón de estado de la ficha dice cómo vas y, con estado, un toque abre «¿Cómo vas con…?».
final class TitleStatusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testUnaSerieQueVasViendoAbreElMenuDelEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-title", "series:tt0386676"]
        app.launch()
        let status = app.buttons["title-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "la ficha tiene el botón de estado")
        // El botón siempre se llama «Guardar»; el estado va abajo en chico (11 nov).
        let said = status.label + " " + String(describing: status.value ?? "")
        XCTAssertTrue(status.label.contains("Guardar"), "el botón se llama «Guardar» (dice «\(status.label)»)")
        XCTAssertTrue(said.contains("Viendo"), "una serie a medias dice «Viendo» debajo (dice «\(said)»)")
        status.tap()
        XCTAssertTrue(app.buttons["Vista"].waitForExistence(timeout: 5), "el menú ofrece «Vista»")
        XCTAssertTrue(app.buttons["En Mi lista"].exists, "y «En Mi lista»")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "menu"; a.lifetime = .keepAlways; add(a)
    }

    /// G2-A: Biblioteca › Guardado es un tablero; «Vistas» abre lo visto por mes y «En Mi lista», tu lista.
    func testGuardadoEsUnTableroQueAbreCadaEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let watched = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Vistas'")).firstMatch
        XCTAssertTrue(watched.waitForExistence(timeout: 20), "el tablero tiene «Vistas»")
        watched.tap()
        XCTAssertTrue(app.navigationBars["Vistas"].waitForExistence(timeout: 10), "abre Vistas")
        sleep(2)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "vistas"; a.lifetime = .keepAlways; add(a)
        app.navigationBars.buttons.firstMatch.tap()
        let list = app.buttons.containing(NSPredicate(format: "label CONTAINS 'En Mi lista'")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.tap()
        XCTAssertTrue(app.buttons["saved-list-menu"].waitForExistence(timeout: 10) || app.navigationBars["Mi lista"].exists, "abre Mi lista")
        sleep(2)
        let b = XCTAttachment(screenshot: app.screenshot()); b.name = "milista"; b.lifetime = .keepAlways; add(b)
    }

    /// «Mover a…»: mantener el dedo sobre un póster de Vistas lo regresa a Mi lista, con aviso y «Deshacer».
    func testMantenerElDedoMueveAOtroEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let watched = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Vistas'")).firstMatch
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        watched.tap()
        XCTAssertTrue(app.navigationBars["Vistas"].waitForExistence(timeout: 10))
        let poster = app.buttons.matching(identifier: "title-link").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10), "hay pósters en Vistas")
        poster.press(forDuration: 1.2)
        let move = app.buttons["Mi lista"]
        XCTAssertTrue(move.waitForExistence(timeout: 5), "el menú «Mover a…» ofrece «Mi lista»")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "mover"; a.lifetime = .keepAlways; add(a)
        move.tap()
        XCTAssertTrue(app.staticTexts["Guardada en Mi lista"].waitForExistence(timeout: 5), "avisa con «Deshacer»")
    }
}
