import XCTest

/// Inicio en pantalla ancha (Fernando, 18 nov 2026: MI2 · II1 · C1–C6, docs/producto/inicio-ancho-2026-11-18/). Regla en
/// `docs/ios-interfaz.md` § «Pantalla ancha: la orilla crece y las filas tienen flechas».
extension DesignRulesTests {
    /// C4: toda fila horizontal de la app lleva ‹ › con el puntero (`.pagingArrows()`); con mouse de rueda no había cómo
    /// moverlas. Se cuenta por archivo: cada `ScrollView(.horizontal` de una fila de pósters o tarjetas tiene su `.pagingArrows()`.
    func testEveryHomeRowHasPointerArrows() throws {
        let files = try sources(["Design", "Screens"])
        let rows = ["Rail.swift", "HomeView.swift", "HomeTimeline.swift", "HomeChannels.swift", "HomeTopTen.swift", "HomeMark.swift"]
        for name in rows {
            let text = try XCTUnwrap(files.first { $0.name == name }, name).lines.joined(separator: "\n")
            // Las filas de pósters o tarjetas (no el carrusel de la portada ni las pastillas de servicio, que van ancladas).
            let scrolls = text.components(separatedBy: "ScrollView(.horizontal").count - 1
            let exempt = text.components(separatedBy: "scrollTargetBehavior(.paging)").count - 1 + (name == "HomeTopTen.swift" ? 1 : 0)
            let arrows = text.components(separatedBy: ".pagingArrows()").count - 1
            XCTAssertGreaterThanOrEqual(arrows, scrolls - exempt, "\(name): cada fila horizontal lleva `.pagingArrows()` (C4)")
        }
    }

    /// C2: el margen de los lados crece con la ventana cuando hay espacio (`DS.Space.wideGutter`), no es un número fijo.
    func testTheGutterGrowsWithTheWindow() throws {
        let files = try sources(["Design"])
        let tokens = try XCTUnwrap(files.first { $0.name == "Tokens.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(tokens.contains("static var gutter: CGFloat { WindowMetrics.roomy ? wideGutter : s4 }"),
                      "`DS.Space.gutter` usa `wideGutter` con espacio (C2)")
        XCTAssertFalse(tokens.contains("static let gutter"), "el margen no vuelve a ser fijo")
    }

    /// MI2 · II1: el tablero se decide en un solo lugar (`HomeBoard.isOn`) y Inicio no lo repite a mano.
    func testHomeBoardIsDecidedInOnePlace() throws {
        let files = try sources(["Screens"])
        let home = try XCTUnwrap(files.first { $0.name == "HomeView.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(home.contains("HomeBoard.isOn(typeSize)"), "Inicio pregunta a `HomeBoard.isOn` si va el tablero")
        XCTAssertFalse(home.contains("DS.HomeBoard.from"), "el ancho del tablero no se compara a mano en Inicio")
        // La portada llena su ancho, alineada con las filas de abajo: con el alto fijo los puntos cabían adentro y el arte se
        // encogía al centro, con hueco a los lados (24 nov 2026: «los pósters están como descentrados»).
        XCTAssertTrue(home.contains("spotlightPart(model).frame(width: HomeBoard.heroWidth)\n") || home.contains("spotlightPart(model).frame(width: HomeBoard.heroWidth)\r"),
                      "la portada del tablero lleva solo su ancho; su alto lo da su proporción")
    }
}
