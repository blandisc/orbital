import XCTest

/// El reproductor: botones con nombre y la hoja «Audio y subtítulos» (con su pestaña «Versión»).
final class PlayerPanelUITests: XCTestCase {
    func testAudioAndSubtitlesOpensFromTheSubtitleButtonWithItsVersionTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        // Una sola entrada: el botón de subtítulos de la barra (ya no hay «Audio y subtítulos» en el «⋯»).
        let subtitles = app.buttons["player-next-subtitle"]
        if !subtitles.waitForExistence(timeout: 3) { app.tap() }
        XCTAssertTrue(subtitles.waitForExistence(timeout: 10), "el botón de subtítulos está en la barra")
        subtitles.tap()
        // En horizontal, a la derecha con dos pestañas fijas: «Audio y subtítulos» y «Versión».
        let versionTab = app.buttons["Versión"]
        XCTAssertTrue(versionTab.waitForExistence(timeout: 5), "abre «Audio y subtítulos» con su pestaña «Versión»")
        XCTAssertTrue(app.buttons["Audio y subtítulos"].exists)
        versionTab.tap()
        XCTAssertTrue(app.buttons["Por idioma"].waitForExistence(timeout: 5), "la pestaña «Versión», por idioma o todas las fuentes")
        app.buttons["Audio y subtítulos"].tap()
        XCTAssertTrue(app.buttons["Listo"].waitForExistence(timeout: 5))
        app.buttons["Listo"].tap()
        XCTAssertTrue(versionTab.waitForNonExistence(timeout: 5), "«Listo» la cierra")
        XCUIDevice.shared.orientation = .portrait
    }

    /// En vertical (abierta con `-demo-player audio`): bajo el video, con su título y «Listo», que la cierra.
    func testAudioAndSubtitlesInPortrait() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play",
                               "-demo-player-portrait", "-demo-player", "audio"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let done = app.buttons["subtitle-dock-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), "abre «Audio y subtítulos» bajo el video")
        XCTAssertTrue(app.staticTexts["Audio y subtítulos"].exists, "con su título")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "«Listo» la cierra")
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

    /// El «⋯» ya no repite «Audio y subtítulos» (era la misma hoja que el botón de subtítulos).
    func testTheMoreMenuDoesNotRepeatAudioAndSubtitles() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play", "-demo-player-portrait"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(8)
        let more = app.buttons["player-more"]
        if !more.isHittable { app.tap() }
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        XCTAssertTrue(app.buttons["player-lock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["player-settings"].exists)
    }
}
