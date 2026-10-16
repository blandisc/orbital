import XCTest
@testable import OrbitalCore

/// La regla «nada se crea suelto» (como `tests/web/design-system.test.mjs` en la TV): la paleta es la misma que la de
/// Orbital y las pantallas no escriben colores, tamaños de letra ni duraciones a mano.
final class DesignTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    func testPaletteMatchesOrbitalsPaletteJSON() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("orbital/web/styles/palette.json"))
        let json = try XCTUnwrap(JSON.parse(data)?.object)
        for (name, hex) in DesignTokens.palette {
            XCTAssertEqual(json[name]?.string?.lowercased(), hex.lowercased(), "el color \(name) cambió en Orbital: actualiza DesignTokens")
        }
        let known = Set(DesignTokens.palette.keys)
        for key in json.keys where key != "_" { XCTAssertTrue(known.contains(key), "Orbital tiene un color nuevo («\(key)») que falta en DesignTokens") }
    }

    /// Modo claro y oscuro: el texto se lee en los dos (WCAG AA), y el acento y la acción principal se distinguen del fondo.
    func testBothAppearancesHaveReadableContrast() {
        typealias R = DesignTokens.Role
        for mode in ["dark", "light"] {
            func hex(_ role: R) -> String { mode == "dark" ? role.hex.dark : role.hex.light }
            for background in [R.background, .surface] {
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.label), hex(background)), 7, "\(mode): texto sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.secondaryLabel), hex(background)), 4.5, "\(mode): texto secundario sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.accent), hex(background)), 4.5, "\(mode): el acento se lee sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.live), hex(background)), 4.5, "\(mode): «En vivo» se lee sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.danger), hex(background)), 4.5, "\(mode): el error se lee sobre \(background)")
            }
            XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.onPrimary), hex(.primary)), 7, "\(mode): texto del botón principal")
        }
    }

    func testHexParsing() throws {
        let c = try XCTUnwrap(rgb(hex: "#f5f4f0"))
        XCTAssertEqual(c.r, 245.0 / 255, accuracy: 1e-9)
        XCTAssertNil(rgb(hex: "#12345")); XCTAssertNil(rgb(hex: "zzzzzz"))
        for (_, hex) in DesignTokens.palette { XCTAssertNotNil(rgb(hex: hex)) }
    }

    /// Los archivos de pantalla (todo lo que no es el sistema de diseño) no pintan nada «suelto».
    func testScreensUseOnlyDesignSystemTokens() throws {
        // Las pantallas y la extensión de widgets (que usa los mismos tokens: `Sources/Design/Tokens.swift`).
        let sources = repo.appendingPathComponent("ios/App")
        let roots = ["ios/App/Sources", "ios/App/Widgets"].map { repo.appendingPathComponent($0) }
        let files = roots.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }.flatMap { $0.allObjects }
        XCTAssertEqual(files.isEmpty, false, "faltan ios/App/Sources y ios/App/Widgets")
        let forbidden: [(String, String)] = [
            (#"Color\(\s*(red|white|hue|\.sRGB)"#, "color escrito a mano"), (#"Color\(\s*""#, "color por nombre (usa un token)"),
            (#"UIColor\(\s*(red|white|hue|named)"#, "UIColor a mano"), (#"#colorLiteral"#, "color literal"), (#"\.foregroundColor\(\.(red|blue|green|white|black|gray|yellow|orange|pink|purple)"#, "color del sistema"),
            (#"\.(red|blue|green|yellow|orange|pink|purple)\b(?!\w)"#, "color del sistema"),
            (#"\.font\(\.system\(size:"#, "tamaño de letra a mano"), (#"\.animation\(\.[a-zA-Z]+\(duration:\s*[0-9.]+"#, "duración a mano"),
            (#"withAnimation\(\.[a-zA-Z]+\(duration:\s*[0-9.]+"#, "duración a mano"), (#"\.cornerRadius\(\s*[0-9]"#, "radio a mano"),
            (#"\.padding\(\s*[0-9]"#, "espacio a mano"), (#"\.zIndex\(\s*[0-9]"#, "capa a mano"),
            (#"\.frame\([^)]*\b(width|height|minHeight|maxWidth|minWidth|maxHeight):\s*[0-9]"#, "medida a mano"),
            (#"\.opacity\(\s*[0-9]"#, "opacidad a mano"), (#"sleep\(nanoseconds:\s*[0-9]"#, "espera a mano"),
            (#"(struct|class)\s+\w+\s*:\s*[^{]*\b(ButtonStyle|PrimitiveButtonStyle|ToggleStyle|PickerStyle|TabViewStyle)\b"#, "estilo de control propio: usa el nativo de Apple (HIG)"),
            (#"\.presentationBackground\("#, "fondo de hoja propio: deja el vidrio nativo (Liquid Glass)"),
            (#"\.listRowBackground\(DS\.fill\)"#, "renglón con relleno translúcido: los renglones van en DS.surface (blancos en claro)"),
            (#"\.aspectRatio\(\s*[0-9]"#, "relación de aspecto a mano"), (#"\.minimumScaleFactor\(\s*[0-9]"#, "escala a mano"),
        ]
        var problems: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            if relative == "Sources/Design/Tokens.swift" { continue }   // aquí se convierten los tokens a SwiftUI; el resto, también del diseño, los usa
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() where !line.contains("ds-exception:") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for (pattern, what) in forbidden where line.range(of: pattern, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): \(what): \(line.trimmingCharacters(in: .whitespaces))")
                }
                // La app (no el widget, que tiene sus propios tamaños) solo escribe texto con las recetas de Proyección.
                if relative.hasPrefix("Sources/"), line.contains("DS.font(") {
                    problems.append("\(relative):\(index + 1): tamaño de letra suelto (usa una receta: DS.TextRecipe / .recipe(…)): \(line.trimmingCharacters(in: .whitespaces))")
                }
                // Los colores fijos no cambian con el modo claro u oscuro: van los papeles (`DS.text`, `DS.bg`…).
                if relative.hasPrefix("Sources/Screens/"), line.range(of: #"Color\.(white|black)|\.foregroundStyle\(\.(white|black)\)"#, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): color fijo (no cambia con el modo): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Valores sueltos en las pantallas (usa un token o márcalo con «ds-exception: motivo»):\n" + problems.joined(separator: "\n"))
    }
}
