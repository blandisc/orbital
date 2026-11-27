import XCTest

/// HB1 (en prueba, 27 nov 2026): las dos formas de poner el filtro de Inicio y Ajustes en el Duo cerrado, tocadas de verdad.
/// Guarda capturas en `ORBITAL_SHOTS` (o /tmp/orbital-shots). Solo en el Duo (iPhone ancho y bajo).
final class HB1CaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    private func open(_ option: String) throws {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-appearance", "light", "-demo-hb", option]
        app.launch()
        let f = app.windows.firstMatch.frame
        try XCTSkipUnless(f.height > f.width && f.width / f.height > 0.6, "solo en el Duo")
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        sleep(2)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/hb1-\(name).png"))
    }

    func testA_ProfileMenuHasTheFilterAndSettings() throws {
        try open("a")
        let menu = app.buttons["home-profile-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "tu foto, con su globo")
        XCTAssertTrue(app.buttons["home-remote"].isHittable, "el control sigue a un toque")
        shot("a-reposo")
        menu.tap()
        let movies = app.buttons["kind-movie"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5), "el globo trae el filtro")
        shot("a-abierto")
        movies.tap()
        sleep(2)
        shot("a-peliculas")
        app.buttons["home-profile-menu"].tap()
        let settings = app.buttons["home-profile-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "y Ajustes")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 10), "Ajustes abre")
    }

    func testB_FilterSitsOnTheHero() throws {
        try open("b")
        let pill = app.buttons["kind-all"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "la pastilla del tipo, en la portada")
        XCTAssertTrue(app.buttons["home-remote"].isHittable, "el control sigue a un toque")
        XCTAssertTrue(app.buttons["Ajustes"].firstMatch.isHittable, "y tu foto")
        shot("b-reposo")
        pill.tap()
        let movies = app.buttons["kind-movie"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5), "se abre con los tres")
        usleep(600_000)
        shot("b-abierto")
        movies.tap()
        sleep(3)
        shot("b-peliculas")
    }
}
