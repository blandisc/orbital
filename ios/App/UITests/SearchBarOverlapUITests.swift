import XCTest

/// Buscar: al subir por la página, el campo de búsqueda (que regresa con la barra de arriba) no se pone encima de los
/// filtros (Fernando, 13 nov 2026: «cuando ves para arriba, no se ponga el buscador encima de los filtros»).
final class SearchBarOverlapUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        // Copia en disco para revisarla sin abrir el xcresult (`ORBITAL_SHOTS`, carpeta de la Mac).
        if let dir = ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    func testElCampoNoTapaLosFiltrosAlSubir() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-no-idle", "-demo-tab", "2"]
        app.launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Buscar abre con su campo")
        sleep(2)
        shot(app, "0-arriba")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        // Bajar bastante, luego subir un poco (la barra regresa).
        start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1)
        start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1); shot(app, "1-abajo")
        let up = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        up.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        sleep(1); shot(app, "2-subiendo")
        up.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        sleep(1); shot(app, "3-mas-arriba")
        up.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        sleep(1); shot(app, "4-hasta-arriba")
        // Lo que se ve bajo el campo no queda tapado: ningún elemento tocable empieza por arriba de su orilla de abajo.
        if field.exists && field.isHittable {
            let covered = app.buttons.allElementsBoundByIndex.filter { b in
                b.isHittable && b.frame.minY < field.frame.maxY - 2 && b.frame.maxY > field.frame.maxY + 2 && b.frame.minY > field.frame.minY
            }
            XCTAssertTrue(covered.isEmpty, "botones tapados por el campo: \(covered.map { $0.identifier + "/" + $0.label })")
        }
    }
}
