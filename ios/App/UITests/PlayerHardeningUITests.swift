import XCTest

/// Lo que se rompió el 28 oct en el reproductor, probado con la app de verdad: un pellizco leve no recorta el video y volver de
/// segundo plano deja el reproductor vivo (con su botón, no una pantalla negra).
final class PlayerHardeningUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play",
                               "-demo-player-portrait"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(9)
        return app
    }

    /// Parado no hay zoom (Fernando, 21 nov 2026: «hacia arriba no tiene mucho sentido porque hace como un zoom raro»): abrir los
    /// dedos no recorta y el «⋯» no ofrece «Imagen».
    func testPinchInPortraitDoesNotCrop() {
        let app = launch()
        sleep(5)   // que se escondan los controles
        app.pinch(withScale: 2, velocity: 1)
        sleep(1)
        if !app.buttons["player-more"].waitForExistence(timeout: 2) { app.tap() }
        app.buttons["player-more"].tap()
        XCTAssertTrue(app.buttons["player-speed"].waitForExistence(timeout: 5), "el «⋯» abierto")
        XCTAssertFalse(app.buttons["player-zoom"].exists, "parado no hay «Imagen»")
    }

    func testBackFromBackgroundThePlayerIsStillThere() {
        let app = launch()
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        sleep(6)
        if !app.buttons["player-close"].exists { app.tap() }   // trae los controles
        XCTAssertTrue(app.buttons["player-close"].waitForExistence(timeout: 5), "el reproductor sigue abierto")
        let bigButton = app.buttons["Pausa"].exists || app.buttons["Continuar"].exists || app.buttons["Cargando"].exists
        XCTAssertTrue(bigButton, "el botón grande está (play, pausa o carga), no una pantalla vacía")
    }
}
