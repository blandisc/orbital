import XCTest

/// Regla (26 nov 2026, Fernando: «esto se corta y no se ve bien»): lo de la isla abierta cabe entero en el alto que da iOS.
/// La isla abierta mide como mucho ~160 pt y iOS se queda con unos 40 de orillas; lo que pasa de ahí se corta por abajo (la
/// pausa de «Viendo en la TV» salía a la mitad). Cada actividad en vivo usa en la isla sus medidas propias, no las de la
/// pantalla bloqueada.
extension DesignRulesTests {
    func testTheOpenIslandFitsWhole() throws {
        let tokens = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Tokens.swift"), encoding: .utf8)
        func value(_ name: String) throws -> Double {
            let pattern = try NSRegularExpression(pattern: "\\b\(name): CGFloat = ([0-9.]+)")
            let match = try XCTUnwrap(pattern.firstMatch(in: tokens, range: NSRange(tokens.startIndex..., in: tokens)), "falta DS.Widget.\(name)")
            return try XCTUnwrap(Double(tokens[Range(match.range(at: 1), in: tokens)!]))
        }
        let usable = 160.0 - 40.0, line = 20.0, gap = 4.0
        // «Viendo en la TV»: arriba el póster (2:3) junto a nombre y hora; abajo la línea de tiempo y los botones.
        let tv = try value("islandTVPoster") * 1.5 + line + gap + (try value("islandKey"))
        XCTAssertLessThanOrEqual(tv, usable, "«Viendo en la TV» en la isla mide \(tv) pt (caben \(usable))")
        // Descargas: arriba el póster; abajo la barra y una línea.
        let downloads = try value("islandPoster") * 1.5 + gap + 6 + gap + line
        XCTAssertLessThanOrEqual(downloads, usable, "Descargas en la isla mide \(downloads) pt (caben \(usable))")

        let widget = try String(contentsOf: repo.appendingPathComponent("ios/App/Widgets/TVActivityWidget.swift"), encoding: .utf8)
        let island = try XCTUnwrap(widget.range(of: "DynamicIsland {").map { widget[$0.upperBound...] }?.components(separatedBy: "compactLeading").first)
        XCTAssertTrue(island.contains("TVButtons(state: context.state, size: DS.Widget.islandKey)"), "en la isla, los botones con su medida de isla")
        XCTAssertTrue(island.contains("DS.Widget.islandTVPoster"), "en la isla, el póster con su medida de isla")
    }
}
