import XCTest

/// El replanteamiento de la Mac, como la app de escritorio de la tele (Fernando, 16 nov 2026: «hazlo de acuerdo a tus
/// sugerencias», RF2 · RI2 · RN2 · RP2 · RB2). Regla en `docs/ios-interfaz.md` § «La Mac con su propio acomodo».
extension DesignRulesTests {
    func testMacLooksLikeTheDesktop() throws {
        let files = try sources(["Design", "Screens", "App"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // RF2: la ficha en la Mac sin pestañas, todo en filas a lo ancho, y las reseñas en columnas de igual alto.
        let title = try code("TitleView.swift")
        XCTAssertTrue(title.contains("if ThisDevice.isMac { macSections(model) } else { tabbedSections(model) }"), "RF2: la ficha de la Mac va en filas, sin pestañas")
        XCTAssertTrue(title.contains("columns: DS.Mac.reviewColumns"), "RF2: las reseñas en columnas")
        let reviews = try code("Letterboxd.swift")
        XCTAssertTrue(reviews.contains("Grid(alignment: .topLeading") && !reviews.contains("LazyVGrid"), "RF2: las reseñas en `Grid` (con `LazyVGrid` cada tarjeta medía distinto)")
        // RI2: Inicio como la tele: la portada a lo ancho y lo que sigue encimado en su borde (ya no la portada partida).
        let home = try code("HomeView.swift")
        XCTAssertFalse(home.contains("splitTop("), "RI2: Inicio ya no se parte en dos columnas")
        XCTAssertTrue(home.contains("upNextRail(model)"), "RI2: sin nada a medias, lo que sigue va en la fila encimada")
        // RN2: las pestañas en una cápsula al centro (si cabe) y «Buscar» junto al logo, en el orden de ⌘1 ⌘2 ⌘3.
        let strip = try code("MacTabStrip.swift")
        XCTAssertTrue(strip.contains(".overlay { if MacTabStrip.centered { MacTabStrip() } }"), "RN2: la cápsula al centro del renglón de arriba")
        XCTAssertTrue(try code("HomeHeader.swift").contains(".overlay { if ThisDevice.isMac && MacTabStrip.centered { MacTabStrip() } }"), "RN2: la cápsula al centro en Inicio")
        XCTAssertTrue(strip.contains("if !MacTabStrip.centered { MacTabStrip(compact: true)"), "RN2: en una ventana angosta la cápsula va junto al logo (al centro se encimaba)")
        XCTAssertTrue(strip.contains("struct MacSearchChip: View"), "RN2: «Buscar» junto al logo")
        let order = ["Text(\"Inicio\")", "Text(\"Explorar\")", "Text(\"Biblioteca\")"].compactMap { strip.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 3); XCTAssertEqual(order, order.sorted(), "RN2: la cápsula en el orden del menú «Ir»")
        XCTAssertFalse(strip.contains("fill(DS.paper)"), "RN2: la elegida con el color del texto (crema fijo no se distinguía en modo claro)")
        // RP2: todo enlace con póster responde al puntero en la Mac; el marco y ▶ ＋ van sobre el póster, no sobre la tarjeta.
        XCTAssertTrue(try code("TitlePanel.swift").contains(".macPosterHover(route)"), "RP2: los pósters responden al puntero")
        XCTAssertTrue(try code("RichTitle.swift").contains(".macPosterHover(nil)"), "RP2: también los pósters de TMDB")
        XCTAssertTrue(try code("Posters.swift").contains(".macPosterBounds()"), "RP2: el póster dice dónde está, para su marco y ▶ ＋")
        let hover = try code("MacPosterHover.swift")
        XCTAssertTrue(hover.contains("struct PosterQuick: Equatable"), "RP2: ▶ ＋ comparables (si no, cada pasada de la raíz repinta cada póster)")
        XCTAssertTrue(hover.contains("DS.Mac.quickMinWidth") && hover.contains("accessibilityAction(named:"), "RP2: ▶ ＋ solo en pósters grandes y también en VoiceOver")
        XCTAssertTrue(try code("RootView.swift").contains(".environment(\\.posterQuick, ThisDevice.isMac ? .app(env) : nil)"), "RP2: ▶ y ＋ conectados en la raíz")
        XCTAssertTrue(try code("AppEnvironment+Titles.swift").contains("inList == true { return notify(\"Ya está en Mi lista\") }"), "RP2: ＋ sobre algo guardado no ofrece «Deshacer» (lo sacaba de Mi lista)")
        // RB2: en la Mac un aviso vacío ocupa casi todo el alto de lo que lo contiene, no de la ventana.
        let feedback = try code("Feedback.swift")
        XCTAssertTrue(feedback.contains("containerRelativeFrame(.vertical) { length, _ in length * DS.Mac.emptyShare }"), "RB2: el aviso vacío al centro de su lugar en la Mac")
        XCTAssertFalse(feedback.contains("WindowMetrics.size.height * DS.Mac.emptyShare"), "RB2: no con el alto de la ventana (en una hoja se salía)")
    }

    /// La Mac no tiene sensor de movimiento: crear un `CMMotionManager` ahí y soltarlo al salir de una pantalla con cielo
    /// (Ajustes) trababa la app para siempre (17 nov 2026). Todo sensor de CoreMotion se pide solo fuera de la Mac.
    func testNoMotionSensorOnTheMac() throws {
        for file in try sources(["Design", "Screens", "App", "Platform"]) {
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for sensor in ["CMMotionManager()", "CMAltimeter()", "CMPedometer()", "CMHeadphoneMotionManager()"] {
                guard let use = text.range(of: sensor) else { continue }
                let before = text[text.startIndex..<use.lowerBound].suffix(400)
                XCTAssertTrue(before.contains("guard !ProcessInfo.processInfo.isiOSAppOnMac"),
                              "\(file.name): \(sensor) sin «guard !ProcessInfo.processInfo.isiOSAppOnMac» justo antes: en la Mac traba la app")
            }
        }
    }

    /// MA2 (17 nov 2026): en la Mac, lo que se abre desde una página de Ajustes se queda a la derecha, junto a la lista
    /// (`PaneLink`). Con un `NavigationLink` se empujaba a toda la ventana: una columna angosta sola, sin la lista. Y una sola
    /// pantalla de código para conectar cuentas (`DeviceCodeCard`).
    func testSettingsPagesOpenBesideTheList() throws {
        let pages = ["SettingsView.swift", "SettingsView+Cuentas.swift", "SettingsView+Idiomas.swift", "DebridAccountView.swift",
                     "TorrentioSettings.swift", "TorrentioSettings+Opciones.swift", "AddonsSettings.swift", "AddonDetail.swift",
                     "VoiceGuideView.swift", "YourLanguagesView.swift"]
        let files = try sources(["Design", "Screens"])
        for name in pages {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            XCTAssertFalse(text.contains("NavigationLink {"), "\(name): en Ajustes, `PaneLink` (en la Mac abre a la derecha), no `NavigationLink`")
        }
        for file in files where file.name != "Guide.swift" {
            let text = file.lines.joined(separator: "\n")
            XCTAssertFalse(text.contains("Escribe este código en \\("), "\(file.name): el código para conectar una cuenta va en `DeviceCodeCard`")
        }
    }
    /// Rendimiento y tamaños de la Mac (17 nov 2026: «muchos problemas de performance… un monitor ultrawide y no funciona»).
    /// Regla en `docs/ios-interfaz.md` § «Rendimiento de la Mac».
    func testMacPerformanceAndWideWindows() throws {
        let files = try sources(["Design", "Screens", "Platform"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // Una animación larga de fondo no va con `withAnimation` ni `TimelineView`: dejan el reloj de pantalla de SwiftUI
        // corriendo a 165 Hz aunque ya terminaron (Inicio quieto gastaba ~48 % de CPU). La respiración va con `Breathing`.
        let art = try code("Art.swift")
        XCTAssertTrue(art.contains("struct Breathing<Content: View>: View") && art.contains("Breathing(from: breathFrom)"), "la portada respira con `Breathing` (una tarea que se detiene)")
        XCTAssertFalse(art.contains("TimelineView"), "Art.swift: sin `TimelineView` (no suelta el reloj de pantalla)")
        XCTAssertFalse(try code("Tokens.swift").contains("static let breathe"), "sin la animación larga `DS.Motion.breathe`")
        // El cielo en la Mac a 2 cuadros por segundo (era ~9 de 10 % de la CPU en reposo).
        XCTAssertTrue(try code("Tokens+Sky.swift").contains("isiOSAppOnMac ? 1.0 / 2"), "el cielo de la Mac, lento")
        // Ultrawide: la portada de Inicio sin tope de ancho en la Mac y el arte a la derecha, fundido (no un cuadro al centro).
        XCTAssertTrue(try code("Tokens+Home.swift").contains("isiOSAppOnMac ? fitted : min(aspectWideMax, fitted)"), "Inicio: en la Mac la portada no se topa a lo ancho")
        XCTAssertTrue(try code("Posters.swift").contains("ZStack(alignment: bleed ? .trailing : .center)"), "arte de portada en ventana muy ancha: a la derecha, fundido")
        // Las tarjetas a lo ancho llenan la fila como las demás (con tope unas seguían y otras no; Fernando, 17 nov 2026):
        // «Porque viste…» pone el encabezado al lado en ventanas anchas y «Decide por mí» llena su tira.
        XCTAssertFalse(try code("ParaTiB.swift").contains(".macCardWidth()"), "«Decide por mí» a todo lo ancho, como las otras filas")
        XCTAssertTrue(try code("Collections.swift").contains("becauseSideFrom"), "«Porque viste…»: encabezado al lado en ventana ancha")
        // Abrir pantallas rápido: estantes perezosos, pósters de adorno ligeros y Ajustes sin tipos gigantes.
        XCTAssertTrue(try code("ListsView.swift").contains("ShelfStack(lazy:"), "Explorar arma sus estantes al llegar a ellos")
        XCTAssertTrue(try code("ParaTiB.swift").contains("decorative: true"), "el muro y la tira de Explorar con pósters de adorno")
        XCTAssertTrue(try code("SettingsView.swift").contains("-> AnyView"), "Ajustes: el destino borrado de tipo (abría lento)")
        // La ficha ancha (iPad, Mac): el margen crece con la ventana; con 40 pt fijos «Ver» quedaba clavado a la izquierda.
        XCTAssertTrue(try code("TitleView+Detalles.swift").contains("wideStage.leading"), "ficha ancha: el margen sale de la receta `WideStage`")
        XCTAssertTrue(try code("TitleView.swift").contains("StageSides(") && code("TitleView.swift").contains("StageEdges("), "ficha ancha: escenario centrado con arte a los lados")
        // M2 · I1 · A1 (Fernando, 18 nov 2026): banda a dos columnas en ventanas anchas y acostadas (Mac, iPad acostado),
        // con el arte más bajo; en la Mac las acciones son círculos con su nombre siempre visible.
        let title = try code("TitleView.swift")
        XCTAssertTrue(title.contains("if wideBand {") && title.contains("DS.TitleAction.bandHeroShare"), "M2: la banda a dos columnas con el arte más bajo")
        XCTAssertTrue(title.contains(".environment(\\.roundActionTiles, roundTiles)") && title.contains("roundTiles: Bool { ThisDevice.isMac"), "A1: círculos con nombre solo en la Mac")
        XCTAssertTrue(try code("TitleActions.swift").contains("private var roundBody"), "A1: la pieza del círculo vive en el catálogo")
        // «más» solo si el texto de verdad se corta: nada de contar letras.
        XCTAssertTrue(try code("TitleView+Detalles.swift").contains("FoldingText("), "la sinopsis usa `FoldingText`")
        for file in files where file.lines.joined().contains("\"más\"") || file.lines.joined().contains("\"Más\"") {
            let text = file.lines.joined(separator: "\n")
            XCTAssertFalse(text.range(of: #"\.count > DS\.[A-Za-z.]*Fold"#, options: .regularExpression) != nil, "\(file.name): «más» por número de letras; usa `FoldingText`")
        }
        XCTAssertFalse(try code("TitleView+Detalles.swift").contains("? DS.TitleAction.wideSide :"), "ficha ancha: sin el margen fijo de 40 pt")
        // La ventana más chica de la Mac: 560 (a 420 la barra de arriba se salía).
        XCTAssertTrue(try code("WindowMetrics.swift").contains("isiOSAppOnMac ? 560 : 375"), "la ventana mínima de la Mac, 560")
    }
}
