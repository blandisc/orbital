import XCTest

/// Con el título arriba, lo que pasa por debajo se tapa (revisión de la Mac, 22 nov 2026): en «Mi lista», una colección o los
/// rankings de una plataforma, el título y «Editar» quedaban encima de los pósters al bajar; el borde suave del sistema casi
/// no se nota en la Mac. Toda pantalla de pósters con título lleva el borde firme, como Inicio y Buscar.
/// Regla en `docs/ios-interfaz.md` § «El replanteamiento de la Mac».
extension DesignRulesTests {
    func testPosterScreensWithATitleCoverWhatScrollsUnder() throws {
        var missing: [String] = []
        var screens = 0
        for file in try sources() where file.path.contains("Screens/") {
            let grid = file.lines.contains { $0.contains("SortableGrid(") }
            let titled = file.lines.contains { $0.contains(".navigationTitle(") || $0.contains(".dsInlineTitle(") }
            guard grid, titled else { continue }
            screens += 1
            if !file.lines.contains(where: { $0.contains("scrollEdgeEffectStyle(.hard, for: .top)") }) { missing.append(file.path) }
        }
        XCTAssertGreaterThanOrEqual(screens, 3, "se leyeron las pantallas de pósters")
        XCTAssertEqual(missing, [], "Pantalla de pósters con título sin borde firme arriba: el título queda encima de los pósters")
    }
}
