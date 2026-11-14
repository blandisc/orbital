import XCTest

/// «Decide por mí»: de «Una por una» se puede regresar a «Tres que caben», ida y vuelta varias veces y también después de
/// arrastrar una carta (Fernando, 13 nov 2026, la 2291: «ya no deja regresar»). Y la puerta de Inicio abre la hoja ahí mismo.
final class DecideTabsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because",
                               "-demo-appearance", "dark", "-demo-no-idle"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testLasPestanasVanYRegresan() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        let trioTab = app.buttons["Tres que caben"], deckTab = app.buttons["Una por una"]
        XCTAssertTrue(deckTab.waitForExistence(timeout: 30), "la hoja de Decide abre")
        let shuffle = app.descendants(matching: .any).matching(identifier: "decide-shuffle").firstMatch
        let deck = app.descendants(matching: .any).matching(identifier: "match-deck").firstMatch
        XCTAssertTrue(shuffle.waitForExistence(timeout: 15), "empieza en «Tres que caben»")
        for round in 1...3 {
            deckTab.tap()
            XCTAssertTrue(deck.waitForExistence(timeout: 8), "vuelta \(round): llega a «Una por una»")
            if round == 2 {
                // Arrastrar una carta y soltarla antes del umbral (regresa), y luego regresar de pestaña.
                let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                mid.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.56)), withVelocity: .slow, thenHoldForDuration: 0)
                sleep(1)
            }
            shot(app, "mazo-\(round)")
            XCTAssertTrue(trioTab.waitForExistence(timeout: 4) && trioTab.isHittable, "vuelta \(round): «Tres que caben» se puede tocar")
            trioTab.tap()
            XCTAssertTrue(shuffle.waitForExistence(timeout: 8), "vuelta \(round): regresa a «Tres que caben»")
            shot(app, "trio-\(round)")
        }
    }

    /// De «Una por una» a «Tres que caben» con la carta que veías (Fernando, 13 nov 2026: «mejor la transición del póster»):
    /// después de pasar dos cartas, al regresar la de arriba queda elegida entre los tres (se encoge hasta su cartel).
    func testLaCartaQueVeiasQuedaElegidaEntreLosTres() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        let trioTab = app.buttons["Tres que caben"], deckTab = app.buttons["Una por una"]
        XCTAssertTrue(deckTab.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["decide-shuffle"].waitForExistence(timeout: 15))
        deckTab.tap()
        let pass = app.descendants(matching: .any)["match-discard"].firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 8), "el mazo con su «Paso»")
        for _ in 0..<2 { pass.tap(); sleep(1) }
        let info = app.descendants(matching: .any)["match-info"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 4))
        let seen = info.label
        trioTab.tap()
        let chosen = app.descendants(matching: .any)["decide-chosen"].firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 8), "regresa a los tres")
        XCTAssertFalse(chosen.label.isEmpty)
        XCTAssertTrue(seen.contains(chosen.label), "la elegida es la carta que veías («\(seen)» / «\(chosen.label)»)")
        shot(app, "trio-con-la-carta")
    }

    /// «Una por una» abre sin colgarse (Fernando, 13 nov 2026, la 2291–2293: «truena cada vez que la abro»), sus botones
    /// quedan completos debajo de los datos de la carta (no se encima nada), «Filtros» abre su hoja en las dos pestañas y se
    /// regresa a «Tres que caben». Con tiempos límite: si la app se cuelga, la prueba falla en vez de esperar.
    func testUnaPorUnaAbreSinColgarseYSusBotonesCaben() {
        runDeck(extra: [])
    }

    /// Lo mismo con letra de accesibilidad (el mazo se desliza para que los botones quepan).
    func testUnaPorUnaConLetraGrande() {
        runDeck(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    private func runDeck(extra: [String]) {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide", "-demo-decide-tab", "deck"] + extra)
        let deck = app.descendants(matching: .any).matching(identifier: "match-deck").firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 30), "«Una por una» abre")
        let info = app.descendants(matching: .any).matching(identifier: "match-info").firstMatch
        let pass = app.descendants(matching: .any)["match-discard"].firstMatch, play = app.buttons["match-play"]
        XCTAssertTrue(info.waitForExistence(timeout: 10) && pass.waitForExistence(timeout: 5), "la carta con sus datos y sus botones")
        sleep(1)
        shot(app, "mazo-abierto")
        XCTAssertLessThanOrEqual(info.frame.maxY, pass.frame.minY + 1, "los datos de la carta no se enciman con los botones")
        XCTAssertLessThanOrEqual(play.frame.maxY, app.windows.firstMatch.frame.maxY, "los botones caben en la pantalla")
        XCTAssertTrue(pass.isHittable && play.isHittable, "los botones se pueden tocar")
        let filters = app.buttons["decide-filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5), "el mismo botón «Filtros»")
        filters.tap()
        XCTAssertTrue(app.buttons["decide-more-done"].waitForExistence(timeout: 8), "la hoja de filtros abre desde el mazo")
        shot(app, "filtros-mazo")
        app.buttons["decide-more-done"].tap()
        XCTAssertTrue(deck.waitForExistence(timeout: 8), "regresa al mazo")
        let trioTab = app.buttons["Tres que caben"]
        XCTAssertTrue(trioTab.waitForExistence(timeout: 5) && trioTab.isHittable, "«Tres que caben» se puede tocar")
        trioTab.tap()
        let shuffle = app.descendants(matching: .any).matching(identifier: "decide-shuffle").firstMatch
        XCTAssertTrue(shuffle.waitForExistence(timeout: 10), "regresa a «Tres que caben»")
        filters.tap()
        XCTAssertTrue(app.buttons["decide-more-done"].waitForExistence(timeout: 8), "la hoja de filtros abre desde «Tres que caben»")
        let hour = app.buttons["decide-time-hour"]
        if hour.waitForExistence(timeout: 3), hour.isEnabled { hour.tap() }
        shot(app, "filtros-trio")
        app.buttons["decide-more-done"].tap()
        XCTAssertTrue(shuffle.waitForExistence(timeout: 10), "y de vuelta a los tres")
    }

    /// La hoja de filtros (13 nov 2026): las baldosas de una fila miden lo mismo aunque una parta su nombre («Para pensar»),
    /// y elegir una calificación deja el mismo número arriba y en «Ver N» (antes las baldosas decían «0» con «5 opciones»).
    func testLaHojaDeFiltrosCuadraYSusFilasSonParejas() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        let filters = app.buttons["decide-filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 30), "la hoja de Decide abre")
        filters.tap()
        let done = app.buttons["decide-more-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "la hoja de filtros abre")
        sleep(3)   // que lleguen los datos de Cinemeta de la demo
        shot(app, "filtros-arriba")
        let moods = ["light", "intense", "think", "together"].map { app.buttons["decide-mood-\($0)"] }.filter { $0.exists }
        XCTAssertGreaterThanOrEqual(moods.count, 2, "las baldosas de ánimo")
        let heights = Set(moods.map { Int($0.frame.height.rounded()) })
        XCTAssertEqual(heights.count, 1, "las baldosas de ánimo miden lo mismo: \(moods.map { $0.frame.height })")
        let tops = Set(moods.map { Int($0.frame.minY.rounded()) })
        XCTAssertLessThanOrEqual(tops.count, 2, "en dos por dos, dos filas parejas")
        let seven = app.buttons["decide-rating-7"]
        XCTAssertTrue(seven.waitForExistence(timeout: 5))
        // «Ver N» va fijo abajo y lo de debajo se ve a través: se sube hasta que la baldosa quede por encima (en el SE, sin
        // esto, el toque caía en «Ver N» y cerraba los filtros).
        for _ in 0..<3 where !seven.isHittable || seven.frame.maxY > done.frame.minY - 4 { app.swipeUp(velocity: .slow); sleep(1) }
        if seven.isEnabled {
            seven.tap()
            sleep(1)
            shot(app, "filtros-7")
            let label = app.staticTexts["decide-filters-count"].label
            let top = label.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
            let ver = done.label.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
            if let top, let ver { XCTAssertEqual(top, ver, "arriba («\(label)») y «\(done.label)» dicen lo mismo") }
        }
        app.swipeUp(); sleep(1); shot(app, "filtros-medio")
        app.swipeUp(); sleep(1); shot(app, "filtros-abajo")
    }

    func testInicioAbreLaHojaAhiMismo() {
        let app = launch(["-demo-tab", "0", "-demo-open", "home-decide"])
        let deckTab = app.buttons["Una por una"]
        XCTAssertTrue(deckTab.waitForExistence(timeout: 30), "la hoja abre sobre Inicio")
        let shuffle = app.descendants(matching: .any).matching(identifier: "decide-shuffle").firstMatch
        XCTAssertTrue(shuffle.waitForExistence(timeout: 20), "con sus tres carteles, no vacía")
        sleep(1)
        shot(app, "inicio-hoja")
        app.descendants(matching: .any).matching(identifier: "decide-close").firstMatch.tap()
        sleep(2)
        shot(app, "inicio-cerrada")
        XCTAssertFalse(deckTab.exists, "la hoja se cerró")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home-decide").firstMatch.waitForExistence(timeout: 5), "sigues en Inicio")
    }
}
