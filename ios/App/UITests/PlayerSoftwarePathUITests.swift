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

    /// Lo que dice la barra de avance («2:07 / 9:59»), con los controles a la vista.
    private func shownTime(_ app: XCUIApplication) -> Double {
        if !app.otherElements["player-scrub"].exists && !app.sliders["player-scrub"].exists { app.tap(); sleep(1) }
        let element = app.otherElements["player-scrub"].exists ? app.otherElements["player-scrub"] : app.sliders["player-scrub"]
        let text = (element.value as? String) ?? ""
        let first = text.components(separatedBy: " / ").first ?? ""
        let parts = first.split(separator: ":").compactMap { Double($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Volver a la app sigue donde ibas (antes se volvía a cargar desde 0:00) y la pantalla queda en orden.
    func testBackFromBackgroundKeepsThePlace() throws {
        let video = try XCTUnwrap(env["DEMO_VIDEO"], "sin DEMO_VIDEO: corre scripts/ios_software_path.sh")
        let tag = env["DEMO_SOFTWARE"] == "1" ? "software" : "nativo"
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0096697", "-demo-open", "play",
                               "-demo-player-portrait", "-demo-video", video] + (tag == "software" ? ["-demo-software-path"] : [])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(30)
        let before = shownTime(app)
        shot("\(tag)-fondo-1-antes")
        XCTAssertGreaterThan(before, 5, "ya iba avanzando")
        XCUIDevice.shared.press(.home)
        sleep(5)
        app.activate()
        for i in 1...4 { sleep(5); shot("\(tag)-fondo-2-vuelta-\(i * 5)s") }
        let after = shownTime(app)
        shot("\(tag)-fondo-3-despues")
        XCTAssertGreaterThanOrEqual(after, before - 2, "sigue donde iba (\(before) → \(after)), no desde 0:00")
        XCTAssertTrue(app.buttons["player-close"].exists, "con la barra de arriba")
    }

    /// Abre el MKV servido desde la Mac en vertical, con el video a la altura `center` (-1: donde abre).
    private func launch(_ center: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0096697", "-demo-open", "play",
                               "-demo-player-portrait", "-demo-video", env["DEMO_VIDEO"] ?? "", "-player-portrait-center", center]
            + (env["DEMO_SOFTWARE"] == "1" ? ["-demo-software-path"] : [])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(12)
        return app
    }

    /// En pausa, salir y volver: regresa en pausa en el mismo punto, con ✕ y la barra; play sigue de ahí.
    /// Subir el video arrastrando hasta arriba: queda entero (sin cortarse bajo el reloj) y no brinca al soltarlo.
    /// (Capturas p1…p5 y r1…r5 en SHOTS.)

    func testPausedReturnThenPlay() throws {
        _ = try XCTUnwrap(env["DEMO_VIDEO"])
        let app = launch("0.5")
        if !app.buttons["Pausa"].exists { app.tap(); sleep(1) }
        app.buttons["Pausa"].tap(); sleep(1)
        shot("p1-pausado")
        XCUIDevice.shared.press(.home); sleep(6); app.activate(); sleep(3)
        shot("p2-de-vuelta")
        if !app.buttons["Continuar"].exists { app.tap(); sleep(1) }
        shot("p3-con-controles")
        app.buttons["Continuar"].tap(); sleep(1)
        shot("p4-play-1s"); sleep(4); shot("p5-play-5s")
    }
    func testRaiseVideoByDragging() throws {
        _ = try XCTUnwrap(env["DEMO_VIDEO"])
        let app = launch("-1")
        let win = app.windows.firstMatch
        // la agarradera: el borde de abajo del video (cerca de y = 60 + alto 9/16 del ancho)
        _ = win.frame
        let start = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))   // lo negro de abajo: mueve el video
        let mid = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
        let end = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        shot("r1-antes")
        start.press(forDuration: 0.05, thenDragTo: mid, withVelocity: 40, thenHoldForDuration: 0.6)
        shot("r2-un-poco")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.2)
        shot("r3-arriba-0s"); sleep(1); shot("r4-arriba-1s")
        // Al soltar ya se ven los controles: un toque solo si no (otro toque los escondería).
        if !app.buttons["player-close"].exists { app.tap(); sleep(1) }
        shot("r5-controles")
        XCTAssertTrue(app.buttons["player-close"].exists, "con la barra de ✕")
        XCTAssertLessThan(app.buttons["player-close"].frame.maxY, app.windows.firstMatch.frame.maxY, "✕ dentro de la pantalla")
    }
}
