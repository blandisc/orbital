import XCTest

/// Lo que va en la barra de arriba (`.toolbar { … }`), en un menú contextual (`.contextMenu { … }`, cuya vista previa también se
/// arma fuera del árbol de la app) y la ficha (`TitleView`) leen los objetos del entorno como opcionales
/// (`@Environment(AppEnvironment.self) private var env: AppEnvironment?`).
///
/// Por qué (R1, 31 oct 2026): al mantener presionado un póster de Inicio («Sugerencias para ti»), iOS armaba la ficha y los
/// botones de su barra (`UIKitBarItemHost`) en un árbol que todavía no tenía el entorno de la app, y el
/// `@Environment(AppEnvironment.self)` obligatorio de `TitleView` tiraba la app («No Observable object of type
/// AppEnvironment found»), 3 de 3 veces. Con el opcional, ese instante usa `AppEnvironment.shared` (el mismo objeto) o lo de
/// omisión. `ChaosRegressionUITests.testInicioMantenerPresionadoSugerencia` lo prueba en el simulador.
final class ToolbarEnvironmentTests: XCTestCase {
    var sources: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("ios/App/Sources")
    }

    /// Un objeto del entorno leído obligatorio: `@Environment(Tipo.self) private var nombre` sin `: Tipo?`.
    static let required = try! NSRegularExpression(pattern: #"@Environment\(([A-Z]\w*)\.self\)\s*(?:private\s+|fileprivate\s+)?var\s+\w+\s*(?!:\s*\w+\?)(?:$|\n|//)"#,
                                                   options: [.anchorsMatchLines])

    func testToolbarPiecesReadTheEnvironmentOptionally() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)).allObjects
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "falta ios/App/Sources")
        let texts = try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }

        // Las vistas que leen un objeto del entorno obligatorio.
        var strict = Set<String>()
        let structPattern = try NSRegularExpression(pattern: #"^\s*(?:private\s+|fileprivate\s+)?struct\s+(\w+)"#, options: [.anchorsMatchLines])
        for (_, text) in texts {
            let ns = text as NSString
            let starts = structPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for (i, match) in starts.enumerated() {
                let end = i + 1 < starts.count ? starts[i + 1].range.location : ns.length
                let body = ns.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
                if Self.required.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) != nil {
                    strict.insert(ns.substring(with: match.range(at: 1)))
                }
            }
        }
        XCTAssertFalse(strict.isEmpty, "la búsqueda ya no encuentra vistas con entorno (¿cambió la forma de escribirlo?)")

        // Lo que hay dentro de cada `.toolbar { … }`, de cada `@ToolbarContentBuilder` y de cada menú contextual.
        var problems: [String] = []
        for (name, text) in texts {
            let chars = Array(text)
            var blocks: [String] = []
            for marker in [".toolbar {", "@ToolbarContentBuilder", ".contextMenu {", ".contextMenu(menuItems:"] {
                var search = text.startIndex
                while let found = text.range(of: marker, range: search..<text.endIndex) {
                    search = found.upperBound
                    // Desde el principio del marcador: si ya trae su «{», ese es el bloque (antes se saltaba al siguiente).
                    var i = text.distance(from: text.startIndex, to: found.lowerBound)
                    while i < chars.count, chars[i] != "{" { i += 1 }
                    guard i < chars.count else { break }
                    var depth = 0, j = i
                    repeat { if chars[j] == "{" { depth += 1 } else if chars[j] == "}" { depth -= 1 }; j += 1 } while depth > 0 && j < chars.count
                    blocks.append(String(chars[i..<j]))
                }
            }
            for block in blocks {
                for view in strict where block.range(of: #"\b\#(view)\("#, options: .regularExpression) != nil {
                    problems.append("\(name): `\(view)` va en la barra o en un menú contextual y lee el entorno obligatorio; hazlo opcional (`: Tipo?`)")
                }
            }
        }
        if let title = texts.first(where: { $0.0 == "TitleView.swift" })?.1,
           Self.required.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) != nil {
            problems.append("TitleView.swift: la ficha lee el entorno obligatorio; hazlo opcional (`: Tipo?`)")
        }
        XCTAssertTrue(problems.isEmpty, Set(problems).sorted().joined(separator: "\n"))
    }
}
