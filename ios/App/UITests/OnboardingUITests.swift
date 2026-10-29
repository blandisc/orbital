import XCTest

/// La guía de la primera vez (corte C), de punta a punta con la demo (`-demo-first-run`): clave incompleta, no reconocida,
/// cuenta gratuita y buena; Trakt con su código; saltar la TV y Stremio; reabrir desde Ajustes. En cada paso el botón de
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

    /// La guía completa. Con `capture`, una captura de cada pantalla con el prefijo de su número.
    func walkTheGuide(capture: Bool) {
        let c: (String) -> Void = { name in if capture { self.shot(name) } }
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Tus películas y series en tu bolsillo.", 20); c("01-bienvenida")
        next(); wait("Orbital junta tres piezas"); c("02-como-funciona")
        next(); wait("Es un servicio de pago"); c("03-real-debrid")
        next(); wait("Con ella Orbital puede pedir videos")
        XCTAssertFalse(nextButton().isEnabled, "sin clave no se avanza")
        app.swipeDown(); c("04-clave-vacia")
        enter(Self.badToken); usleep(400_000); c("05-clave-comprobando")
        wait("no reconoce"); XCTAssertFalse(nextButton().isEnabled); c("07-clave-no-reconocida")
        enter(Self.shortToken); wait("incompleta"); XCTAssertFalse(nextButton().isEnabled); c("06-clave-incompleta")
        enter(Self.freeToken); wait("Tu cuenta es gratuita"); XCTAssertFalse(nextButton().isEnabled); c("08-cuenta-gratuita")
        enter(Self.goodToken); wait("fernando · Premium"); XCTAssertTrue(nextButton().isEnabled); c("09-clave-buena")
        next(); wait("De dónde salen las versiones"); wait("Torrentio"); c("10-complementos")
        next(); wait("Esperando a que lo apruebes"); c("11-trakt-codigo")
        wait("Conectado como fernando", 20); wait("Trajimos", 15); c("12-trakt-conectado")
        next(); wait("En la TV: Ajustes"); c("13-tu-tv")
        let skip = app.buttons.matching(identifier: "guide-skip").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(skip, "la TV tiene «Ahora no»"); skip?.tap()
        wait("Ya puedes ver lo que quieras"); wait("¿Usas Stremio?"); c("14-todo-listo")
        next()
        XCTAssertTrue(app.tabBars.buttons.firstMatch.waitForExistence(timeout: 10) || app.buttons["Inicio"].waitForExistence(timeout: 5),
                      "al terminar, la app (sin Stremio: «Ahora no»)")
    }
}

final class OnboardingUITests: GuideUITestCase {
    func testCompleteTheGuideWithEveryKeyProblem() { walkTheGuide(capture: false) }

    func testReopenTheGuideFromSettings() {
        launch(["-demo-open", "settings"])
        let guide = app.buttons["settings-guide"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !(guide.exists && guide.isHittable) { app.swipeUp() }   // la lista crea el renglón al llegar a él
        guide.tap()
        wait("Tus películas y series en tu bolsillo.")
        XCTAssertTrue(nextButton().isHittable)
    }
}
