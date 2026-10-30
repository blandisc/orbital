import XCTest

/// El Inicio nuevo con toques de verdad (modo demo, Cinemeta real): el selector de tipo esconde lo que es solo de series, y la
/// hoja de Canales busca y añade una serie. Deja capturas como adjuntos de la prueba.
final class HomeNewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-because", "-demo-airings", "-demo-tab", "0", "-demo-appearance", "dark", "-demo-no-idle"]
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    /// Baja hasta que aparezca el elemento (o se rinde).
    private func scrollTo(_ element: XCUIElement, tries: Int = 8) {
        for _ in 0..<tries where !element.isHittable { app.swipeUp(velocity: .slow) }
    }

    func testPeliculasEscondeCanales() {
        let edit = app.buttons["home-channels-edit"]
        scrollTo(edit)
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "Canales aparece con Todo")
        shot("canales")
        // Volver arriba y elegir Películas en la franja.
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        let filter = app.segmentedControls["home-kind-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.buttons["Películas"].tap()
        sleep(1)
        shot("peliculas")
        for _ in 0..<8 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(app.buttons["home-channels-edit"].exists, "con Películas no hay Canales")
    }

    func testBuscarYAnadirUnCanal() throws {
        let edit = app.buttons["home-channels-edit"]
        scrollTo(edit)
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        edit.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "la hoja tiene buscador")
        shot("hoja")
        search.tap()
        search.typeText("malcolm\n")   // buscar y bajar el teclado
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-tt'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "encuentra la serie y ofrece Añadir")
        shot("resultados")
        // El primero que se ve y que todavía no es canal (no uno escondido detrás del teclado).
        let add = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isHittable && !$0.isSelected })
        let row = app.buttons[add.identifier]
        add.tap()
        // Con el buscador activo, iOS usa el primer toque para cerrarlo: si no cambió, un segundo toque.
        sleep(1); shot("tras-toque")
        if !row.isSelected { row.tap(); sleep(1); shot("tras-segundo-toque") }
        XCTAssertTrue(row.isSelected, "ya es canal")
        shot("anadido")
    }

    func testElFiltroSeAbreDesdeInicio() {
        let door = app.buttons["home-filters"]
        XCTAssertTrue(door.waitForExistence(timeout: 20), "la puerta del filtro está en la franja")
        door.tap()
        XCTAssertTrue(app.descendants(matching: .any)["advanced-filter"].waitForExistence(timeout: 10), "se abre el cajón del filtro")
        shot("filtro")
    }
}
