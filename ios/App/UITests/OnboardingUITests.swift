import XCTest

/// La guía de la primera vez (corte C), de punta a punta con la demo (`-demo-first-run`): clave incompleta, no reconocida,
/// cuenta gratuita y buena; Trakt con su código; saltar Stremio; reabrir desde Ajustes. En cada paso el botón de
/// seguir tiene que quedar dentro de la pantalla (iPhone SE, mini y Pro Max).
///
/// Con `TEST_RUNNER_SHOTS=<carpeta>` además guarda una captura de cada pantalla (`FlowCaptureUITests` usa lo mismo).
class GuideUITestCase: XCTestCase {
    var app: XCUIApplication!
    static let shortToken = "QX7MZ2K9PLA4RT8W"
    static let badToken = "BAD" + String(repeating: "QX7MZ2K9PL", count: 5)
    static let freeToken = "FREE" + String(repeating: "QX7MZ2K9PL", count: 5)
    static let goodToken = String(repeating: "QX7MZ2K9PL", count: 5) + "AB"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    var shots: String? { ProcessInfo.processInfo.environment["SHOTS"] }

    /// Una captura a la resolución del simulador (solo con `SHOTS`).
    func shot(_ name: String) {
        guard let shots else { return }
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: shots).appendingPathComponent(name + ".png"))
    }

    func launch(_ args: [String]) {
        app.terminate()
        // `MAC_LOOK=1`: el acomodo de la Mac (`-demo-mac-look`) y acostado, como se ve la ventana en la Mac.
        let mac = ProcessInfo.processInfo.environment["MAC_LOOK"] != nil
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle"] + args + (shots != nil ? ["-demo-appearance", "dark"] : [])
            + (mac ? ["-demo-mac-look"] : [])
        if mac { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()
    }

    func text(_ fragment: String) -> XCUIElement {
        // Los avisos y las piezas juntan su texto en un solo elemento (no siempre es un `staticText`).
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @discardableResult
    func wait(_ fragment: String, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = text(fragment)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "no apareció «\(fragment)»", file: file, line: line)
        return found
    }

    /// El botón que sigue (el de la página a la vista), dentro de la pantalla y tocable.
    func nextButton(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let buttons = app.buttons.matching(identifier: "guide-next")
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        let visible = buttons.allElementsBoundByIndex.last { $0.isHittable } ?? buttons.firstMatch
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(visible.frame), "el botón se sale de la pantalla: \(visible.frame) en \(screen)", file: file, line: line)
        return visible
    }

    func next(file: StaticString = #filePath, line: UInt = #line) { nextButton(file: file, line: line).tap() }

    /// Escribe una clave y la manda (Intro comprueba).
    func enter(_ token: String) {
        let field = app.textFields["debrid-token"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<3 where !field.isHittable { app.scrollViews.firstMatch.swipeUp() }
        // Los botones de abajo flotan sobre la lista: XCUITest da el campo por tocable aunque quede debajo (en el SE, con RC1).
        let bar = app.buttons["guide-next"]
        for _ in 0..<3 where bar.exists && field.frame.maxY > bar.frame.minY { app.scrollViews.firstMatch.swipeUp() }
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "Pega tu clave" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(token + "\n")
    }

    /// De la bienvenida a tu nube (v3, 18 nov 2026): la TV y Trakt se dejan para después.
    func toTheCloud() {
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 20); sleep(4)
        next(); wait("Tu iPhone, control de tu TV")
        app.buttons["guide-skip"].firstMatch.tap(); wait("Sigue donde te quedaste")
        app.buttons["guide-skip"].firstMatch.tap(); wait("Ve todo al instante, aquí")
    }

    /// La guía completa (versión 3: el camino sale de la versión, nada obligatorio). Con `capture`, una captura de cada
    /// pantalla con el prefijo de su número.
    func walkTheGuide(capture: Bool) {
        let c: (String) -> Void = { name in if capture { self.shot(name) } }
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 20); sleep(4); c("01-bienvenida")
        next(); wait("Tu iPhone, control de tu TV"); c("02-tv")
        app.buttons["guide-skip"].firstMatch.tap(); wait("Sigue donde te quedaste"); c("03-trakt")
        next(); wait("Esperando a que lo apruebes"); c("04-trakt-codigo")   // TK-C3: «Conectar Trakt» abre el código
        wait("Listo, fernando", 20); c("05-trakt-conectado")
        next(); wait("Trajimos lo tuyo"); c("06-lo-tuyo")   // K4-B: Trakt trajo algo
        next(); wait("Ve todo al instante, aquí")
        XCTAssertTrue(app.buttons["guide-skip"].exists, "«Ahora no, después» siempre deja seguir")
        // DN1: «Elegir tu nube» abre la hoja «Tu nube»: primero cuál de las tres, nunca Real-Debrid solo.
        next(); wait("Ya tengo cuenta"); c("07-tu-nube")
        XCTAssertTrue(app.buttons["cloud-connect-torbox"].exists && app.buttons["cloud-connect-alldebrid"].exists, "las tres nubes")
        app.buttons["cloud-connect-realdebrid"].tap(); c("07-clave-a-mano")
        enter(Self.badToken); wait("no reconoce"); c("08-clave-no-reconocida")
        enter(Self.shortToken); wait("incompleta")
        enter(Self.freeToken); wait("Tu cuenta es gratuita")
        enter(Self.goodToken); wait("Real-Debrid · fernando", 15); c("09-clave-buena")   // conectada: la hoja se cierra sola
        next()
        wait("Tu Orbital ya está lista."); c("10-listo")
        next()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 10) || app.buttons["Inicio"].waitForExistence(timeout: 5),
                      "al terminar, la app")
    }
}

final class OnboardingUITests: GuideUITestCase {
    func testCompleteTheGuideWithEveryKeyProblem() { walkTheGuide(capture: false) }

    /// Para revisar la guía: con `SHOTS`, una captura de cada pantalla en el aparato donde corra (iPhone, iPad, Mac).
    func testCaptureTheGuideForReview() { walkTheGuide(capture: true) }

    /// «Después» en cada paso: de la bienvenida a «Listo» sin conectar nada (nada es obligatorio).
    func testLaterSkipsStraightToTheEnd() {
        toTheCloud()
        app.buttons["guide-skip"].firstMatch.tap()
        wait("Tu Orbital ya está lista.")
    }

    func testSkipFromAnyStep() {
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 20)
        app.buttons["guide-skip-all"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 10) || app.buttons["Inicio"].waitForExistence(timeout: 5))
    }

    func testReopenTheGuideFromSettings() {
        launch(["-demo-open", "settings"])
        let learn = app.buttons["settings-learn"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !(learn.exists && learn.isHittable) { app.swipeUp() }   // la lista crea el renglón al llegar a él
        learn.tap()
        let guide = app.buttons["settings-guide"]
        for _ in 0..<4 where !(guide.exists && guide.isHittable) { app.swipeUp() }
        guide.tap()
        wait("Todo lo que quieres ver, en un solo lugar.")
    }

    /// RC1 · Real-Debrid con código (en la hoja «Tu nube», DN1): sin copiar ni pegar, el código grande y, al aprobarlo, conectado solo.
    func testRealDebridConnectsWithACode() {
        toTheCloud()
        next()   // «Conectar tu nube» (DN1): la hoja «Tu nube», Real-Debrid y «Conectar con un código»
        app.buttons["cloud-connect-realdebrid"].firstMatch.waitForExistence(timeout: 10)
        app.buttons["cloud-connect-realdebrid"].firstMatch.tap()
        app.buttons["debrid-code-start"].firstMatch.waitForExistence(timeout: 10)
        app.buttons["debrid-code-start"].firstMatch.tap()
        wait("Escribe este código en real-debrid.com/device")
        XCTAssertTrue(app.descendants(matching: .any)["debrid-code"].firstMatch.waitForExistence(timeout: 5))
        wait("Real-Debrid · fernando", 20)
        XCTAssertTrue(nextButton().isEnabled, "conectada: «Seguir»")
    }
}
