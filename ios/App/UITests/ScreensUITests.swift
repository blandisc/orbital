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

    /// Descargas vacía: no hay nada que bajar, así que deslizar no mueve nada (antes el título se encogía).
    func testEmptyDownloadsDoesNotScroll() {
        app.launchArguments = ["-demo", "-demo-tab", "3", "-demo-no-idle"]
        app.launch()
        let empty = app.staticTexts["Nada descargado"]
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "el vacío de Descargas")
        let title = app.navigationBars.staticTexts["Descargas"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "el título")
        sleep(1)
        let before = title.frame
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.5)
        XCTAssertEqual(title.frame, before, "el título se queda igual mientras deslizas")
    }

    /// Mi media con poco (o nada): si todo cabe, deslizar no mueve nada ni encoge el título (antes rebotaba siempre).
    func testShortMiMediaDoesNotScroll() {
        for drive in ["linked", "unlinked"] {
            app.launchArguments = ["-demo", "-demo-tab", "3", "-demo-media", "-demo-onedrive", drive, "-demo-no-idle"]
            app.launch()
            let title = app.navigationBars.staticTexts["Descargas"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 20), "el título (\(drive))")
            sleep(3)
            let before = title.frame
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.5)
            XCTAssertEqual(title.frame, before, "el título se queda igual (\(drive))")
            app.terminate()
        }
    }

    /// Buscar: al bajar despacio (como con el dedo, a 120 cuadros por segundo cada cuadro avanza poco), la barra se va igual.
    func testSearchBarHidesOnSlowScroll() {
        app.launchArguments = ["-demo", "-demo-tab", "2", "-demo-no-idle"]
        app.launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "la barra a la vista al abrir")
        sleep(2)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 300, thenHoldForDuration: 0.3)
        XCTAssertTrue(waitUntil { !field.exists || !field.isHittable || field.frame.width < 120 }, "al bajar despacio, la barra se esconde")
    }

    /// Buscar con el campo abierto (vacío o con algo escrito): al bajar, la barra se esconde igual (antes se quedaba fija).
    func testOpenFieldHidesOnScroll() { openFieldHidesOnScroll(typing: nil) }
    func testTypedFieldHidesOnScroll() { openFieldHidesOnScroll(typing: "the") }

    private func openFieldHidesOnScroll(typing text: String?) {
        app.launchArguments = ["-demo", "-demo-tab", "0", "-demo-free-tabs", "-demo-no-idle"]
        app.launch()
        let tab = app.tabBars.buttons["Buscar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "la lupa en la barra")
        sleep(2)   // que termine de llegar Inicio
        let spot = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY))
        spot.tap(); Thread.sleep(forTimeInterval: 0.3); spot.tap()   // dos toques seguidos
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "el campo con el teclado")
        if let text { app.typeText(text); sleep(4) }
        let field = app.searchFields.firstMatch
        app.swipeUp(); sleep(1); app.swipeUp()
        XCTAssertTrue(waitUntil { !field.exists || !field.isHittable || field.frame.width < 120 }, "al bajar, la barra se esconde")
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
