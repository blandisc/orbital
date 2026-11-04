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
        app.launchArguments = ["-demo", "-demo-no-idle"] + args + (shots != nil ? ["-demo-appearance", "dark"] : [])
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
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "Pega tu clave" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(token + "\n")
    }

    /// La guía completa (versión 2: nada obligatorio). Con `capture`, una captura de cada pantalla con el prefijo de su número.
    func walkTheGuide(capture: Bool) {
        let c: (String) -> Void = { name in if capture { self.shot(name) } }
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 20); sleep(4); c("01-bienvenida")
        next(); wait("¿Qué te gusta?"); c("02-gustos")
        next(); wait("¿Qué ya tienes?"); c("03-que-tienes")
        app.buttons["have-debrid-has"].tap()
        next(); wait("Ver aquí mismo, sin esperar")
        XCTAssertFalse(nextButton().isEnabled, "con «Ya lo tengo», «Continuar» espera la clave")
        XCTAssertTrue(app.buttons["guide-skip"].exists, "pero «Cuando quiera ver algo» siempre deja seguir")
        app.swipeDown(); c("04-clave-vacia")
        enter(Self.badToken); wait("no reconoce"); XCTAssertFalse(nextButton().isEnabled); c("05-clave-no-reconocida")
        enter(Self.shortToken); wait("incompleta"); XCTAssertFalse(nextButton().isEnabled)
        enter(Self.freeToken); wait("Tu cuenta es gratuita"); XCTAssertFalse(nextButton().isEnabled)
        enter(Self.goodToken); wait("fernando · Premium"); XCTAssertTrue(nextButton().isEnabled); c("06-clave-buena")
        next(); wait("Esperando a que lo apruebes"); c("07-trakt-codigo")
        wait("Conectado como fernando", 20); c("08-trakt-conectado")
        next()
        XCTAssertFalse(app.staticTexts["Tu TV"].exists, "sin TV no hay paso de la TV")
        wait("Tu Orbital ya está lista."); c("09-listo")
        next()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 10) || app.buttons["Inicio"].waitForExistence(timeout: 5),
                      "al terminar, la app")
    }
}

final class OnboardingUITests: GuideUITestCase {
    func testCompleteTheGuideWithEveryKeyProblem() { walkTheGuide(capture: false) }

    /// «Después» en todo: de «¿Qué ya tienes?» directo a «Listo» (C1, D1: nada detiene la guía).
    func testLaterSkipsStraightToTheEnd() {
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 20); sleep(4)
        next(); wait("¿Qué te gusta?")
        next(); wait("¿Qué ya tienes?")
        app.buttons["have-debrid-later"].tap()
        app.buttons["have-trakt-later"].tap()
        next(); wait("Tu Orbital ya está lista.")
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
}
