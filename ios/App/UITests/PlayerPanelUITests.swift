import XCTest

/// El reproductor: botones con nombre y el panel «Ajustes del video» (renglones que llevan a su página y vuelven).
final class PlayerPanelUITests: XCTestCase {
    func testTheVideoSettingsPanelOpensItsPagesAndComesBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(9)
        app.tap()
        let settings = app.buttons["Audio y subtítulos"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "el botón dice qué hace")
        XCTAssertTrue(app.buttons["En la TV"].exists, "y el de la TV también")
        settings.tap()
        XCTAssertTrue(app.staticTexts["Ajustes del video"].waitForExistence(timeout: 5), "abre el panel")
        app.buttons["panel-subtitles"].tap()
        XCTAssertTrue(app.staticTexts["Subtítulos"].waitForExistence(timeout: 5), "su página")
        XCTAssertTrue(app.buttons["Sin subtítulos"].exists, "con sus opciones")
        app.buttons["panel-back"].tap()
        XCTAssertTrue(app.buttons["panel-audio"].waitForExistence(timeout: 5), "y vuelve")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.staticTexts["Ajustes del video"].waitForExistence(timeout: 5), "en vertical sigue, como hoja")
    }
}
