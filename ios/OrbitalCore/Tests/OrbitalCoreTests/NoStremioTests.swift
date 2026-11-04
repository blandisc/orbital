import XCTest

/// Stremio fuera de la app (E1, Fernando, 3 nov 2026: «que en la aplicación ya no haya ningún elemento de Stremio»): ningún
/// texto de la pantalla lo nombra. La información de títulos y los subtítulos siguen saliendo de servicios públicos en dominios
/// de Stremio, pero nunca se dice. `StremioAPI.swift` es el código viejo de la cuenta, sin pantalla que lo enseñe.
final class NoStremioTests: XCTestCase {
    var ios: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    func testNoScreenTextNamesStremio() throws {
        var found: [String] = []
        for folder in ["App/Sources", "App/Widgets", "OrbitalCore/Sources"] {
            let base = ios.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)).allObjects
            for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "StremioAPI.swift" {
                for (i, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated() {
                    let code = line.trimmingCharacters(in: .whitespaces)
                    if code.hasPrefix("//") { continue }
                    let text = code.components(separatedBy: " // ").first ?? code
                    // Cada literal por separado; `== "Stremio"` compara lo que manda una consola vieja, no se enseña.
                    let literals = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
                        .matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
                    if literals.contains(where: { $0.contains("Stremio") }), !text.contains(#"== "Stremio""#) {
                        found.append("\(file.lastPathComponent):\(i + 1)")
                    }
                }
            }
        }
        XCTAssertEqual(found, [], "un texto de la pantalla nombra a Stremio")
    }

    func testTheCatalogHasNoStremioText() throws {
        let data = try Data(contentsOf: ios.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        let api = ["Error de Stremio", "No pude conectar con Stremio: %@", "Respuesta de Stremio sin resultado",
                   "Stremio no devolvió la clave de sesión", "Stremio respondió HTTP %@"]
        XCTAssertEqual(strings.keys.filter { $0.contains("Stremio") && !api.contains($0) }.sorted(), [])
    }
}
