import XCTest

/// iPad y Mac tienen su propio tamaño (MAC-A, Fernando, 16 nov 2026: «crea otro mini sistema de diseño para iPad y Mac con
/// nuevos tamaños»). Regla en `docs/ios-interfaz.md` § «iPad y Mac: su propio tamaño»: macOS dibuja la app al 77 %, así que en
/// la Mac la letra va por `DS.styled` (sin Dynamic Type en la Mac), las pestañas van en el renglón del logo y no en un carril
/// aparte, y el arte grande se pide al ancho de la ventana.
extension DesignRulesTests {
    func testMacHasItsOwnSizes() throws {
        let design = try sources(["Design"])
        let tokens = try XCTUnwrap(design.first { $0.name == "Tokens.swift" })
        let mac = try XCTUnwrap(design.first { $0.name == "Tokens+Mac.swift" }, "El mini sistema de la Mac vive en Tokens+Mac.swift")
        let code = (tokens.lines + mac.lines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        // Toda receta de letra pasa por `DS.styled`: un `.system(.estilo, …)` suelto en la Mac sale al 77 % (de 13 en vez de 16).
        let loose = code.filter { $0.contains(".system(.") || $0.contains(".system(face.style") }
            .filter { !$0.contains("guard ProcessInfo.processInfo.isiOSAppOnMac else { return .system(style") }
        XCTAssertEqual(loose, [], "Las letras de los tokens van por DS.styled(…) para tener su tamaño de Mac")
        let joined = code.joined(separator: "\n")
        XCTAssertTrue(joined.contains("enum Mac {"), "Los tamaños de la Mac viven en DS.Mac")
        XCTAssertTrue(joined.contains("static let typeScale"), "DS.Mac.typeScale: cuánto crece la letra en la Mac")
        // Un control de tamaño fijo con ícono crece como la letra en la Mac: el selector Todo · Películas · Series se veía con
        // el ícono llenando su círculo (Fernando, 16 nov 2026: «dale una pulida a los selectores»).
        let learn = try XCTUnwrap(design.first { $0.name == "Tokens+Learn.swift" }).lines.joined(separator: "\n")
        for size in ["closed", "open", "dense"] {
            XCTAssertTrue(learn.contains("static var \(size): CGFloat { Mac.sized("), "DS.KindPill.\(size) crece en la Mac")
        }
        // El arte a sangre se pide al ancho de la ventana solo en la Mac (si no, la portada se ve pixeleada); en iPhone y iPad,
        // 800 (más era casi el triple de memoria por imagen en el iPad).
        for token in ["static var bleed: CGFloat {", "static var wide: CGFloat {"] {
            let line = try XCTUnwrap(code.first { $0.contains(token) }, token)
            XCTAssertTrue(line.contains("ProcessInfo.processInfo.isiOSAppOnMac ?") && line.contains("WindowMetrics.column.width"),
                          "\(token) crece con la ventana solo en la Mac")
        }
    }

    func testMacTabsLiveInTheLogoRow() throws {
        let files = try sources(["Design", "Screens"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // Cada pantalla de arriba lleva las pestañas de la Mac en su renglón (si falta una, en la Mac esa pantalla queda sin pestañas).
        XCTAssertTrue(try code("HomeHeader.swift").contains("MacTabStrip()"), "Inicio: las pestañas en el renglón del logo")
        for screen in ["ParaTiView.swift", "DownloadsView.swift", "BrowseView.swift"] {
            XCTAssertTrue(try code(screen).contains(".macTopBar()"), "\(screen): el logo y las pestañas de la Mac en su barra")
        }
        let root = try code("RootView.swift")
        XCTAssertEqual(root.components(separatedBy: ".macHidesTabBar()").count - 1, 4, "Las cuatro pestañas esconden la barra del sistema en la Mac")
        let mac = try code("MacTabStrip.swift")
        XCTAssertTrue(root.contains(".modifier(TabStyle())") && mac.contains("content.tabViewStyle(.tabBarOnly)"),
                      "En la Mac no hay barra lateral (salía vacía y tapaba el contenido)")
        // Solo el logo de Inicio dice dónde está: dos que lo dijeran se pelean y la app se traba redibujando.
        XCTAssertTrue(try code("MacTabStrip.swift").contains("AppMark(small: true, reportsFrame: false)"), "El logo de la barra de la Mac no reporta su lugar")
        // Con el título del sistema, las pestañas de la barra se iban a «More»; en la barra la Mac reporta letra de accesibilidad.
        for (screen, title) in [("DownloadsView.swift", "Biblioteca"), ("BrowseView.swift", "Buscar")] {
            XCTAssertTrue(try code(screen).contains(".navigationTitle(ThisDevice.isMac ? Text(verbatim: \"\") : Text(\"\(title)\"))"), "\(screen): sin título en la Mac")
        }
        XCTAssertTrue(try code("Filters.swift").contains("tabs(titles: ThisDevice.isMac ||"), "En la Mac las pestañas llevan nombre")
        // La barra le ofrece poco ancho a lo de la izquierda: sin su tamaño propio, los nombres se recortaban hasta desaparecer.
        XCTAssertTrue(try code("MacTabStrip.swift").contains(".fixedSize()"), "Las pestañas de la barra de la Mac conservan su nombre")
        XCTAssertTrue(root.contains(".macDefaults()") && mac.contains(".controlSize(.large)"), "En la Mac los botones del sistema van en grande")
    }

    /// Inicio en ventana muy ancha se acomoda como la entrada del escritorio de la tele (Fernando, 16 nov 2026: «toma más
    /// inspiración de la app de escritorio para Inicio»): portada en tarjeta a la izquierda y una lista a la derecha.
    func testWideHomeLooksLikeTheDesktop() throws {
        let files = try sources(["Design", "Screens"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        let tokens = try code("Tokens+Home.swift")
        XCTAssertTrue(tokens.contains("static let splitFrom: CGFloat = 1100"), "Desde qué ancho Inicio va a dos columnas")
        XCTAssertTrue(tokens.contains("static var split: Bool { ProcessInfo.processInfo.isiOSAppOnMac && WindowMetrics.column.width >= splitFrom }"),
                      "Solo la Mac, y lo decide la columna (el iPad acostado no cambia)")
        let home = try code("HomeView.swift")
        XCTAssertTrue(home.contains("if twoColumns { splitTop(model, continuing: continuing) }"), "Inicio arma las dos columnas")
        XCTAssertTrue(home.contains("if continuing.isEmpty { upNextList(model) } else { continueList(model, items: continuing) }"),
                      "Sin nada a medias, la derecha no queda vacía")
        XCTAssertTrue(home.contains("DS.HomeHero.split && !spotlightItems(home.model).isEmpty"),
                      "Dos columnas solo si el carrusel tiene algo con el tipo puesto (si no, la izquierda quedaba vacía)")
        XCTAssertTrue(home.contains("if !next.isEmpty { DSSectionHead(title: Text(\"Lo que sigue\")"), "Sin renglones, sin encabezado suelto")
        XCTAssertTrue(home.contains("card: twoColumns"), "En dos columnas la portada es tarjeta (no pasa detrás de la barra)")
        XCTAssertTrue(try code("Projection.swift").contains("struct StillRow: View"), "El renglón de «Seguir viendo» es pieza del catálogo")
    }
    /// En la Mac lo de Inicio y Explorar llena la ventana (Fernando, 16 nov 2026: «en plataformas… no se extiende completamente
    /// a la derecha, tampoco premios», «en lo que sigue meterle una fila más», «Top 10 pasa del 4 al 6»).
    func testMacRowsFillTheWindow() throws {
        let files = try sources(["Design", "Screens"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        let screens = try code("Tokens+Screens.swift"), home = try code("Tokens+Home.swift")
        XCTAssertTrue(home.contains("static var scale: CGFloat {") && home.contains("static var maxWidth: CGFloat { baseWidth * scale }"),
                      "Plataformas, Premios y Estudios crecen hasta llenar el renglón en la Mac")
        XCTAssertTrue(screens.contains("static var emblem: CGFloat { 70 * PlatformFan.scale }"), "El emblema crece con su tarjeta")
        XCTAssertTrue(try code("ListsView.swift").contains("await model.loadRankings(hub)"), "Cada plataforma pide su ranking si llega vacía (Prime Video salía en blanco)")
        XCTAssertTrue(home.contains("static var splitRows: Int {"), "«Lo que sigue» llena la altura de la portada (no un número fijo)")
        XCTAssertTrue(home.contains("static func width(count: Int) -> CGFloat {"), "Canales llena el renglón en la Mac")
        // El puesto es el de lo que ves: con el del ranking mezclado, al quedarse con las series brincaba del 4 al 6.
        XCTAssertTrue(try code("HomeTopTen.swift").contains("RankedPosterCard(rank: i + 1,"), "El Top 10 se numera dentro de lo que ves")
        XCTAssertTrue(try code("ParaTiB.swift").contains("struct DecideStrip: View"), "La entrada de «Decide por mí» se asoma en la Mac")
        XCTAssertTrue(try code("BrowseView.swift").contains("if ThisDevice.isMac, !model.popular.isEmpty { popularWall(model) }"), "Buscar vacío en la Mac: un muro de lo popular")
        // Sobre el mosaico de Explorar las pestañas se perdían entre los pósters.
        XCTAssertTrue(try code("MacTabStrip.swift").contains(".frame(height: DS.Mac.topScrim)"), "Una sombra bajo la barra de la Mac")
        // Segunda pasada (16 nov): el muro de Buscar llena lo alto, Inicio lleva la sombra bajo la barra, una sola pestaña no
        // se dibuja y lo que se lee en la ficha va a un ancho de lectura.
        XCTAssertTrue(try code("BrowseView.swift").contains("private static func wallRows(posterWidth: CGFloat) -> Int {"), "El muro de Buscar llena lo alto")
        XCTAssertTrue(try code("HomeView.swift").contains(".macTopShade()"), "Inicio también lleva la sombra bajo la barra")
        XCTAssertTrue(try code("Filters.swift").contains("if options.count < 2 { EmptyView() }"), "Una sola pestaña no se dibuja")
        XCTAssertTrue(try code("TitleView.swift").contains(".frame(maxWidth: DS.TitleAction.wideReading, alignment: .leading)"), "Las reseñas a ancho de lectura")
        // Cuarta pasada (16 nov, MB1 · MA1 · MS1 · MC1): la Mac con su propio acomodo.
        XCTAssertTrue(try code("DownloadsView.swift").contains("MacSidebar(options:"), "Biblioteca en la Mac: sus partes en una columna a la izquierda")
        XCTAssertTrue(try code("SettingsView+Mac.swift").contains(".environment(\\.settingsPane, SettingsPane("), "Ajustes en la Mac: lista y detalle")
        XCTAssertTrue(try code("BrowseView.swift").contains("if ThisDevice.isMac { MacSearchField(text: $query, focused: $typing)"), "Buscar en la Mac: el campo grande")
        XCTAssertTrue(try code("Filtro.swift").contains("count: mac ? FilterPage.main.count :"), "Buscar en la Mac: los seis mosaicos en una fila")
        // Con 76 pt de alto en una ventana de Mac eran franjas de formulario (Fernando, 16 nov 2026): mosaicos grandes y campo alto.
        XCTAssertTrue(try code("Filtro.swift").contains("minHeight: big ? DS.Mac.doorTileHeight"), "Los mosaicos de Buscar en la Mac son grandes")
        XCTAssertTrue(try code("MacTabStrip.swift").contains(".textFieldStyle(.plain).font(DS.TextRecipe.title.font)"), "El campo de Buscar en la Mac lleva letra grande")
        XCTAssertTrue(try code("MacTabStrip.swift").contains("UIView.setAnimationsEnabled(false)"), "En la Mac la pestaña cambia al momento")
        // La ficha y los tutoriales crecen como la letra (si no, los botones grandes de la Mac iban apretados).
        for token in ["static var wideColumn: CGFloat { Mac.sized(", "static var wideLogoWidth: CGFloat { Mac.sized(", "static var readable: CGFloat { Mac.sized("] {
            XCTAssertTrue(screens.contains(token), token)
        }
        let learn = try code("Tokens+Learn.swift")
        for token in ["static var bubble: CGFloat { Mac.sized(", "static var maxHeight: CGFloat { Mac.sized("] {
            XCTAssertTrue(learn.contains(token), token)
        }
    }

    /// En la Mac el vidrio casi no se ve sobre el fondo oscuro: los controles de vidrio de las pantallas (no los del
    /// reproductor, que van sobre el video) llevan `macPillBase` (Fernando, 16 nov 2026: «el selector de series, películas o
    /// todo se ve medio feo»). Y en la Mac los íconos del tipo van de línea (el rollo relleno se veía como bloque).
    func testMacGlassControlsHaveABase() throws {
        let files = try sources(["Design", "Screens"])
        let player = ["PlayerControls.swift", "SubtitlePanel.swift"]
        for file in files where !player.contains(file.name) {
            for (i, line) in file.lines.enumerated() where line.contains(".glassEffect(.regular.interactive(), in: Capsule())") || line.contains(".glassEffect(.regular.interactive(), in: Circle())") {
                let next = i + 1 < file.lines.count ? file.lines[i + 1] : ""
                XCTAssertTrue(next.contains(".macPillBase("), "\(file.name):\(i + 1): un control de vidrio sin su base en la Mac")
            }
        }
        let filters = try XCTUnwrap(files.first { $0.name == "Filters.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(filters.contains("static var variant: SymbolVariants { ThisDevice.isMac ? .none : .fill }"), "En la Mac los íconos del tipo van de línea")
    }
}
