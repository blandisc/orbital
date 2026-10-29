import XCTest

/// El reproductor cuando una versión se queda cargando, y el panel «Audio y subtítulos» en vertical con un video 4:3, con el MKV
/// servido desde la Mac (`scripts/ios_software_path.sh`; con `HANG=v=1` la versión que abre primero nunca contesta). Las capturas van a
/// `SHOTS` (o /tmp/orbital-stuck). Sin `DEMO_VIDEO` no corre.
final class PlayerStuckUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var folder: String { env["SHOTS"] ?? "/tmp/orbital-stuck" }

    private func shot(_ name: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    private func launch() throws -> XCUIApplication {
        let video = try XCTUnwrap(env["DEMO_VIDEO"], "sin DEMO_VIDEO: corre scripts/ios_software_path.sh")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0096697", "-demo-open", "play",
                               "-demo-player-portrait", "-demo-versions", "-demo-video", video]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        return app
    }

    private func button(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        // Los controles se esconden solos: si no están (o van de salida), un toque los trae.
        let b = app.buttons[id]
        for _ in 0..<3 where !(b.exists && b.isHittable) { app.tap(); _ = b.waitForExistence(timeout: 2); sleep(1) }
        return b
    }

    /// La versión que abre se queda cargando: elegir otra a mano la pone a sonar (antes solo se veía la carga).
    func testChoosingAnotherVersionWhileOneIsStuck() throws {
        let app = try launch()
        sleep(8)
        shot("s1-cargando")
        XCTAssertTrue(app.buttons["player-close"].exists, "con ✕ a la vista mientras carga")
        button(app, "player-more").tap()
        XCTAssertTrue(app.buttons["player-versions"].waitForExistence(timeout: 5), "«Versión» en el «⋯» mientras carga")
        app.buttons["player-versions"].tap()
        app.buttons["Todas las fuentes"].tap()
        sleep(1)
        shot("s2-versiones")
        // Otra que ya está en Real-Debrid («4K · DV · 16.6 GB»): se abre su renglón y «Cambiar a esta».
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "4K · DV · 16.6 GB")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let change = app.buttons["all-sources-primary"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        for i in 1...4 { sleep(4); shot("s3-cambiada-\(i * 4)s") }
        XCTAssertFalse(app.buttons["Cargando"].exists, "ya suena la que elegiste")
        app.tap(); sleep(1); shot("s3-toque")
        // La pantalla de su tamaño: antes, el fondo ambiente la estiraba a 1383 puntos y ✕ y «⋯» quedaban fuera.
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(app.buttons["player-close"].frame), "✕ dentro de la pantalla (\(app.buttons["player-close"].frame))")
        button(app, "player-more").tap()
        let zoom = app.buttons["player-zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        shot("s4-menu")
        print("zoom: \(zoom.label)")
        XCTAssertTrue(zoom.label.contains("Normal"), "el video en su franja, no agrandado (\(zoom.label))")
    }

    /// Sin tocar nada: la versión trabada da paso sola a otra en menos de un minuto (antes, si se colgaba al pedirla otra vez,
    /// cargaba para siempre).
    func testAStuckVersionGivesWayOnItsOwn() throws {
        let app = try launch()
        sleep(20); shot("a1-cargando-20s")
        XCTAssertTrue(app.buttons["player-close"].exists, "✕ a la vista mientras carga")
        sleep(40); shot("a2-60s")
        app.tap(); sleep(1); shot("a3-controles")
        XCTAssertTrue(app.buttons["Pausa"].waitForExistence(timeout: 5), "ya suena otra versión")
    }

    /// El peor caso de abajo en vertical: el video hasta arriba (la barra de ✕ baja con los controles), la tarjeta de «Siguiente
    /// episodio» y letra muy grande. Todo dentro de la pantalla (antes se salían por abajo).
    func testTheControlsBelowTheVideoNeverLeaveTheScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play",
                               "-demo-player-portrait", "-demo-player-state", "upnext", "-player-portrait-center", "0",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(12)
        let close = app.buttons["player-close"]
        for _ in 0..<3 where !close.exists { app.tap(); sleep(2) }   // un toque a la vez: dos seguidos los vuelven a esconder
        XCTAssertTrue(close.exists, "con los controles a la vista")
        shot("c1-abajo")
        let screen = app.windows.firstMatch.frame
        print("✕ en \(close.frame), pantalla \(screen)")
        XCTAssertLessThanOrEqual(close.frame.maxY, screen.maxY, "la barra de ✕ dentro de la pantalla")
        XCTAssertTrue(close.isHittable, "y se puede tocar")
    }

    /// «Audio y subtítulos» en vertical: pegado abajo y del alto que pide, sin hueco debajo, al abrir y cerrar renglones, con los
    /// subtítulos apagados o prendidos, y al volver de «Versión».
    func testTheSubtitleDockSitsAtTheBottom() throws {
        let app = try launch()
        sleep(14)
        button(app, "player-next-subtitle").tap()
        let done = app.buttons["subtitle-dock-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        sleep(1)
        let screen = app.windows.firstMatch.frame
        let last = app.buttons["player-version"]
        /// El renglón de abajo («Versión») contra la orilla de abajo (con el área segura y el margen, ~50).
        func checkBottom(_ step: String) {
            sleep(2)
            shot(step)
            let gap = screen.maxY - last.frame.maxY
            print("hueco abajo (\(step)): \(gap)")
            XCTAssertTrue(last.isHittable, "\(step): el panel se ve entero")
            XCTAssertLessThan(gap, 80, "\(step): el panel abajo, sin espacio muerto")
        }
        let row = { (name: String) in app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Inglés")).firstMatch.tap(); sleep(2); shot("d1-ingles")   // 4:3 con subtítulos y su renglón abierto: no cabe entero, se desplaza
        row("Subtítulos").tap(); checkBottom("d2-subtitulos-cerrado")
        row("Tamaño").tap(); checkBottom("d3-tamano-abierto")
        row("Tamaño").tap(); checkBottom("d4-tamano-cerrado")
        row("Subtítulos").tap(); sleep(1)
        row("Apagados").tap(); checkBottom("d5-apagados")
        row("Subtítulos").tap(); checkBottom("d6-apagados-cerrado")
        last.tap(); sleep(1); shot("d7-version")
        app.buttons["version-back"].tap(); checkBottom("d8-de-vuelta")
    }
}
