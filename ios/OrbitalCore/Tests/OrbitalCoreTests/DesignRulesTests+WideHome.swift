import XCTest

/// Inicio en pantalla ancha (Fernando, 18 nov 2026: MI2 · II1 · C1–C6, docs/producto/inicio-ancho-2026-11-18/). Regla en
/// `docs/ios-interfaz.md` § «Pantalla ancha: la orilla crece y las filas tienen flechas».
extension DesignRulesTests {
    /// C4: toda fila horizontal de la app lleva ‹ › con el puntero (`.pagingArrows()`); con mouse de rueda no había cómo
    /// moverlas. Antes se revisaban solo los archivos de Inicio y las filas de Explorar, Biblioteca y la ficha se quedaron sin
    /// ellas (recorrido de la Mac, 26 nov 2026). Ahora cada `ScrollView(.horizontal` de toda la app tiene su `.pagingArrows()`
    /// poco después, o dice en su renglón «sin flechas: <motivo>» (cápsulas, selectores, carruseles de página completa).
    func testEveryRowHasPointerArrows() throws {
        let files = try sources(["Design", "Screens"])
        var rows = 0
        for file in files {
            let lines = file.lines
            for (i, line) in lines.enumerated() where line.contains("ScrollView(.horizontal") {
                if line.contains("sin flechas:") { continue }
                rows += 1
                // Hasta la siguiente fila (o 45 renglones): su `.pagingArrows()` va al cerrar la `ScrollView`.
                let next = lines[(i + 1)...].firstIndex { $0.contains("ScrollView(.horizontal") } ?? lines.count
                let after = lines[i..<min(next, i + 45)].joined(separator: "\n")
                XCTAssertTrue(after.contains(".pagingArrows()"),
                              "\(file.name):\(i + 1): una fila horizontal lleva `.pagingArrows()` (C4) o dice «sin flechas: <motivo>»")
            }
        }
        XCTAssertGreaterThanOrEqual(rows, 15, "no encontré las filas de pósters")
    }

    /// PU2-A (26 nov 2026): el letrero de un título dice el mismo nombre que su póster. El logo llega con el nombre de la fuente
    /// (casi siempre en inglés); si el nombre que enseñamos es otro («Tierra de Mafia» y «MOBLAND»), va el nombre en letra.
    /// Todo logo que se pinta junto a un nombre pasa por `titleName.logo(`, `DisplayTitle.logoFits(` o, en la ficha,
    /// `model.logo(shown:)` (compara con `originalTitle`, el nombre que trae el logo; `title` ya llega en tu idioma).
    func testLogosSayTheShownName() throws {
        var checked = 0
        for file in try sources(["Design", "Screens"]) {
            for (i, line) in file.lines.enumerated()
            where (line.contains("TitleLogo(") || line.contains(" logo: ")) && (line.contains("titleName(") || line.contains("title: name")) {
                checked += 1
                XCTAssertTrue(line.contains("titleName.logo(") || line.contains("logoFits(") || line.contains(".logo(shown:"),
                              "\(file.name):\(i + 1): el logo junto a un nombre pasa por `titleName.logo(` (PU2-A)")
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 8, "no encontré los logos de la ficha, la portada y las tarjetas")
    }

    /// PU3-A (26 nov 2026): en la Mac, Ajustes deja el margen de la app como las demás pantallas y la sección abierta se nota,
    /// con el relleno de lo elegido de toda la app (`DS.Opacity.selectedFill`), no con una superficie apenas distinta.
    func testSettingsSidebarKeepsTheGutterAndShowsWhereYouAre() throws {
        let files = try sources(["Design", "Screens"])
        let mac = try XCTUnwrap(files.first { $0.name == "SettingsView+Mac.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(mac.contains(".padding(.leading, DS.Space.gutter)"), "la lista de Ajustes deja el margen de la app")
        let parts = try XCTUnwrap(files.first { $0.name == "SettingsParts.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(parts.contains("if on { DS.text.opacity(DS.Opacity.selectedFill)"), "la sección abierta lleva el relleno de lo elegido")
        for file in files {
            for (i, line) in file.lines.enumerated() where line.range(of: #"(on|selected|isOn|current) \? DS\.surfaceRaised|if (on|selected) \{ DS\.surfaceRaised"#, options: .regularExpression) != nil {
                XCTFail("\(file.name):\(i + 1): lo elegido se marca con `DS.Opacity.selectedFill`, no con `surfaceRaised` (apenas se nota)")
            }
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
