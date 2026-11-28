import XCTest

/// «Todas» elige solo lo que se ve. Con un filtro puesto (género, década, «Estado»), elegir todas tomaba también los escondidos
/// y «Quitar» se los llevaba sin que se vieran (revisión del 27 nov 2026). Quien ofrece «Todas» lo saca de
/// `ListBarParts.visible`, que trae lo que la cuadrícula muestra.
extension DesignRulesTests {
    func testSelectAllPicksOnlyWhatIsShown() throws {
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) {
            for line in source.lines where line.contains("SelectionHeader(selection") || line.contains("ListSelectButtons(selection") {
                if !line.contains("ListBarParts.visible(") { offenders.append(source.name) }
            }
        }
        XCTAssertEqual(offenders, [], "«Todas» elige con `ListBarParts.visible(parts, else:)`: solo lo que se ve")
    }
}
