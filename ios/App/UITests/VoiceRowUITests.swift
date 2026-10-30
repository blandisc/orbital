import XCTest

/// El renglón de la voz del control (`VoiceRow`): quieto con su pista, la respuesta con sus salidas, las varias en carrusel,
/// la orden que no llegó y la guía. Se toca la pista (la frase de `-demo-voice`), que se manda como si la hubieras dicho, y
/// el modo demo contesta como la consola. Guarda una captura de cada estado en `ORBITAL_SHOTS` (o /tmp/orbital-shots).
final class VoiceRowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "solo en iPhone")
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func open(_ args: [String]) {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-no-idle", "-demo-tv-now"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        let size = app.windows.firstMatch.frame.size
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/voz-\(Int(size.width))x\(Int(size.height))-\(name).png"))
    }

    /// Abre el control, toca la pista y espera lo que contesta.
    private func say(_ phrase: String, full: Bool, extra: [String] = []) {
        open(["-demo-open", full ? "remote-full" : "remote", "-demo-voice", phrase] + extra)
        let hint = app.buttons["voice-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 30), "no sale la pista")
        shot((full ? "estirado" : "corta") + "-quieto")
        hint.tap()
    }

    func testAnswerWithItsWaysOut() {
        say("pon The Office", full: false)
        XCTAssertTrue(app.buttons["voice-episodes"].waitForExistence(timeout: 10), "la respuesta no trae «Elegir episodio»")
        XCTAssertTrue(app.buttons["voice-other"].exists)
        sleep(1); shot("corta-respuesta")
        // Se pliega sola y deja la respuesta como pista.
        XCTAssertTrue(app.buttons["voice-mic"].waitForExistence(timeout: 12))
        sleep(1); shot("corta-plegada")
    }

    func testAnswerInTheFullRemote() {
        say("pon The Office", full: true)
        XCTAssertTrue(app.buttons["voice-episodes"].waitForExistence(timeout: 10))
        sleep(1); shot("estirado-respuesta")
        app.buttons["voice-episodes"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), "no abre la lista de episodios")
        sleep(2); shot("episodios")
    }

    func testSeveralMatchesInACarousel() {
        say("pon dune", full: true)
        XCTAssertTrue(app.staticTexts["Poniéndose"].waitForExistence(timeout: 10), "las varias no salen en carrusel")
        sleep(1); shot("estirado-varias-pon")
    }

    func testSearchShowsTheListToPick() {
        say("busca dune", full: false)
        XCTAssertTrue(app.buttons["voice-choice-play"].firstMatch.waitForExistence(timeout: 10))
        sleep(1); shot("corta-varias-busca")
    }

    func testWhenItDoesNotArrive() {
        say("pon The Office", full: true, extra: ["-demo-voice-fail", "tunnel"])
        XCTAssertTrue(app.buttons["voice-check-connection"].waitForExistence(timeout: 15), "no dice qué tramo falló")
        sleep(1); shot("estirado-no-llego")
    }

    func testTheGuideFromTheQuestionMark() {
        open(["-demo-open", "remote"])
        let guide = app.buttons["remote-voice-guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 30))
        guide.tap()
        XCTAssertTrue(app.staticTexts["Lo esencial"].waitForExistence(timeout: 10), "la guía no abre en Lo esencial")
        sleep(1); shot("guia")
    }
}
