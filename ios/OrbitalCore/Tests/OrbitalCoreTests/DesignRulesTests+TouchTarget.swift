import XCTest

/// OI-1 (auditoría de diseño del 20 nov 2026): todo control de ícono se atina con el dedo, 44 × 44 pt como mínimo. `DSIconButton`
/// solo daba 44 en su tamaño grande; había 20 medianos y 2 chicos (la ✕ de «No calificar esta», las flechas ‹ › de Colecciones).
/// Ahora el círculo se dibuja igual, pero la pieza ocupa y responde en 44 × 44: el aire alrededor es su lugar en el acomodo,
/// así que nunca se encima con el control de al lado.
extension DesignRulesTests {
    func testIconControlsAnswerInFortyFourPoints() throws {
        let code = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Buttons.swift"), encoding: .utf8)
        let start = try XCTUnwrap(code.range(of: "struct DSIconButton"), "existe DSIconButton")
        let end = try XCTUnwrap(code.range(of: "struct ConfirmIconButton"), "le sigue ConfirmIconButton")
        let piece = String(code[start.upperBound..<end.lowerBound])
        XCTAssertTrue(piece.contains(".frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)"),
                      "DSIconButton ocupa 44 × 44 en todos sus tamaños (también .small y .regular)")
        XCTAssertTrue(piece.contains(".contentShape(Rectangle())"), "todo su lugar responde, no solo el círculo")
        XCTAssertTrue(piece.contains(".onTapGesture(perform: action)"), "el aire alrededor del círculo hace lo mismo que el botón")

        let files = try sources()
        var problems: [String] = []
        // Nadie le quita su lugar a un DSIconButton (un marco fijo más chico o el tamaño .mini).
        problems += hits(#"DSIconButton\(.*\)\s*(\{.*\})?\s*\.(frame\((width|height):|controlSize\(\.mini|dsControlSize\(\.mini)"#, in: files)
        // Un botón que solo lleva un ícono (fuera de DSIconButton) declara sus 44: `DS.Size.touchTarget` en su renglón o en los
        // tres de abajo, el tamaño grande, o `ds-exception:` (en la barra de arriba el sistema ya le da los 44).
        for file in files where !isPlayer(file) && !isArt(file) && !isTokens(file) {
            for (i, line) in file.lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                guard line.range(of: #"Button\b[^\n]*(\{|label:)\s*\{?\s*Image\("#, options: .regularExpression) != nil,
                      line.range(of: #"Text\(|Label|systemImage:"#, options: .regularExpression) == nil else { continue }
                let window = file.lines[i..<min(file.lines.count, i + 4)].joined(separator: "\n")
                let declared = ["DS.Size.touchTarget", "ds-exception:", "dsControlSize(.large)", "controlSize(.large)"].contains { window.contains($0) }
                if !declared { problems.append("\(file.path):\(i + 1): \(code.prefix(140))") }
            }
        }
        check(problems, "Control de ícono bajo 44 × 44 pt (usa DSIconButton o un marco de DS.Size.touchTarget dentro del botón)")
    }
}
