import XCTest

/// El reproductor: botones con nombre y el panel «Ajustes del video» (renglones que llevan a su página y vuelven).
final class PlayerPanelUITests: XCTestCase {
    func testTheVideoSettingsPanelOpensItsPagesAndComesBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        app.tap()
        let settings = app.buttons["Audio y subtítulos"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "el botón dice qué hace")
        XCTAssertTrue(app.buttons["player-lock"].exists, "Bloquear, redondo como los demás")
        settings.tap()
        XCTAssertTrue(app.staticTexts["Ajustes del video"].waitForExistence(timeout: 5), "abre el panel")
        app.buttons["panel-subtitles"].tap()
        XCTAssertTrue(app.staticTexts["Subtítulos"].waitForExistence(timeout: 5), "su página")
        XCTAssertTrue(app.buttons["player-subtitle-language"].exists, "con su idioma arriba")
        app.buttons["panel-back"].tap()
        XCTAssertTrue(app.buttons["panel-audio"].waitForExistence(timeout: 5), "y vuelve")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.staticTexts["Ajustes del video"].waitForExistence(timeout: 5), "en vertical sigue, como hoja")
    }

    /// Bloqueado: tocar solo enseña «Desbloquear»; ese botón desbloquea. La tarjeta de «Siguiente episodio» no se ve.
    func testLockShowsAnUnlockButtonAndHidesUpNext() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play",
                               "-demo-player-state", "upnext"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        XCTAssertTrue(app.buttons["Ahora no"].waitForExistence(timeout: 10), "la tarjeta del siguiente episodio")
        app.tap()
        if !app.buttons["player-lock"].waitForExistence(timeout: 3) { app.tap() }
        let lock = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Bloquear", "player-lock")).firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Ahora no"].exists, "bloqueado, la tarjeta no se ve ni se toca")
        let unlock = app.buttons["player-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3), "al bloquear aparece «Desbloquear»")
        sleep(4)
        XCTAssertFalse(unlock.exists, "y se va solo")
        app.tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 3), "un toque lo trae")
        unlock.tap()
        XCTAssertTrue(app.buttons["player-close"].waitForExistence(timeout: 3), "desbloquear trae los controles")
        XCTAssertTrue(app.buttons["Ahora no"].exists, "y la tarjeta")
    }
}
