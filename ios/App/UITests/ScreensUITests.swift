import XCTest

/// Lo que el usuario vio fallar en su iPhone, con la app de verdad en el simulador (modo demo).
final class ScreensUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Para ti › Listas con tu Orbital: el Top 10 de Netflix y las tendencias de Disney+ llevan la cifra grande.
    /// «Tus plataformas»: cada una en su tarjeta (Netflix y Disney+); al tocar Netflix, sus rankings con la cifra grande.
    func testPlatformsOpenTheirRankingsWithTheBigNumbers() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-console", "-demo-tab", "1", "-demo-mode", "lists", "-demo-no-idle"]
        app.launch()
        let netflix = app.buttons["platform-netflix"]
        // Explorar es perezoso: Plataformas se arma al acercarse (bajo la portada y «Lo que se ve hoy»).
        _ = app.buttons["paraTi-sections"].waitForExistence(timeout: 20)
        for _ in 0..<12 where !(netflix.exists && netflix.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(netflix.waitForExistence(timeout: 5), "la tarjeta de Netflix")
        // El carrusel es perezoso: en iOS 27 la de al lado aún no existe hasta deslizar hacia ella.
        let disney = app.buttons["platform-disney"]
        if !disney.waitForExistence(timeout: 5) { netflix.swipeLeft() }
        XCTAssertTrue(disney.waitForExistence(timeout: 10), "y la de Disney+")
        if !netflix.isHittable { disney.swipeRight() }
        XCTAssertTrue(waitUntil { netflix.exists && netflix.isHittable }, "Netflix otra vez a la mano")
        netflix.tap()
        let ranked = app.descendants(matching: .any).matching(identifier: "ranked-poster")
        XCTAssertTrue(ranked.firstMatch.waitForExistence(timeout: 20), "sus rankings, con la cifra grande")
    }

    /// Buscar ya no trae «Por género» (Fernando, 13 nov 2026: el filtro avanzado ya busca por género; eran dos puertas a lo
    /// mismo). La puerta del filtro sigue arriba.
    func testBrowseHasNoGenreShortcut() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "2"]
        app.launch()
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 20), "Buscar abrió")
        app.swipeUp(); app.swipeUp()
        XCTAssertFalse(app.descendants(matching: .any)["art-tile-genre-action"].exists, "«Por género» volvió a Buscar")
        XCTAssertFalse(app.staticTexts["Por género"].exists, "«Por género» volvió a Buscar")
    }
    /// Buscar: la barra se ve al abrir y se queda al bajar y al subir. La barra de pestañas ya no se encoge (Fernando, 2 nov
    /// 2026: «la barra siempre debería estar completa, siempre deberíamos poder ver todo»); antes esta prueba pedía que se
    /// escondiera.
    func testSearchBarStaysOnScroll() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "2", "-demo-no-idle"]
        app.launch()
        let field = revealSearchField()
        XCTAssertTrue(field.exists, "la barra a la vista al abrir")
        XCTAssertTrue(field.isHittable)
        app.swipeUp(); sleep(1)
        XCTAssertTrue(field.exists && field.isHittable, "al bajar, la barra sigue")
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(waitUntil { field.exists && field.isHittable && field.frame.width > 200 }, "al subir, sigue completa")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "sin teclado todavía")
    }

    /// Descargas vacía: no hay nada que bajar, así que deslizar no mueve nada (antes el título se encogía).
    func testEmptyDownloadsDoesNotScroll() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "3", "-demo-library", "downloads", "-demo-no-idle"]
        app.launch()
        let empty = app.staticTexts["Nada descargado"]
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "el vacío de Descargas")
        let title = app.navigationBars.staticTexts["Biblioteca"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "el título")
        sleep(1)
        let before = title.frame
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.5)
        XCTAssertEqual(title.frame, before, "el título se queda igual mientras deslizas")
    }

    /// Biblioteca abre en Guardado la primera vez (BI2-A) y Guardado abre en la pestaña «Mi lista» con sus pósters (GD2, 13 nov
    /// 2026), con el mismo filtro de toda lista y su «Estado» (BI3-A): elegir «Vistas» deja la cápsula para quitarlo.
    func testBibliotecaAbreEnGuardadoConElFiltroDeLasListas() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tab", "3", "-demo-no-idle"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["Biblioteca"].firstMatch.waitForExistence(timeout: 20), "el título")
        XCTAssertTrue(app.buttons["saved-tab-mylist"].waitForExistence(timeout: 20), "las pestañas de Guardado")
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 20), "los pósters de Mi lista")
        let filter = app.buttons["list-controls"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10), "«Ordenar y filtrar», el de toda lista")
        filter.tap()
        let state = app.buttons["Estado"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5), "«Estado» en el menú")
        XCTAssertFalse(app.buttons["Ocultar lo que ya vi"].exists, "con «Estado» no hace falta «Ocultar lo que ya vi»")
        state.tap()
        let watched = app.buttons["Vistas"].firstMatch
        XCTAssertTrue(watched.waitForExistence(timeout: 5), "Por ver · A medias · Vistas")
        watched.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Vistas'")).firstMatch.waitForExistence(timeout: 5), "la cápsula de lo filtrado")
    }

    /// La 1774 (Fernando, 4 nov 2026): en Mi media sus selectores funcionan (Todo · Películas · Series · Sin ver y «Más ›
    /// Ver carpetas») y la hoja de un pedido de Real-Debrid no trae ✕ (se jala hacia abajo).
    func testMiMediaSelectorsAndRequestSheetWithoutClose() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "3", "-demo-library", "media", "-demo-onedrive", "linked", "-demo-no-idle"]
        app.launch()
        let movies = app.buttons["Películas"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 20), "el filtro de Mi media")
        movies.tap()
        XCTAssertTrue(app.staticTexts["Películas"].firstMatch.waitForExistence(timeout: 5), "la sección de películas")
        XCTAssertFalse(app.staticTexts["Severance"].exists, "con Películas no sale la serie")
        app.buttons["Más"].firstMatch.tap()
        let folders = app.buttons["Ver carpetas"].firstMatch
        XCTAssertTrue(folders.waitForExistence(timeout: 5), "«Ver carpetas» en el menú")
        folders.tap()
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).buttons.firstMatch.waitForExistence(timeout: 5), "abrió las carpetas")
        app.terminate()

        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "3", "-demo-library", "downloads", "-demo-rd", "premium", "-demo-rd-request", "all",
                               "-demo-rd-sheet", "ready", "-demo-no-idle"]
        app.launch()
        XCTAssertTrue(app.buttons["debrid-watch-now"].waitForExistence(timeout: 20), "la hoja del pedido listo")
        XCTAssertFalse(app.buttons["sheet-close"].exists, "una hoja con asa no lleva ✕")
    }

    /// Mi media sin carpeta (todo cabe): deslizar no mueve nada ni encoge el título (antes rebotaba siempre).
    func testShortMiMediaDoesNotScroll() {
        for drive in ["unlinked"] {
            app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "3", "-demo-media", "-demo-onedrive", drive, "-demo-no-idle"]
            app.launch()
            let title = app.navigationBars.staticTexts["Biblioteca"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 20), "el título (\(drive))")
            sleep(3)
            let before = title.frame
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.5)
            XCTAssertEqual(title.frame, before, "el título se queda igual (\(drive))")
            app.terminate()
        }
    }

    /// El campo de Buscar al abrir. iOS 26 lo deja a la vista; iOS 27 lo abre guardado bajo el título (el cajón automático
    /// del sistema) y sale con un tirón corto hacia abajo, como en las apps de Apple.
    private func revealSearchField() -> XCUIElement {
        let field = app.searchFields.firstMatch
        _ = app.navigationBars["Buscar"].waitForExistence(timeout: 20)
        if field.waitForExistence(timeout: 3) { return field }
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)), b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 300, thenHoldForDuration: 0.5)
        _ = field.waitForExistence(timeout: 5)
        return field
    }

    /// Buscar hasta el fondo: la barra de abajo se queda a la vista, sin brincar con el rebote del final (la barra ya no se
    /// encoge, 2 nov 2026). También con algo sonando en la TV (el accesorio sobre la barra).
    func testSearchBarStaysAtTheBottom() { searchBarAtTheBottom(tv: false) }
    func testSearchBarStaysAtTheBottomWithTV() { searchBarAtTheBottom(tv: true) }

    private func searchBarAtTheBottom(tv: Bool) {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "2", "-demo-no-idle"] + (tv ? ["-demo-tv-now"] : [])
        app.launch()
        XCTAssertTrue(revealSearchField().exists, "la barra a la vista al abrir")
        sleep(2)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        for _ in 0..<8 { from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 500, thenHoldForDuration: 0.1) }
        sleep(2)
        // La barra de abajo: con la lupa (iOS 27) o con el campo (iOS 26).
        let tab = app.tabBars.buttons["Buscar"], field = app.searchFields.firstMatch
        let barShown = { (tab.exists && tab.isHittable) || (field.exists && field.isHittable && field.frame.minY > self.app.frame.midY) }
        XCTAssertTrue(barShown(), "en el fondo, la barra sigue a la vista")
        to.press(forDuration: 0.05, thenDragTo: from, withVelocity: 400, thenHoldForDuration: 0.3)
        XCTAssertTrue(waitUntil { barShown() }, "al subir con el dedo, sigue")
    }

    /// Buscar › «Ver todo» de lo más popular hoy: abre la lista completa, un título se abre y se regresa, y funciona otra vez.
    func testPopularSeeAllOpens() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "2", "-demo-no-idle"]
        app.launch()
        // El encabezado entero es el botón; «Ver todo» es la flecha junto al título (su pista, no su nombre).
        let seeAll = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Lo más popular hoy'")).firstMatch
        XCTAssertTrue(seeAll.waitForExistence(timeout: 20), "el botón «Ver todo»")
        for round in 1...2 {
            seeAll.tap()
            let title = app.navigationBars.staticTexts["Lo más popular hoy"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "abre la lista completa (vez \(round))")
            let poster = app.buttons["title-link"].firstMatch
            XCTAssertTrue(poster.waitForExistence(timeout: 10), "con sus títulos (vez \(round))")
            if round == 1 {
                poster.tap()
                XCTAssertTrue(waitUntil(10) { !title.exists }, "abre el título")
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(title.waitForExistence(timeout: 10), "regresa a la lista")
            }
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(seeAll.waitForExistence(timeout: 10), "regresa a Buscar (vez \(round))")
        }
    }

    /// Ajustes › «Un Simpson al azar»: las clásicas por omisión; tocar una temporada la agrega y «Las clásicas» la regresa.
    func testSimpsonsSeasonsPicker() {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-open", "settings", "-demo-no-idle"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Un Simpson al azar'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "el renglón «Un Simpson al azar»")
        row.tap()
        checkSeasons()
    }

    private func checkSeasons() {
        let picker = app.descendants(matching: .any)["simpsons-seasons"].firstMatch
        for _ in 0..<6 where !picker.exists || !picker.isHittable { app.swipeUp() }
        let one = app.buttons["Temporada 1"].firstMatch, five = app.buttons["Temporada 5"].firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 10), "las temporadas")
        XCTAssertFalse(one.isSelected, "la 1 no viene elegida")
        XCTAssertTrue(five.isSelected, "la 5 sí (las clásicas)")
        one.tap()
        XCTAssertTrue(waitUntil { one.isSelected }, "tocarla la agrega")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "seasons"; shot.lifetime = .keepAlways; add(shot)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Las clásicas'")).firstMatch.tap()
        XCTAssertTrue(waitUntil { !one.isSelected }, "«Las clásicas» la quita")
    }

    /// Buscar con el campo abierto (vacío o con algo escrito): al bajar, el campo sigue ahí (la barra ya no se encoge, 2 nov).
    func testOpenFieldStaysOnScroll() { openFieldStaysOnScroll(typing: nil) }
    func testTypedFieldStaysOnScroll() { openFieldStaysOnScroll(typing: "the") }

    private func openFieldStaysOnScroll(typing text: String?) {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "0", "-demo-free-tabs", "-demo-no-idle"]
        app.launch()
        let tab = app.tabBars.buttons["Buscar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "la lupa en la barra")
        sleep(2)   // que termine de llegar Inicio
        let spot = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY))
        spot.tap(); Thread.sleep(forTimeInterval: 0.3); spot.tap()   // dos toques seguidos
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "el campo con el teclado")
        if let text { app.typeText(text); sleep(4) }
        let field = app.searchFields.firstMatch
        app.swipeUp(); sleep(1); app.swipeUp()
        XCTAssertTrue(waitUntil { field.exists && field.isHittable }, "al bajar, el campo sigue")
    }

    /// Tocar la lupa dos veces (desde otra pestaña): el primer toque abre Buscar, el segundo el campo con el teclado.
    /// (También con la barra encogida: bajaste en Inicio y la lupa quedó sola a la derecha.)
    func testSecondTapOnSearchTabOpensTheField() { secondTapOpensTheField(minimized: false) }
    func testSecondTapOnMinimizedSearchTabOpensTheField() { secondTapOpensTheField(minimized: true) }

    private func secondTapOpensTheField(minimized: Bool) {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-tab", "0", "-demo-free-tabs", "-demo-no-idle"]
        app.launch()
        if minimized { sleep(3); app.swipeUp(); sleep(1); shot("g-minimized") }
        let tab = app.tabBars.buttons["Buscar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "la lupa en la barra")
        // El mismo punto de la pantalla las dos veces (la lupa se vuelve el campo al abrir Buscar).
        let spot = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY))
        spot.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "abre Buscar")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "el primer toque no abre el teclado")
        spot.tap()
        let ok = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(ok, "el segundo toque abre el campo con el teclado")
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if check() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return check()
    }
}
