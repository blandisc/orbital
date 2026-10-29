import XCTest

/// Capturas del flujo nuevo (guía, Ajustes y lo que cambió fuera de ella) para el Canvas de Fernando, en modo oscuro y a la
/// resolución del simulador. Solo corre con `TEST_RUNNER_SHOTS=<carpeta>`; sin eso se salta.
final class FlowCaptureUITests: GuideUITestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(shots == nil, "solo para capturas (TEST_RUNNER_SHOTS)")
    }

    func test1Guide() { walkTheGuide(capture: ProcessInfo.processInfo.environment["ONLY"] == nil) }

    /// Un renglón de Ajustes por su título (el renglón dice «Cuentas, Falta Real-Debrid»).
    func row(_ title: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    func open(_ title: String) {
        let found = row(title)
        for _ in 0..<6 where !(found.waitForExistence(timeout: 3) && found.isHittable) { app.swipeUp() }
        XCTAssertTrue(found.exists, "el renglón «\(title)»")
        found.tap()
    }

    func settings(rd: String) {
        launch(["-demo-open", "settings", "-demo-rd", rd, "-demo-trakt", "-demo-no-tv"])
        XCTAssertTrue(row("Cuentas").waitForExistence(timeout: 20))
        sleep(2)
    }

    func test2Settings() {
        settings(rd: "premium")
        shot("15-ajustes")
        open("Cuentas"); wait("Premium"); sleep(1); shot("16-cuentas-real-debrid")
        app.swipeUp(); sleep(1); shot("20-stremio-respaldo")
        app.swipeDown()
        open("Trakt"); sleep(2); shot("19-trakt-principal")
        app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        open("Complementos"); wait("Torrentio"); sleep(1); shot("21-complementos")
        app.buttons["Ordenar"].tap(); sleep(1); shot("22-complementos-ordenar")
        app.buttons["Listo"].tap(); sleep(1)
        app.buttons["addons-add"].tap(); sleep(1); shot("23-complementos-agregar")
        app.buttons["Pegar dirección"].tap(); sleep(1); shot("24-pegar-direccion")
        app.alerts.buttons.element(boundBy: 1).tap(); sleep(1)
        app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        let guide = app.buttons["settings-guide"]
        for _ in 0..<6 where !(guide.exists && guide.isHittable) { app.swipeUp() }
        sleep(1); shot("25-como-funciona-orbital")
        guide.tap(); wait("Tus películas y series en tu bolsillo."); sleep(1); shot("26-guia-desde-ajustes")
    }

    func test3DebridSoonAndExpired() {
        settings(rd: "14"); open("Cuentas"); wait("Premium"); sleep(1); shot("17-real-debrid-14-dias")
        settings(rd: "expired"); open("Cuentas"); wait("Venció"); sleep(1); shot("18-real-debrid-vencido")
    }

    /// En pantallas con muchos elementos (Inicio, Buscar) solo se buscan textos: buscar en todo tarda demasiado.
    func waitText(_ fragment: String, _ timeout: TimeInterval = 25) {
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch.waitForExistence(timeout: timeout), "«\(fragment)»")
    }

    func test4OutsideTheGuide() {
        launch(["-demo-notice", "rd-vencido", "-demo-rd", "expired"]); sleep(6); shot("27-ver-con-real-debrid-vencido")
        launch(["-demo-signed-out"]); sleep(8); shot("28-inicio-sin-stremio")
        launch(["-demo-tab", "2"]); sleep(10); shot("29-buscar-tendencia-trakt")
        launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-shelf", "critics"]); sleep(12); shot("30-para-ti-aprobadas-por-la-critica")
    }

    /// Con tu Orbital conectada, Trakt se abre y se desconecta en Cuentas (antes decía «Desde tu Orbital» y no se tocaba).
    func test6TraktWithOrbital() {
        launch(["-demo-open", "settings", "-demo-rd", "premium", "-demo-trakt"])
        XCTAssertTrue(row("Cuentas").waitForExistence(timeout: 20)); sleep(2)
        open("Cuentas"); wait("Premium"); sleep(1); shot("32-cuentas-trakt-con-orbital")
        open("Trakt"); sleep(2); shot("33-trakt-con-orbital")
        XCTAssertTrue(app.buttons["Desconectar Trakt"].waitForExistence(timeout: 5), "con tu Orbital, Trakt también se desconecta aquí")
    }

    func test5EpisodeMenu() {
        launch(["-demo-title", "series:tt0386676"])
        // Se marca visto el primero con su «⋯»; ya visto enseña su ✓ en vez del «⋯» y su menú se abre manteniéndolo presionado.
        let more = app.buttons.matching(identifier: "episode-more").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 25))
        for _ in 0..<3 where !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.buttons["Marcar como visto"].waitForExistence(timeout: 5)); app.buttons["Marcar como visto"].tap()
        let seen = app.images["Visto"].firstMatch
        XCTAssertTrue(seen.waitForExistence(timeout: 15), "un episodio visto")
        seen.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Marcar como no visto"].waitForExistence(timeout: 5), "el episodio visto ofrece desmarcarlo")
        sleep(1); shot("31-episodio-marcar-como-no-visto")
    }
}
