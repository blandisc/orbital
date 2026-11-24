import XCTest

/// Abrir la app, cambiar de pestaña y abrir una ficha en la Mac no arman lo que nadie ve (24 nov 2026, medido con
/// Instruments en la app instalada). Regla en `docs/ios-interfaz.md` § «Lo que no se ve no se arma».
extension DesignRulesTests {
    func testWhatIsNotSeenIsNotBuilt() throws {
        let files = try sources(["Design", "Screens", "App"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // El panel de la derecha (inspector) arma lo de adentro solo abierto: cerrado, SwiftUI lo armaba al abrir la app y lo
        // volvía a pintar con cada sondeo de la TV (~0.3 s del arranque).
        for file in files {
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            var rest = text[...]
            while let use = rest.range(of: ".inspector(isPresented: ") {
                let after = rest[use.upperBound...]
                let shown = String(after.prefix { $0 != ")" })
                XCTAssertTrue(after.prefix(200).contains("{ if \(shown)"), "\(file.name): lo de adentro de `.inspector` se arma solo si \(shown)")
                rest = after
            }
        }
        // En la ficha, lo de abajo (episodios, reparto, detalles) se arma al asomarse, no al abrir.
        XCTAssertTrue(try code("TitleView.swift").contains("if belowFold { LazyVStack("), "lo de abajo de la ficha va perezoso")
        // «Decide por mí» no rehace su abanico de pósters en cada pasada: lo guarda hasta que el modelo cambie.
        XCTAssertTrue(try code("DecideSheet.swift").contains("DecideFanMemo"), "el abanico de «Decide por mí» se guarda por versión del modelo")
    }

    /// Un valor que se compara no avisa cuando es el mismo: con `@Tracked(always: true)` cada sondeo repintaba la ficha entera
    /// aunque nada hubiera cambiado. `always` queda para lo que no se puede comparar.
    func testTrackedValuesCompareBeforeNotifying() throws {
        let base = repo.appendingPathComponent("ios/OrbitalCore/Sources/OrbitalModels")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)).allObjects
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ObservableModel.swift" }
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("@Tracked(always: true)"), "\(url.lastPathComponent): `@Tracked` sin `always` (sus valores se comparan; con `always` repinta sin cambios)")
        }
    }
}
