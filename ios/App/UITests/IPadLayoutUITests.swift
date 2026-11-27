import XCTest

/// El iPad (y la Mac «Diseñada para iPad»): la app en vertical y en horizontal, con lo principal a la vista. Guarda una
/// captura de cada pantalla en `ORBITAL_SHOTS` (o /tmp/orbital-shots); en horizontal sale girada (así las da XCUITest).
///   xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,name=Orbital QA iPad' \
///     -only-testing:OrbitalUITests/IPadLayoutUITests
/// En un iPhone no corre (allá la app es vertical y el giro lo prueba `PlayerRotationUITests`), salvo `testLandscapeTour`.
final class IPadLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUpWithError() throws {
        // El recorrido acostado también corre en un iPhone (el iPhone Duo cerrado y acostado, 27 nov 2026): ahí la app se
        // queda vertical salvo el reproductor, y el recorrido lo enseña tal cual.
        let tourOnPhone = name.contains("LandscapeTour") && ProcessInfo.processInfo.environment["ORBITAL_HANDSHAKE"] != nil
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad || tourOnPhone, "solo en iPad")
        if name.contains("LandscapeTour") { try XCTSkipIf(ProcessInfo.processInfo.environment["ORBITAL_HANDSHAKE"] == nil, "solo con ORBITAL_HANDSHAKE") }
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func open(_ args: [String], _ orientation: UIDeviceOrientation) {
        app.terminate()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle"] + args
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(4)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/ipad-\(name).png"))
    }

    /// Las pestañas (arriba, con la barra lateral) en las dos orientaciones.
    func testTabsInBothOrientations() {
        for (orientation, tag) in [(UIDeviceOrientation.portrait, "v"), (.landscapeLeft, "h")] {
            open(["-demo-tab", "0"], orientation)
            // En vertical son botones de la barra de arriba; en horizontal, renglones de la barra lateral.
            let tab = { (name: String) in self.app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch }
            XCTAssertTrue(tab("Inicio").waitForExistence(timeout: 30), "\(tag): falta la pestaña Inicio")
            XCTAssertTrue(tab("Explorar").exists, "\(tag): falta la pestaña Explorar")
            shot("inicio-\(tag)")
            open(["-demo-tab", "1"], orientation)
            shot("parati-\(tag)")
        }
    }

    /// El índice de Explorar (☰) lleva a cada grupo y el grupo se ve: con la bandera de demostración, saltar a «Géneros» o
    /// «Premios» dejaba la página en blanco (17 nov 2026).
    func testSectionIndexLandsOnEachGroup() {
        open(["-demo-tab", "1"], .portrait)
        let menu = app.buttons["paraTi-sections"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "falta el índice de Explorar")
        sleep(8)   // que lleguen las colecciones de TMDB
        for name in ["Géneros", "Premios", "Temporadas", "Plataformas"] {
            menu.tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "falta \(name) en el índice")
            item.tap()
            sleep(2)
            shot("indice-\(name)")
            let head = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(head.exists && head.isHittable, "\(name): el salto no deja ver su grupo")
        }
    }

    /// La ficha y sus acciones en horizontal (el arte no tapa el botón de ver).
    func testTitleInLandscape() {
        open(["-demo-tmdb", "-demo-title", "series:tt0386676"], .landscapeLeft)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continuar' OR label BEGINSWITH 'Ver '")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "falta el botón de ver")
        XCTAssertTrue(play.isHittable, "el botón de ver queda fuera de la pantalla")
        shot("ficha-h")
    }

    /// «¿Qué vemos?» es una tarjeta de su alto (antes salía cortada a ~70 pt).
    func testSheetsAreFullSizeCards() {
        open(["-demo-tab", "1", "-demo-open", "decide"], .portrait)
        // «Afinar» va al pie de la tarjeta y sale siempre (con sugerencia o con «Nada con…» si un filtro guardado no deja opciones).
        let filters = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Afinar'")).firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 40), "Decide por mí no enseña «Afinar»")
        XCTAssertTrue(filters.isHittable, "la tarjeta queda cortada: «Afinar» no se alcanza")
        shot("decidir-v")
    }

    /// Tocar una serie o película abre su ficha en el panel de la derecha (de pie y acostado): lo de atrás sigue a la vista
    /// La ficha del iPad (FE1, 4 nov 2026): a pantalla completa, como la de la TV, con «Ver» a la vista; ‹ regresa.
    func testTitleOpensFullScreen() {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            open(["-demo-tmdb", "-demo-title", "movie:tt1160419"], orientation)
            let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continuar' OR label BEGINSWITH 'Ver'")).firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30), "\(orientation.rawValue): la ficha no abrió")
            XCTAssertTrue(play.isHittable, "\(orientation.rawValue): «Ver» queda fuera de la vista")
            shot("ficha-\(orientation == .portrait ? "v" : "h")")
        }
    }

    /// PA5-A (Fernando, 23 nov 2026: «El iPad no se conecta a la TV»): ni el control (antes un panel a la derecha, CT2) ni
    /// nada de la TV en Ajustes; Ajustes abre con el esqueleto de la TV (PA1-A) y su Diagnóstico.
    func testTheIPadHasNothingOfTheTV() {
        open(["-demo-tv-now", "-demo-open", "remote"], .landscapeLeft)
        let inicio = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Inicio")).firstMatch
        XCTAssertTrue(inicio.waitForExistence(timeout: 30), "la app abre")
        sleep(3)
        XCTAssertFalse(app.buttons["remote-panel-close"].exists, "sin el panel del control")
        let type = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Escribir en la TV' OR placeholderValue CONTAINS 'Escribir en la TV'")).firstMatch
        XCTAssertFalse(type.exists, "sin el control de la TV")
        open(["-demo-open", "settings"], .portrait)
        let languages = app.descendants(matching: .any)["settings-languages"]
        XCTAssertTrue(languages.waitForExistence(timeout: 30), "Ajustes abre")
        XCTAssertFalse(app.descendants(matching: .any)["settings-orbital"].exists, "sin «Usar con tu Orbital»")
        XCTAssertFalse(app.staticTexts["Tu Orbital"].exists, "sin «Tu Orbital»")
        let diagnostics = app.descendants(matching: .any)["settings-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5), "Diagnóstico en Ajustes")
        diagnostics.tap()
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics-trakt"].waitForExistence(timeout: 10), "Diagnóstico abre con Trakt")
        XCTAssertFalse(app.descendants(matching: .any)["diagnostics-tv"].exists, "Diagnóstico sin la TV en el iPad")
        shot("diagnostico-v")
    }

    /// PA7-A: las pestañas de la ficha dicen lo mismo que el iPhone y la TV, caben enteras (con su nombre) y cada una abre.
    func testTitleTabsUseTheSameNames() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            // The Bear: con el TMDB de mentira trae reparto y parecidas (The Office es de `demoSpanish` y llega sin ellas).
            open(["-demo-tmdb", "-demo-title", "series:tt14452776"], orientation)
            let tabs = app.descendants(matching: .any)["title-tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 30), "\(orientation.rawValue): sin pestañas")
            for _ in 0..<4 where !tabs.isHittable { app.swipeUp() }
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Reparto y equipo")).firstMatch.waitForExistence(timeout: 10),
                          "\(orientation.rawValue): la demo no trajo reparto")
            for name in ["Episodios", "Reparto y equipo", "Más como esto", "Detalles"] {
                let tab = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(orientation.rawValue): falta «\(name)»")
                XCTAssertTrue(tab.isHittable, "\(orientation.rawValue): «\(name)» no se alcanza")
                XCTAssertGreaterThanOrEqual(tab.frame.minX, 0); XCTAssertLessThanOrEqual(tab.frame.maxX, app.frame.width, "«\(name)» cortada")
                tab.tap()
            }
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Reparto", "Parecidas")).firstMatch.exists, "sin los nombres cortos")
            shot("ficha-pestanas-\(orientation == .portrait ? "v" : "h")")
        }
    }

    /// Capturas derechas en horizontal: XCUITest las da giradas, así que la prueba avisa (`ready_<nombre>`) y un guion aparte
    /// toma la foto con `simctl io screenshot` y responde (`done_<nombre>`). Solo corre con `ORBITAL_HANDSHAKE` (una carpeta).
    func testLandscapeTour() throws {
        let dir = try XCTUnwrap(ProcessInfo.processInfo.environment["ORBITAL_HANDSHAKE"], "sin ORBITAL_HANDSHAKE")
        let screens: [(String, [String])] = [
            ("inicio", ["-demo-tab", "0"]), ("parati", ["-demo-tab", "1"]), ("mosaico", ["-demo-tab", "1", "-demo-mode", "mosaic"]),
            ("reproductor-pie", ["-demo-title", "series:tt0386676", "-demo-open", "play"]),
            ("subtitulos-pie", ["-demo-title", "series:tt0386676", "-demo-open", "play", "-demo-player", "dock"]), ("listas", ["-demo-tab", "1", "-demo-mode", "lists", "-demo-airings"]),
            ("ficha", ["-demo-tmdb", "-demo-title", "series:tt0386676"]), ("buscar", ["-demo-tab", "2"]),
            ("descargas", ["-demo-tab", "3", "-demo-downloads"]),
            ("decidir", ["-demo-tab", "1", "-demo-open", "decide"]), ("fuentes", ["-demo-title", "series:tt0386676", "-demo-open", "sources"]),
            ("reproductor", ["-demo-title", "series:tt0386676", "-demo-open", "play"]), ("ajustes", ["-demo-open", "settings"]),
            // Las pantallas que llegaron después del 29 oct (Inicio nuevo, el mazo, Lo que ves, Colecciones, la consola).
            ("buscar-dune", ["-demo-tab", "2", "-demo-search", "dune"]), ("biblioteca", ["-demo-tab", "3", "-demo-trakt"]),
            ("ficha-peli", ["-demo-title", "movie:tt1160419"]), ("guardar", ["-demo-title", "movie:tt1160419", "-demo-open", "save"]),
            ("match", ["-demo-tab", "1", "-demo-open", "match"]), ("lo-que-ves", ["-demo-tab", "1", "-demo-open", "watching"]),
            ("colecciones", ["-demo-tab", "1", "-demo-open", "repisa"]), ("anio", ["-demo-open", "year"]),
            ("filtro", ["-demo-tab", "2", "-demo-open", "filter-genre"]), ("calificar", ["-demo-rate"]),
            ("consola", ["-demo-game", "-demo-open", "game"]), ("simpsons", ["-demo-open", "simpsons"]),
            ("primera-vez", ["-demo-first-run"]),
        ]
        let only = ProcessInfo.processInfo.environment["ORBITAL_TOUR_ONLY"]?.split(separator: ",").map(String.init)
        for (name, args) in screens where only?.contains(name) ?? true {
            // `ORBITAL_TOUR_PORTRAIT=1`: todo de pie (el iPad vertical); sin él, acostado salvo las «-pie».
            let portrait = ProcessInfo.processInfo.environment["ORBITAL_TOUR_PORTRAIT"] != nil
            open(args, portrait || name.hasSuffix("-pie") ? .portrait : .landscapeLeft)
            sleep(name.hasPrefix("reproductor") || ["decidir", "match"].contains(name) ? 12 : 8)
            if name.hasPrefix("reproductor") { app.tap(); sleep(1) }
            if name == "subtitulos-pie" { sleep(4) }
            FileManager.default.createFile(atPath: "\(dir)/ready_\(name)", contents: nil)
            for _ in 0..<60 where !FileManager.default.fileExists(atPath: "\(dir)/done_\(name)") { sleep(1) }
        }
    }

    /// El reproductor en horizontal (como se ve una película en el iPad).
    func testPlayerInLandscape() {
        open(["-demo-title", "series:tt0386676", "-demo-open", "play"], .landscapeLeft)
        sleep(8)
        app.tap()
        // Horizontal de verdad: el panel de «Audio y subtítulos» va a la derecha y no sale la rueda del modo iPod.
        XCTAssertFalse(app.descendants(matching: .any)["ipod-center"].exists, "en horizontal no va el modo iPod")
        shot("reproductor-h")
    }
}
