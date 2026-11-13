import XCTest

/// «Decide por mí» pulido (DE1, Fernando, 13 nov 2026: «Construye DE1 y DE2 para ver cómo se ven»). Reglas en
/// `docs/ios-interfaz.md` § «Un filtro que se ve puesto, filtra» y § «Lo que quitas se puede deshacer».
extension DesignRulesTests {
    private func file(_ name: String, in files: [Source]) throws -> String {
        try XCTUnwrap(files.first { $0.name == name }, "falta \(name)").lines.joined(separator: "\n")
    }

    /// Un filtro que se ve puesto, filtra: la cápsula del tiempo enseña el que elegiste (`shownTime`) o «Cualquier duración»,
    /// nunca el de la hora (`m.time`), que solo ordena (F3: decía «1 h» y salían películas de tres horas).
    func testAFilterThatLooksOnFilters() throws {
        let files = try sources()
        let decide = try file("DecideView.swift", in: files)
        XCTAssertTrue(decide.contains("words.timeTitle(m)") && decide.contains("selected: m.shownTime != nil"),
                      "La cápsula del tiempo dice el que elegiste o «Cualquier duración» y se ve puesta solo entonces")
        check(hits(#"timeName\(m\.time\)|selected: m\.timeChosen"#, in: files), "Ningún filtro enseña puesto el tiempo de la hora (no filtra)")
        let words = try file("DecideWords.swift", in: files)
        XCTAssertTrue(words.contains("if let t = m.shownTime"), "«Nada con…» no culpa al tiempo que no elegiste")
    }

    /// Lo que quitas se puede deshacer: «No me interesa» y «Hoy no» de Decide, y «Paso» y «Para hoy» del mazo, avisan con
    /// «Deshacer» (F5). Ninguno llama al modelo sin su aviso.
    func testWhatYouRemoveCanBeUndone() throws {
        let files = try sources()
        let decide = try file("DecideView.swift", in: files)
        // Una sola llamada a cada uno, la de `remove`, que avisa con «Deshacer».
        XCTAssertEqual(decide.components(separatedBy: "m.notInterested()").count - 1, 1, "«No me interesa» pasa por `remove`")
        XCTAssertEqual(decide.components(separatedBy: "m.skipToday()").count - 1, 1, "«Hoy no» pasa por `remove`")
        XCTAssertTrue(decide.contains("private func remove(_ m: DecideModel"))
        XCTAssertTrue(decide.contains("m.undoRemoval()") && decide.contains(#"actionTitle: "Deshacer""#))
        let deck = try file("MatchDeckScreen.swift", in: files)
        XCTAssertFalse(deck.contains("onDiscard: { model.discard($0) }"), "«Paso» avisa con «Deshacer»")
        XCTAssertTrue(deck.contains("model.undoDiscard(s)"), "«Paso · Deshacer» regresa la carta")
        XCTAssertTrue(deck.contains(#"secondTitle: "Deshacer""#) && deck.contains("model.undo(s)"), "«Para hoy · Ver ya · Deshacer»")
    }

    /// Sin huecos ni botones que no hacen nada: los carteles van en `DecideTrioLayout` (centrados, cada uno de un tercio) y
    /// «Barajar» se apaga cuando no hay más (F4).
    func testDecideTrioHasNoHolesNorDeadShuffle() throws {
        let decide = try file("DecideView.swift", in: try sources())
        XCTAssertTrue(decide.contains("DecideTrioLayout {"), "los carteles en su pieza")
        XCTAssertFalse(decide.contains("Color.clear.aspectRatio"), "sin lugares vacíos de relleno")
        XCTAssertTrue(decide.contains("!m.canShuffle"), "«Barajar» se apaga si no hay a qué barajar")
    }

    /// Sin red no se culpa a los filtros: el vacío de Decide sale de `m.empty` (sin conexión, sin sugerencias o filtros) y los
    /// dos primeros ofrecen «Reintentar» (F2); el mazo dice lo mismo (F8).
    func testEmptySaysWhy() throws {
        let files = try sources()
        let decide = try file("DecideView.swift", in: files)
        XCTAssertTrue(decide.contains("m.empty") && decide.contains("case .offline, .nothingSuggested:") && decide.contains("decide-retry"))
        let deck = try file("MatchDeckScreen.swift", in: files)
        XCTAssertTrue(deck.contains("DS.Symbol.offline") && deck.contains("match-retry"), "el mazo sin red: «Sin conexión · Reintentar»")
    }

    /// Una opción en 0 no se toca (F13) y las opciones de «Afinar» llevan ícono o arte, no cápsulas de solo texto.
    func testDeadOptionsAreNotTappableAndChoicesHaveIcons() throws {
        let pages = try file("DecideFilterPages.swift", in: try sources())
        XCTAssertGreaterThanOrEqual(pages.components(separatedBy: "DecideModel.offered(").count - 1, 3, "géneros, épocas y premios usan `offered`")
        XCTAssertTrue(pages.contains("FameQuadrant(selected: m.fame, counts:"), "Fama, el cuadro del filtro avanzado con sus cuentas")
        XCTAssertTrue(pages.contains("FilterLogoChoice("), "Premios con su estatuilla")
        XCTAssertFalse(pages.contains("PanelChip("), "sin cápsulas de solo texto en «Afinar»")
    }

    /// El dado es solo «Decide por mí» (`DS.Symbol.decide`): «Temporadas» de la dona y «Repartido por décadas» tienen el suyo.
    func testTheDiceIsOnlyDecide() throws {
        let files = try sources(["Design", "Screens"])
        // Las entradas de la barra (Explorar y el mosaico) aún lo escriben tal cual hasta DE2.
        let allowed: Set<String> = ["Icons.swift", "ListsView.swift", "ParaTiView.swift"]
        check(hits(#""dice(\.fill)?""#, in: files, skip: { allowed.contains($0.name) }), "El dado solo para «Decide por mí»: usa DS.Symbol.decide")
        check(hits(#"symbol: "dice"|systemName: "dice""#, in: files, skip: { allowed.contains($0.name) }), "El dado solo para «Decide por mí»")
    }
}
