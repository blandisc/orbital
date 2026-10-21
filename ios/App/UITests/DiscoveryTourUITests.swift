import XCTest

/// Recorre las pantallas de descubrir (Persona, Género, Los Simpson, rankings, «Ver todo», Para ti) y guarda una captura
/// de cada una en `ORBITAL_SHOTS` (o /tmp/orbital-shots) para revisarlas en varios tamaños. Solo navega: no falla si una
/// pantalla no aparece (lo dice la captura).
final class DiscoveryTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        sleep(3)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    private func launch(_ args: [String]) {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-no-idle"] + args
        app.launch()
    }

    func testTour() {
        // Buscar › Género y «Lo más popular hoy» › Ver todo.
        launch(["-demo-tab", "2"])
        shot("browse")
        let seeAll = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver todo'")).firstMatch
        if seeAll.waitForExistence(timeout: 15) { seeAll.tap(); shot("popular-all"); app.navigationBars.buttons.firstMatch.tap() }
        let action = app.descendants(matching: .any)["art-tile-genre-action"]
        if !action.waitForExistence(timeout: 5) { app.swipeUp() }
        if action.waitForExistence(timeout: 10) { action.tap(); _ = app.buttons["title-link"].firstMatch.waitForExistence(timeout: 15); shot("genre") }

        // Persona (TMDB de mentira: Steve Carell).
        launch(["-demo-tmdb", "-demo-title", "series:tt0386676"])
        let face = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Steve Carell'")).firstMatch
        for _ in 0..<6 where !face.isHittable { app.swipeUp() }
        if face.exists { face.tap(); shot("person") }

        // Inicio › Los Simpson.
        launch(["-demo-tab", "0"])
        let donut = app.buttons["home-random-simpsons"]
        if donut.waitForExistence(timeout: 15) { donut.tap(); shot("simpsons") }

        // Para ti: encabezado, «Porque viste», rankings de una plataforma y un «Ver todo» de estante.
        launch(["-demo-console", "-demo-because", "-demo-tab", "1", "-demo-mode", "lists"])
        shot("parati")
        launch(["-demo-console", "-demo-tab", "1", "-demo-mode", "lists"])
        let netflix = app.buttons["platform-netflix"]
        if netflix.waitForExistence(timeout: 20) { netflix.tap(); shot("platform") }
        launch(["-demo-console", "-demo-tab", "1", "-demo-mode", "lists"])
        let shelfAll = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver todo'")).firstMatch
        if shelfAll.waitForExistence(timeout: 20) { shelfAll.tap(); shot("shelf-all") }
        launch(["-demo-tab", "1", "-demo-mode", "mosaic"])
        shot("parati-mosaic")
    }

    /// «Porque viste» deslizado hasta que se ve entero (sus flechas no deben quedar bajo la barra de pestañas).
    func testBecause() {
        launch(["-demo-console", "-demo-because", "-demo-tab", "1", "-demo-mode", "lists"])
        let because = app.descendants(matching: .any)["because-deck"]
        _ = because.waitForExistence(timeout: 20)
        for _ in 0..<8 where !because.isHittable { app.swipeUp(velocity: .slow) }
        shot("because")
        app.swipeUp()
        shot("because-2")
    }
}
