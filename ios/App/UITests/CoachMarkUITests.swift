import XCTest

/// Los avisos sobre la pantalla (F3): salen una vez a quien ya hizo la guía, «Ver la historia» abre la suya, «Entendido» y
/// «Saltar avisos» los cierran, y solo sale uno cada vez que abres la app.
final class CoachMarkUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() { app.terminate() }

    private func launch(_ args: [String]) {
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-free-tabs", "-demo-coach"] + args
        app.launch()
    }

    private func coach(_ id: String) -> XCUIElement { app.descendants(matching: .any)["coach-\(id)"].firstMatch }

    func testSearchCoachOpensItsStory() {
        launch(["-demo-tab", "2"])
        XCTAssertTrue(coach("advanced-search").waitForExistence(timeout: 20), "Buscar: el aviso con foco de la búsqueda avanzada")
        app.buttons["coach-story"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["story-deck"].firstMatch.waitForExistence(timeout: 10), "«Ver la historia» la abre")
        XCTAssertFalse(coach("advanced-search").exists)
    }

    func testDownloadsCoachClosesWithUnderstood() {
        launch(["-demo-tab", "3"])
        XCTAssertTrue(coach("downloads").waitForExistence(timeout: 20), "Biblioteca: su aviso")
        app.buttons["coach-done"].tap()
        XCTAssertTrue(coach("downloads").waitForNonExistence(timeout: 5))
    }

    func testOnlyOneCoachPerLaunchAndSkipAllSilencesThem() {
        launch(["-demo-tab", "3"])
        XCTAssertTrue(coach("downloads").waitForExistence(timeout: 20))
        app.buttons["coach-skip-all"].tap()
        XCTAssertTrue(coach("downloads").waitForNonExistence(timeout: 5))
        let search = app.tabBars.buttons["Buscar"]
        for _ in 0..<4 where !search.exists { app.swipeDown(velocity: .fast) }
        search.tap()
        sleep(3)
        XCTAssertFalse(coach("advanced-search").exists, "uno por apertura, y «Saltar avisos» los calla")
    }

    func testExploreCoachOnlyInTheMosaic() {
        launch(["-demo-tab", "1", "-demo-mode", "lists"])
        sleep(4)
        XCTAssertFalse(coach("explore").exists, "en las listas no hay pósters que acercar")
    }

    /// Fer, 4 nov: el botón de Ajustes los trae de vuelta, aunque no hayas hecho la guía nueva.
    func testSettingsButtonBringsThemBack() {
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-free-tabs", "-demo-tab", "3", "-demo-open", "settings"]
        app.launch()
        // Desde el 11 nov, dentro de Ajustes › Aprende (una sola entrada).
        let learn = app.buttons["settings-learn"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !(learn.exists && learn.isHittable) { app.swipeUp() }
        learn.tap()
        let reset = app.buttons["learn-reset"]
        for _ in 0..<6 where !(reset.exists && reset.isHittable) { app.swipeUp() }
        reset.tap()
        app.buttons["Volver a verlos"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(coach("downloads").waitForExistence(timeout: 15), "de vuelta en Biblioteca, su aviso")
    }
}
