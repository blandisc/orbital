import XCTest

/// El reproductor: botones con nombre y el panel «Ajustes del video» (renglones que llevan a su página y vuelven).
final class PlayerPanelUITests: XCTestCase {
    func testTheVideoSettingsPanelOpensItsPagesAndComesBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        if !app.buttons["player-more"].waitForExistence(timeout: 3) { app.tap() }
        XCTAssertTrue(app.buttons["player-more"].waitForExistence(timeout: 10), "Audio y subtítulos, zoom, ventana, la TV y bloquear van en el «⋯»")
        app.buttons["player-more"].tap()
        let settings = app.buttons["player-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "el renglón dice qué hace")
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
        if !app.buttons["player-more"].waitForExistence(timeout: 3) { app.tap() }
        let more = app.buttons["player-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let lock = app.buttons["player-lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 3), "el «⋯» abre con Bloquear")
        sleep(6)   // más que lo que tardan los controles en esconderse: el globo sigue abierto
        XCTAssertTrue(lock.exists, "con el «⋯» abierto los controles no se esconden")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "player-more"; shot.lifetime = .keepAlways; add(shot)
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

    /// El zoom: al tocarlo sale el aviso con el modo nuevo (se captura justo después del toque).
    func testZoomShowsItsToast() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        if !app.buttons["player-more"].waitForExistence(timeout: 3) { app.tap() }
        XCTAssertTrue(app.buttons["player-more"].waitForExistence(timeout: 5))
        app.buttons["player-more"].tap()   // el zoom va en el «⋯», con el modo puesto a la derecha
        let zoom = app.buttons["player-zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "player-zoom-toast"; shot.lifetime = .keepAlways; add(shot)
        XCUIDevice.shared.orientation = .portrait
    }
}
