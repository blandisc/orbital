import XCTest

/// Toda lista tuya ofrece los mismos órdenes; uno que no aplica no aparece (13 nov 2026, con «Agregadas: más recientes / más
/// viejas»; docs/ios-interfaz.md). Qué órdenes caben lo decide `OrbitalModels.ListSort.offered` y cada lista recuerda el suyo
/// con `ListSort.saved`/`remember`: ninguna pantalla arma su propia lista de órdenes ni guarda el orden por su lado.
extension DesignRulesTests {
    func testListsShareOneSortPiece() throws {
        let files = try sources()
        check(hits(#"ListSort\.allCases|"list-sort\."#, in: files), "Los órdenes salen de ListSort.offered y se recuerdan con ListSort.saved/remember")
        let controls = try XCTUnwrap(files.first { $0.name == "ListControls.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(controls.contains("ListSort.offered(for: items"), "SortableGrid ofrece los órdenes de ListSort.offered")
        XCTAssertTrue(controls.contains("ListSort.saved(listID:") && controls.contains("ListSort.remember("), "SortableGrid recuerda el orden por lista")
    }

    /// Cada orden tiene su nombre en inglés en el catálogo (los de «Agregadas…» incluidos).
    func testEverySortNameIsTranslated() throws {
        let file = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/ListControls.swift"), encoding: .utf8)
        let start = try XCTUnwrap(file.range(of: "extension ListSort {"), "los nombres de los órdenes viven en ListControls.swift")
        let controls = String(file[start.upperBound...]).components(separatedBy: "\n}\n")[0]   // solo los nombres de los órdenes
        let catalog = try String(contentsOf: repo.appendingPathComponent("ios/App/Resources/Localizable.xcstrings"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"case \.[a-zA-Z]+: "([^"]+)""#)
        let names = regex.matches(in: controls, range: NSRange(controls.startIndex..., in: controls)).compactMap { Range($0.range(at: 1), in: controls).map { String(controls[$0]) } }
        XCTAssertTrue(names.contains("Agregadas: más recientes") && names.contains("Agregadas: más viejas"))
        check(names.filter { !catalog.contains("\"\($0)\": {") }, "Cada orden está en Localizable.xcstrings con su inglés")
    }
}
