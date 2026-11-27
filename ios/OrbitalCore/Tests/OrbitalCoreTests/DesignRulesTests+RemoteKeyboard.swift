import XCTest

/// El control de la TV (Fernando, 26 nov 2026): el teclado no se va solo al moverte por los resultados, un juego que se abre
/// se puede cerrar desde el control, y «Buscar» no sale dos veces seguidas (la TV abrió un juego con dos).
extension DesignRulesTests {
    func testRemoteKeepsTheKeyboardAndCanCloseAGame() throws {
        let files = try sources(["Design", "Screens"])
        func text(_ name: String) throws -> String { try XCTUnwrap(files.first { $0.name == name }).lines.joined(separator: "\n") }
        let field = try text("Remote.swift")
        XCTAssertFalse(field.contains("focused = wants"), "que la TV deje el campo no esconde el teclado")
        let sheet = try text("RemoteSheet.swift")
        XCTAssertTrue(sheet.contains("editing && model.context == .browse ? .typing"), "con el teclado arriba, el control no cambia de forma")
        XCTAssertTrue(sheet.contains("remote-close-game") && sheet.contains("model.game(\"close\")"), "el control cierra un juego")
        XCTAssertTrue(sheet.contains("timeIntervalSince(submittedAt) > 1"), "un «Buscar» repetido al instante no sale")
    }
}
