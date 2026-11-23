import XCTest

/// Ajustes con los principios del sistema base (AJ-A, Fernando, 20 nov 2026): dos defectos que se repetían.
extension DesignRulesTests {
    /// En un grupo de Ajustes donde los renglones llevan ícono, el interruptor también lleva el suyo (con su color): si no, su
    /// texto empieza más a la izquierda que el de los demás («Buscar subtítulos en internet» era el único sin ícono).
    func testSettingsTogglesInAnIconGroupHaveTheirIcon() throws {
        var offenders: [String] = []
        for file in try sources(["Screens"]) where file.name.hasPrefix("SettingsView") {
            let text = file.lines.joined(separator: "\n")
            for block in sectionBlocks(text) where block.contains("SettingsRow(") {
                for call in calls("DSToggleRow(", in: block) where !(call.contains("symbol:") && call.contains("tint:")) {
                    offenders.append("\(file.name): \(call.prefix(80))")
                }
            }
        }
        XCTAssertEqual(offenders, [], "un interruptor en un grupo con íconos lleva symbol: y tint:, como SettingsRow")
    }

    /// Cada renglón de Ajustes lleva su ícono en su color, también los interruptores y selectores de las subpáginas (Fernando,
    /// 23 nov 2026: «muy crudo»): un `Toggle("…")`, `Picker("…")` o `LabeledContent("…")` suelto empieza más a la izquierda que
    /// los demás y sin color. Se usan `DSToggleRow`, `SettingsMenuRow`, `SettingsChoiceRow` y `SettingsRow`.
    func testEverySettingsRowHasItsIcon() throws {
        let bare = try NSRegularExpression(pattern: #"\b(Toggle|Picker|LabeledContent)\(""#)
        var offenders: [String] = []
        for file in try sources(["Screens"]) where file.name.hasPrefix("SettingsView") {
            for line in file.lines where bare.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                offenders.append("\(file.name): \(line.trimmingCharacters(in: .whitespaces).prefix(80))")
            }
        }
        XCTAssertEqual(offenders, [], "un renglón de Ajustes sin ícono: usa DSToggleRow, SettingsMenuRow o SettingsChoiceRow")
    }

    /// El destello (SF «sparkles») es de Explorar y de lo que se descubre; no se usa para otra cosa (Aprende lo usaba y se veía
    /// igual que la pestaña Explorar de abajo). Un archivo nuevo que lo use entra aquí con su porqué.
    func testSparklesOnlyMeansDiscover() throws {
        let allowed: [String: String] = [
            "Icons.swift": "DS.Symbol.recommended, la versión recomendada (decisión anterior: «el destello, solo eso»)",
            "MacTabStrip.swift": "la pestaña Explorar en la Mac",
            "BrandWelcome.swift": "«Descubre lo mejor para esta noche»",
            "FameQuadrant.swift": "Joyas ocultas: descubrir",
            "LessonScenes+Today.swift": "la lección de qué ver hoy",
            "LessonCatalog.swift": "la lección «¿Qué veo hoy?»",
            "SourcesSheet.swift": "la leyenda de la versión recomendada",
            "OnboardingWin.swift": "el mosaico de Explorar en la bienvenida",
        ]
        let hits = hits("\"sparkles\"", in: try sources()).filter { hit in !allowed.keys.contains { hit.contains("/\($0):") } }
        XCTAssertEqual(hits, [], "el destello es de Explorar y de descubrir; para otra cosa, otro ícono")
    }

    /// Los bloques `Section { … }` de un archivo (hasta su llave de cierre).
    private func sectionBlocks(_ text: String) -> [String] { calls("Section {", in: text, open: "{", close: "}") }

    /// Cada llamada que empieza con `head`, hasta que cierra su paréntesis (o su llave).
    private func calls(_ head: String, in text: String, open: Character = "(", close: Character = ")") -> [String] {
        var out: [String] = []
        var search = text.startIndex
        while let range = text.range(of: head, range: search..<text.endIndex) {
            var depth = 0, i = range.lowerBound
            while i < text.endIndex {
                if text[i] == open { depth += 1 } else if text[i] == close { depth -= 1; if depth == 0 { break } }
                i = text.index(after: i)
            }
            out.append(String(text[range.lowerBound..<min(i, text.endIndex)]))
            search = range.upperBound
        }
        return out
    }
}
