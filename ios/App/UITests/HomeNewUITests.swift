import XCTest

/// El Inicio nuevo con toques de verdad (modo demo, Cinemeta real): el selector de tipo esconde lo que es solo de series, y la
/// hoja de Canales busca y añade una serie. Deja capturas como adjuntos de la prueba.
final class HomeNewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-because", "-demo-airings", "-demo-tab", "0", "-demo-appearance", "dark", "-demo-no-idle"]
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

    /// «Añadir canal» va al final del renglón de Canales (17 nov 2026): baja hasta el renglón y lo desliza de lado.
    private func reachAddChannel() -> XCUIElement {
        let add = app.buttons["home-channels-add"]
        let head = app.staticTexts["Canales"].firstMatch
        for _ in 0..<25 where !(head.exists && head.frame.minY > 80 && head.frame.maxY < app.frame.height * 0.55) { app.swipeUp(velocity: .slow) }
        let onScreen = { add.exists && !add.frame.isEmpty && self.app.frame.insetBy(dx: 8, dy: 8).contains(CGPoint(x: add.frame.midX, y: add.frame.midY)) }
        for _ in 0..<8 where !onScreen() {
            let y = (head.frame.maxY + 90) / app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: y)))
        }
        return add
    }

    func testPeliculasEscondeCanales() {
        let edit = reachAddChannel()
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "Canales aparece con Todo")
        shot("canales")
        // Volver arriba y elegir Películas en la franja.
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        // La pastilla del tipo (`KindPill`): recogida dice lo que ves; tocarla la abre con los tres.
        let all = app.buttons["kind-all"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 10), "la pastilla del tipo de Inicio")
        all.tap()
        let movies = app.buttons["kind-movie"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5), "abierta, con Películas")
        movies.tap()
        sleep(1)
        shot("peliculas")
        for _ in 0..<8 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(app.buttons["home-channels-add"].exists, "con Películas no hay Canales")
    }

    func testBuscarYAnadirUnCanal() throws {
        let edit = reachAddChannel()
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

    /// Revisión del 28 nov: quitar un canal en «Tus canales» lo deja en su lugar con «+» mientras la hoja sigue abierta; un
    /// toque más lo regresa (antes desaparecía y solo se podía buscar otra vez).
    func testQuitarUnCanalSePuedeRegresarSinBuscarlo() {
        let edit = reachAddChannel()
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        edit.tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-pick-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "tus canales en la hoja")
        let id = first.identifier
        let pick = app.buttons[id]
        XCTAssertEqual(pick.value as? String, "Es canal")
        pick.tap()
        sleep(1)
        XCTAssertTrue(pick.exists, "se queda en su lugar")
        XCTAssertEqual(pick.value as? String, "No es canal")
        shot("quitado")
        pick.tap()
        sleep(1)
        XCTAssertEqual(pick.value as? String, "Es canal", "un toque más lo regresa")
    }

    func testInicioYaNoTieneFiltro() {
        XCTAssertTrue(app.descendants(matching: .any)["home-kind-filter"].waitForExistence(timeout: 20), "la franja del tipo")
        XCTAssertFalse(app.buttons["home-filters"].exists, "el filtro vive en Buscar, no en Inicio")
    }
}
