import XCTest

/// Pegar es el botón del sistema (`PasteButton`), nunca leer el portapapeles por código: así iOS no pregunta «Permitir pegar»
/// cada vez (Fernando, 22 nov 2026, al pegar la clave de una nube). Escribir en el portapapeles («Copiar») sí se vale. Regla en
/// `docs/ios-interfaz.md` § «Pegar es el botón del sistema».
extension DesignRulesTests {
    func testPastingIsTheSystemButton() throws {
        var reads: [String] = []
        for file in try sources(["Design", "Screens", "Platform", "Support"]) {
            for (i, line) in file.lines.enumerated() where line.contains("UIPasteboard.general.") {
                let writes = line.range(of: #"UIPasteboard\.general\.\w+\s*=[^=]"#, options: .regularExpression) != nil
                if !writes { reads.append("\(file.name):\(i + 1)") }
            }
        }
        XCTAssertEqual(reads, [], "Lee el portapapeles por código (sale «Permitir pegar»): usa `PasteButton`")
    }
}
