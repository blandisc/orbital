import XCTest

/// El reproductor con un MKV 4:3 como los de Los Simpson, servido desde la Mac (`scripts/ios_software_path.sh`): sonar, pellizcar
/// en horizontal, girar a vertical y volver de segundo plano. Con `DEMO_SOFTWARE=1` el motor va por su ruta de software (la de los
/// MKV raros), que antes solo se podía probar en el iPhone. Sin `DEMO_VIDEO` no corre (no hay video que servir).
/// Las capturas van a `SHOTS` (o /tmp/orbital-software-path) para revisarlas.
final class PlayerSoftwarePathUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var folder: String { env["SHOTS"] ?? "/tmp/orbital-software-path" }

    private func shot(_ name: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    /// El zoom puesto, como lo dice el renglón «Zoom» del «⋯».
    private func zoomLabel(_ app: XCUIApplication) -> String {
        if !app.buttons["player-more"].waitForExistence(timeout: 2) { app.tap() }
        guard app.buttons["player-more"].waitForExistence(timeout: 3) else { return "" }
        app.buttons["player-more"].tap()
        let row = app.buttons["player-zoom"]
        _ = row.waitForExistence(timeout: 5)
        let label = row.label
        app.buttons["player-more"].tap()
        sleep(1)
        return label
    }

    func testA43MkvPlaysRotatesAndComesBack() throws {
        let video = try XCTUnwrap(env["DEMO_VIDEO"], "sin DEMO_VIDEO: corre scripts/ios_software_path.sh")
        let tag = env["DEMO_SOFTWARE"] == "1" ? "software" : "nativo"
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0096697", "-demo-open", "play",
                               "-demo-video", video] + (tag == "software" ? ["-demo-software-path"] : [])
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(12)
        shot("\(tag)-1-horizontal")
        XCTAssertFalse(app.buttons["Cargando"].exists, "ya suena (no se quedó cargando)")

        sleep(5)   // que se escondan los controles
        app.pinch(withScale: 2, velocity: 1)   // «Recortar» en horizontal
        sleep(2)
        shot("\(tag)-2-horizontal-recortar")

        XCUIDevice.shared.orientation = .portrait
        sleep(4)
        shot("\(tag)-3-vertical")
        XCTAssertTrue(zoomLabel(app).contains("Normal"), "al girar a vertical, el cuadro completo (no agrandado)")

        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        sleep(6)
        shot("\(tag)-4-de-vuelta")
        if !app.buttons["player-close"].exists { app.tap() }
        XCTAssertTrue(app.buttons["player-close"].waitForExistence(timeout: 5), "el reproductor sigue abierto")
    }
}
