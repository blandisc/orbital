import XCTest

/// MO1 y X1 (Fernando, 13 nov 2026). «La puerta de algo grande es grande y tiene nombre: nada importante vive solo como un
/// ícono en una barra» y «el control de una sección va en el renglón de su rótulo». Reglas en `docs/ios-interfaz.md`.
extension DesignRulesTests {
    private func file(_ name: String, in files: [Source]) throws -> String {
        try XCTUnwrap(files.first { $0.name == name }, "falta \(name)").lines.joined(separator: "\n")
    }

    /// Lo que va entre `.toolbar {` y su cierre (contando llaves): los botones de la barra de arriba de una pantalla.
    private func toolbars(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let start = rest.range(of: ".toolbar {") {
            var depth = 0
            var end = start.upperBound
            for i in rest[start.lowerBound...].indices {
                if rest[i] == "{" { depth += 1 }
                if rest[i] == "}" { depth -= 1; if depth == 0 { end = i; break } }
            }
            out.append(String(rest[start.lowerBound..<end]))
            rest = rest[end...]
        }
        return out
    }

    /// El mosaico no vive en la barra de Explorar: su puerta es la portada, con su chapa (ícono y nombre), se toca entera y se
    /// hunde al tocarla. Ninguna barra de arriba lleva un botón que cambie al mosaico.
    func testTheMosaicDoorIsTheCoverWithAName() throws {
        let files = try sources()
        for source in files {
            for bar in toolbars(source.lines.joined(separator: "\n")) {
                XCTAssertFalse(bar.contains("mode = .mosaic") || bar.contains("DS.Symbol.mosaic") || bar.contains("square.grid.3x3"),
                               "\(source.name): el mosaico no vive como un ícono en la barra de arriba; su puerta es la portada (MO1)")
            }
        }
        let cover = try file("ParaTiB.swift", in: files)
        XCTAssertTrue(cover.contains("MosaicDoorBadge(count: count)"), "La portada lleva su chapa con cuántas piezas trae")
        XCTAssertTrue(cover.contains("Image(systemName: DS.Symbol.mosaic)") && cover.contains("Text(\"Pasea por tus \\(count)\")"),
                      "La chapa lleva ícono y nombre (no un ícono solo ni una cápsula de solo texto)")
        XCTAssertTrue(cover.contains("Button(action: walk)") && cover.contains("DS.ParaTiB.doorPressed") && cover.contains("DS.Motion.press"),
                      "Toda la portada se toca y se hunde al tocarla (DS.Motion.press)")
        XCTAssertTrue(cover.contains("private var isDoor: Bool { count > 0 }"), "Sin piezas, la portada no promete un muro vacío (F8)")
        let lists = try file("ListsView.swift", in: files)
        XCTAssertTrue(lists.contains("count: model.mosaic.count"), "La chapa cuenta las piezas del mosaico de verdad")
        XCTAssertTrue(lists.contains("beyond: model.mosaic.isEmpty ? nil : DS.ParaTiB.doorPull"), "Sin piezas tampoco se abre al jalar")
    }

    /// La primera vez la portada se endereza sola una sola vez (recordado), nunca con «Reducir movimiento»; se mueve con
    /// `DS.Motion.grow` (abrir) y `DS.Motion.fold` (cerrar), y jalar solo abre con el dedo puesto, más allá de «actualizar».
    func testTheMosaicDoorMovesWithTokensAndTheRefreshStaysShort() throws {
        let files = try sources()
        let cover = try file("ParaTiB.swift", in: files)
        XCTAssertTrue(cover.contains("@AppStorage(MosaicCover.hintKey)") && cover.contains("hintSeen = true"), "El aviso sale una sola vez")
        XCTAssertTrue(cover.contains("quiet = reduceMotion") && cover.contains("guard isDoor, settled, !quiet"), "Nunca con «Reducir movimiento»")
        XCTAssertTrue(cover.contains("DS.Motion.grow(reduceMotion)") && cover.contains("DS.Motion.fold(reduceMotion)"),
                      "Abre con DS.Motion.grow y se recoge con DS.Motion.fold")
        XCTAssertNil(cover.range(of: #"DS\.Motion\.(pop|spring|toastPop|toastGrow)\b|\.bouncy\b"#, options: .regularExpression),
                     "La portada no rebota: resorte sobrio")
        let refresh = try file("RefreshOrbit.swift", in: files)
        XCTAssertTrue(refresh.contains("if interacting, let beyond { state.door = distance >= beyond }"),
                      "La puerta solo cuenta con el dedo puesto (la inercia no abre nada)")
        XCTAssertTrue(refresh.contains("guard let beyond, beyond > DS.Refresh.threshold"), "La puerta va más allá de «actualizar»")
        let tokens = try file("Tokens+Home.swift", in: try sources(["Design"]))
        let pull = try XCTUnwrap(tokens.range(of: #"doorPull: CGFloat = ([0-9.]+)"#, options: .regularExpression).map { Double(tokens[$0].split(separator: "=").last!.trimmingCharacters(in: .whitespaces)) ?? 0 })
        XCTAssertGreaterThanOrEqual(pull, 80 * 1.5, "Para entrar hay que jalar bastante más que para actualizar (DS.Refresh.threshold = 80)")
    }

    /// F1: del mosaico siempre se sale con un botón a la vista, en iPhone, iPad y Mac (no solo deslizando de lado).
    func testTheMosaicAlwaysHasAVisibleWayOut() throws {
        let view = try file("ParaTiView.swift", in: try sources())
        XCTAssertTrue(view.contains("accessibilityIdentifier(\"paraTi-back\")"), "El mosaico tiene su flecha para regresar")
        XCTAssertEqual(view.components(separatedBy: "{ mosaicBack(m) }").count - 1, 2,
                       "La salida va a la izquierda en el iPhone y a la derecha en el iPad y la Mac (allá lo de la izquierda se va a «⋯»)")
        XCTAssertTrue(view.contains("DS.Symbol.close"), "En el iPad y la Mac la salida es ✕ (DS.Symbol.close)")
    }

    /// X1: el selector de tipo de Explorar va en el renglón de su rótulo (el accesorio de `DSChapterHead`), que baja entero a su
    /// propio renglón si no cabe; nunca suelto debajo del rótulo.
    func testTheSectionControlSitsInItsHeadRow() throws {
        let files = try sources()
        let lists = try file("ListsView.swift", in: files)
        let lines = lists.components(separatedBy: "\n")
        let filter = try XCTUnwrap(lines.firstIndex { $0.contains("DSKindFilter(") })
        XCTAssertTrue(lines[max(0, filter - 2)..<filter].contains { $0.contains("DSChapterHead(") && $0.hasSuffix("{") },
                      "El selector de «Lo que se ve hoy» es el accesorio de su DSChapterHead (en su renglón, a la derecha)")
        let head = try file("Collections.swift", in: files)
        XCTAssertTrue(head.contains("ViewThatFits(in: .horizontal)") && head.contains("line: false"),
                      "DSChapterHead pone el control en lugar de la línea y, si no cabe, lo baja entero (ViewThatFits)")
    }
}
