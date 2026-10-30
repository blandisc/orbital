import XCTest

/// El cielo de fondo con toques de verdad (modo demo): Buscar y «Lo que ves», en oscuro y en claro. Deja capturas como adjuntos.
final class SkyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(tab: Int, appearance: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-tab", "\(tab)", "-demo-mode", "lists",
                               "-demo-appearance", appearance, "-demo-no-idle"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func testCieloEnBuscar() {
        for appearance in ["dark", "light"] {
            let app = launch(tab: 2, appearance: appearance)
            XCTAssertTrue(app.navigationBars["Buscar"].waitForExistence(timeout: 20), "está Buscar")
            sleep(3)
            shot(app, "buscar-\(appearance)")
            app.terminate()
        }
    }

    func testCieloEnLoQueVes() {
        for appearance in ["dark", "light"] {
            let app = launch(tab: 1, appearance: appearance, extra: ["-demo-open", "watching"])
            XCTAssertTrue(app.descendants(matching: .any)["watching-wrapped"].waitForExistence(timeout: 20), "se abre «Lo que ves»")
            sleep(3)
            shot(app, "lo-que-ves-\(appearance)")
            app.terminate()
        }
    }
}
