import XCTest

/// El título de una pantalla que se abre encima va siempre a la izquierda en el iPhone, junto a «‹» (TD1, Fernando, 27 nov 2026:
/// «siempre a la izquierda en todos iPhones… más fácil mantener»). iOS lo centraba si cabía y si no lo mandaba a la izquierda:
/// dos páginas de Ajustes seguidas se veían distintas en el Duo. Toda pantalla lo pide con `dsInlineTitle`; solo las hojas con
/// «Cancelar» a la izquierda y las hojas del reproductor (Audio, Subtítulos) dejan el del sistema al centro: ahí no hay «‹».
extension DesignRulesTests {
    func testInlineTitlesUseTheSharedRecipe() throws {
        // «Cancelar» de la misma hoja: unos renglones abajo del título.
        func cancelNear(_ lines: [String], _ i: Int) -> Bool {
            lines[i..<min(lines.count, i + 4)].contains { $0.contains(".cancellationAction") }
        }
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) where source.name != "NavigationTitle.swift" {
            if source.name == "PlayerScreen+DockData.swift" { continue }   // hojas del reproductor, con «Listo»
            for (i, line) in source.lines.enumerated() {
                let previous = i > 0 ? source.lines[i - 1] : ""
                if line.contains(".dsInlineTitle("), cancelNear(source.lines, i) {
                    offenders.append("\(source.name):\(i + 1) (hoja con «Cancelar»: título al centro)")
                    continue
                }
                let titled = line.contains("avigationTitle(") || previous.contains("avigationTitle(")
                guard titled, line.contains(".navigationBarTitleDisplayMode(.inline)") else { continue }
                if cancelNear(source.lines, i) { continue }
                offenders.append("\(source.name):\(i + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "un título de pantalla va con `dsInlineTitle` (a la izquierda en el iPhone)")
        let recipe = try XCTUnwrap(try sources(["Design"]).first { $0.name == "NavigationTitle.swift" })
        let text = recipe.lines.joined(separator: "\n")
        XCTAssertTrue(text.contains(".toolbar(removing: .title)") && text.contains("placement: .topBarLeading"),
                      "la receta quita el título del centro y lo pone junto a «‹»")
    }
}
