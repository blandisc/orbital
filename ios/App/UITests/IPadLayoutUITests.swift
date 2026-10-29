import XCTest

/// El iPad (y la Mac «Diseñada para iPad»): la app en vertical y en horizontal, con lo principal a la vista. Guarda una
/// captura de cada pantalla en `ORBITAL_SHOTS` (o /tmp/orbital-shots); en horizontal sale girada (así las da XCUITest).
///   xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,name=Orbital QA iPad' \
///     -only-testing:OrbitalUITests/IPadLayoutUITests
/// En un iPhone no corre (allá la app es vertical y el giro lo prueba `PlayerRotationUITests`).
final class IPadLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "solo en iPad")
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func open(_ args: [String], _ orientation: UIDeviceOrientation) {
        app.terminate()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-demo", "-demo-no-idle"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(4)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/ipad-\(name).png"))
    }

    /// Las pestañas (arriba, con la barra lateral) en las dos orientaciones.
    func testTabsInBothOrientations() {
        for (orientation, tag) in [(UIDeviceOrientation.portrait, "v"), (.landscapeLeft, "h")] {
            open(["-demo-tab", "0"], orientation)
            // En vertical son botones de la barra de arriba; en horizontal, renglones de la barra lateral.
            let tab = { (name: String) in self.app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch }
            XCTAssertTrue(tab("Inicio").waitForExistence(timeout: 30), "\(tag): falta la pestaña Inicio")
            XCTAssertTrue(tab("Para ti").exists, "\(tag): falta la pestaña Para ti")
            shot("inicio-\(tag)")
            open(["-demo-tab", "1"], orientation)
            shot("parati-\(tag)")
        }
    }

    /// La ficha y sus acciones en horizontal (el arte no tapa el botón de ver).
    func testTitleInLandscape() {
        open(["-demo-tmdb", "-demo-title", "series:tt0386676"], .landscapeLeft)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continuar' OR label BEGINSWITH 'Ver'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "falta el botón de ver")
        XCTAssertTrue(play.isHittable, "el botón de ver queda fuera de la pantalla")
        shot("ficha-h")
    }

    /// «¿Qué vemos?» es una tarjeta de su alto (antes salía cortada a ~70 pt) y el control abre completo.
    func testSheetsAreFullSizeCards() {
        open(["-demo-tab", "1", "-demo-open", "decide"], .portrait)
        let shuffle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Barajar'")).firstMatch
        XCTAssertTrue(shuffle.waitForExistence(timeout: 40), "¿Qué vemos? no enseña «Barajar»")
        XCTAssertTrue(shuffle.isHittable, "«Barajar» queda cortado")
        shot("decidir-v")
        open(["-demo-tv-now", "-demo-open", "remote"], .landscapeLeft)
        let type = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Escribir en la TV' OR placeholderValue CONTAINS 'Escribir en la TV'")).firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 30), "el control no abre completo")
        shot("control-h")
    }

    /// El reproductor en horizontal (como se ve una película en el iPad).
    func testPlayerInLandscape() {
        open(["-demo-title", "series:tt0386676", "-demo-open", "play"], .landscapeLeft)
        sleep(8)
        app.tap()
        // Horizontal de verdad: el panel de «Audio y subtítulos» va a la derecha y no sale la rueda del modo iPod.
        XCTAssertFalse(app.descendants(matching: .any)["ipod-center"].exists, "en horizontal no va el modo iPod")
        shot("reproductor-h")
    }
}
