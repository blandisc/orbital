import XCTest

/// Pruebas «de caos» (QA de regresión, 31 oct 2026): intentan romper la app en modo demo con toques en ráfaga, desplazar
/// muy rápido, los extremos de Época, filtros sin resultados, modo claro, menús contextuales y la letra más grande. No miden
/// un diseño: miden que la app siga viva, sin pantallas en blanco y que nada se salga de la pantalla. Solo quedan los
/// escenarios que dan un veredicto confiable en el simulador (los de giros, fondo y regreso, sin red, reproductor y hojas
/// apiladas se quitaron: fallaban por la prueba —la barra de pestañas encogida de iOS 26, `isHittable` con pósters fuera de
/// pantalla—, no por la app). Con `TEST_RUNNER_SHOTS=<carpeta>` guarda también las capturas en esa carpeta.
final class ChaosRegressionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private let base = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because",
                        "-demo-mode", "lists", "-demo-no-idle", "-demo-free-tabs"]

    private func launch(tab: Int, appearance: String = "dark", _ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = base + ["-demo-tab", "\(tab)", "-demo-appearance", appearance] + extra
        app.launch()
    }

    private func shot(_ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name; a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS"] {
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(name).png"))
        }
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    /// La app sigue viva y en primer plano.
    private func alive(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "la app se cayó o se fue: \(step)", file: file, line: line)
    }

    /// Algo visible en pantalla (no una pantalla en blanco): al menos unos cuantos botones o textos tocables.
    private func notBlank(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        let win = app.windows.firstMatch.frame
        let visible = app.buttons.allElementsBoundByIndex.prefix(60).filter { $0.exists && win.intersects($0.frame) && !$0.frame.isEmpty }.count
            + app.staticTexts.allElementsBoundByIndex.prefix(60).filter { $0.exists && win.intersects($0.frame) && !$0.frame.isEmpty }.count
        XCTAssertGreaterThan(visible, 3, "pantalla casi vacía: \(step)", file: file, line: line)
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        // La barra de pestañas de iOS 26 se encoge al desplazar: subir hasta que vuelva.
        for _ in 0..<6 where !b.exists { app.swipeDown(velocity: .fast) }
        if b.exists { b.tap() } else { XCTFail("no aparece la pestaña \(name)"); shot("sin-pestana-\(name)") }
    }

    /// Un póster a la vista (botón alto y angosto, de preferencia `title-link`), como coordenada: se busca en una sola
    /// foto del árbol (rápido) y no con `isHittable`, que truena con lo que está fuera de pantalla.
    private func aPoster(onlyLinks: Bool = false) -> XCUICoordinate? {
        guard let root = try? app.snapshot() else { return nil }
        let win = root.frame
        let safe = win.insetBy(dx: 0, dy: 100)   // ni bajo la barra de arriba ni bajo las pestañas
        var found: [XCUIElementSnapshot] = []
        func walk(_ e: XCUIElementSnapshot) {
            let f = e.frame
            if e.elementType == .button, f.height > 100, f.width > 60, f.width < 300, f.height > f.width, safe.contains(f), !onlyLinks || e.identifier == "title-link" { found.append(e) }
            e.children.forEach(walk)
        }
        walk(root)
        guard let pick = found.first(where: { $0.identifier == "title-link" }) ?? found.first else { print("CHAOS sin póster"); return nil }
        print("CHAOS póster: \(pick.identifier) \(pick.label) \(pick.frame)")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        return origin.withOffset(CGVector(dx: pick.frame.midX - win.minX, dy: pick.frame.midY - win.minY))
    }

    // MARK: Cuelgue del menú contextual (reproducción)

    /// Inicio: bajar dos pantallas y mantener presionado el primer póster de «Sugerencias para ti» (`title-link`). El 31 oct
    /// tiraba la app 3 de 3 veces (la ficha armaba su barra sin el entorno de la app); ahora abre el menú del póster.
    func testInicioMantenerPresionadoSugerencia() {
        launch(tab: 0)
        sleep(6)
        for _ in 0..<2 { app.swipeUp(velocity: .slow) }
        sleep(2)
        shot("repro-antes")
        guard let p = aPoster(onlyLinks: true) else { XCTFail("sin póster"); return }
        p.press(forDuration: 1.3)
        XCTAssertTrue(app.buttons["Descargar"].waitForExistence(timeout: 5), "no abrió el menú del póster")
        shot("repro-menu")
        alive("mantener presionado en Inicio")
    }

    // MARK: Pestañas

    // MARK: Ráfagas de toques

    /// La puerta de «Decide por mí» tocada cinco veces seguidas: una sola hoja, que se cierra; luego el mazo.
    func testRafagaEnLaTarjetaDelMazo() {
        launch(tab: 1)
        let card = app.buttons["paraTi-decide"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        for _ in 0..<5 { if card.exists && card.isHittable { card.tap() } }
        sleep(2)
        alive("ráfaga en la tarjeta")
        shot("rafaga-mazo")
        let close = app.buttons["decide-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        sleep(2)
        XCTAssertFalse(app.buttons["decide-close"].exists, "quedó una hoja apilada debajo")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "vuelve a Explorar")
        // Pasar 30 cartas muy rápido.
        card.tap()
        app.buttons["Una por una"].firstMatch.tap()
        let deck = any("match-deck")
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        for i in 0..<30 { if deck.exists { i % 2 == 0 ? deck.swipeLeft(velocity: .fast) : deck.swipeRight(velocity: .fast) } }
        sleep(1)
        alive("30 cartas")
        shot("mazo-30-cartas")
        if app.buttons["decide-close"].exists { app.buttons["decide-close"].tap() }
    }

    /// La puerta del filtro tocada en ráfaga, y abrir/cerrar el cajón muchas veces.
    func testRafagaEnLaPuertaDelFiltro() {
        launch(tab: 2)
        let door = app.buttons["browse-filters"]
        XCTAssertTrue(door.waitForExistence(timeout: 20))
        for _ in 0..<4 { if door.isHittable { door.tap() } }
        sleep(2)
        alive("ráfaga en la puerta")
        shot("rafaga-puerta")
        for _ in 0..<6 {
            app.swipeDown(velocity: .fast)
            if door.waitForExistence(timeout: 3), door.isHittable { door.tap() }
        }
        sleep(1)
        alive("abrir y cerrar el cajón")
        shot("cajon-abrir-cerrar")
    }

    // MARK: Desplazar

    /// Desplazar muy rápido Inicio y Explorar de arriba abajo, y los estantes de lado.
    func testDesplazarMuyRapido() {
        for (t, name) in [(0, "inicio"), (1, "explorar")] {
            launch(tab: t)
            sleep(4)
            for _ in 0..<15 { app.swipeUp(velocity: 4000) }
            shot("rapido-\(name)-abajo")
            alive("abajo \(name)")
            notBlank("abajo de \(name)")
            for _ in 0..<15 { app.swipeDown(velocity: 4000) }
            sleep(1)
            for _ in 0..<3 { app.swipeUp(velocity: .slow) }
            // Estantes de lado.
            let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            for _ in 0..<10 { mid.press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)), withVelocity: 5000, thenHoldForDuration: 0) }
            shot("rapido-\(name)-de-lado")
            alive("de lado \(name)")
            app.terminate()
        }
    }

    /// El mosaico: arrastres rápidos en todas direcciones, tocar a media inercia y salir/entrar.
    func testMosaicoEnRafaga() {
        launch(tab: 1)
        let walk = app.buttons["paraTi-walk-mosaic"]
        XCTAssertTrue(walk.waitForExistence(timeout: 20))
        walk.tap()
        // El mosaico ya no sale como `otherElements` (tanda 4): se busca por su identificador en cualquier tipo.
        let mosaic = app.descendants(matching: .any)["mosaic"]
        XCTAssertTrue(mosaic.waitForExistence(timeout: 10))
        sleep(2)
        // Verticales y en diagonal: un arrastre de lado (a cualquier lado) es el gesto que regresa a Explorar
        // (`DS.Mosaic.swipeBack`) y saldría del mosaico a propósito.
        let pts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.5, 0.8, 0.5, 0.1), (0.5, 0.1, 0.5, 0.9), (0.1, 0.9, 0.9, 0.1), (0.9, 0.1, 0.1, 0.9), (0.9, 0.9, 0.1, 0.1)]
        for _ in 0..<4 {
            for p in pts {
                mosaic.coordinate(withNormalizedOffset: CGVector(dx: p.0, dy: p.1))
                    .press(forDuration: 0.01, thenDragTo: mosaic.coordinate(withNormalizedOffset: CGVector(dx: p.2, dy: p.3)), withVelocity: 6000, thenHoldForDuration: 0)
            }
        }
        mosaic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()   // tocar a media inercia
        sleep(2)
        alive("mosaico en ráfaga")
        shot("mosaico-rafaga")
        XCTAssertTrue(app.buttons.matching(identifier: "mosaic-tile").firstMatch.exists, "el mosaico se quedó sin piezas")
        // Salir y entrar 5 veces seguidas.
        for _ in 0..<5 {
            let back = app.buttons["paraTi-back"]
            if back.exists && back.isHittable { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
            if walk.waitForExistence(timeout: 5) { walk.tap() }
        }
        sleep(3)
        alive("mosaico 5 veces")
        XCTAssertTrue(app.buttons.matching(identifier: "mosaic-tile").firstMatch.waitForExistence(timeout: 10), "tras entrar 5 veces el mosaico no tiene piezas")
        shot("mosaico-5-veces")
    }

    // MARK: Girar

    // MARK: Filtro y Época

    /// La regla de Época en sus extremos: lo más reciente, lo más viejo, una década tocada dos veces y arrastres fuera de la regla.
    func testEpocaEnLosExtremos() {
        launch(tab: 2)
        let era = app.buttons["browse-filter-era"]
        XCTAssertTrue(era.waitForExistence(timeout: 20))
        era.tap()
        let ruler = any("filter-year-ruler")
        XCTAssertTrue(ruler.waitForExistence(timeout: 10))
        // Tocar el extremo derecho (años muy recientes) y arrastrar hasta fuera de la pantalla.
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        sleep(1); shot("epoca-toque-derecha")
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 1.4, dy: 0.5)), withVelocity: 3000, thenHoldForDuration: 0.1)
        sleep(1); shot("epoca-arrastre-fuera-derecha")
        print("CHAOS ruler value derecha: \(String(describing: ruler.value)) · era: \(app.buttons["filter-era"].label)")
        // Encoger la ventana hasta un solo año (orilla izquierda contra la derecha).
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 1.2, dy: 0.5)), withVelocity: 3000, thenHoldForDuration: 0.1)
        sleep(1); shot("epoca-un-anio")
        print("CHAOS ruler value un año: \(String(describing: ruler.value)) · era: \(app.buttons["filter-era"].label)")
        // Al otro extremo.
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: -0.5, dy: 0.5)), withVelocity: 6000, thenHoldForDuration: 0.1)
        sleep(1); shot("epoca-izquierda")
        print("CHAOS ruler value izquierda: \(String(describing: ruler.value)) · era: \(app.buttons["filter-era"].label)")
        // Décadas: la última dos veces (elige y quita), y luego la primera.
        let decades = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'filter-decade-'"))
        let all = decades.allElementsBoundByIndex
        if let last = all.last, let first = all.first {
            last.tap(); sleep(1); shot("epoca-ultima-decada")
            print("CHAOS última década: \(last.identifier) → \(app.buttons["filter-era"].label)")
            last.tap(); sleep(1)
            print("CHAOS última década otra vez: \(app.buttons["filter-era"].label)")
            first.tap(); sleep(1)
            for _ in 0..<10 { last.tap(); first.tap() }   // ráfaga
            sleep(1)
            shot("epoca-rafaga-decadas")
        }
        alive("Época en los extremos")
        app.buttons["filter-results"].tap()
        sleep(5)
        alive("resultados con Época extrema")
        notBlank("resultados con Época extrema")
        shot("epoca-resultados")
    }

    /// Un filtro que no puede dar nada (un año + calificación 8+ + varios géneros + ocultar lo visto): «Ver resultados» debe
    /// decir que no hay nada, no quedarse en blanco o cargando.
    func testVerResultadosSinResultados() {
        launch(tab: 2)
        let door = app.buttons["browse-filters"]
        XCTAssertTrue(door.waitForExistence(timeout: 20))
        door.tap()
        XCTAssertTrue(any("advanced-filter").waitForExistence(timeout: 10))
        app.buttons["filter-era"].tap()
        let ruler = any("filter-year-ruler")
        if ruler.waitForExistence(timeout: 5) {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'filter-decade-'")).firstMatch.tap()   // la década más vieja
        }
        if app.buttons["filter-rating"].exists {
            app.buttons["filter-rating"].tap(); sleep(1)
            let slider = any("filter-tmdb-slider")   // el deslizador del público, hasta Excelente
            // Es una regla propia (no un deslizador del sistema): se arrastra hasta casi el final.
            if slider.waitForExistence(timeout: 3) {
                slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            }
        }
        let genres = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browse-filter-genre' OR identifier == 'filter-genre'"))
        if genres.firstMatch.exists {
            genres.firstMatch.tap(); sleep(1)
            for g in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'filter-genre-'")).allElementsBoundByIndex.prefix(4) where g.isHittable { g.tap() }
        }
        shot("sin-resultados-cajon")
        app.buttons["filter-results"].tap()
        sleep(8)
        alive("sin resultados")
        shot("sin-resultados")
        let results = app.buttons.matching(identifier: "filter-result").count
        print("CHAOS resultados con filtro imposible: \(results)")
        if results == 0 { notBlank("sin resultados debería decir algo") }
        // Y volver al cajón para quitarlo todo.
        app.navigationBars.buttons.firstMatch.tap()
        sleep(2)
        alive("volver de sin resultados")
        shot("sin-resultados-vuelta")
    }

    // MARK: Buscar

    // MARK: Tamaño de letra y apariencia

    /// Modo claro en las pantallas nuevas.
    func testModoClaro() {
        launch(tab: 0, appearance: "light")
        sleep(6)
        shot("claro-inicio")
        tab("Explorar"); sleep(4); shot("claro-explorar")
        app.buttons["paraTi-walk-mosaic"].tap(); sleep(2); shot("claro-mosaico")
        if app.buttons["paraTi-back"].exists { app.buttons["paraTi-back"].tap() }
        tab("Buscar"); sleep(2)
        app.buttons["browse-filters"].tap(); sleep(2); shot("claro-filtro")
        if app.buttons["filter-era"].exists { app.buttons["filter-era"].tap(); sleep(1); shot("claro-epoca") }
        alive("modo claro")
    }

    // MARK: Fondo, red y reproductor

    // MARK: Hojas y menús

    /// Mantener presionado un póster de Inicio y de Explorar: sale el menú, se cierra y se usan sus acciones.
    func testMenusContextuales() {
        launch(tab: 0)
        sleep(6)
        for name in ["inicio", "explorar"] {
            if name == "explorar" { tab("Explorar"); sleep(4); for _ in 0..<2 { app.swipeUp(velocity: .slow) } }
            guard let p = aPoster() else { print("CHAOS sin póster en \(name)"); continue }
            p.press(forDuration: 1.3)
            sleep(1)
            shot("menu-\(name)")
            let items = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.map(\.label)
            print("CHAOS menú \(name): \(items.prefix(20))")
            // Cerrar tocando fuera y volver a abrir y tocar la primera acción.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            sleep(1)
            if let p2 = aPoster() {
                p2.press(forDuration: 1.3); sleep(1)
                let menuItem = app.collectionViews.buttons.firstMatch
                if menuItem.exists { print("CHAOS acción: \(menuItem.label)"); menuItem.tap(); sleep(2) }
                shot("menu-\(name)-accion")
            }
            alive("menú \(name)")
            if app.navigationBars.buttons.firstMatch.exists, !app.tabBars.firstMatch.isHittable { app.navigationBars.buttons.firstMatch.tap() }
        }
    }

    // MARK: Letra de accesibilidad máxima (R2)

    /// Con la letra más grande (AX5) nada se sale de la pantalla en Inicio (portada, Todo · Películas · Series, «Lo nuevo de
    /// lo tuyo», Seguir viendo), Explorar, Buscar, Descargas y una ficha. Cada pantalla con su propio arranque (la barra de
    /// pestañas se esconde al desplazar y con esta letra no siempre vuelve). Mide en el árbol que ningún texto ni botón
    /// visible empiece antes de la orilla izquierda ni termine después de la derecha.
    func testLetraMaximaSinSalirseDeLaPantalla() {
        let xxxl = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let screens: [(name: String, tab: Int, extra: [String], scrolls: Int)] = [
            ("inicio", 0, [], 0), ("inicio-abajo", 0, [], 2), ("explorar", 1, [], 0), ("buscar", 2, [], 0), ("descargas", 3, [], 0),
            ("ficha", 0, ["-demo-title", "series:tt0386676"], 0),
        ]
        for screen in screens {
            launch(tab: screen.tab, xxxl + screen.extra)
            sleep(6)
            for _ in 0..<screen.scrolls { app.swipeUp(velocity: .slow) }
            sleep(1)
            shot("xxxl-\(screen.name)")
            alive("letra máxima: \(screen.name)")
            XCTAssertEqual(offscreen(), [], "con letra máxima se sale de la pantalla: \(screen.name)")
            app.terminate()
        }
    }

    /// Textos y botones a la vista (no los de un carrusel horizontal, que siguen fuera a propósito) que cruzan una orilla.
    private func offscreen() -> [String] {
        guard let root = try? app.snapshot() else { return ["sin árbol"] }
        let win = root.frame
        var out: [String] = []
        func walk(_ e: XCUIElementSnapshot, inCarousel: Bool) {
            let carousel = inCarousel || (e.elementType == .scrollView && e.frame.width >= win.width - 1 && e.frame.height < win.height * 0.8)
            let f = e.frame
            if !carousel, [.staticText, .button].contains(e.elementType), !f.isEmpty, f.width < win.width * 2,
               f.minY > win.minY + 40, f.maxY < win.maxY - 90,   // ni la barra de estado ni la de pestañas
               f.minX < win.minX - 1 || f.maxX > win.maxX + 1 {
                out.append("\(e.elementType.rawValue) «\(e.label.prefix(40))» \(Int(f.minX))…\(Int(f.maxX))")
            }
            e.children.forEach { walk($0, inCarousel: carousel) }
        }
        walk(root, inCarousel: false)
        return out
    }
}
