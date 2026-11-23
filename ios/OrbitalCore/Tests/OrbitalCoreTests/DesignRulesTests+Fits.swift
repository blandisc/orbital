import XCTest

/// Cambiar de pestaña no traba (Fernando, 22 nov 2026: «le doy clic a inicio, explorar y se tarda muchísimo»): el panel de
/// Inicio probaba doce versiones de sí mismo con `ViewThatFits` (seis cantidades de renglones, con y sin «Lo nuevo») y la tira de
/// «Decide por mí» hasta ocho tiras de pósters; la Mac pasaba casi todo el tiempo acomodándolas. Lo que tiene imágenes o
/// renglones cuenta cuántos caben con el espacio medido. `ViewThatFits` con un `ForEach` de versiones, solo para texto
/// (`DataLine`, los datos del mosaico). Regla en `docs/ios-interfaz.md` § «El replanteamiento de la Mac».
extension DesignRulesTests {
    func testOnlyTextTriesManyVersionsToFit() throws {
        let textOnly = ["Projection.swift", "Mosaic.swift"]
        var heavy: [String] = []
        for file in try sources() where !textOnly.contains(where: { file.path.hasSuffix($0) }) {
            for (i, line) in file.lines.enumerated() where line.contains("ViewThatFits(") {
                let next = file.lines[(i + 1)..<min(file.lines.count, i + 3)]
                if next.contains(where: { $0.contains("ForEach(") }) { heavy.append("\(file.path):\(i + 1)") }
            }
        }
        XCTAssertEqual(heavy, [], "`ViewThatFits` que arma muchas versiones de algo con imágenes: cuenta cuántos caben")
    }
}
