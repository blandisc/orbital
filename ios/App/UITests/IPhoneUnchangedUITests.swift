import XCTest

/// Lo que se hizo para el iPad y la Mac no cambia el iPhone (`docs/producto/ipad-y-mac-2026-10.md`): el control es la hoja
/// de siempre (no el panel), Buscar enseña dos géneros por renglón y la ficha y Ajustes van a todo lo ancho (sin el margen
/// de lectura). Guarda una captura de cada una en `ORBITAL_SHOTS` (o /tmp/orbital-shots). En un iPad no corre.
final class IPhoneUnchangedUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }
    private var width: CGFloat { app.windows.firstMatch.frame.width }

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "solo en iPhone")
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    private func open(_ args: [String]) {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-no-idle"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(2)
        let device = "\(Int(width))x\(Int(app.windows.firstMatch.frame.height))"
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/iphone-\(device)-\(name).png"))
    }

    func testTheRemoteIsTheUsualSheet() {
        open(["-demo-tv-now", "-demo-open", "remote-full"])
        let type = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Escribir en la TV' OR placeholderValue CONTAINS 'Escribir en la TV'")).firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 30), "el control completo no abre")
        XCTAssertFalse(app.buttons["remote-panel-close"].exists, "en el iPhone el control no es el panel del iPad")
        shot("control")
    }

    func testBrowseShowsTwoGenresPerRow() {
        open(["-demo-tab", "2"])
        let action = app.descendants(matching: .any)["art-tile-genre-action"], comedy = app.descendants(matching: .any)["art-tile-genre-comedy"]
        let drama = app.descendants(matching: .any)["art-tile-genre-drama"]
        if !action.waitForExistence(timeout: 20) { app.swipeUp() }
        XCTAssertTrue(drama.waitForExistence(timeout: 20), "no salen los géneros")
        XCTAssertEqual(action.frame.minY, comedy.frame.minY, accuracy: 2, "Acción y Comedia en el mismo renglón")
        XCTAssertGreaterThan(drama.frame.minY, action.frame.maxY - 2, "Drama ya en el siguiente: dos por renglón")
        XCTAssertGreaterThan(action.frame.width, width * 0.4, "cada género ocupa casi la mitad del ancho")
        shot("buscar")
        // Tocar un género abre su lista (las piezas del catálogo son enfocables para el teclado del iPad: el toque sigue igual).
        action.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 15), "tocar un género ya no abre su lista")
    }

    func testTitleAndSettingsUseTheFullWidth() {
        open(["-demo-tmdb", "-demo-title", "series:tt0386676"])
        let play = app.buttons["title-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30), "falta el botón de ver")
        XCTAssertGreaterThan(play.frame.width, width - 80, "el botón de ver va casi de orilla a orilla (sin margen de lectura)")
        shot("ficha")
        open(["-demo-open", "settings"])
        let profile = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Tu perfil'")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 30), "Ajustes no abre")
        XCTAssertLessThan(profile.frame.minX, 60, "Ajustes con sus márgenes de siempre")
        shot("ajustes")
    }
}
