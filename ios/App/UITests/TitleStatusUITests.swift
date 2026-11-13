import XCTest

/// G1-A (Fernando, 9 nov 2026): el botón de estado de la ficha dice cómo vas y, con estado, un toque abre «¿Cómo vas con…?».
final class TitleStatusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testUnaSerieQueVasViendoAbreElMenuDelEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-title", "series:tt0386676"]
        app.launch()
        let status = app.buttons["title-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "la ficha tiene el botón de estado")
        // F1 (12 nov): ya en alguna parte, el mosaico dice «Guardada» (un renglón); dónde está, al tocarlo.
        let said = status.label + " " + String(describing: status.value ?? "")
        XCTAssertTrue(status.label.contains("Guardada"), "el mosaico dice «Guardada» (dice «\(status.label)»)")
        XCTAssertTrue(said.contains("Viendo"), "VoiceOver dice «Viendo» (dice «\(said)»)")
        status.tap()
        XCTAssertTrue(app.buttons["En Mi lista"].waitForExistence(timeout: 5), "el menú ofrece «En Mi lista»")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "menu"; a.lifetime = .keepAlways; add(a)
    }

    /// GD2 (13 nov 2026, en lugar del tablero G2-A): Guardado son pestañas; «Vistas» trae lo visto por mes, «Las dejé» y el
    /// historial, y «Mi lista» regresa a tu lista.
    func testGuardadoSonPestanasConCadaEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let watched = app.buttons["saved-tab-watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20), "las pestañas tienen «Vistas»")
        watched.tap()
        XCTAssertTrue(app.buttons["Historial"].waitForExistence(timeout: 10), "Vistas trae su historial adentro")
        sleep(2)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "vistas"; a.lifetime = .keepAlways; add(a)
        app.buttons["saved-tab-mylist"].tap()
        XCTAssertTrue(app.buttons["list-edit"].waitForExistence(timeout: 10), "regresa a Mi lista")
        sleep(2)
        let b = XCTAttachment(screenshot: app.screenshot()); b.name = "milista"; b.lifetime = .keepAlways; add(b)
    }

    /// «Mover a…»: mantener el dedo sobre un póster de Vistas lo regresa a Mi lista, con aviso y «Deshacer».
    func testMantenerElDedoMueveAOtroEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-tab", "3"]
        app.launch()
        let watched = app.buttons["saved-tab-watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20))
        watched.tap()
        sleep(1)   // la cuadrícula de Mi lista se va
        let poster = app.buttons.matching(identifier: "title-link").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10), "hay pósters en Vistas")
        poster.press(forDuration: 1.2)
        let move = app.buttons.matching(NSPredicate(format: "label == 'Mi lista' AND identifier != 'saved-tab-mylist'")).firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5), "el menú «Mover a…» ofrece «Mi lista»")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "mover"; a.lifetime = .keepAlways; add(a)
        move.tap()
        XCTAssertTrue(app.staticTexts["Guardada en Mi lista"].waitForExistence(timeout: 5), "avisa con «Deshacer»")
    }
}
