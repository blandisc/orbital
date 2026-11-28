import XCTest

/// Lo que cambia se ve al momento. Una vista que recibe un modelo suelto (`let model: SavedModel`, no su `ModelObserver`) no
/// se vuelve a pintar cuando el modelo cambia, salvo que lo siga con `model.track()`: así el «···» de tus listas nunca salía
/// (27 nov 2026). Los modelos que se siguen por propiedad (`observesByProperty`) no lo necesitan.
extension DesignRulesTests {
    func testViewsWithALooseModelFollowIt() throws {
        let core = repo.appendingPathComponent("ios/OrbitalCore/Sources")
        var models: Set<String> = [], byProperty: Set<String> = []
        let files = try XCTUnwrap(FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil)).allObjects
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: /class (\w+): ObservableModel/) { models.insert(String(match.1)) }
            if text.contains("observesByProperty: Bool { true }"), let match = text.firstMatch(of: /class (\w+): ObservableModel/) {
                byProperty.insert(String(match.1))
            }
        }
        let loose = models.subtracting(byProperty)
        XCTAssertTrue(loose.contains("SavedModel"), "la regla encuentra los modelos")
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) {
            let text = source.lines.joined(separator: "\n")
            var inView = false   // solo vistas y modificadores (un `Transferable` no se pinta)
            for line in source.lines {
                if let decl = line.firstMatch(of: /^\s*(?:private |fileprivate )?(?:struct|final class|class|enum|extension) [^{]*/) {
                    inView = decl.0.contains("View")
                }
                guard inView, let match = line.firstMatch(of: /^\s*(?:let|var) model: (\w+)\s*(?:\/\/.*)?$/), loose.contains(String(match.1)) else { continue }
                if !text.contains("model.track()") && !text.contains("model.trackAll()") { offenders.append(source.name) }
            }
        }
        XCTAssertEqual(offenders, [], "con el modelo suelto, `let _ = model.track()` al empezar `body` (o pásale su ModelObserver)")
    }

    /// Y lo que hiciste no se pierde al repintarse: el modelo de una pantalla se arma dentro de `State(wrappedValue:)`, no en una
    /// línea antes. SwiftUI vuelve a llamar al `init` en cada repintado del padre y lo armado afuera se tiraba («¿Qué vemos?» y la
    /// guía, 28 nov 2026).
    func testScreenModelsAreBuiltInsideTheirState() throws {
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) {
            for (i, line) in source.lines.enumerated() where line.contains("State(wrappedValue: ModelObserver(") {
                let before = source.lines[max(0, i - 4)..<i]
                if before.contains(where: { $0.contains("let model = ") || $0.contains("var model = ") }) { offenders.append("\(source.name):\(i + 1)") }
            }
        }
        XCTAssertEqual(offenders, [], "arma el modelo dentro de State(wrappedValue: ModelObserver(Self.makeModel(…)))")
    }
}
