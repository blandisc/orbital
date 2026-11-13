import XCTest

/// La pasada completa de «Decide por mí» (Fernando, 13 nov 2026: «Revisa simetría, revisa espacios, revisa todo… También la
/// página de filtros dale una buena pulida»). Se mide con los marcos, no a ojo (`docs/ios-entrega.md`): márgenes iguales,
/// lo que comparte renglón comparte alto y orilla, el encabezado no brinca entre pestañas; y se toca cada control de ida y
/// vuelta. Las capturas quedan en `ORBITAL_SHOTS` (si se da) para revisarlas.
final class DecidePolishUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because",
                               "-demo-no-idle"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// El selector de tipo de la hoja (Explorar, abajo, tiene el suyo).
    private func kindButton(_ app: XCUIApplication, _ id: String) -> XCUIElement { any(app, "decide-kind").buttons["kind-" + id].firstMatch }
    private func number(_ label: String) -> Int? { label.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } }
    private func open(_ app: XCUIApplication) {
        XCTAssertTrue(any(app, "decide-shuffle").waitForExistence(timeout: 30), "la hoja de Decide abre en «Tres que caben»")
    }

    /// Lo que comparte renglón mide lo mismo y cuelga de las mismas orillas que la hoja (márgenes iguales a los dos lados).
    private func checkRow(_ items: [XCUIElement], window: CGRect, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard items.count > 1 else { return }
        let rows = Dictionary(grouping: items) { Int($0.frame.minY.rounded()) }
        for (_, row) in rows where row.count > 1 {
            let heights = row.map(\.frame.height), widths = row.map(\.frame.width)
            XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1, "\(what): misma altura en la fila \(heights)", file: file, line: line)
            XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 1, "\(what): mismo ancho en la fila \(widths)", file: file, line: line)
        }
        let left = items.map(\.frame.minX).min() ?? 0, right = window.maxX - (items.map(\.frame.maxX).max() ?? 0)
        XCTAssertEqual(left, right, accuracy: 1.5, "\(what): margen izquierdo \(left) = derecho \(right)", file: file, line: line)
    }

    /// La hoja de filtros: cada fila pareja y centrada, el número de arriba = «Ver N» = la baldosa elegida, «Quitar filtros»
    /// solo con algo puesto, y quitarlo regresa todo.
    func testLaHojaDeFiltrosSeMideYSeToca() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        open(app)
        let window = app.windows.firstMatch.frame
        app.buttons["decide-filters"].tap()
        let done = app.buttons["decide-more-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "la hoja de filtros abre")
        sleep(4)   // los datos de Cinemeta de la demo
        shot(app, "filtros-1-arriba")
        XCTAssertFalse(app.buttons["decide-filters-clear"].exists, "sin nada puesto, «Quitar filtros» no está")
        let times = ["short", "hour", "long"].map { app.buttons["decide-time-\($0)"] }
        let moods = ["light", "intense", "think", "together"].map { app.buttons["decide-mood-\($0)"] }
        checkRow(times, window: window, "Duración")
        checkRow(moods, window: window, "Ánimo")
        XCTAssertEqual(times[0].frame.minX, moods[0].frame.minX, accuracy: 1, "Duración y Ánimo empiezan en la misma orilla")
        XCTAssertEqual(times[2].frame.maxX, moods[3].frame.maxX, accuracy: 1, "y terminan en la misma")
        let top = app.staticTexts["decide-filters-count"]
        let before = number(top.label)
        XCTAssertEqual(before, number(done.label), "arriba («\(top.label)») = «\(done.label)»")
        // Calificación: no dice 0 si hay opciones arriba, y elegirla cuadra con arriba y con «Ver N».
        let seven = app.buttons["decide-rating-7"]
        while !seven.isHittable || seven.frame.maxY > done.frame.minY { app.swipeUp(velocity: .slow) }
        let ratings = [6, 7, 8].map { app.buttons["decide-rating-\($0)"] }
        checkRow(ratings, window: window, "Calificación")
        XCTAssertLessThanOrEqual(seven.frame.maxY, done.frame.minY, "«Ver N» no tapa la baldosa")
        shot(app, "filtros-2-calificacion")
        seven.tap()
        sleep(1)
        let after = number(top.label)
        XCTAssertEqual(after, number(done.label), "con 7+, arriba = «Ver N»")
        XCTAssertEqual(seven.value as? String, after.map { "\($0) opciones" }, "la baldosa elegida dice lo mismo que arriba")
        if let before, let after { XCTAssertLessThanOrEqual(after, before) }
        let clear = app.buttons["decide-filters-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3), "con algo puesto, «Quitar filtros» aparece")
        shot(app, "filtros-3-puesto")
        clear.tap()
        sleep(1)
        XCTAssertEqual(number(top.label), before, "«Quitar filtros» regresa la cuenta")
        XCTAssertFalse(clear.exists, "y se va")
        // Lo de más abajo: según quién, Letterboxd, premios, géneros y épocas, parejos.
        app.swipeUp(velocity: .slow); sleep(1); shot(app, "filtros-4-medio")
        let sources = ["imdb", "trakt", "tmdb"].map { app.buttons["decide-source-\($0)"] }
        checkRow(sources, window: window, "Según")
        app.swipeUp(velocity: .slow); sleep(1); shot(app, "filtros-5-premios")
        app.swipeUp(velocity: .slow); sleep(1); shot(app, "filtros-6-generos")
        let genres = ["comedy", "drama", "action", "thriller", "horror", "sci-fi"].map { app.buttons["decide-genre-\($0)"] }.filter { $0.exists && $0.isHittable }
        checkRow(genres, window: window, "Géneros")
        app.swipeUp(velocity: .slow); sleep(1); shot(app, "filtros-7-abajo")
        done.tap()
        XCTAssertTrue(any(app, "decide-shuffle").waitForExistence(timeout: 8), "«Ver N» regresa a los tres")
    }

    /// El encabezado (título, pestañas, tipo y «Filtros») es el mismo al pixel en las dos pestañas, con márgenes iguales, y la
    /// ✕ y «Filtros» cuelgan de la misma orilla derecha.
    func testElEncabezadoNoBrincaYCuadra() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        open(app)
        sleep(2)
        let window = app.windows.firstMatch.frame
        let close = any(app, "decide-close"), filters = app.buttons["decide-filters"], kind = any(app, "decide-kind")
        let trioTab = app.buttons["Tres que caben"], deckTab = app.buttons["Una por una"]
        func frames() -> [CGRect] { [close.frame, filters.frame, kind.frame, trioTab.frame, deckTab.frame] }
        let trio = frames()
        XCTAssertEqual(close.frame.maxX, filters.frame.maxX, accuracy: 1, "la ✕ y «Filtros» en la misma orilla derecha")
        XCTAssertEqual(kind.frame.minX, window.maxX - filters.frame.maxX, accuracy: 1.5, "el tipo y «Filtros»: márgenes iguales")
        XCTAssertEqual(kind.frame.midY, filters.frame.midY, accuracy: 1, "el tipo y «Filtros» comparten centro")
        // La hoja corta flota con orillas y se dibuja a escala (≈ 0.96): 44 pt se miden un poco menos.
        let scale: CGFloat = 0.95
        for target in [close, filters] { XCTAssertGreaterThanOrEqual(min(target.frame.width, target.frame.height), 44 * scale - 1, "objetivo de toque ≥ 44 pt") }
        XCTAssertEqual(close.frame.width, filters.frame.width, accuracy: 1, "la ✕ y «Filtros», el mismo círculo")
        let posters = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["decide-chosen", "decide-option"])).allElementsBoundByIndex
        XCTAssertEqual(posters.count, 3)
        let watch = app.buttons["decide-watch"], shuffle = any(app, "decide-shuffle")
        XCTAssertEqual(watch.frame.midY, shuffle.frame.midY, accuracy: 1, "Ver y Barajar comparten centro")
        XCTAssertEqual(watch.frame.minX, window.maxX - (posters.map(\.frame.maxX).max() ?? 0), accuracy: 2, "los botones cuelgan de las orillas de los carteles")
        shot(app, "trio-encabezado")
        deckTab.tap()
        XCTAssertTrue(any(app, "match-deck").waitForExistence(timeout: 8))
        sleep(2)
        shot(app, "mazo-encabezado")
        // La hoja crece (los tres van en una hoja corta, el mazo en la alta) y la corta se dibuja a escala: se compara la
        // posición de cada pieza respecto a la ✕ y al centro, con un margen del 5 % por la escala.
        let deck = frames()
        for (a, b) in zip(trio, deck) {
            let dyA = a.minY - trio[0].minY, dyB = b.minY - deck[0].minY
            XCTAssertEqual(dyA, dyB, accuracy: max(1, abs(dyB) * 0.05), "el encabezado no brinca al cambiar de pestaña \(dyA) vs \(dyB)")
            let dxA = a.midX - window.midX, dxB = b.midX - window.midX
            XCTAssertEqual(dxA, dxB, accuracy: max(1, abs(dxB) * 0.05), "ni de lado \(dxA) vs \(dxB)")
        }
        let actions = ["match-discard", "match-tonight", "match-save", "match-play"].map { app.buttons[$0] }
        XCTAssertEqual(Set(actions.map { Int($0.frame.midY.rounded()) }).count, 1, "los cuatro botones del mazo en un renglón")
        let gaps = zip(actions, actions.dropFirst()).map { $1.frame.midX - $0.frame.midX }
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), 2, "repartidos con el mismo paso \(gaps)")
        let card = any(app, "match-info")
        XCTAssertEqual(window.midX, (actions[0].frame.minX + actions[3].frame.maxX) / 2, accuracy: 2, "los botones, centrados")
        XCTAssertLessThanOrEqual(card.frame.maxY, actions[0].frame.minY, "los datos de la carta no se enciman con los botones")
    }

    /// Cambiar de tipo y regresar deja los mismos tres y la misma elegida (y también en el mazo, la misma carta arriba).
    func testCambiarDeTipoYRegresarConservaLoMismo() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        open(app)
        sleep(2)
        func trio() -> [String] {
            app.buttons.matching(NSPredicate(format: "identifier IN %@", ["decide-chosen", "decide-option"])).allElementsBoundByIndex.map(\.label)
        }
        let first = trio(), chosen = app.buttons["decide-chosen"].label
        XCTAssertEqual(first.count, 3)
        kindButton(app, "movie").tap(); sleep(2)
        kindButton(app, "series").tap(); sleep(2)
        kindButton(app, "all").tap(); sleep(2)
        XCTAssertEqual(trio(), first, "regresan los mismos tres")
        XCTAssertEqual(app.buttons["decide-chosen"].label, chosen, "y la misma elegida")
        // El mazo: empieza por el cartel elegido y, de regreso, esa carta vuelve a ser la elegida.
        app.buttons["Una por una"].tap()
        let info = any(app, "match-info")
        XCTAssertTrue(info.waitForExistence(timeout: 8))
        sleep(1)
        XCTAssertTrue(info.label.contains(chosen), "el mazo empieza por el cartel elegido («\(chosen)»; arriba: «\(info.label)»)")
        let topBefore = info.label
        kindButton(app, "movie").tap(); sleep(2)
        kindButton(app, "all").tap(); sleep(2)
        XCTAssertEqual(info.label, topBefore, "ir y volver de tipo no rebaraja el mazo")
        app.buttons["Tres que caben"].tap()
        XCTAssertTrue(any(app, "decide-shuffle").waitForExistence(timeout: 8))
        XCTAssertEqual(trio(), first, "de regreso, los mismos tres")
        XCTAssertEqual(app.buttons["decide-chosen"].label, chosen, "y la carta de arriba es la elegida")
    }

    /// Los botones del mazo hacen lo suyo y se pueden deshacer; los de los tres también (Barajar da otros, ⋯ › Hoy no).
    func testCadaBotonHaceLoSuyo() {
        let app = launch(["-demo-tab", "1", "-demo-mode", "lists", "-demo-open", "decide"])
        open(app)
        sleep(2)
        func trio() -> [String] {
            app.buttons.matching(NSPredicate(format: "identifier IN %@", ["decide-chosen", "decide-option"])).allElementsBoundByIndex.map(\.label)
        }
        let first = trio()
        let shuffle = any(app, "decide-shuffle")
        shuffle.tap()
        // A medio camino: la cascada de salida y entrada.
        usleep(120_000); shot(app, "barajar-medio-1")
        usleep(150_000); shot(app, "barajar-medio-2")
        sleep(2)
        XCTAssertNotEqual(trio(), first, "Barajar da otros tres")
        // Tocar otro cartel lo elige.
        let other = app.buttons["decide-option"].firstMatch
        let name = other.label
        other.tap(); sleep(1)
        XCTAssertEqual(app.buttons["decide-chosen"].label, name, "tocar un cartel lo elige")
        // ⋯ › Hoy no: se va y se puede deshacer.
        any(app, "decide-more").tap()
        let today = app.buttons["Hoy no"]
        XCTAssertTrue(today.waitForExistence(timeout: 3), "«⋯» ofrece «Hoy no»")
        today.tap(); sleep(1)
        XCTAssertFalse(trio().contains(name), "«Hoy no» la quita")
        let undo = app.buttons["Deshacer"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "con «Deshacer»")
        shot(app, "trio-hoy-no")
        undo.tap(); sleep(1)
        XCTAssertTrue(trio().contains(name), "«Deshacer» la regresa")
        // El mazo: Paso, Para hoy y Guardar mandan la carta y se deshacen.
        app.buttons["Una por una"].tap()
        let info = any(app, "match-info")
        XCTAssertTrue(info.waitForExistence(timeout: 8)); sleep(1)
        for id in ["match-discard", "match-save", "match-tonight"] {
            let before = info.label
            app.buttons[id].tap()
            usleep(200_000); shot(app, "mazo-\(id)-medio")
            sleep(2)
            XCTAssertNotEqual(info.label, before, "\(id): la carta sale y sube la siguiente")
            let back = app.buttons["Deshacer"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3), "\(id): con «Deshacer»")
            back.tap(); sleep(2)
            XCTAssertEqual(info.label, before, "\(id): «Deshacer» la regresa")
        }
    }
}
