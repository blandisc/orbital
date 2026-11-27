import XCTest

/// Elegir versión no reproduce (Fernando, 26 nov 2026: «al momento de cambiarla automáticamente la reproduce y no me deja
/// enviarla a la TV»). Regla en `docs/ios-interfaz.md` § «La versión vive en el botón»: la de la ficha queda elegida y
/// «Ver» y «En la TV» la usan.
extension DesignRulesTests {
    func testChoosingAVersionDoesNotPlay() throws {
        let files = try sources(["Screens", "App"])
        let actions = try XCTUnwrap(files.first { $0.name == "TitleView+Acciones.swift" }).lines.joined(separator: "\n")
        XCTAssertNotNil(actions.range(of: #"case \.watch where videoID == model\.continueVideoID: model\.select\("#, options: .regularExpression),
                        "Elegir la versión del botón «Ver» solo la elige (`model.select`), no reproduce")
        XCTAssertNotNil(actions.range(of: "model.chosenSource(for: videoID)"), "«Ver» usa la versión que elegiste")
        let title = try XCTUnwrap(files.first { $0.name == "TitleView.swift" }).lines.joined(separator: "\n")
        XCTAssertNotNil(title.range(of: "source: model.chosenSource(for: nil)"), "«En la TV» manda la versión que elegiste")
    }
}
