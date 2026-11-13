import XCTest

/// Lo que se desplaza a lo ancho abre mostrando lo importante completo, y dice que hay más (Fernando, 13 nov 2026, sobre
/// «Día por día»: «aparece como rota, o sea, no se ve completa, tienes que darle a la derecha cuando la abres»). Regla en
/// `docs/ios-interfaz.md` § «Lo que se desplaza a lo ancho». Y la de las gráficas: una gráfica, un color; el nombre y el valor
/// en el mismo renglón («Tus géneros», antes una dona de cinco colores).
extension DesignRulesTests {
    /// `defaultScrollAnchor(.trailing…)` no es de fiar con una lista perezosa ni con contenido que crece después (el historial
    /// completo llega tras abrir): el mapa abría en el otro extremo. Para abrir en el final se va por id (`ScrollPosition`).
    func testWideStripsOpenByIDNotByDefaultAnchor() throws {
        let files = try sources()
        check(hits(#"defaultScrollAnchor\(\.trailing"#, in: files), "Lo que abre en su final va por id (`ScrollPosition.scrollTo(id:)`, como `DSWeekStrip`), no con `defaultScrollAnchor(.trailing)`")
    }

    /// Los mapas de semanas (los «Día por día») son una sola pieza, `DSWeekStrip`: nadie arma su propio `ScrollView` de casillas.
    func testWeekMapsUseTheStrip() throws {
        let files = try sources()
        for name in ["LoQueVes.swift", "YearView.swift"] {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            XCTAssertTrue(file.lines.contains { $0.contains("DSWeekStrip(") }, "\(name): el mapa día por día va en `DSWeekStrip`")
        }
        let strip = try XCTUnwrap(files.first { $0.name == "WeekStrip.swift" }, "falta Design/WeekStrip.swift")
        let code = strip.lines.joined(separator: "\n")
        for (needle, why) in [
            ("DS.WeekStrip.fit(available:", "las casillas salen del ancho que le queda (semanas enteras, nunca una a medias)"),
            ("scrollTo(id:", "abre en lo de hoy por su id, también cuando llegan más semanas"),
            (".scrollTargetBehavior(.viewAligned)", "se detiene por semanas"),
            (".edgeFade()", "lo que queda atrás se desvanece en la orilla: dice que hay más"),
            (".scrollDisabled(", "si todo cabe, no se desliza"),
        ] { XCTAssertTrue(code.contains(needle), "DSWeekStrip: \(why) (`\(needle)`)") }
    }

    /// Una gráfica, un color: «Tus géneros» son barras de un solo color con el nombre y el valor en su renglón; nada de donas
    /// de colores ni de `Charts` en «Lo que ves».
    func testGenreChartIsOneColorWithNameAndValueTogether() throws {
        let file = try XCTUnwrap(try sources(["Design"]).first { $0.name == "LoQueVes.swift" })
        let code = file.lines.joined(separator: "\n")
        XCTAssertFalse(code.contains("SectorMark") || code.contains("import Charts"), "«Tus géneros» va en barras, no en dona")
        XCTAssertFalse(code.contains("genreColors"), "«Tus géneros» lleva un solo color (el largo dice cuánto), no uno por género")
        XCTAssertTrue(code.contains(".accessibilityValue(Text(share, format: .percent"), "VoiceOver lee el nombre y su parte: «Comedia, 34 %»")
    }
}
