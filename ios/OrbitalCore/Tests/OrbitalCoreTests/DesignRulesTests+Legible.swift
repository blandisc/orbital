import XCTest
import OrbitalCore

/// OI-5 (auditoría de diseño del 20 nov 2026): nada se escribe en 11 pt. Había 31 textos así, 26 en los widgets; lo más chico es
/// `DS.font(.sm)` / `caption` (12). Si un texto no cabe, se acomoda con el sistema (otra palabra, otro arreglo), no con una letra
/// más chica. `TextSize.xs` y `Typeface.xs` ya no existen.
extension DesignRulesTests {
    func testNothingIsWrittenInElevenPoints() throws {
        let sizes = try String(contentsOf: repo.appendingPathComponent("ios/OrbitalCore/Sources/OrbitalCore/DesignTokens.swift"), encoding: .utf8)
        let line = try XCTUnwrap(sizes.components(separatedBy: "\n").first { $0.contains("enum TextSize") }, "existe DesignTokens.TextSize")
        XCTAssertFalse(line.contains("xs"), "TextSize sin xs (11 pt)")
        XCTAssertGreaterThanOrEqual(DesignTokens.TextSize.sm, 12, "el tamaño más chico es de 12 pt o más")

        let tokens = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Tokens.swift"), encoding: .utf8)
        let typeface = try XCTUnwrap(tokens.range(of: "enum Typeface"), "existe DS.Typeface")
        XCTAssertFalse(tokens[typeface.upperBound...].prefix(600).contains("case .xs"), "DS.Typeface sin .xs (caption2, 11 pt)")

        // La app y los widgets (que viven aparte, en ios/App/Widgets).
        var files = try sources()
        let widgets = repo.appendingPathComponent("ios/App/Widgets")
        let found = try XCTUnwrap(FileManager.default.enumerator(at: widgets, includingPropertiesForKeys: nil)).allObjects
        for case let file as URL in found where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            files.append(Source(path: "../Widgets/" + file.lastPathComponent, lines: text.components(separatedBy: "\n")))
        }
        XCTAssertTrue(files.contains { $0.path.hasPrefix("../Widgets/") }, "se leyeron los widgets")
        // `Tokens+Mac` traduce cada estilo a su tamaño en la Mac (ahí caption2 es de 13): es la tabla, no un texto.
        let problems = hits(#"DS\.font\(\.xs|Typeface\.xs|TextSize\.xs|\.caption2\b|size:\s*11(\.0)?\b"#, in: files, skip: { $0.name == "Tokens+Mac.swift" })
        check(problems, "Texto en 11 pt (lo más chico es DS.font(.sm) o caption, 12 pt)")
    }
}
