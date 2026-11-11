import XCTest

/// El iPad (y la Mac «Diseñada para iPad»): la app en vertical y en horizontal, con lo principal a la vista. Guarda una
/// captura de cada pantalla en `ORBITAL_SHOTS` (o /tmp/orbital-shots); en horizontal sale girada (así las da XCUITest).
///   xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination 'platform=iOS Simulator,name=Orbital QA iPad' \
///     -only-testing:OrbitalUITests/IPadLayoutUITests
/// En un iPhone no corre (allá la app es vertical y el giro lo prueba `PlayerRotationUITests`).
final class IPadLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: String { ProcessInfo.processInfo.environment["ORBITAL_SHOTS"] ?? "/tmp/orbital-shots" }

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "solo en iPad")
        if name.contains("LandscapeTour") { try XCTSkipIf(ProcessInfo.processInfo.environment["ORBITAL_HANDSHAKE"] == nil, "solo con ORBITAL_HANDSHAKE") }
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func open(_ args: [String], _ orientation: UIDeviceOrientation) {
        app.terminate()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-demo", "-demo-no-idle"] + args
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

    /// La ficha y sus acciones en horizontal (el arte no tapa el botón de ver).
    func testTitleInLandscape() {
        open(["-demo-tmdb", "-demo-title", "series:tt0386676"], .landscapeLeft)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continuar' OR label BEGINSWITH 'Ver '")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "falta el botón de ver")
        XCTAssertTrue(play.isHittable, "el botón de ver queda fuera de la pantalla")
        shot("ficha-h")
    }

    /// «¿Qué vemos?» es una tarjeta de su alto (antes salía cortada a ~70 pt) y el control abre completo.
    func testSheetsAreFullSizeCards() {
        open(["-demo-tab", "1", "-demo-open", "decide"], .portrait)
        // «Más filtros» va al pie de la tarjeta y sale siempre (con sugerencia o con «Nada con…» si un filtro guardado no deja opciones).
        let filters = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Más filtros'")).firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 40), "Decide por mí no enseña «Más filtros»")
        XCTAssertTrue(filters.isHittable, "la tarjeta queda cortada: «Más filtros» no se alcanza")
        shot("decidir-v")
        open(["-demo-tv-now", "-demo-open", "remote"], .landscapeLeft)
        let type = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Escribir en la TV' OR placeholderValue CONTAINS 'Escribir en la TV'")).firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 30), "el control no abre completo")
        shot("control-h")
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

    /// El control en horizontal es un panel fijo a la derecha (se navega a la vez); de pie, la tarjeta de siempre.
    func testRemoteIsAPanelWhenWideAndACardWhenNarrow() {
        open(["-demo-tv-now", "-demo-open", "remote"], .landscapeLeft)
        let close = app.buttons["remote-panel-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30), "en horizontal el control va en un panel con «Cerrar»")
        let paraTi = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Explorar")).firstMatch
        XCTAssertTrue(paraTi.isHittable, "con el panel abierto se sigue navegando")
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 3), "«Cerrar» cierra el panel")
        open(["-demo-tv-now", "-demo-open", "remote"], .portrait)
        let pause = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Escribir en la TV' OR placeholderValue CONTAINS 'Escribir en la TV'")).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 30), "de pie el control abre completo")
        XCTAssertFalse(app.buttons["remote-panel-close"].exists, "de pie es tarjeta, no panel")
        shot("control-v")
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
            ("descargas", ["-demo-tab", "3", "-demo-downloads"]), ("control", ["-demo-tv-now", "-demo-open", "remote"]),
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
