import XCTest

/// GD2 (Fernando, 13 nov 2026: «Pestañas, como la tele», en lugar del tablero G2-A del 9 nov). Reglas en
/// `docs/ios-interfaz.md` § «Lo guardado se ve al entrar», «Sin conexión nunca se ve como vacío» y «Un vacío enseña qué hacer».
extension DesignRulesTests {
    private func savedScreens() throws -> [Source] {
        try sources(["Screens"]).filter { $0.name.hasPrefix("Saved") || $0.name == "LibrarySavedView.swift" }
    }

    private func code(_ file: Source) -> [String] {
        file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Guardado abre en los pósters de Mi lista con sus cuatro partes en el selector de Orbital (SG1, `DSSelector` completo), no en un índice que hay
    /// que tocar para ver algo: ni tablero ni pantallas aparte por estado.
    func testSavedOpensOnTabsNotAnIndex() throws {
        let files = try sources(["Design", "Screens"])
        check(hits(#"SavedStateRoute|SavedStateScreen|SavedStateTile|HistoryRoute|"saved-list-menu""#, in: files),
              "Guardado son pestañas (GD2): sin el tablero, sus pantallas por estado ni el menú de listas de antes")
        let saved = try XCTUnwrap(files.first { $0.name == "LibrarySavedView.swift" })
        let body = code(saved)
        XCTAssertTrue(body.contains { $0.contains("DSSelector(") && $0.contains("size: .full") }, "Las partes de Guardado van en el selector de Orbital, completo (SG1)")
        for id in ["saved-tab-mylist", "saved-tab-watching", "saved-tab-watched", "saved-tab-lists"] {
            XCTAssertTrue(body.contains { $0.contains("\"\(id)\"") }, "falta la pestaña \(id)")
        }
        XCTAssertTrue(body.contains { $0.contains("case myList, watching, watched, lists") },
                      "Las pestañas, en orden: Mi lista · Viendo · Vistas · Listas")
    }

    /// Sin internet (o Trakt sin contestar) Guardado lo dice y ofrece «Reintentar»: se revisa antes de decidir que está vacío.
    func testSavedNeverShowsOfflineAsEmpty() throws {
        let files = try savedScreens()
        let saved = code(try XCTUnwrap(files.first { $0.name == "LibrarySavedView.swift" }))
        let offline = try XCTUnwrap(saved.firstIndex { $0.contains("model.unreachable") }, "Guardado ya no revisa si no llegó nada (`unreachable`)")
        let empty = try XCTUnwrap(saved.firstIndex { $0.contains("isNew(board)") }, "Guardado ya no tiene la guía de cuenta nueva")
        XCTAssertLessThan(offline, empty, "Sin conexión se revisa antes que «vacío»")
        XCTAssertTrue(saved.contains { $0.contains("DSErrorState(") }, "Sin conexión, `DSErrorState` con «Reintentar»")
        let list = code(try XCTUnwrap(files.first { $0.name == "SavedListScreen.swift" }))
        let failed = try XCTUnwrap(list.firstIndex { $0.contains("model.failed && items.isEmpty") && $0.contains("if ") })
        let emptyList = try XCTUnwrap(list.firstIndex { $0.contains("else if isEmpty") })
        XCTAssertLessThan(failed, emptyList, "Una lista que no llegó dice «Reintentar» antes que «está vacía»")
    }

    /// Cada vacío de Guardado trae un ícono y a dónde ir (un botón), no solo un letrero.
    func testSavedEmptyStatesTeachWhatToDo() throws {
        var problems: [String] = []
        for file in try savedScreens() {
            for (i, line) in file.lines.enumerated() where line.contains("DSEmptyState(") {
                let call = file.lines[i..<min(file.lines.count, i + 8)].joined(separator: "\n")
                let action = call.contains("Button(") || call.contains("NavigationLink(") || call.contains("searchButton")
                if !action || !call.contains("symbol:") { problems.append("\(file.path):\(i + 1)") }
            }
        }
        check(problems, "Un vacío enseña qué hacer: ícono, qué pasa y un botón a dónde ir")
    }

    /// El aviso flotante «¿Qué tal…?» no tapa lo último de Guardado, y las listas abiertas llevan el mismo cielo.
    func testSavedKeepsItsSkyAndRoomForTheReminder() throws {
        let files = try savedScreens()
        let saved = code(try XCTUnwrap(files.first { $0.name == "LibrarySavedView.swift" }))
        XCTAssertTrue(saved.contains { $0.contains("ratingReminderHeight") }, "Guardado deja lugar abajo para «¿Qué tal…?»")
        let list = code(try XCTUnwrap(files.first { $0.name == "SavedListScreen.swift" }))
        XCTAssertTrue(list.contains { $0.contains("Backdrop()") }, "Una lista abierta lleva el cielo de Guardado")
    }
}
