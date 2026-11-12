import XCTest

/// Las acciones de un título y lo que acompaña a un control (Fernando, 12 nov 2026: «Me gusta la F1. Y vamos a ir con R1»).
/// Reglas en `docs/ios-interfaz.md` § «Las acciones de un título» y § «Lo que acompaña a un control va en su misma línea»:
/// - las acciones de la ficha viven en una sola fila de mosaicos de un renglón (Guardar · Descargar · Vista · Tráiler); no hay
///   botones de acción sueltos en otra parte de la ficha (los círculos de la temporada, «Vista» en el menú de «Guardar»);
/// - una sola fila de estrellas a la vista (la de la serie o la película); la temporada se califica desde «Vista»;
/// - lo que acompaña a un control va en su misma línea y centrado con él: «3 de 22 vistos» con la temporada, «Tu nota» con
///   tus estrellas y, bajo «Continuar», la barra, «quedan…» y ↺ «Desde el principio» (botón redondo, sin texto en color).
extension DesignRulesTests {
    private func titleFiles() throws -> [Source] { try sources(["Design", "Screens"]).filter(isTitleScreen) }

    private func code(_ file: Source) -> String {
        file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    /// El cuerpo de una función o vista (desde su firma hasta la siguiente `func`/`struct`/`var` del mismo nivel).
    private func block(_ signature: String, in text: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: signature), "falta «\(signature)»")
        let rest = text[start.upperBound...]
        let end = rest.range(of: #"\n    (@ViewBuilder )?(private )?(static )?(func|var) |\n(struct|extension|enum) "#, options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(text[start.lowerBound..<end])
    }

    func testTitleActionsLiveInOneRowOfOneLineTiles() throws {
        let files = try sources(["Design", "Screens"])
        // 1 · Ninguna tarjeta de acción lleva un segundo renglón (en ninguna pantalla).
        check(hits(#"ActionTileLabel\([^)]*\bdetail:"#, in: files), "Una tarjeta de acción va en un solo renglón: sin `detail:` (F1)")
        // 2 · La fila de la ficha: los cuatro, en su orden, en una sola pieza.
        let view = try XCTUnwrap(files.first { $0.path == "Screens/TitleView.swift" })
        let row = try block("private func actionTiles(", in: code(view))
        let order = ["statusAction(", "downloadAction(", "watchedAction(", "Text(\"Tráiler\")"].map { row.range(of: $0)?.lowerBound }
        XCTAssertFalse(order.contains(nil), "la fila de la ficha tiene Guardar, Descargar, Vista y Tráiler")
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), "en el orden Guardar · Descargar · Vista · Tráiler")
        // 3 · Fuera de la fila no hay botones de acción del título: ni los círculos de la temporada ni sus identificadores.
        let title = try titleFiles()
        check(hits(#"SeasonActionButton|"season-download"|"season-mark-watched"|actionTileRow|reservesDetail"#, in: title),
              "Las acciones de un título viven en la fila de mosaicos (bajar y marcar la temporada: en «Descargar» y «Vista»)")
        // «Vista» del menú de «Guardar» solo cuando no está su mosaico.
        let status = try XCTUnwrap(files.first { $0.name == "TitleView+Estado.swift" })
        XCTAssertTrue(code(status).contains("if !canMarkWatched(model)"), "«Guardar» no repite «Vista» cuando ya está su mosaico")
        XCTAssertTrue(code(status).contains("Text(\"Guardada\")"), "ya guardada, el mosaico dice «Guardada» (un renglón)")
        // El nombre no toca la orilla de la tarjeta: aire a los lados en todos sus estilos (antes solo en las teclas).
        let tile = code(try XCTUnwrap(files.first { $0.name == "TitleActions.swift" }))
        XCTAssertTrue(code(view).contains("ActionTileRow { actionTiles(model) }"),
                      "la fila de la ficha reparte parejo (`ActionTileRow`): un `HStack` daba más ancho a «Descargar» que a «Vista»")
        XCTAssertTrue(tile.contains(".padding(.horizontal, DS.Space.s1)\n"), "el nombre de una tarjeta de acción lleva aire a los lados, siempre")
        XCTAssertNil(tile.range(of: #"padding\(\.horizontal, style == \.key \? [^:]+: 0\)"#, options: .regularExpression),
                     "sin aire a los lados solo en la ficha, «Guardada» tocaba la orilla con letra grande")
    }

    func testOneRowOfStarsInTheTitle() throws {
        // Las estrellas a la vista en la ficha: solo «Tu calificación» (y cada capítulo en su fila); la de la temporada en su hoja.
        let title = try titleFiles()
        var places: [String] = []
        for file in title {
            let text = code(file)
            var from = text.startIndex
            while let hit = text.range(of: "RatingStars(", range: from..<text.endIndex) {
                let before = text[text.startIndex..<hit.lowerBound]
                let owner = String(before).matches(of: /(func|struct) [A-Za-z]+/).last.map { String($0.output.0) } ?? "?"
                places.append("\(file.name) · \(owner)")
                from = hit.upperBound
            }
        }
        XCTAssertEqual(places.sorted(), ["TitleView+Acciones.swift · func yourRating", "TitleView+TusVistas.swift · struct SeasonRatingSheet"],
                       "Una sola fila de estrellas a la vista en la ficha («Tu calificación»); la temporada se califica desde «Vista» (F1)")
        let watched = try XCTUnwrap(title.first { $0.name == "TitleView+Watched.swift" })
        XCTAssertTrue(code(watched).contains("ratingSeason = season"), "«Calificar la temporada» vive en el menú de «Vista»")
    }

    func testCompanionsShareTheControlsLine() throws {
        let files = try sources(["Design", "Screens"])
        // La temporada: cápsula y «N de M vistos» en un HStack centrado (antes un VStack con los vistos debajo).
        let view = code(try XCTUnwrap(files.first { $0.path == "Screens/TitleView.swift" }))
        let heading = try block("private func seasonHeading(", in: view)
        XCTAssertTrue(heading.contains("HStack(alignment: .center"), "«3 de 22 vistos» va en la línea de la temporada, centrado con ella")
        XCTAssertTrue(heading.contains("seasonControl(") && heading.contains("vistos"), "la línea de la temporada lleva el selector y cuántos llevas")
        XCTAssertFalse(heading.contains("VStack"), "nada debajo de la temporada en su encabezado (la barra va aparte, a todo lo ancho)")
        // «Tu nota»: un botón redondo al final de «Tu calificación», no un renglón a todo lo ancho.
        let acciones = code(try XCTUnwrap(files.first { $0.name == "TitleView+Acciones.swift" }))
        XCTAssertTrue(try block("func yourRating(", in: acciones).contains("noteButton(model)"), "«Tu nota» va al final del renglón de «Tu calificación»")
        let vistas = code(try XCTUnwrap(files.first { $0.name == "TitleView+TusVistas.swift" }))
        XCTAssertTrue(try block("func noteButton(", in: vistas).contains("DSIconButton("), "«Tu nota» es un botón redondo del catálogo")
        XCTAssertNil(vistas.range(of: "func yourNote("), "no vuelve el renglón «Tu nota ›» a todo lo ancho")
        // R1: la barra, «quedan…» y ↺ en una línea; ↺ es redondo y sin texto en color.
        let main = code(try XCTUnwrap(files.first { $0.name == "ContinueAction.swift" }))
        let line = try block("private var resumeLine", in: main)
        XCTAssertTrue(line.contains("HStack(") && line.contains("bar") && line.contains("status(left)") && line.contains("restartButton"),
                      "bajo «Continuar»: la barra, «quedan…» y ↺ en la misma línea")
        let restart = try block("private var restartButton", in: main)
        XCTAssertTrue(restart.contains("DSIconButton(") && restart.contains("\"Desde el principio\"") && restart.contains("\"title-restart\""),
                      "↺ es un `DSIconButton` con su nombre para VoiceOver («Desde el principio») y su identificador")
        XCTAssertNil(main.range(of: #"Button\("Desde el principio""#), "«Desde el principio» ya no es un texto en color (R1)")
    }
}
