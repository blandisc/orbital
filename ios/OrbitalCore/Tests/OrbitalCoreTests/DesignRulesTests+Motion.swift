import XCTest

/// Lo que crece no choca (Fernando, 13 nov 2026, el selector de Inicio: «como que lo tocas y como que rebota de inmediato en
/// los botones que están arriba a la derecha… que tenga un poquito de física, de intencionalidad»). Regla en
/// `docs/ios-interfaz.md` § «Lo que crece no choca».
extension DesignRulesTests {
    /// Los tiempos de los resortes, leídos de `Tokens.swift` (`static let growDuration = 0.42, growBounce = 0.06`).
    private func motionNumber(_ name: String, in tokens: Source) -> Double? {
        for line in tokens.lines {
            guard let r = line.range(of: #"\b\#(name)\s*(?::\s*\w+)?\s*=\s*([0-9.]+)"#, options: .regularExpression) else { continue }
            return Double(line[r].split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "")
        }
        return nil
    }

    /// `grow` casi no se pasa (sin rebote visible contra el vecino) y es más lento que `fold` (lo de al lado cede primero y
    /// cerrar es más rápido que abrir).
    func testGrowSettlesWithoutBouncingAndFoldIsFaster() throws {
        let tokens = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Tokens.swift" })
        let bounce = try XCTUnwrap(motionNumber("growBounce", in: tokens), "Falta DS.Motion.growBounce")
        let grow = try XCTUnwrap(motionNumber("growDuration", in: tokens), "Falta DS.Motion.growDuration")
        XCTAssertLessThanOrEqual(bounce, 0.1, "DS.Motion.grow rebota: lo que crece junto a otra cosa se asienta sin pasarse (≤ 0.1)")
        let fold = try XCTUnwrap(tokens.lines.first { $0.contains("static func fold(") })
        XCTAssertTrue(fold.contains(".smooth(duration: DesignTokens.Motion.base)") || fold.contains(".smooth(duration: DesignTokens.Motion.fast)"),
                      "DS.Motion.fold es un resorte sin rebote y corto (base o fast): \(fold)")
        XCTAssertGreaterThan(grow, 0.22, "Abrir (grow) es más lento que ceder y cerrar (fold, 0.22)")
        let learn = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Tokens+Learn.swift" })
        let enter = try XCTUnwrap(motionNumber("enterScale", in: learn))
        XCTAssertGreaterThanOrEqual(enter, 0.75, "Lo que llega a la pastilla no nace de la nada (DS.KindPill.enterScale ≥ 0.75)")
    }

    /// El selector de tipo (`KindPill`, el mismo en Inicio, Explorar y las listas) y la cápsula de Inicio se mueven con
    /// `grow`/`fold`: nada de resortes con rebote ni curvas sueltas, y el cierre que espera al círculo se puede cancelar.
    func testKindPillMovesWithGrowAndFold() throws {
        let files = try sources()
        let filters = try XCTUnwrap(files.first { $0.name == "Filters.swift" })
        let header = try XCTUnwrap(files.first { $0.name == "HomeHeader.swift" })
        let start = try XCTUnwrap(filters.lines.firstIndex { $0.hasPrefix("struct KindPill") })
        let pill = filters.lines[start...].prefix { !$0.hasPrefix("/// Al apretar") }.joined(separator: "\n")
        let cap = header.lines.joined(separator: "\n")
        for (name, code) in [("KindPill", pill), ("HomeHeader", cap)] {
            XCTAssertNil(code.range(of: #"DS\.Motion\.(pop|spring|morph|toastPop|toastGrow)\b|\.bouncy\b"#, options: .regularExpression),
                         "\(name): sin resortes con rebote; lo que crece usa DS.Motion.grow y lo que cede o se recoge DS.Motion.fold")
        }
        XCTAssertTrue(pill.contains("DS.Motion.grow(reduceMotion)") && pill.contains("DS.Motion.fold(reduceMotion)"),
                      "KindPill abre con DS.Motion.grow y se recoge con DS.Motion.fold")
        XCTAssertTrue(pill.contains("folding?.cancel()"), "Otro toque cancela el cierre pendiente: todo se puede interrumpir")
        XCTAssertTrue(cap.contains("DS.Motion.fold(reduceMotion)"), "La cápsula de Inicio cede su lugar con DS.Motion.fold")
        // Lo elegido se ve un momento antes de recogerse, y el círculo nunca se sale de la pastilla (13 nov 2026).
        let tokens = files.map { $0.lines.joined(separator: "\n") }.joined(separator: "\n")
        let settle = try XCTUnwrap(tokens.firstMatch(of: /static let settle: Duration = \.milliseconds\((\d+)\)/))
        XCTAssertGreaterThanOrEqual(Int(settle.1) ?? 0, 500, "La pastilla espera al menos medio segundo antes de recogerse (DS.KindPill.settle)")
        XCTAssertTrue(pill.contains(".padding(DS.KindPill.markInset)") && pill.contains(".clipShape(Capsule())"),
                      "El círculo de lo elegido es más chico que su lugar y la pastilla recorta lo que se salga")
        XCTAssertTrue(pill.contains("naming = true") && pill.contains("Text(chosen)"),
                      "Al elegir, la pastilla dice el nombre de lo elegido antes de recogerse: un ícono solo no dice qué escogiste")
        // Ya no existe el resorte con rebote que usaba el selector.
        check(hits(#"DS\.Motion\.morph\b"#, in: files), "DS.Motion.morph ya no existe: usa DS.Motion.grow (crece) o DS.Motion.fold (cede)")
    }
}
