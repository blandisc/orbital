import XCTest

/// El arte nunca enseña su orilla (Fernando, 13 nov 2026, AR1 · «Se funde»: «en las landing pages, cuando le das para abajo…
/// sale como un color sólido que corta el póster»). Regla en `docs/ios-interfaz.md` § «El arte nunca enseña su orilla»:
/// el arte se funde con el fondo que de verdad tiene detrás; nada de un color pintado encima, nada que lo recorte mientras
/// se mueve y una transición larga bajo la barra.
extension DesignRulesTests {
    private func file(_ name: String, in files: [Source]) throws -> String {
        let source = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
        return source.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    private var heroCollapse: String {
        get throws {
            let url = repo.appendingPathComponent("ios/OrbitalCore/Sources/OrbitalModels/HeroCollapse.swift")
            return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
    }

    /// 1 · Sin color pintado encima: el arte no se recoge hacia un color (`collapse: Color`), no lleva velo ni degradado del
    /// tono del arte, y la ficha no le pasa `Backdrop.tone` (el velo opaco del color del arte era el «bloque»).
    func testArtFadesIntoTheRealBackgroundWithoutAPaintedVeil() throws {
        let files = try sources()
        let art = try file("Art.swift", in: files)
        XCTAssertNil(art.range(of: #"var collapse\s*:\s*Color"#, options: .regularExpression),
                     "BleedArt no se recoge hacia un color: se desvanece y deja ver el fondo de verdad (`collapses: Bool`)")
        XCTAssertNil(art.range(of: #"func veil\(|\.dim\b|\.rise\b|riseSolid|riseTop"#, options: .regularExpression),
                     "BleedArt no pinta un velo ni un degradado del color del arte encima al recogerse")
        XCTAssertTrue(art.contains("var collapses"), "BleedArt dice si se recoge con `collapses`")
        check(hits(#"BleedArt\([^)]*collapse:"#, in: files), "Ningún arte se recoge hacia un color pintado encima (`collapse:`)")
        check(hits(#"Backdrop\.tone\("#, in: files, skip: { $0.name == "Backdrop.swift" }),
              "El tono del arte es el fondo (`Backdrop`), no un velo sobre el arte")
        let tokens = try file("Tokens+Screens.swift", in: files)
        let hero = try XCTUnwrap(tokens.range(of: "enum TitleHero").map { String(tokens[$0.lowerBound...].prefix(2500)) })
        XCTAssertNil(hero.range(of: #"\b(dim|riseEnd|riseSolidAt|riseSolidOpacity|riseTopOpacity|riseMin)\b"#, options: .regularExpression),
                     "DS.TitleHero sin tokens de velo (dim, rise…): el arte se funde con el fondo")
    }

    /// 2 · Nada lo recorta mientras se mueve: sin parallax ni encogido en la cuenta del recogido (sacaban la parte fundida
    /// fuera del recorte del zoom y dejaban costuras a los lados), y el origen del zoom es un marco quieto, no el arte.
    func testArtIsNeverClippedWhileItMoves() throws {
        let core = try heroCollapse
        XCTAssertNil(core.range(of: #"\b(parallax|shrink|offset)\b"#, options: .regularExpression),
                     "HeroCollapse sin parallax, encogido ni corrimiento: el arte se va con el contenido")
        let files = try sources()
        let tokens = try file("Tokens+Screens.swift", in: files)
        let hero = try XCTUnwrap(tokens.range(of: "enum TitleHero").map { String(tokens[$0.lowerBound...].prefix(2500)) })
        XCTAssertNil(hero.range(of: #"\b(parallax|shrink)\b"#, options: .regularExpression), "DS.TitleHero sin parallax ni encogido")
        let art = try file("Art.swift", in: files)
        XCTAssertNil(art.range(of: #"\.offset\(y: s\."#, options: .regularExpression), "el arte no se corre al desplazar")
        XCTAssertNotNil(art.range(of: #"\.background \{[^\n]*playerZoomSource"#, options: .regularExpression),
                        "el origen del zoom va en un marco quieto detrás del arte (`.background { … playerZoomSource }`)")
        let title = try file("TitleView+Hero.swift", in: files)
        XCTAssertFalse(title.contains(".playerZoomSource("),
                       "la ficha no pone el zoom sobre el arte que se mueve (su recorte cortaba el arte): `BleedArt(zoom:)`")
    }

    /// 3 · Arriba, una transición larga (no una franja con orilla ni texto cortado a la mitad en el SE); en el iPad, detrás de
    /// la ficha va el fondo de la sala, el mismo que hay debajo del arte.
    func testTopOfTheTitleFadesLongAndThePadHasNoTintBand() throws {
        let files = try sources()
        let tokens = try file("Tokens+Screens.swift", in: files)
        let line = try XCTUnwrap(tokens.components(separatedBy: "\n").first { $0.contains("static let topFade") })
        let value = try XCTUnwrap(line.range(of: #"topFade: CGFloat = ([0-9.]+)"#, options: .regularExpression).map {
            Double(line[$0].split(separator: "=").last!.trimmingCharacters(in: .whitespaces))
        } ?? nil)
        XCTAssertGreaterThanOrEqual(value, 90, "DS.TitleAction.topFade ≥ 90: lo que sube bajo la barra se desvanece despacio")
        let view = try file("TitleView.swift", in: files)
        XCTAssertTrue(view.contains("if sizeClass == .regular { DS.backdropDeep.ignoresSafeArea() } else { Backdrop(tint: tint.colors) }"),
                      "en el iPad la ficha va sobre el fondo de la sala (sin el tono arriba que la máscara de la barra dejaba ver)")
        let chrome = try file("TitleScrollChrome.swift", in: files)
        XCTAssertTrue(chrome.contains("scheme == .light"), "en claro el logo de la barra va en el color del texto (uno blanco no se leía)")
    }
}
