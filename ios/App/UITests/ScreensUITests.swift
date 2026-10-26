import XCTest

/// Lo que el usuario vio fallar en su iPhone, con la app de verdad en el simulador (modo demo).
final class ScreensUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Para ti › Listas con tu Orbital: el Top 10 de Netflix y las tendencias de Disney+ llevan la cifra grande.
    /// «Tus plataformas»: cada una en su tarjeta (Netflix y Disney+); al tocar Netflix, sus rankings con la cifra grande.
    func testPlatformsOpenTheirRankingsWithTheBigNumbers() {
        app.launchArguments = ["-demo", "-demo-console", "-demo-tab", "1", "-demo-mode", "lists", "-demo-no-idle"]
        app.launch()
        let netflix = app.buttons["platform-netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 20), "la tarjeta de Netflix")
        XCTAssertTrue(app.buttons["platform-disney"].waitForExistence(timeout: 10), "y la de Disney+")
        netflix.tap()
        let ranked = app.descendants(matching: .any).matching(identifier: "ranked-poster")
        XCTAssertTrue(ranked.firstMatch.waitForExistence(timeout: 20), "sus rankings, con la cifra grande")
    }

    /// Buscar › Explora: cada género con su imagen fija (sin esperar a la red) y al tocarlo, su lista aparece pronto.
    func testExploreGenresHaveArtAndOpenQuickly() {
        app.launchArguments = ["-demo", "-demo-tab", "2"]
        app.launch()
        let action = app.descendants(matching: .any)["art-tile-genre-action"]
        if !action.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(action.waitForExistence(timeout: 10), "el género Acción con su arte fijo")
        for genre in ["comedy", "drama", "scifi", "horror", "thriller"] {
            XCTAssertTrue(app.descendants(matching: .any)["art-tile-genre-\(genre)"].exists, "\(genre) con su arte")
        }
        action.tap()
        let start = Date()
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 15), "la lista del género aparece")
        print("GENRE-OPEN \(Date().timeIntervalSince(start)) s")
    }
    /// Buscar: la barra se ve al abrir, se esconde al bajar y vuelve al subir.
    func testSearchBarHidesOnScroll() {
        app.launchArguments = ["-demo", "-demo-tab", "2", "-demo-no-idle"]
        app.launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "la barra a la vista al abrir")
        XCTAssertTrue(field.isHittable)
        app.swipeUp()
        XCTAssertTrue(waitUntil { !field.exists || !field.isHittable || field.frame.width < 120 }, "al bajar, la barra se esconde")
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(waitUntil { field.exists && field.isHittable && field.frame.width > 200 }, "al subir, vuelve")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "sin teclado todavía")
    }

    /// Tocar la lupa dos veces (desde otra pestaña): el primer toque abre Buscar, el segundo el campo con el teclado.
    /// (También con la barra encogida: bajaste en Inicio y la lupa quedó sola a la derecha.)
    func testSecondTapOnSearchTabOpensTheField() { secondTapOpensTheField(minimized: false) }
    func testSecondTapOnMinimizedSearchTabOpensTheField() { secondTapOpensTheField(minimized: true) }

    private func secondTapOpensTheField(minimized: Bool) {
        app.launchArguments = ["-demo", "-demo-tab", "0", "-demo-free-tabs", "-demo-no-idle"]
        app.launch()
        if minimized { sleep(3); app.swipeUp(); sleep(1); shot("g-minimized") }
        let tab = app.tabBars.buttons["Buscar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "la lupa en la barra")
        // El mismo punto de la pantalla las dos veces (la lupa se vuelve el campo al abrir Buscar).
        let spot = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY))
        spot.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "abre Buscar")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "el primer toque no abre el teclado")
        spot.tap()
        let ok = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(ok, "el segundo toque abre el campo con el teclado")
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if check() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return check()
    }
}
