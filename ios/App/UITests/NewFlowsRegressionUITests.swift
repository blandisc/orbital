import XCTest

/// Regresión de los flujos nuevos (Inicio nuevo, Para ti B, el mazo, el filtro avanzado, Lo que ves y el Wrapped,
/// Colecciones, calificar y el cielo), con toques de verdad en modo demo. Se corre en un iPhone grande y en el SE.
/// (Lo de Canales, la portada del mosaico, «La temporada» y «Tuyo» ya lo cubren HomeNewUITests y ParaTiBUITests.)
final class NewFlowsRegressionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false }

    private func launch(tab: Int, _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because", "-demo-tab", "\(tab)",
                               "-demo-mode", "lists", "-demo-appearance", "dark", "-demo-no-idle"] + extra
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// Baja hasta que el elemento se puede tocar (o se rinde a las 25 vueltas).
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<25 where !element.exists || !element.isHittable { app.swipeUp(velocity: .slow) }
    }

    // MARK: Inicio

    /// Inicio de arriba abajo: la franja del tipo, «Lo nuevo de lo tuyo» (con su calendario), «Por lo que viste» y Canales.
    func testInicioDeArribaAbajo() {
        launch(tab: 0)
        XCTAssertTrue(any("home-kind-filter").waitForExistence(timeout: 20), "la franja del tipo")
        XCTAssertTrue(app.buttons["home-filters"].exists, "la puerta del filtro")
        shot("inicio-arriba")
        let calendar = app.buttons["release-calendar"]
        scrollTo(calendar)
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), "«Lo nuevo de lo tuyo» con su calendario")
        shot("inicio-lo-nuevo")
        calendar.tap()
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 10))
        shot("calendario")
        app.swipeDown(velocity: .fast)   // cierra la hoja
        let because = any("because-deck")
        scrollTo(because)
        XCTAssertTrue(because.waitForExistence(timeout: 10), "«Por lo que viste»")
        let channels = app.buttons["home-channels-edit"]
        scrollTo(channels)
        XCTAssertTrue(channels.waitForExistence(timeout: 10), "Canales")
        shot("inicio-canales")
    }

    /// El filtro avanzado desde Inicio hasta abrir una ficha.
    func testFiltroAvanzadoHastaUnaFicha() {
        launch(tab: 0)
        let door = app.buttons["home-filters"]
        XCTAssertTrue(door.waitForExistence(timeout: 20))
        door.tap()
        XCTAssertTrue(any("advanced-filter").waitForExistence(timeout: 10), "se abre el cajón")
        let results = app.buttons["filter-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10), "«Ver resultados»")
        shot("filtro")
        results.tap()
        let first = app.buttons["filter-result"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "llegan resultados")
        shot("filtro-resultados")
        first.tap()
        XCTAssertTrue(app.buttons["title-save"].waitForExistence(timeout: 20), "se abre la ficha")
        shot("filtro-ficha")
    }

    /// La pastilla de calificar sale con lo que terminaste hace poco, y la ✕ la quita.
    func testCalificarYQuitarLaPastilla() {
        launch(tab: 0, ["-demo-rate"])
        let pill = any("rating-reminder")
        XCTAssertTrue(pill.waitForExistence(timeout: 20), "sale la pastilla de calificar")
        shot("calificar")
        app.buttons["rating-reminder-dismiss"].tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), "la ✕ la quita")
    }

    // MARK: Para ti

    /// «¿Qué vemos hoy?»: el mazo guarda, descarta, se desliza y se cierra.
    func testElMazoGuardaDescartaYSeCierra() {
        launch(tab: 1)
        let card = app.buttons["paraTi-match"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let deck = any("match-deck")
        XCTAssertTrue(deck.waitForExistence(timeout: 10), "se abre el mazo")
        shot("mazo")
        app.buttons["match-save"].tap()
        app.buttons["match-discard"].tap()
        deck.swipeLeft(velocity: .fast)
        deck.swipeRight(velocity: .fast)
        XCTAssertTrue(app.buttons["match-close"].exists, "sigue el mazo tras pasar cuatro cartas")
        shot("mazo-tras-cartas")
        app.buttons["match-close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "se cierra y vuelve a Para ti")
    }

    /// «Decide por mí» abre el sorteo (en un iPhone angosto vive en el menú del índice).
    func testDecidePorMiAbreElSorteo() {
        launch(tab: 1)
        XCTAssertTrue(app.buttons["paraTi-match"].waitForExistence(timeout: 20))
        let dice = app.buttons["Decide por mí"]
        if dice.exists && dice.isHittable { dice.tap() } else {
            app.buttons["paraTi-sections"].tap()
            app.buttons["Decide por mí"].tap()
        }
        XCTAssertTrue(app.buttons["decide-watch"].waitForExistence(timeout: 15), "se abre el sorteo, no el mazo")
        XCTAssertFalse(any("match-deck").exists)
        shot("decide")
    }

    /// Un círculo del índice baja a su grupo.
    func testUnCirculoBajaASuGrupo() {
        launch(tab: 1)
        let circle = app.buttons["Temporadas"].firstMatch
        XCTAssertTrue(circle.waitForExistence(timeout: 20))
        circle.tap()
        XCTAssertTrue(app.buttons["season-now"].waitForExistence(timeout: 10), "llega a Temporadas")
        shot("circulo-temporadas")
    }

    /// Lo que ves (con el cielo detrás) abre el Wrapped y se cierra.
    func testLoQueVesYElWrapped() {
        launch(tab: 1, ["-demo-open", "watching"])
        let wrapped = app.buttons["watching-wrapped"]
        XCTAssertTrue(wrapped.waitForExistence(timeout: 20), "«Lo que ves»")
        shot("lo-que-ves")
        wrapped.tap()
        XCTAssertTrue(any("wrapped").waitForExistence(timeout: 10), "se abre el Wrapped")
        shot("wrapped")
        app.buttons["wrapped-close"].tap()
        XCTAssertTrue(wrapped.waitForExistence(timeout: 10), "vuelve a «Lo que ves»")
    }

    /// Colecciones (la repisa del canon) abre.
    func testColeccionesAbre() {
        launch(tab: 1, ["-demo-open", "repisa"])
        let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'repisa-'")).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 20), "se abre Colecciones con sus colecciones")
        shot("colecciones")
        shelf.tap()
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 10), "abre una colección")
        shot("coleccion")
    }

    /// Buscar con el cielo detrás se usa normal: se abre el campo y se escribe.
    func testBuscarConCielo() {
        launch(tab: 2)
        XCTAssertTrue(app.navigationBars["Buscar"].waitForExistence(timeout: 20))
        let field = app.searchFields.firstMatch
        if !field.exists { app.tabBars.buttons["Buscar"].tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "el campo de búsqueda")
        field.tap()
        field.typeText("dune")
        shot("buscar")
    }
}
