import XCTest

/// Reglas de acomodo que salieron de «Decide por mí» (13 nov 2026, la 2291–2293: «truena cada vez que la abro», «ya no deja
/// regresar», «los botones se comen con la tarjeta»). En `docs/ios-interfaz.md` § «ViewThatFits no se anida ni vive bajo
/// alineación por línea base», § «Un gesto de contenido nunca tapa los controles de la hoja» y § «En una hoja, lo que crece
/// cede ante los controles».
extension DesignRulesTests {
    /// El código sin comentarios (los renglones con `ds-exception:` cuentan como vacíos).
    private func code(_ file: Source) -> String {
        file.lines.map { line in
            if line.contains("ds-exception:") { return "" }
            guard let range = line.range(of: "//") else { return line }
            return String(line[..<range.lowerBound])
        }.joined(separator: "\n")
    }

    /// Lo que va entre las llaves que abren después de `index` (nil si no hay).
    private func block(_ text: String, after index: String.Index) -> Substring? {
        guard let open = text[index...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < text.endIndex {
            if text[i] == "{" { depth += 1 } else if text[i] == "}" { depth -= 1; if depth == 0 { return text[text.index(after: open)..<i] } }
            i = text.index(after: i)
        }
        return nil
    }

    private func line(of index: String.Index, in text: String) -> Int { text[..<index].filter { $0 == "\n" }.count + 1 }

    /// ViewThatFits no se anida ni vive bajo alineación por línea base: mide cada rama en cada pasada, y si adentro hay otro
    /// `ViewThatFits`, una pila por línea base, una guía de alineación o una pieza que las trae (`DSSheetHeader`,
    /// `DSKindFilter`, `DSTextTabs`), o si vive dentro de una pila alineada por línea base o por `.sectionTitle`, cada
    /// pregunta de alineación vuelve a medirlo todo. En la hoja de Decide eso colgó la app (0x8BADF00D). Se decide por el
    /// tamaño de letra (`dynamicTypeSize`) o con una pieza de `Layout`.
    func testViewThatFitsIsNotNestedNorUnderBaseline() throws {
        let files = try sources(["App", "Design", "Screens", "Support", "Platform"])
        let inside = #"ViewThatFits\b|TextBaseline|alignmentGuide\(|alignment: \.sectionTitle|DSSheetHeader\(|DSTextTabs\(|DSKindFilter\("#
        let outer = #"(HStack|VStack|ZStack|HStackLayout|VStackLayout)\(alignment: \.(firstTextBaseline|lastTextBaseline|sectionTitle)"#
        var problems: [String] = []
        for file in files {
            let text = code(file)
            var start = text.startIndex
            while let found = text.range(of: "ViewThatFits(", range: start..<text.endIndex) {
                start = found.upperBound
                guard let body = block(text, after: found.upperBound),
                      let bad = body.range(of: inside, options: .regularExpression) else { continue }
                problems.append("\(file.path):\(line(of: found.lowerBound, in: text)): ViewThatFits con \(body[bad]) adentro")
            }
            start = text.startIndex
            while let found = text.range(of: outer, options: .regularExpression, range: start..<text.endIndex) {
                start = found.upperBound
                guard let body = block(text, after: found.upperBound), body.contains("ViewThatFits(") else { continue }
                problems.append("\(file.path):\(line(of: found.lowerBound, in: text)): ViewThatFits bajo alineación por línea base")
            }
        }
        check(problems, "ViewThatFits no se anida ni vive bajo alineación por línea base")
        // La hoja de Decide, sin ninguno: su encabezado se mide en cada cambio de alto.
        for name in ["DecideView.swift", "DecideControls.swift", "DecideFilterPages.swift", "MatchDeckScreen.swift", "MazoMatch.swift"] {
            let f = try XCTUnwrap(files.first { $0.name == name })
            XCTAssertFalse(code(f).contains("ViewThatFits("), "\(name): sin ViewThatFits (se decide por el tamaño de letra)")
        }
        let decide = try XCTUnwrap(files.first { $0.name == "DecideView.swift" })
        XCTAssertTrue(code(decide).contains("adapts: false"), "las pestañas de Decide sin medir cinco formas")
    }

    /// Un gesto de contenido nunca tapa los controles de la hoja: en Decide el encabezado (título, pestañas, «Filtros») es
    /// uno solo, va encima del contenido (`zIndex`) y la carta del mazo que se avienta hacia arriba no le quita los toques.
    func testContentGestureNeverCoversSheetControls() throws {
        let files = try sources()
        let source = try XCTUnwrap(files.first { $0.name == "DecideView.swift" })
        let decide = code(source), raw = source.lines.joined(separator: "\n")
        XCTAssertEqual(decide.components(separatedBy: "header(m)").count - 1, 1, "un solo encabezado para las dos pestañas")
        XCTAssertTrue(raw.contains("header(m)\n                .zIndex(1)"), "el encabezado va encima del contenido")
        XCTAssertTrue(decide.contains("tabTransition(.deck)") && decide.contains("tabTransition(.trio)"), "cada pestaña entra de su lado")
    }

    /// En una hoja, lo que crece cede ante los controles: la carta del mazo toma lo que sobra después de sus datos y de los
    /// cuatro botones con sus nombres (`MatchDeckLayout`, en una pasada), también con letra grande, y el mazo se queda sobre
    /// el área segura. Nada se encima ni se recorta.
    func testGrowingContentYieldsToControls() throws {
        let files = try sources()
        let mazo = code(try XCTUnwrap(files.first { $0.name == "MazoMatch.swift" }))
        XCTAssertTrue(mazo.contains("struct MatchDeckLayout: Layout"), "la carta y sus datos en una pieza de acomodo")
        XCTAssertFalse(mazo.contains("cardInset"), "sin un estado que se persiga con la medida de la carta")
        let screen = code(try XCTUnwrap(files.first { $0.name == "MatchDeckScreen.swift" }))
        XCTAssertTrue(screen.contains(".layoutPriority(-1)"), "el mazo cede primero")
        XCTAssertFalse(screen.contains("ScrollView {"), "los botones nunca se van fuera de la pantalla")
        let decide = code(try XCTUnwrap(files.first { $0.name == "DecideView.swift" }))
        XCTAssertTrue(decide.contains("edges: mode == .trio ? .bottom : []"), "el mazo, sobre el área segura")
    }

    /// Cambiar de tipo no vuelve a barajar (Fernando, 13 nov 2026): la pastilla de Decide usa `switchKind`, que regresa los
    /// tres que ya veías con ese tipo.
    func testKindChangeKeepsThePicks() throws {
        let controls = code(try XCTUnwrap(try sources().first { $0.name == "DecideControls.swift" }))
        XCTAssertTrue(controls.contains("m.switchKind("), "el tipo cambia sin barajar")
        XCTAssertFalse(controls.contains("m.kind = "), "nadie cambia el tipo por fuera de `switchKind`")
    }
}
