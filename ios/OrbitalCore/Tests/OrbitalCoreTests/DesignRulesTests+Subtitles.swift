import XCTest

/// Opciones que se eligen: renglones con palomita (S1, Fernando, 11 nov 2026: «Me gusta tu propuesta S1»). Regla en
/// `docs/ios-interfaz.md` § «Opciones que se eligen».
extension DesignRulesTests {
    /// «Audio y subtítulos» elige con renglones: nada de cápsulas, acordeones ni `Capsule()`.
    func testSubtitlePanelChoosesWithRows() throws {
        let panel = try sources(["Design", "Screens"]).filter { $0.name.hasPrefix("SubtitlePanel") || $0.name == "PlayerScreen+DockData.swift" }
        XCTAssertGreaterThanOrEqual(panel.count, 3, "se leyeron las piezas del panel")
        check(hits(#"FlowChips\(|PanelChip\(|DisclosureGroup|Capsule\(|\.capsule\b"#, in: panel),
              "«Audio y subtítulos» elige con renglones con palomita (SubtitleRow), no con cápsulas ni acordeones")
        // La bandera de un renglón: una sola forma, en la columna del ícono.
        check(hits(#"Text\(verbatim: LanguageFlags\.flagged|LanguageFlags\.flagOnly"#, in: panel),
              "La bandera de un renglón va con Text.flagMark/Text.flag, no pegada al nombre como texto")
    }

    /// Los botones en pareja («−» «+», ‹ ›) miden lo mismo: marco fijo del símbolo. Un «+» solo (agregar) no va en pareja.
    func testPairedIconButtonsAreSteady() throws {
        let files = try sources()
        check(hits(#"DSIconButton\(symbol: "(minus|chevron\.left|chevron\.right)""#, in: files, skip: { $0.name == "ComponentPreviews.swift" }, unless: "steady: true"),
              "Un «−» o ‹ › de DSIconButton va con `steady: true` (los dos del mismo tamaño)")
        let rows = try XCTUnwrap(files.first { $0.name == "SubtitlePanel+Rows.swift" }).lines.joined(separator: "\n")
        XCTAssertEqual(rows.components(separatedBy: "steady: true").count - 1, 2, "SubtitleSteps arma sus dos botones con marco fijo")
        let buttons = try XCTUnwrap(files.first { $0.name == "Buttons.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(buttons.contains("DS.IconButton.steadyGlyph"), "DSIconButton(steady:) enmarca el símbolo en un tamaño fijo")
        XCTAssertTrue(buttons.contains("buttonRepeatBehavior"), "Mantener presionado «−»/«+» repite")
    }

    /// Ningún aviso vibra en el panel: el reproductor no vibra mientras ves.
    func testSubtitlePanelNeverVibrates() throws {
        let panel = try sources(["Design"]).filter { $0.name.hasPrefix("SubtitlePanel+") }
        XCTAssertEqual(panel.count, 2)
        check(hits(#"dsFeedback|sensoryFeedback"#, in: panel), "El panel de subtítulos no vibra")
    }

    /// Donde quedan cápsulas, las de una fila miden lo mismo: `FlowChips` da a cada una el alto de su línea, `PanelChip` lo
    /// llena, y el selector de temporada usa un solo tamaño y forma para la elegida y las demás.
    func testChipsInALineMeasureTheSame() throws {
        let files = try sources(["Design"])
        let controls = try XCTUnwrap(files.first { $0.name == "PlayerControls.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(controls.contains("anchor: .leading, proposal: ProposedViewSize(width: width, height: height)"),
                      "FlowChips coloca cada cápsula con el alto de su línea")
        let chip = controls.components(separatedBy: "struct PanelChip").last ?? ""
        XCTAssertTrue(chip.contains(".frame(maxHeight: .infinity)"), "PanelChip llena el alto que le da su línea")
        let surfaces = try XCTUnwrap(files.first { $0.name == "Surfaces.swift" }).lines.joined(separator: "\n")
        let picker = surfaces.components(separatedBy: "struct DSSeasonPicker").last?.components(separatedBy: "\nstruct ").first ?? ""
        XCTAssertEqual(picker.components(separatedBy: ".controlSize(").count - 1, 1, "Temporadas: un solo tamaño para todas")
        XCTAssertEqual(picker.components(separatedBy: ".buttonBorderShape(").count - 1, 1, "Temporadas: una sola forma para todas")
    }
}
