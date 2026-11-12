import XCTest

/// Un panel alto no deja el fondo vacío (CT2, Fernando, 11 nov 2026: «Vamos con CT2»; antes: «no tiene caso tener todo ese
/// espacio vacío abajo»). Regla en `docs/ios-interfaz.md` § «Un panel alto no deja el fondo vacío»: en el panel del control del
/// iPad, lo de arriba informa (lo que suena o tus «Seguir viendo») y el control se ancla abajo; el pad se queda con lo que
/// sobra y el contenido mide al menos el alto del panel. La hoja del iPhone no cambia.
extension DesignRulesTests {
    func testTallPanelsAnchorTheControlAtTheBottom() throws {
        let files = try sources(["Screens"])
        let panel = try XCTUnwrap(files.first { $0.name == "RemoteSheet+Panel.swift" }, "falta el panel del control (RemoteSheet+Panel.swift)")
        let code = panel.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertTrue(code.contains(".frame(minHeight: panelHeight"), "El contenido del panel mide al menos el alto del panel (si no, sobra abajo)")
        XCTAssertTrue(code.contains("onScrollGeometryChange"), "El alto del panel se mide del ScrollView")
        XCTAssertTrue(code.contains("navigation(model, growing: true"), "En el panel el pad crece con lo que sobra")
        XCTAssertTrue(code.contains("contextKeys: model.context != .player"), "Con el reproductor arriba, el panel no repite Salir, Audio y subtítulos y Versión")
        XCTAssertTrue(code.contains(".frame(maxHeight: .infinity, alignment: .bottom)"), "El control del panel va anclado abajo")
        XCTAssertTrue(code.contains("RemotePanelIdle("), "Con la tele en reposo, lo de arriba informa (Seguir viendo o las frases de la voz)")
        XCTAssertFalse(code.contains("Spacer()"), "Nada de un hueco: lo que sobra lo absorbe el pad, no un `Spacer`")

        let sheet = try XCTUnwrap(files.first { $0.name == "RemoteSheet.swift" })
        let sheetCode = sheet.lines.joined(separator: "\n")
        XCTAssertTrue(sheetCode.contains("if let close { panel(model, close: close) }"), "El panel (iPad) y la hoja (iPhone) se separan por `close`")
        XCTAssertTrue(sheetCode.contains("maxHeight: growing ? .infinity : DS.Remote.padHeightFitted"), "En la hoja el pad conserva su alto de siempre")
    }
}
