import XCTest

/// El mosaico de «Para ti» con gestos de verdad (como un dedo en el iPhone), en el modo demo: arrastrar lo baja (también
/// con una pieza elegida y con un deslizamiento corto, por la inercia) y quieto se mueve solo. Mide dónde quedó una pieza
/// concreta, no el modelo.
final class MosaicUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Con `idle: false` el mosaico no se mueve solo: lo que se mida es solo del dedo.
    private func launch(idle: Bool = false) {
        app.launchArguments = ["-demo", "-demo-tab", "1", "-demo-mode", "mosaic", "-demo-appearance", "dark"] + (idle ? [] : ["-demo-no-idle"])
        app.launch()
        XCTAssertTrue(mosaic.waitForExistence(timeout: 20), "el mosaico aparece")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20), "con piezas")
        sleep(2)
    }

    private var mosaic: XCUIElement { app.otherElements["mosaic"] }
    private var tiles: XCUIElementQuery { app.buttons.matching(identifier: "mosaic-tile") }

    /// Una pieza a media pantalla de la columna del centro, y dónde está.
    private func probe() -> (label: String, x: CGFloat, y: CGFloat) {
        let area = mosaic.frame
        let middle = tiles.allElementsBoundByIndex
            .filter { $0.frame.midY > area.minY + area.height * 0.3 && $0.frame.midY < area.maxY - area.height * 0.2 }
            .min { abs($0.frame.midX - area.midX) < abs($1.frame.midX - area.midX) }
        let tile = middle ?? tiles.firstMatch
        return (tile.label, tile.frame.midX, tile.frame.midY)
    }

    /// Cuánto subió esa pieza (la de la misma columna con ese nombre); si ya no está, subió más que la pantalla.
    private func rise(of p: (label: String, x: CGFloat, y: CGFloat)) -> CGFloat {
        let same = tiles.allElementsBoundByIndex.filter { $0.label == p.label && abs($0.frame.midX - p.x) < 20 }
        guard let now = same.min(by: { abs($0.frame.midY - p.y) < abs($1.frame.midY - p.y) }) else { return .infinity }
        return p.y - now.frame.midY
    }

    private func drag(fromY: CGFloat, toY: CGFloat, hold: TimeInterval = 0.05, velocity: XCUIGestureVelocity = .default) {
        let start = mosaic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = mosaic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: hold, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0)
    }

    /// «Pasear por el mosaico» desde Listas, volver a Listas y entrar otra vez: el mosaico vuelve a tener piezas (el error
    /// del 31 oct 2026: la segunda vez ya no cargaba).
    func testWalkTheMosaicTwice() {
        app.launchArguments = ["-demo", "-demo-tab", "1", "-demo-mode", "lists", "-demo-appearance", "dark", "-demo-no-idle"]
        app.launch()
        let walk = app.buttons["paraTi-walk-mosaic"]
        for round in 1...2 {
            XCTAssertTrue(walk.waitForExistence(timeout: 20), "el botón de pasear (vuelta \(round))")
            walk.tap()
            XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20), "el mosaico tiene piezas (vuelta \(round))")
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "mosaico-\(round)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["paraTi-mode"].tap()
        }
    }

    /// Fernando, 31 oct 2026: «entras y sales y se queda negro». Con la animación de reposo (como en su iPhone): entrar,
    /// esperar a que se ponga en reposo, salir (a las listas, a otra pestaña, a una ficha) y volver.
    func testMosaicComesBackAfterLeaving() {
        app.launchArguments = ["-demo", "-demo-tab", "1", "-demo-mode", "lists", "-demo-appearance", "dark"]
        app.launch()
        let walk = app.buttons["paraTi-walk-mosaic"]
        func snap(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(walk.waitForExistence(timeout: 20)); walk.tap()
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20)); sleep(9); snap("1-reposo")
        app.buttons["paraTi-back"].tap(); sleep(1)
        XCTAssertTrue(walk.waitForExistence(timeout: 10)); walk.tap(); sleep(2); snap("2-vuelta-listas")
        app.tabBars.buttons.element(boundBy: 0).tap(); sleep(2)
        app.tabBars.buttons.element(boundBy: 1).tap(); sleep(2); snap("3-vuelta-pestana")
        if let tile = tiles.allElementsBoundByIndex.first(where: \.isHittable) { tile.tap(); sleep(1); tile.tap(); sleep(3)
            app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(2); snap("4-vuelta-ficha") }
    }

    /// El muro de pósters detrás de «Para ti» sigue ahí después de pasear por el mosaico (se quedaba negro).
    func testCoverWallAfterWalking() {
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-tmdb", "-demo-tab", "1", "-demo-mode", "lists", "-demo-appearance", "dark"]
        app.launch()
        let walk = app.buttons["paraTi-walk-mosaic"]
        func snap(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(walk.waitForExistence(timeout: 30)); sleep(3); snap("a-listas")
        walk.tap(); XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20)); sleep(3)
        app.buttons["paraTi-back"].tap(); sleep(3); snap("b-de-vuelta")
        sleep(5); snap("c-despues")
    }

    func testDraggingUpScrollsTheMosaicDown() {
        launch()
        let p = probe()
        drag(fromY: 0.8, toY: 0.3)
        sleep(1)
        XCTAssertGreaterThan(rise(of: p), 150, "al arrastrar hacia arriba el mosaico baja")
        let q = probe()
        drag(fromY: 0.8, toY: 0.3)
        sleep(1)
        XCTAssertGreaterThan(rise(of: q), 150, "y sigue bajando (no se atora tras el primer arrastre)")
    }

    func testAfterChoosingATileTheMosaicStillScrolls() {
        launch()
        // La primera que se puede tocar (en un SE la tercera puede quedar bajo la franja o fuera de la pantalla).
        guard let tile = tiles.allElementsBoundByIndex.dropFirst().first(where: \.isHittable) else { return XCTFail("ninguna pieza a la vista") }
        tile.tap()   // la elige (un segundo toque la abriría)
        sleep(1)
        let p = probe()
        drag(fromY: 0.8, toY: 0.3)
        sleep(1)
        XCTAssertGreaterThan(rise(of: p), 150, "con una pieza elegida, arrastrar también baja el mosaico (no se queda pegado)")
        XCTAssertTrue(mosaic.exists, "y no abrió la ficha")
    }

    func testDraggingThatStartsOnTheChosenTileScrolls() {
        launch()
        // Una pieza a media pantalla (las piezas van por columnas: un índice fijo puede quedar fuera de la vista).
        let screen = app.windows.firstMatch.frame
        guard let tile = tiles.allElementsBoundByIndex.first(where: { $0.frame.midY > screen.height * 0.35 && $0.frame.midY < screen.height * 0.6 }) else {
            return XCTFail("no hay una pieza a media pantalla")
        }
        tile.tap()
        sleep(1)
        let p = probe()
        let from = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)))
        sleep(1)
        XCTAssertGreaterThan(rise(of: p), 150, "arrastrar desde la pieza elegida baja el mosaico")
        XCTAssertTrue(mosaic.exists, "y no la abre")
    }

    func testAQuickFlickKeepsGoing() {
        launch()
        let p = probe()
        let finger = mosaic.frame.height * 0.15
        drag(fromY: 0.7, toY: 0.55, hold: 0.01, velocity: .fast)
        sleep(2)
        XCTAssertGreaterThan(rise(of: p), finger * 1.4, "un deslizamiento corto y rápido sigue con inercia, más allá de lo que movió el dedo")
    }

    func testIdleTheMosaicMovesByItself() {
        launch(idle: true)
        let p = probe()
        sleep(8)
        XCTAssertGreaterThan(rise(of: p), 20, "quieto unos segundos, el mosaico sube solo")
    }

    /// Elegida una pieza, su pie dice cómo abrir la ficha («Más › Ver la ficha», y tocar su nombre); «Ver en la TV» avisa al
    /// tocar y confirma, y el aviso sale encima del pie (antes lo tapaba).
    func testTheChosenTileOpensItsPageAndSendsToTheTV() {
        launch()
        guard let tile = tiles.allElementsBoundByIndex.dropFirst().first(where: \.isHittable) else { return XCTFail("ninguna pieza a la vista") }
        tile.tap()
        let caption = app.descendants(matching: .any).matching(identifier: "mosaic-caption-open").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "el pie de la elegida")
        app.buttons["Más"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Ver la ficha"].waitForExistence(timeout: 5), "«Más» trae la ficha")
        XCTAssertTrue(app.buttons["Ver en la TV"].exists)
        app.buttons["Ver en la TV"].tap()
        let sent = app.staticTexts["Ya está en tu Orbital"]
        XCTAssertTrue(sent.waitForExistence(timeout: 8), "confirma que llegó a la TV")
        shot("mosaico-aviso")
        XCTAssertLessThan(sent.frame.maxY, caption.frame.minY, "el aviso va encima del pie, no sobre sus botones")
        app.buttons["Más"].firstMatch.tap()
        app.buttons["Ver la ficha"].tap()
        XCTAssertTrue(mosaic.waitForNonExistence(timeout: 5), "abrió la ficha")
        shot("mosaico-ficha")
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] else { return }
        try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
