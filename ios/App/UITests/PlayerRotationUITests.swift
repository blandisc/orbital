import XCTest

/// El reproductor gira con el teléfono y «Bloquear» congela el giro hasta desbloquear.
final class PlayerRotationUITests: XCTestCase {
    private func isLandscape(_ app: XCUIApplication) -> Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
    }

    private func wait(_ app: XCUIApplication, landscape: Bool, timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if isLandscape(app) == landscape { return true }
            usleep(250_000)
        }
        return isLandscape(app) == landscape
    }

    func testThePlayerFollowsTheDeviceAndTheLockFreezesIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-appearance", "dark", "-demo-no-idle", "-demo-title", "series:tt0386676", "-demo-open", "play"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(9)
        XCTAssertTrue(wait(app, landscape: false), "abre como está el teléfono (vertical)")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait(app, landscape: false), "al poner el teléfono vertical, el video se pone vertical")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait(app, landscape: true), "y vuelve a horizontal")

        app.tap()
        let lock = app.buttons["player-lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.tap()
        sleep(1)
        XCUIDevice.shared.orientation = .portrait
        sleep(3)
        XCTAssertTrue(isLandscape(app), "bloqueado no gira")

        app.tap()
        let unlock = app.buttons["player-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.tap()
        XCTAssertTrue(wait(app, landscape: false), "al desbloquear sigue al teléfono")
    }
}
