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
        app.launchArguments = ["-demo", "-demo-tab", "1", "-demo-appearance", "dark"] + (idle ? [] : ["-demo-no-idle"])
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
        let tile = tiles.element(boundBy: 2)
        XCTAssertTrue(tile.isHittable)
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
        let tile = tiles.element(boundBy: 4)
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
}
