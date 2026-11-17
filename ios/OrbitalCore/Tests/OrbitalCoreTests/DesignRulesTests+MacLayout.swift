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
        XCTAssertTrue(strip.contains("ToolbarItem(placement: .principal) { if MacTabStrip.centered { MacTabStrip() } }"), "RN2: la cápsula al centro de la barra")
        XCTAssertTrue(try code("HomeHeader.swift").contains(".overlay { if ThisDevice.isMac && MacTabStrip.centered { MacTabStrip() } }"), "RN2: la cápsula al centro en Inicio")
        XCTAssertTrue(strip.contains("if !MacTabStrip.centered { MacTabStrip(compact: true) }"), "RN2: en una ventana angosta la cápsula va junto al logo (al centro se encimaba)")
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
}
