import XCTest

/// «Decide por mí» pulido (DE1, Fernando, 13 nov 2026: «Construye DE1 y DE2 para ver cómo se ven»). Reglas en
/// `docs/ios-interfaz.md` § «Un filtro que se ve puesto, filtra» y § «Lo que quitas se puede deshacer».
extension DesignRulesTests {
    private func file(_ name: String, in files: [Source]) throws -> String {
        try XCTUnwrap(files.first { $0.name == name }, "falta \(name)").lines.joined(separator: "\n")
    }

    /// Un filtro que se ve puesto, filtra: la baldosa del tiempo se ve elegida solo con el que elegiste (`shownTime`), nunca
    /// con el de la hora (`m.time`), que solo ordena (F3: decía «1 h» y salían películas de tres horas).
    func testAFilterThatLooksOnFilters() throws {
        let files = try sources()
        let pages = try file("DecideFilterPages.swift", in: files)
        XCTAssertTrue(pages.contains("let on = m.shownTime == t"), "La baldosa del tiempo se ve puesta solo con el que elegiste")
        let controls = try file("DecideControls.swift", in: files)
        XCTAssertTrue(controls.contains("let t = m.shownTime"), "la línea de lo puesto dice solo el tiempo que elegiste")
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
        XCTAssertGreaterThanOrEqual(pages.components(separatedBy: "n?.open == true").count - 1, 3, "géneros, épocas y premios se tocan solo si dejan algo (`Tally.open`, como `offered`)")
        XCTAssertTrue(pages.contains("FameQuadrant(selected: m.fame, counts:"), "Fama, el cuadro del filtro avanzado con sus cuentas")
        XCTAssertTrue(pages.contains("FilterLogoChoice("), "Premios con su estatuilla")
        XCTAssertFalse(pages.contains("PanelChip("), "sin cápsulas de solo texto en «Afinar»")
    }

    /// El dado es solo «Decide por mí» (`DS.Symbol.decide`): «Temporadas» de la dona y «Repartido por décadas» tienen el suyo.
    func testTheDiceIsOnlyDecide() throws {
        let files = try sources(["Design", "Screens"])
        let allowed: Set<String> = ["Icons.swift"]
        check(hits(#""dice(\.fill)?""#, in: files, skip: { allowed.contains($0.name) }), "El dado solo para «Decide por mí»: usa DS.Symbol.decide")
        check(hits(#"symbol: "dice"|systemName: "dice""#, in: files, skip: { allowed.contains($0.name) }), "El dado solo para «Decide por mí»")
    }

    /// Una pregunta, una puerta (DE2): «Decide por mí» se abre solo desde `DecideDoor` (Explorar e Inicio), siempre con la
    /// misma hoja (`DecideSheet`, que arma `DecideView` con lo de Explorar) sobre la pantalla donde estás: Inicio ya no te
    /// manda a Explorar (13 nov 2026). Las dos puertas llevan el mismo abanico (`decideFan`). Adentro, «Tres que caben» y
    /// «Una por una» son pestañas de la misma hoja y el mazo ya no es su propia pantalla.
    func testOneQuestionOneDoor() throws {
        let files = try sources()
        check(hits(#"DecideView\("#, in: files, skip: { $0.name == "DecideView.swift" }).filter { !$0.hasPrefix("Screens/DecideSheet.swift") },
              "«Decide por mí» se arma solo en `DecideSheet`")
        check(hits(#"DecideSheet\("#, in: files).filter { !$0.hasPrefix("Screens/ParaTiView.swift") && !$0.hasPrefix("Screens/DecideHomeRow.swift") },
              "La hoja se abre desde las dos puertas: Explorar e Inicio")
        check(hits(#"MatchDeckScreen\("#, in: files, skip: { $0.name == "MatchDeckScreen.swift" }).filter { !$0.hasPrefix("Screens/DecideView.swift") },
              "El mazo vive dentro de «Decide por mí» («Una por una»), no en otra pantalla")
        check(hits(#"MatchTeaser|"¿Qué vemos hoy\?"|DS\.Symbol\.decide\) *\}.*ToolbarItem|ToolbarItem[^\n]*DS\.Symbol\.decide"#, in: files),
              "Sin otra puerta: ni «¿Qué vemos hoy?» ni el dado en la barra")
        check(hits(#"openDecide"#, in: try sources(["App", "Design", "Screens"])), "Inicio abre la hoja ahí mismo: sin saltar a Explorar")
        let decide = try file("DecideView.swift", in: files)
        XCTAssertTrue(decide.contains(#"Text("Tres que caben")"#) && decide.contains(#"Text("Una por una")"#), "las dos pestañas, con los nombres de la TV")
        XCTAssertTrue(decide.contains("m.deckPool()"), "el mazo usa los mismos filtros")
        let paraTi = try file("ParaTiView.swift", in: files)
        XCTAssertFalse(paraTi.contains("fullScreenCover"), "sin la pantalla aparte del mazo")
        let explore = try file("ListsView.swift", in: files), home = try file("DecideHomeRow.swift", in: files)
        XCTAssertTrue(explore.contains("model.decideFan()") && home.contains(".decideFan()"), "la misma puerta con el mismo abanico en Explorar y en Inicio")
    }

    /// Una hoja, un renglón de controles (Fernando, 13 nov 2026): las dos pestañas usan el mismo `DecideControls`, con el tipo
    /// y un solo botón «Filtros» (`DSFiltersButton`, el mismo número en las dos), que abre una sola hoja de filtros por
    /// secciones (`DecideFilters`). Lo puesto se dice en una línea que solo existe si hay algo puesto. La cuenta va junto al
    /// título.
    func testOneControlRowPerSheet() throws {
        let files = try sources()
        let decide = try file("DecideView.swift", in: files)
        XCTAssertEqual(decide.components(separatedBy: "DecideControls(").count - 1, 1, "un solo renglón de controles, en el encabezado de las dos pestañas")
        XCTAssertFalse(decide.contains("DSCapsuleLabel") || decide.contains("Grid("), "sin rejilla de cápsulas de filtros")
        let controls = try file("DecideControls.swift", in: files)
        XCTAssertFalse(controls.contains("DSCapsuleLabel"), "sin cápsulas de texto")
        XCTAssertEqual(controls.components(separatedBy: "DSFiltersButton(").count - 1, 1, "un solo botón «Filtros»")
        XCTAssertFalse(controls.contains("timeMenu") || controls.contains("ratingMenu"), "sin los menús de cada filtro")
        XCTAssertFalse(controls.contains("deck ? tonight"), "el mismo número en las dos pestañas")
        XCTAssertTrue(controls.contains("if !parts.isEmpty { setLine("), "sin nada puesto, la línea de lo puesto no existe")
        XCTAssertTrue(controls.contains(#"Button("Quitar filtros""#) && controls.contains(#"Button("Cambiar filtros""#), "la línea ofrece quitarlo o cambiarlo")
        let pages = try file("DecideFilterPages.swift", in: files)
        for section in ["Esta noche", "Qué tan buena", "Qué tipo", "De dónde"] {
            XCTAssertTrue(pages.contains(#"DSSectionHead(title: "\#(section)", level: .section)"#), "la hoja de filtros, por secciones: \(section)")
        }
        XCTAssertTrue(pages.contains("DecideChoice(") && pages.contains(#"Text("Quitar filtros")"#) && pages.contains("decide-filters-count"),
                      "baldosas con nombre, «Quitar filtros» y cuántas quedan")
        XCTAssertTrue(pages.contains("m.filtersSignature != opened"), "al salir se baraja solo si cambió algo")
        XCTAssertFalse(pages.contains("LazyVGrid"), "las opciones van en `DecideChoiceGrid` (iguala altos), no en la rejilla perezosa")
        let header = try XCTUnwrap(decide.components(separatedBy: "private func header(").dropFirst().first)
        let title = try XCTUnwrap(header.components(separatedBy: "DSSelector(").first)
        XCTAssertTrue(title.contains("{ countText(m, count); close }"), "la cuenta va junto al título, no en su propio renglón")
        check(hits(#"DSFilterIcon|DSFilterPill"#, in: files), "Sin los cuatro íconos de antes")
    }

    /// Los datos no se enciman con el arte; lo elegido crece (pulido de DE2): la carta del mazo es solo arte del tamaño del
    /// póster, sus datos van debajo (`MatchCardInfo`) en una línea sin cápsulas, «Ver» es el cuarto botón (no flota sobre el
    /// arte) y en «Tres que caben» la elegida crece con su sombra, sin marco ni las otras apagadas.
    func testDataDoesNotSitOnTheArt() throws {
        let files = try sources()
        let mazo = try file("MazoMatch.swift", in: files)
        let card = try XCTUnwrap(mazo.components(separatedBy: "struct MatchCard: View").dropFirst().first?.components(separatedBy: "struct MatchCardInfo").first)
        for drawn in ["ArtVeil", "recipe(", "DSIconButton", "TraktRatings", "Capsule()"] {
            XCTAssertFalse(card.contains(drawn), "la carta del mazo no lleva \(drawn) encima del arte: los datos van debajo")
        }
        XCTAssertTrue(mazo.contains("w / DS.Poster.aspect"), "la carta mide lo que su póster: el arte la llena, sin franjas")
        XCTAssertTrue(mazo.contains("MatchCardInfo(suggestion:") && mazo.contains("reservesSpace: true"), "los datos debajo, con su lugar apartado")
        XCTAssertTrue(mazo.contains("DS.Match.behindPeek"), "las que siguen asoman")
        XCTAssertFalse(mazo.contains("DS.Motion.spring"), "la carta regresa sin rebote")
        let deck = try file("MatchDeckScreen.swift", in: files)
        XCTAssertEqual(deck.components(separatedBy: "MatchActionButton(").count - 1, 4, "Paso · Para hoy · Guardar · Ver: cuatro círculos iguales")
        XCTAssertTrue(try file("MatchActions.swift", in: files).contains("steady: true"), "del mismo tamaño siempre")
        XCTAssertTrue(deck.contains(#"id: "match-play""#), "«Ver» es un botón de la fila")
        let decide = try file("DecideView.swift", in: files)
        XCTAssertFalse(decide.contains("dsSelectionRing") || decide.contains("DS.Opacity.dimmed"), "sin marco blanco ni las otras apagadas")
        XCTAssertTrue(decide.contains("DS.Motion.grow(reduceMotion)") && decide.contains(".bottomLeading"), "la elegida crece desde su base, hacia adentro")
    }

    /// Un número dice lo de ahora (13 nov 2026: las baldosas de «6+» decían «0» con «33 opciones» arriba). Los números de la
    /// hoja de filtros se calculan en su `body` con `tally` (lo de ahora, y nil mientras no se sabe: nunca un «0» falso), no
    /// dentro de una rejilla perezosa que los guarda de la primera vez; las baldosas de una fila miden lo mismo
    /// (`DecideChoiceGrid`, un `Grid`).
    func testFilterNumbersAreFreshAndRowsEven() throws {
        let files = try sources()
        let pages = try file("DecideFilterPages.swift", in: files)
        XCTAssertFalse(pages.contains("LazyVGrid") || pages.contains(".id(m.genres)") || pages.contains(".id(m.decades)"), "sin rejilla perezosa ni el truco de `.id`")
        XCTAssertGreaterThanOrEqual(pages.components(separatedBy: "DecideChoiceGrid(").count - 1, 8, "todas las filas de opciones en `DecideChoiceGrid`")
        XCTAssertTrue(pages.contains("m.tally(deck: deck)") && pages.contains("?.shown"), "arriba y cada baldosa con `tally`; sin saber, sin número")
        XCTAssertFalse(pages.contains("m.count {"), "ninguna baldosa cuenta a su manera")
        let pieces = try file("DecidePieces.swift", in: files)
        XCTAssertTrue(pieces.contains("struct DecideChoiceGrid") && pieces.contains("Grid(horizontalSpacing"), "la rejilla que iguala altos")
        XCTAssertTrue(pieces.contains("maxHeight: .infinity") && pieces.contains(".opacity(count == nil ? 0 : 1)"), "la baldosa llena su fila y aparta el renglón del número")
    }

    /// Un botón fijo abajo deja ver lo que pasa debajo: va en `safeAreaBar(edge: .bottom)` (lo que se desliza se funde detrás
    /// y el último renglón se puede subir por encima), nunca en `safeAreaInset`, que lo cortaba a medias («Ver 33» tapaba los
    /// logos de «Según»).
    func testFixedBottomButtonLetsContentShowThrough() throws {
        check(hits(#"\.safeAreaInset\(edge: \.bottom"#, in: try sources()), "Un botón fijo abajo va en safeAreaBar(edge: .bottom)")
    }

    /// Ninguna tarea sobrevive a su vista (el abort de `completeFuture` tras el congelamiento): Barajar y la carta que vuela se
    /// cancelan al desaparecer, y el modelo de Decide no empieza nada después de `stop()`.
    func testNoTaskOutlivesItsView() throws {
        let files = try sources()
        let decide = try file("DecideView.swift", in: files)
        XCTAssertTrue(decide.contains("shuffling?.cancel()") && decide.contains("guard !Task.isCancelled"), "Barajar se cancela al cerrar")
        let mazo = try file("MazoMatch.swift", in: files)
        XCTAssertTrue(mazo.contains(".onDisappear { flight?.cancel()"), "la carta que vuela se cancela al irse el mazo")
        XCTAssertFalse(mazo.contains("        Task { @MainActor in"), "sin tareas sueltas en el mazo")
        let model = try String(contentsOf: repo.appendingPathComponent("ios/OrbitalCore/Sources/OrbitalModels/DecideModel.swift"), encoding: .utf8)
        XCTAssertTrue(model.contains("guard !stopped else { return }"), "nada empieza después de cerrar la hoja")
    }

    /// Los datos son de la carta que se ve (13 nov 2026): al salir volando una carta, debajo ya dicen los de la que sube a su
    /// lugar (antes «La Oficina» seguía escrita un segundo debajo de «Avengers»).
    func testCardInfoFollowsTheVisibleCard() throws {
        let mazo = try file("MazoMatch.swift", in: try sources())
        XCTAssertTrue(mazo.contains("cards.first(where: { $0.imdb != leaving })"), "los datos saltan la carta que va volando")
        XCTAssertEqual(mazo.components(separatedBy: "leaving = s.imdb").count - 1, 2, "volando y fundiéndose, las dos marcan la que sale")
    }

    /// VoiceOver dice el nombre que se lee (13 nov 2026): el cartel elegido decía «The Office» y debajo se leía «La Oficina».
    func testSpokenTitleIsTheShownTitle() throws {
        let raw = try NSRegularExpression(pattern: #"accessibilityLabel\(Text\(verbatim: (option|s|suggestion|item|card)\.title\)\)"#)
        for source in try sources() {
            let name = source.name, text = source.lines.joined(separator: "\n")
            let hits = raw.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertEqual(hits, 0, "\(name): el nombre de un título va con titleName, como el que se ve")
        }
    }
}
