import XCTest

/// «Sugerencias para ti» en Inicio se desliza y sus pósters se tocan (Fernando, 31 oct 2026: «no puedo picarle a las
/// películas que salen»). El fondo desenfocado de «Por lo que viste», agrandado, se subía encima de la fila y se comía los
/// toques.
final class HomePicksUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSugerenciasParaTiSeDeslizaYSeToca() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because", "-demo-tab", "0",
                               "-demo-mode", "lists", "-demo-appearance", "dark", "-demo-no-idle"]
        app.launch()
        let head = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Sugerencias para ti'")).firstMatch
        for _ in 0..<15 where !(head.exists && head.isHittable && head.frame.minY < app.frame.height * 0.35) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(head.waitForExistence(timeout: 5), "la fila está")
        let row = app.buttons.matching(identifier: "title-link").allElementsBoundByIndex
            .filter { $0.frame.minY > head.frame.maxY && $0.frame.minY < head.frame.maxY + 60 }
        guard let first = row.first else { return XCTFail("no hay pósters bajo «Sugerencias para ti»") }
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "fila"; a.lifetime = .keepAlways; add(a)
        // Deslizar desde la parte baja del póster (donde se encimaba el fondo de abajo).
        let y = first.frame.minY + first.frame.height * 0.8
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let before = first.frame.minX
        origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: y)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: y)))
        sleep(1)
        XCTAssertLessThan(first.frame.minX, before - 40, "la fila se desliza (antes \(before), después \(first.frame.minX))")
        // Tocar un póster a la vista, también abajo, abre su ficha.
        guard let visible = app.buttons.matching(identifier: "title-link").allElementsBoundByIndex
            .first(where: { abs($0.frame.minY - first.frame.minY) < 4 && $0.frame.minX > 0 && $0.frame.maxX < app.frame.width }) else { return XCTFail("sin póster a la vista") }
        origin.withOffset(CGVector(dx: visible.frame.midX, dy: visible.frame.minY + visible.frame.height * 0.8)).tap()
        XCTAssertTrue(app.buttons["title-save"].waitForExistence(timeout: 15), "se abre la ficha")
    }
}
