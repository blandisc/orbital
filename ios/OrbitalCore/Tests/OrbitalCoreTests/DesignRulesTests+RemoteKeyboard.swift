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

    /// Arrastrar la línea de tiempo del control no hace brincar la tarjeta (26 nov 2026): el minuto de arriba ya ocupa su
    /// lugar, la barra gana sobre la hoja y, al soltar, el punto espera a la TV en vez de regresar.
    func testScrubbingTheRemoteDoesNotMoveTheCard() throws {
        let remote = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Remote.swift" }).lines.joined(separator: "\n")
        let scrubber = try XCTUnwrap(remote.range(of: "struct RemoteScrubber").map { String(remote[$0.lowerBound...].prefix(3000)) })
        XCTAssertLessThanOrEqual(scrubber.components(separatedBy: "if let target {").count - 1, 1, "el minuto no aparece de la nada: ocupa su lugar siempre")
        XCTAssertTrue(scrubber.contains(".opacity(target == nil ? 0 : 1)"))
        XCTAssertTrue(scrubber.contains(".highPriorityGesture(DragGesture"), "la barra gana sobre la hoja")
        XCTAssertTrue(scrubber.contains("landing"), "al soltar, el punto espera a la TV")
    }

    /// TC-B e IS-B (26 nov 2026): la tarjeta corta y la isla usan las teclas del control completo (anchas, mate, pegadas),
    /// no círculos ni cápsulas de vidrio.
    func testShortCardAndIslandUseTheRemoteKeys() throws {
        let card = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "TVCards.swift" }).lines.joined(separator: "\n")
        let now = try XCTUnwrap(card.range(of: "struct NowPlayingCard").map { String(card[$0.lowerBound...].prefix(9000)) })
        XCTAssertTrue(now.contains("RemoteKey(symbol: symbol"), "la tarjeta corta usa `RemoteKey`")
        XCTAssertFalse(now.contains("DSIconButton(symbol: symbol"), "sin círculos de vidrio en la tarjeta")
        XCTAssertTrue(now.contains("DSMoreMenu(key:"), "«Más» es otra tecla")
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../App/Widgets/TVActivityWidget.swift").standardized
        let widget = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(widget.contains("if wide { Capsule()"), "la isla usa la forma de las teclas, no cápsulas")
    }
}
