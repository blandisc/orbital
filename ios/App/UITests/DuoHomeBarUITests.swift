import XCTest

/// LD2-B (27 nov 2026): en la pantalla de afuera del Duo, Inicio va en el renglón de la hora: el logo, el control y tu foto a la
/// izquierda; la hora, la señal y la cámara a la derecha. Nada escondido en un botón «…», y los dos botones se tocan. En
/// cualquier otro iPhone (el 17 Pro) el encabezado sigue debajo de la hora, como siempre. Solo corre en iPhone.
final class DuoHomeBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "solo en iPhone")
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-appearance", "light"]
        app.launch()
    }

    private var duo: Bool {
        let f = app.windows.firstMatch.frame
        return f.height > f.width && f.width / f.height > 0.6
    }

    func testHomeSharesTheClockRowOnlyOnTheDuo() {
        let remote = app.buttons["home-remote"]
        XCTAssertTrue(remote.waitForExistence(timeout: 30), "el control, en el encabezado de Inicio")
        let profile = app.buttons["Ajustes"].firstMatch
        XCTAssertTrue(profile.exists, "y tu foto")
        let top = app.windows.firstMatch.frame.minY
        if duo {
            // El renglón de la hora mide ~50: los dos botones caben ahí, no debajo.
            XCTAssertLessThan(remote.frame.midY - top, 60, "en el Duo, el control va en el renglón de la hora")
            XCTAssertLessThan(profile.frame.midY - top, 60, "y tu foto también")
            XCTAssertFalse(app.buttons["Más"].exists, "nada escondido en «…»")
        } else {
            XCTAssertGreaterThan(remote.frame.midY - top, 60, "en los demás iPhone, el encabezado sigue debajo de la hora")
        }
        XCTAssertTrue(remote.isHittable)
        remote.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Pad de la TV"].waitForExistence(timeout: 10), "el control abre")
    }

    func testTheAvatarOpensSettings() {
        let profile = app.buttons["Ajustes"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 30))
        XCTAssertTrue(profile.isHittable, "tu foto se toca")
        profile.tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 10), "y abre Ajustes")
    }

    /// DK-B: al bajar, la barra de pestañas se encoge a un solo botón (la pestaña en la que estás); al subir, vuelve completa.
    func testTheTabBarShrinksWhenScrollingDown() {
        let explore = app.tabBars.buttons["Explorar"]
        XCTAssertTrue(explore.waitForExistence(timeout: 30), "la barra completa al abrir")
        XCTAssertTrue(explore.isHittable)
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(2)
        XCTAssertFalse(explore.exists && explore.isHittable, "al bajar, la barra se encoge a un botón")
        // Al subir con la mano (un deslizar con impulso, como el pulgar): iOS regresa la barra. Un arrastre lento sin soltar no
        // cuenta como «subir» para iOS (28 nov 2026: así fallaba esta prueba, no la app).
        for _ in 0..<3 where !(explore.exists && explore.isHittable) {
            app.swipeDown(velocity: .fast)
            sleep(2)
        }
        XCTAssertTrue(explore.exists && explore.isHittable, "al subir, vuelve completa")
    }

    /// HB1-B: el filtro de Inicio va en la esquina de la portada en todo iPhone (primero el Duo; desde el 27 nov también los
    /// demás, «lo más posible la misma aplicación»); se abre con los tres y filtra.
    func testTheKindFilterSitsOnTheHeroOnTheDuo() {
        let pill = app.buttons["kind-all"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "el filtro de Inicio")
        let top = app.windows.firstMatch.frame.minY
        XCTAssertGreaterThan(pill.frame.minY - top, 60, "sobre la portada (no en el renglón de arriba)")
        XCTAssertGreaterThan(pill.frame.midX, app.windows.firstMatch.frame.midX, "en su esquina derecha")
        XCTAssertFalse(app.navigationBars.buttons["kind-all"].exists, "y no se repite arriba")
        pill.tap()
        let movies = app.buttons["kind-movie"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5), "se abre con los tres")
        movies.tap()
        XCTAssertTrue(app.buttons["kind-movie"].firstMatch.waitForExistence(timeout: 5), "y se queda en Películas")
    }
}
