import XCTest

/// El catálogo de piezas (`ios/App/Sources/Design/`) no conoce el estado global de la app: una pieza recibe sus datos y
/// avisa lo que pasa (así se previsualiza sola, se prueba sola y el widget puede usarla). Lo que necesita `AppEnvironment`
/// es una pantalla y vive en `Screens/`.
final class DesignBoundaryTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// El estado global de la app y el contenedor de servicios.
    static let appState = #"AppEnvironment|@Environment\(AppEnvironment|ListsView\.|\bServices\b"#

    /// Pendientes por archivo (ruta desde `ios/App/Sources/Design/`): cuántos usos quedan. Al quitar uno, baja aquí el número.
    static let pending: [String: Int] = [:]

    func testDesignPiecesDoNotReachTheAppState() throws {
        let design = repo.appendingPathComponent("ios/App/Sources/Design")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: design, includingPropertiesForKeys: nil)).allObjects
        XCTAssertFalse(files.isEmpty, "falta ios/App/Sources/Design")
        let pattern = try NSRegularExpression(pattern: Self.appState)
        var found: [String: Int] = [:]
        for case let file as URL in files where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: design.path + "/", with: "")
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                let hits = pattern.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
                if hits > 0 { found[relative, default: 0] += hits }
            }
        }
        var problems: [String] = []
        for (file, count) in found.sorted(by: { $0.key < $1.key }) {
            let allowed = Self.pending[file] ?? 0
            if count > allowed { problems.append("\(file): \(count) usos del estado de la app (permitidos \(allowed)). Pásale los datos a la pieza o muévela a Screens/") }
            if count < allowed { problems.append("\(file): quedan \(count), la lista dice \(allowed). ¡Bien! Baja el número en `pending`") }
        }
        for (file, allowed) in Self.pending where found[file] == nil {
            problems.append("\(file): ya no tiene usos (la lista dice \(allowed)). Quítalo de `pending`")
        }
        XCTAssertTrue(problems.isEmpty, "Piezas del catálogo que leen el estado de la app:\n" + problems.joined(separator: "\n"))
    }
}
