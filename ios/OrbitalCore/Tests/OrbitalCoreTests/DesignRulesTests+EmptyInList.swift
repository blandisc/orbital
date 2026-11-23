import XCTest

/// Un aviso de «vacío» dentro de una lista no se estira a toda la pantalla (revisión de la Mac, 22 nov 2026): en Descargas,
/// «Nada descargado» y «Nada en la nube» quedaban con el ícono cortado y el botón invisible, porque en la Mac el aviso pide
/// casi todo el alto de lo visible y dentro de un renglón de `List` eso lo aplasta. Todo `DSEmptyState` que va en un renglón
/// (`.listRowBackground`) dice `fills:`. Regla en `docs/ios-interfaz.md` § «El replanteamiento de la Mac».
extension DesignRulesTests {
    func testEmptyStatesInAListDoNotFillTheScreen() throws {
        var missing: [String] = []
        for file in try sources() {
            for (i, line) in file.lines.enumerated() where line.contains("DSEmptyState(") && !line.contains("struct DSEmptyState") {
                let after = file.lines[(i + 1)..<min(file.lines.count, i + 5)]
                if after.contains(where: { $0.contains(".listRowBackground(") }), !line.contains("fills:") {
                    missing.append("\(file.path):\(i + 1)")
                }
            }
        }
        XCTAssertEqual(missing, [], "Aviso vacío en un renglón de lista sin `fills: false`: en la Mac se aplasta")
    }
}

extension DesignRulesTests {
    /// Los botones de vidrio pasan por `dsGlassButton()`, que fija la letra al color del texto (en la Mac el vidrio la ponía
    /// oscura sobre fondo oscuro). Fuera: el reproductor, siempre sobre video oscuro con su propia letra.
    func testGlassButtonsGoThroughTheCatalog() throws {
        var raw: [String] = []
        for file in try sources() where !file.path.contains("Buttons.swift") && !file.path.contains("Player") {
            for (i, line) in file.lines.enumerated() where line.contains(".buttonStyle(.glass)") { raw.append("\(file.path):\(i + 1)") }
        }
        XCTAssertEqual(raw, [], "`.buttonStyle(.glass)` suelto: usa `dsGlassButton()` (la letra se lee en la Mac)")
    }
}

extension DesignRulesTests {
    /// En la Mac, el título de arriba de cada pantalla crece con la escala de la Mac (Fernando, 22 nov 2026: «en Mi media el
    /// título se me hace muy pequeño»). Lo dibuja la barra del sistema: se ajusta al arrancar, en `AppDelegate`.
    func testMacScreenTitlesUseTheMacScale() throws {
        let code = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/App/AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(code.contains("DS.Mac.styleBarTitles()"), "el título de la barra sale con tamaño de iPhone en la Mac")
    }
}
