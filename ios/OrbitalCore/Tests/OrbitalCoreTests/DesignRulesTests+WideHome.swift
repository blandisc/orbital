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

    /// Toda página de lista o formulario va en su columna (`readableListWidth`): en la Mac, «Un Simpson al azar», «Series que
    /// sigues» y el historial iban de orilla a orilla mientras las demás páginas de Ajustes guardaban su columna (26 nov 2026).
    func testListPagesKeepTheirColumn() throws {
        for file in try sources(["Screens"]) {
            let code = file.lines.joined(separator: "\n")
            guard code.contains("dsNavigationTitle("), code.contains("List {") || code.contains("Form {") else { continue }
            XCTAssertTrue(code.contains(".readableListWidth()"), "\(file.path): la lista va en su columna (`.readableListWidth()`)")
        }
    }

    /// Un póster de cuadrícula mide lo mismo que uno de fila: en Buscar, los resultados salían más chicos que «Lo más popular
    /// hoy», justo arriba (26 nov 2026). Las columnas se cuentan con `DS.Poster.railWidth`, no con un tope aparte.
    func testGridPostersMatchTheRows() throws {
        let tokens = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Tokens+Imagery.swift" }).lines.joined(separator: "\n")   // DS.Poster
        XCTAssertTrue(tokens.contains("Int(inner / (railWidth + DS.Space.s2))"), "las columnas de `DSPosterGrid` salen del ancho de una fila")
        XCTAssertFalse(tokens.contains("gridCellMax"), "sin un tope aparte para la cuadrícula")
    }

    /// Lo que te manda a Ajustes nombra una página que existe: quedaban «Ajustes › Avanzado», «› Tus idiomas» y «› Reproductor»
    /// de cuando esas páginas se llamaban así (26 nov 2026). Las páginas salen de `SettingsPage.title`; «Accesibilidad» es la
    /// de Ajustes del sistema y lo de «Letterboxd › Ajustes» es de su página.
    func testSettingsPathsNameRealPages() throws {
        let parts = try XCTUnwrap(try sources(["Design"]).first { $0.name == "SettingsParts.swift" }).lines
        let pages = parts.compactMap { line -> String? in
            guard line.contains("case ."), let range = line.range(of: #"Text\("([^"]+)"\)"#, options: .regularExpression) else { return nil }
            return String(line[range].dropFirst(6).dropLast(2))
        } + ["Accesibilidad"]
        XCTAssertGreaterThanOrEqual(pages.count, 10, "se leen las páginas de Ajustes")
        let data = try Data(contentsOf: repo.appendingPathComponent("ios/App/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        var stale: [String] = []
        for key in strings.keys where !key.contains("Letterboxd › Ajustes") {
            var rest = key[...]
            while let found = rest.range(of: "Ajustes › ") {
                let after = rest[found.upperBound...]
                if !pages.contains(where: { after.hasPrefix($0) }) { stale.append(key) }
                rest = after
            }
        }
        XCTAssertEqual(stale, [], "«Ajustes › …» nombra una página que existe")
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
