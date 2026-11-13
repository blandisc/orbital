import XCTest

/// El iPad con teclado (y la Mac, que usa los mismos atajos): cada atajo de la barra de menús (`AppCommands`) hace lo que
/// dice. Guarda capturas en `ORBITAL_SHOTS` (o /tmp/orbital-shots) para revisar el foco del teclado.
///   xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,name=Orbital QA iPad' \
///     -only-testing:OrbitalUITests/IPadKeyboardUITests
/// En un iPhone no corre (no hay barra de menús).
final class IPadKeyboardUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "solo en iPad")
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func open(_ args: [String]) {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-free-tabs"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/teclado-\(name).png"))
    }

    private func tab(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND selected == true", name)).firstMatch
    }

    /// ⌘1, ⌘2, ⌘3 cambian de pestaña y ⌘F abre Buscar con el campo listo.
    func testTabShortcuts() {
        open(["-demo-tab", "0"])
        XCTAssertTrue(app.descendants(matching: .any)["Inicio"].waitForExistence(timeout: 30))
        sleep(3)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(tab("Explorar").waitForExistence(timeout: 5), "⌘2 no abrió Explorar")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(tab("Biblioteca").waitForExistence(timeout: 5), "⌘3 no abrió Biblioteca")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(tab("Inicio").waitForExistence(timeout: 5), "⌘1 no regresó a Inicio")
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "⌘F no abrió Buscar")
        sleep(2)
        shot("buscar")
    }

    /// «Cancelar» del teclado (`cancelAction`: Esc y ⌘.). Se manda ⌘.: la tecla Esc que inyecta XCUITest en el simulador de
    /// iPadOS 27 no llega como Esc (10 nov 2026); con un teclado de verdad son la misma acción.
    private func cancel() { app.typeKey(".", modifierFlags: .command) }

    /// En la ficha: ⌘D «Guardar en…», ⌥⌘V «Versión», Esc (⌘.) cierra la hoja y ⌘[ regresa.
    func testTitleShortcuts() {
        open(["-demo-tmdb", "-demo-trakt", "-demo-title", "movie:tt1160419"])
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continuar' OR label BEGINSWITH 'Ver'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "la ficha no abrió")
        sleep(4)
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Guardar en…"].waitForExistence(timeout: 8), "⌘D no abrió «Guardar en…»")
        shot("guardar")
        cancel()
        XCTAssertTrue(app.staticTexts["Guardar en…"].waitForNonExistence(timeout: 5), "Esc no cerró la hoja")
        sleep(2)
        app.typeKey("v", modifierFlags: [.command, .option])
        let info = app.buttons["sources-info"]   // la ⓘ del encabezado de «Versión»
        XCTAssertTrue(info.waitForExistence(timeout: 8), "⌥⌘V no abrió «Versión»")
        shot("version")
        cancel()
        XCTAssertTrue(info.waitForNonExistence(timeout: 5), "Esc no cerró «Versión»")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["Inicio"].waitForExistence(timeout: 5))
    }

    /// Tab y flechas con «Acceso total con teclado» (o «Navegación con teclado» en la Mac) prendido: iOS solo mueve el foco por
    /// botones con ese ajuste del sistema (documentación de `focusable(_:interactions:)`). Recorre Inicio, Biblioteca y la ficha
    /// sin cerrarse y guarda capturas para ver el anillo del foco. Solo corre con `ORBITAL_FKA=1` (el ajuste se prende afuera:
    /// `xcrun simctl spawn <udid> defaults write com.apple.Accessibility FullKeyboardAccessEnabled -bool true`).
    func testTabMovesVisibleFocus() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["ORBITAL_FKA"] == nil, "solo con ORBITAL_FKA")
        for (name, args) in [("inicio", ["-demo-tab", "0"]), ("biblioteca", ["-demo-tab", "3", "-demo-trakt"]),
                             ("ficha", ["-demo-tmdb", "-demo-title", "movie:tt1160419"])] {
            open(args)
            sleep(8)
            for step in 1...6 {
                app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
                sleep(1)
                if [1, 3, 6].contains(step) { shot("foco-\(name)-tab\(step)") }
            }
            app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
            sleep(1)
            shot("foco-\(name)-flecha")
            XCTAssertEqual(app.state, .runningForeground, "\(name): la app se cerró al mover el foco")
        }
    }
}
