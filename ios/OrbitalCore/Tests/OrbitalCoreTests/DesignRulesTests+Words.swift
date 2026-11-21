import XCTest

/// La auditoría de diseño del 20 nov 2026, en palabras e íconos:
/// - OI-2 / X1-B (Fernando): «Continuar» y «Siguiente» solo valen con su objeto («Continuar T22 E10» se queda). En la guía y en
///   la configuración el botón dice el verbo de lo que sigue («Elegir plataformas»), y lo que se deja para luego es «Ahora no»,
///   nunca «Saltar».
/// - OI-3: un error trae su arreglo («Reintentar») y una carga dice qué carga («Cargando subtítulos», no «Cargando…»).
/// - OI-8: una palabra y un ícono por idea. «Reintentar», nunca «Volver a intentar»; la ✕ es solo cerrar (quitar es el menos,
///   salir la puerta, pasar el pulgar abajo), y los filtros no usan el ámbar de los avisos.
extension DesignRulesTests {
    func testButtonsSayWhatComesNext() throws {
        let files = try sources()
        var problems: [String] = []
        // Un botón con la palabra sola: en la guía (`primary:`/`secondary:`), un `Button` o una etiqueta de botón.
        let bare = #"(primary|secondary):[^\n]*Text\("(Continuar|Siguiente|Seguir|Saltar|Omitir|Aceptar|OK|Aplicar|Enviar)"\)"#
        problems += hits(bare, in: files)
        problems += hits(#"Button\("(Continuar|Siguiente|Saltar|Omitir|Aceptar|OK|Aplicar|Enviar)"|Text\(last \? "Listo" : "Siguiente"\)|Label\("Saltar""#, in: files)
        // GuidePage no pone un «Continuar» por su cuenta: cada página dice el suyo.
        let guide = try XCTUnwrap(files.first { $0.name == "Guide.swift" })
        XCTAssertFalse(guide.lines.contains { $0.contains("var primary: Text = Text(") }, "GuidePage sin «Continuar» por omisión")
        check(problems, "Botón con «Continuar», «Siguiente» o «Saltar» a secas (di el verbo de lo que sigue; «Ahora no» para dejarlo)")
    }

    func testErrorsCarryTheirFixAndLoadsSayWhat() throws {
        let files = try sources()
        var problems = hits(#"Text\("Cargando…"\)|Text\("Cargando\.\.\."\)|"No se pudo\."|Volver a intentar"#, in: files)
        // «No se pudo cargar» solo en `DSErrorState`, que trae «Reintentar».
        problems += hits(#"Text\("No se pudo cargar"\)"#, in: files, skip: { $0.name == "Feedback.swift" || $0.name == "ComponentPreviews.swift" })
        check(problems, "Error sin arreglo o carga sin decir qué carga")
    }

    func testCrossOnlyCloses() throws {
        let files = try sources()
        // La ✕ con una palabra que no es cerrar: quitar, borrar, limpiar, salir, pasar.
        let problems = hits(#"(xmark|Symbol\.close)[^\n]*"(Quitar|Borrar|Limpiar|Salir|Paso|No calificar)|"(Quitar|Borrar|Limpiar|Salir|Paso|No calificar)[^"]*"[^\n]*(systemImage|symbol): *"xmark"#, in: files)
        check(problems, "La ✕ es solo cerrar: quitar lleva DS.Symbol.remove, salir DS.Symbol.leave y pasar DS.Symbol.matchPass")
        let icons = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Icons.swift"), encoding: .utf8)
        for name in ["matchPass", "remove", "leave"] {
            let line = icons.components(separatedBy: "\n").first { $0.contains("static let \(name) =") || $0.contains(", \(name) =") }
            XCTAssertNotNil(line, "existe DS.Symbol.\(name)")
            XCTAssertFalse(line?.contains("\"xmark") ?? true, "DS.Symbol.\(name) no es la ✕")
        }
        XCTAssertTrue(icons.contains("static let leavePlayer = leave"), "«Salir» del reproductor lleva la puerta")

        let filter = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Tokens+Filtro.swift"), encoding: .utf8)
        XCTAssertFalse(filter.contains("amber"), "los filtros no usan el ámbar de los avisos (DS.warning)")
        let uses = hits(#"DS\.warning"#, in: files.filter { $0.name.hasPrefix("Filtro") || $0.name.hasPrefix("AdvancedFilter") || $0.name.hasPrefix("YearRuler") })
        check(uses, "Un filtro en el ámbar de aviso")
    }

    /// Paridad con la TV (20 nov 2026): una idea por ícono y por color. ♥ es favoritos (Guardar en el mazo es el marcador),
    /// ★ es calificar («Para hoy» es la tachuela), ↻ es «otra vez» (deshacer es la flecha en U y «Desde el principio» la suya),
    /// y el ámbar de aviso no pinta estrellas ni la insignia «Siguiente».
    func testOneIconAndOneColorPerIdea() throws {
        let icons = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Icons.swift"), encoding: .utf8)
        let deck = try XCTUnwrap(icons.components(separatedBy: "\n").first { $0.contains("static let matchPass =") })
        XCTAssertFalse(deck.contains("heart"), "«Guardar» del mazo no es el corazón (es de favoritos)")
        XCTAssertFalse(deck.contains("star"), "«Para hoy» no es la estrella (es de calificar)")
        let files = try sources()
        check(hits(#"arrow\.counterclockwise"#, in: files), "La flecha en círculo al revés: «otra vez» es arrow.clockwise, deshacer arrow.uturn.backward")
        check(hits(#"Rating[^\n]*filled = DS\.warning|Text\("Siguiente"\)\.recipe\([^)]*DS\.warning"#, in: files),
              "Calificar o «Siguiente» en el ámbar de los avisos (las estrellas llevan DS.rating)")
    }

    /// Paridad con la TV (20 nov 2026): en una confirmación el botón seguro dice lo que protege («Dejarla conectada», «Conservar
    /// la clave», «Dejarlo como está», «Ahora no»), nunca «Cancelar». Quedan las hojas con su «Cancelar» de barra (cierra la
    /// hoja) y el de un enlace en curso (detiene el código de Trakt u OneDrive).
    func testSafeButtonSaysWhatItKeeps() throws {
        let files = try sources()
        check(hits(#"Button\("(Cancelar|No)", role: \.cancel\) \{\s*\}"#, in: files), "Confirmación con «Cancelar» (di lo que protege: «Dejarlo como está», «Conservar la clave»…)")
    }
}
