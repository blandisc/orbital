import XCTest

/// La versión vive en el botón (Fernando, 11 nov 2026: «Vamos L3»; antes el renglón «🇲🇽 Español · 1080p ›» iba suelto bajo
/// «Ver» y «rompe simetría»). Regla en `docs/ios-interfaz.md` § «La versión vive en el botón»: en la ficha, el idioma y la
/// calidad se eligen desde la zona derecha del botón principal (`SplitPlayButton`) y no existe un renglón de versión aparte.
/// Estas pruebas fallan si alguien vuelve a pintar un selector de versión suelto en la ficha.
extension DesignRulesTests {
    /// Los archivos de la ficha: sus pantallas y el botón principal.
    func isTitleScreen(_ f: Source) -> Bool { f.name.hasPrefix("TitleView") || f.name == "ContinueAction.swift" }

    /// Dónde puede la ficha abrir «Versión» además de la zona derecha del botón (archivo → cuántos renglones y por qué). Uno
    /// nuevo hace fallar la prueba: si de verdad hace falta, va aquí con su porqué; si es otro selector suelto, no.
    static let otherVersionDoors: [String: (count: Int, why: String)] = [
        "TitleView.swift": (6, "la definición de `openVersions`, ⌥⌘V del teclado (su camino visible es la zona derecha), «Probar otra versión» desde «Tus pedidos», el modo demo, y el «⋯» de cada episodio (dos: iPhone e iPad)"),
        "TitleView+RealDebrid.swift": (2, "«Probar otra versión» es el botón entero cuando un pedido se atoró, y la hoja del pedido"),
        "TitleView+Version.swift": (1, "la zona derecha del botón (`playVersion`)"),
    ]

    func testVersionLivesInThePlayButton() throws {
        let files = try sources(["Design", "Screens"])
        // 1 · La zona que abre «Versión» desde la ficha es una sola pieza.
        check(hits(#""title-sources""#, in: files) { $0.name == "SplitPlayButton.swift" },
              "`title-sources` (la versión que se toca) solo existe en la zona derecha de `SplitPlayButton`")
        check(hits(#"VersionSummary\("#, in: files) { ["SplitPlayButton.swift", "TitleView+Version.swift"].contains($0.name) },
              "La versión del botón se arma solo en `TitleView.playVersion` (TitleView+Version.swift)")
        // 2 · El botón principal no lleva un renglón de versión que se toque: lo de abajo solo informa.
        let main = try XCTUnwrap(files.first { $0.name == "ContinueAction.swift" })
        let code = main.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertTrue(code.contains("SplitPlayButton("), "`ContinueAction` pinta la versión con `SplitPlayButton`")
        XCTAssertNil(code.range(of: #"chevron|versions\s*:|title-sources|LanguageFlags"#, options: .regularExpression),
                     "`ContinueAction` no lleva otro selector de versión (flechita, `versions:`, banderas): la versión va en el botón")
        // 3 · Fuera de la pieza, la ficha solo abre «Versión» por las puertas conocidas.
        var counts: [String: Int] = [:]
        for line in hits(#"openVersions\(|SourcesTarget\([^)]*purpose: \.watch"#, in: files.filter(isTitleScreen)) {
            counts[String(line.split(separator: ":").first ?? "").components(separatedBy: "/").last ?? "", default: 0] += 1
        }
        var problems: [String] = []
        for (file, n) in counts.sorted(by: { $0.key < $1.key }) where n > (Self.otherVersionDoors[file]?.count ?? 0) {
            problems.append("\(file): \(n) lugares abren «Versión» (permitidos \(Self.otherVersionDoors[file]?.count ?? 0)). ¿Un selector de versión suelto?")
        }
        for (file, door) in Self.otherVersionDoors where (counts[file] ?? 0) < door.count {
            problems.append("\(file): quedan \(counts[file] ?? 0), la lista dice \(door.count). Baja el número en `otherVersionDoors`")
        }
        check(problems, "La ficha abre «Versión» desde la zona derecha del botón (docs/ios-interfaz.md § «La versión vive en el botón»)")
    }

    /// `SplitPlayButton` es pieza del catálogo: sus medidas viven en `DS.SplitPlay` y solo ella (y su miniatura de «Aprende»)
    /// las usa; aire parejo: un solo relleno vertical, de su token.
    func testSplitPlayButtonIsACatalogPiece() throws {
        let files = try sources(["Design", "Screens"])
        check(hits(#"DS\.SplitPlay\."#, in: files) { ["SplitPlayButton.swift", "StoryScenes.swift"].contains($0.name) || self.isTokens($0) },
              "Las medidas del botón partido (`DS.SplitPlay`) son de `SplitPlayButton`")
        let piece = try XCTUnwrap(files.first { $0.name == "SplitPlayButton.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(piece.contains("padding(.vertical, DS.SplitPlay.dividerInset)"), "la división deja el mismo aire arriba que abajo")
        XCTAssertNil(piece.range(of: #"padding\(\.(top|bottom)"#, options: .regularExpression), "`SplitPlayButton` no lleva rellenos sueltos arriba o abajo")
        XCTAssertTrue(piece.contains("fixedSize(horizontal: false, vertical: true)"), "los dos lados del botón miden lo mismo de alto")
    }

    /// Un botón, un estado (Fernando, 11 nov 2026: «aparece la parte blanca y la otra aparece la parte gris, en lo que se
    /// carga el botón de reproducir»): el botón partido nunca tiene un lado apagado y el otro prendido, y mientras carga la
    /// ficha o no hay qué ver, el botón va entero (sin zona de versión).
    func testSplitPlayButtonHasOneState() throws {
        let files = try sources(["Design", "Screens"])
        let split = try XCTUnwrap(files.first { $0.name == "SplitPlayButton.swift" })
        let offs = split.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && $0.contains(".disabled(!enabled)") }.count
        XCTAssertEqual(offs, 2, "Los dos lados de `SplitPlayButton` se apagan con el mismo `enabled`")
        check(hits(#"enabled: false.*version:|version:.*enabled: false"#, in: files),
              "Un botón apagado («Cargando», «Aún sin episodios», «Sale el…») va entero: sin `version:`")
    }
}
