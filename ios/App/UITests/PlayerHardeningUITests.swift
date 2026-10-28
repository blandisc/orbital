import XCTest

/// Lo que se rompió el 28 oct en el reproductor, probado con la app de verdad: un pellizco leve no recorta el video y volver de
/// segundo plano deja el reproductor vivo (con su botón, no una pantalla negra).
final class PlayerHardeningUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play",
                               "-demo-player-portrait"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(9)
        return app
    }

    /// El zoom puesto, como lo dice el renglón «Zoom» del «⋯» (el aviso del zoom no lo lee VoiceOver).
    private func zoomLabel(_ app: XCUIApplication) -> String {
        if !app.buttons["player-more"].waitForExistence(timeout: 2) { app.tap() }
        app.buttons["player-more"].tap()
        let row = app.buttons["player-zoom"]
        _ = row.waitForExistence(timeout: 5)
        let label = row.label + " · " + String(describing: row.value ?? "")
        app.buttons["player-more"].tap()   // cierra el «⋯»
        sleep(1)
        return label
    }

    /// Abrir los dedos recorta. (El pellizco leve y el de cerrar no se pueden simular de forma fiable: `pinch(withScale: 1.08)` le
    /// llega a la app como ~2× y el de cerrar a veces ni llega. La zona muerta se prueba en `SettingsTests`.)
    func testPinchOpenCrops() {
        let app = launch()
        XCTAssertTrue(zoomLabel(app).contains("Normal"))
        sleep(5)   // que se escondan los controles
        app.pinch(withScale: 2, velocity: 1)
        sleep(1)
        let opened = zoomLabel(app)
        XCTAssertTrue(opened.contains("Recortar"), "abrir los dedos recorta (\(opened))")

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
