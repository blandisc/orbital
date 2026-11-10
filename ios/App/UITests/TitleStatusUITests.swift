import XCTest

/// G1-A (Fernando, 9 nov 2026): el botón de estado de la ficha dice cómo vas y, con estado, un toque abre «¿Cómo vas con…?».
final class TitleStatusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testUnaSerieQueVasViendoAbreElMenuDelEstado() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-no-idle", "-demo-appearance", "dark", "-demo-title", "series:tt0386676"]
        app.launch()
        let status = app.buttons["title-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "la ficha tiene el botón de estado")
        XCTAssertTrue(status.label.contains("Viendo"), "una serie a medias dice «Viendo» (dice «\(status.label)»)")
        status.tap()
        XCTAssertTrue(app.buttons["Vista"].waitForExistence(timeout: 5), "el menú ofrece «Vista»")
        XCTAssertTrue(app.buttons["En Mi lista"].exists, "y «En Mi lista»")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "menu"; a.lifetime = .keepAlways; add(a)
    }
}
