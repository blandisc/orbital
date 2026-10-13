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

    func testHexParsing() throws {
        let c = try XCTUnwrap(rgb(hex: "#f5f4f0"))
        XCTAssertEqual(c.r, 245.0 / 255, accuracy: 1e-9)
        XCTAssertNil(rgb(hex: "#12345")); XCTAssertNil(rgb(hex: "zzzzzz"))
        for (_, hex) in DesignTokens.palette { XCTAssertNotNil(rgb(hex: hex)) }
    }

    /// Los archivos de pantalla (todo lo que no es el sistema de diseño) no pintan nada «suelto».
    func testScreensUseOnlyDesignSystemTokens() throws {
        let sources = repo.appendingPathComponent("ios/App/Sources")
        guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return XCTFail("falta ios/App/Sources") }
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
            (#"\.aspectRatio\(\s*[0-9]"#, "relación de aspecto a mano"), (#"\.minimumScaleFactor\(\s*[0-9]"#, "escala a mano"),
        ]
        var problems: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            if relative == "Design/Tokens.swift" { continue }   // aquí se convierten los tokens a SwiftUI; el resto, también del diseño, los usa
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() where !line.contains("ds-exception:") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for (pattern, what) in forbidden where line.range(of: pattern, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): \(what): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Valores sueltos en las pantallas (usa un token o márcalo con «ds-exception: motivo»):\n" + problems.joined(separator: "\n"))
    }
}
