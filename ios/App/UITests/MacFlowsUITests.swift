import XCTest

/// Cuatro flujos de punta a punta con el acomodo de la Mac (`-demo-mac-look`: pestañas en cápsula, ficha en filas, Buscar
/// grande), cada uno dos veces: el camino de siempre y una variación (otra entrada, otro título, teclado). Corre en el
/// simulador del iPad porque en la Mac Xcode no corre XCUITest con una app de iPad, y la app se queda dormida si nadie la ve
/// (16 nov 2026). Lo que solo existe en la Mac de verdad (el puntero sobre el póster, la barra de menús) no se prueba aquí.
///
/// Con `SHOTS=<carpeta>` guarda una captura en cada paso.
final class MacFlowsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Piezas

    /// Versiones de la demo que sí arrancan (el video de prueba de Apple, largo): con las de siempre el reproductor se quedaba en
    /// «Todavía no está en la nube» con «Cerrar» (tercera y cuarta vuelta, 16 nov).
    static let canPlay = ["-demo-versions", "-demo-no-tv"]   // sin TV: «Ver» no pregunta «¿En la TV?»

    func launch(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-free-tabs", "-demo-mac-look", "-demo-trakt"] + extra
        app.launch()
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func any(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    @discardableResult
    func wait(_ fragment: String, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = any(fragment)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "no apareció «\(fragment)»", file: file, line: line)
        return found
    }

    func gone(_ element: XCUIElement, _ timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    func button(_ id: String, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = app.buttons[id].firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "no apareció el botón «\(id)»", file: file, line: line)
        return found
    }

    /// La pestaña de la cápsula («Inicio», «Explorar», «Biblioteca»).
    func tab(_ name: String) {
        let strip = app.descendants(matching: .any)["mac-tabs"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15), "sin la cápsula de pestañas de la Mac")
        strip.buttons[name].firstMatch.tap()
        sleep(2)
    }

    /// Buscar desde la cápsula de la lupa y abrir el primer resultado que se llame así.
    func searchAndOpen(_ query: String, expect: String) {
        button("mac-search-chip").tap()
        let field = app.textFields["Películas y series"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "sin el campo de Buscar de la Mac")
        field.tap()
        field.typeText(query)
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'title-link' AND label BEGINSWITH[c] %@", expect)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25), "Buscar «\(query)» no trajo «\(expect)»")
        shot("buscar-\(query)")
        result.tap()
    }

    /// «Ver» en la ficha, cuando ya cargó.
    func playFromTitle(file: StaticString = #filePath, line: UInt = #line) {
        let play = button("title-play", 25, file: file, line: line)
        let ready = NSPredicate(format: "isEnabled == true AND NOT (label CONTAINS[c] 'Cargando')")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: ready, evaluatedWith: play)], timeout: 30), .completed,
                       "«Ver» no se encendió: \(play.label)", file: file, line: line)
        shot("ficha-\(play.label)")
        play.tap()
    }

    /// Deja correr el video lo suficiente para que cuente (más de 20 s) y lo cierra con ✕ o con Esc.
    func watchAndClose(withEscape: Bool, seconds: UInt32 = 28) {
        let video = app.otherElements["player"].firstMatch
        _ = video.waitForExistence(timeout: 15)
        XCTAssertTrue(video.exists || app.buttons["player-close"].waitForExistence(timeout: 10), "no abrió el reproductor")
        sleep(seconds)
        shot("reproductor")
        if withEscape {
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        } else {
            let close = app.buttons["player-close"].firstMatch
            // Los controles se esconden a los 3 s: un toque sobre el video (arriba, en vertical abajo va «Audio y subtítulos»).
            if !close.isHittable { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() }
            XCTAssertTrue(close.waitForExistence(timeout: 5), "sin ✕ para cerrar")
            close.tap()
        }
        XCTAssertTrue(gone(app.otherElements["player"].firstMatch, 10), "el reproductor no se cerró")
        sleep(2)
        shot("reproductor-cerrado")
    }

    /// «Seguir viendo» de Inicio trae una tarjeta con ese nombre.
    func continueRailHas(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let head = app.buttons["home-all-continue"].firstMatch
        for _ in 0..<4 where !head.exists { app.swipeUp() }
        XCTAssertTrue(head.waitForExistence(timeout: 15), "sin «Seguir viendo» en Inicio", file: file, line: line)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "«\(name)» no está en Seguir viendo", file: file, line: line)
        shot("seguir-viendo-\(name)")
    }

    /// Biblioteca › Guardado › Mi lista.
    func openMyList() {
        tab("Biblioteca")
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Guardado'")).firstMatch
        if saved.waitForExistence(timeout: 5) { saved.tap() }
        let myList = button("saved-tab-mylist")
        myList.tap()
        sleep(2)
    }

    func savedPoster(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
    }

    // MARK: - 1. La guía de la primera vez

    func testGuideToTheEnd() {
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        walkGuideFromWelcome()
        XCTAssertTrue(app.descendants(matching: .any)["mac-tabs"].firstMatch.waitForExistence(timeout: 15), "al terminar no llegó a Inicio")
        shot("guia-fin-inicio")
    }

    /// Variación: saltarla a medias, volver a abrirla desde Ajustes (por tu foto) y ahora sí terminarla.
    func testGuideCloseHalfwayAndReopen() {
        launch(["-demo-first-run", "-demo-signed-out", "-demo-no-tv"])
        wait("Todo lo que quieres ver, en un solo lugar.", 25); sleep(3)
        button("guide-next").tap()
        wait("Sigue donde te quedaste")   // v3: en la Mac no hay paso de la TV
        button("guide-skip-all").tap()
        XCTAssertTrue(app.descendants(matching: .any)["mac-tabs"].firstMatch.waitForExistence(timeout: 15), "«Saltar» no llevó a la app")
        shot("guia-saltada")
        // ⌘, no se usa aquí: en el iPad (simulador, iPadOS 27) abre los Ajustes del sistema, no los de Orbital (hallazgo de
        // la tercera vuelta). Se llega como con el dedo: tu foto abre Ajustes (sin historias en Inicio desde el 18 nov).
        let learn = app.buttons["settings-learn"].firstMatch
        let profile = app.buttons["Ajustes"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 8), "sin camino a Ajustes desde Inicio")
        shot("camino-a-ajustes")
        profile.tap()
        // La lista crea el renglón al llegar a él (como en `OnboardingUITests`): primero Ajustes, luego bajar hasta «Aprende».
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15), "tu foto no abrió Ajustes")
        for _ in 0..<8 where !(learn.exists && learn.isHittable) { app.swipeUp() }
        learn.tap()
        let again = app.buttons["settings-guide"].firstMatch
        for _ in 0..<4 where !(again.exists && again.isHittable) { app.swipeUp() }
        again.tap()
        walkGuideFromWelcome()
    }

    private func walkGuideFromWelcome() {
        wait("Todo lo que quieres ver, en un solo lugar.", 25); sleep(3)
        shot("guia-1-bienvenida")
        button("guide-next").tap(); wait("Sigue donde te quedaste")   // v3: Trakt, luego tu nube
        button("guide-skip").tap(); wait("Para ver aquí, conecta un servicio de nube")
        shot("guia-4-debrid")
        button("guide-skip").tap()
        wait("Tu Orbital ya está lista.")
        shot("guia-5-lista")
        // «Ir a Inicio»: el último paso (al reabrirla desde Ajustes, el de `guide-next` no siempre se da por tocable).
        let home = app.buttons["Ir a Inicio"].firstMatch
        if home.waitForExistence(timeout: 5) { home.tap() } else { app.buttons.matching(identifier: "guide-next").allElementsBoundByIndex.last { $0.isHittable }?.tap() }
        // Reabierta desde Ajustes, al terminar regresa a donde la abriste (Ajustes), no a Inicio: basta con que se cierre.
        XCTAssertTrue(gone(any("Tu Orbital ya está lista."), 8), "la guía no se cerró")
    }

    // MARK: - 2. Ver algo por primera vez

    func testSearchWatchAndContinue() throws {
        // Pendiente (16 nov 2026, seis vueltas): la demo no trae una versión que arranque desde Buscar o Explorar con el acomodo de
        // la Mac. Sin banderas, el reproductor abre en «Todavía no está en la nube»; con `-demo-versions`, «Ver» no abre nada.
        // Falta una bandera de demo con un video que arranque para cualquier título; hasta entonces no se da por comprobado.
        try XCTSkipIf(true, "pendiente: la demo no tiene una versión que arranque para este título")
        launch(Self.canPlay)
        searchAndOpen("matrix", expect: "The Matrix")
        playFromTitle()
        watchAndClose(withEscape: false)
        tab("Inicio")
        continueRailHas("Matrix")
    }

    /// Variación: desde Explorar con ⌘2, otro título, y de regreso a Inicio con ⌘1. (Esc para cerrar el video no se puede
    /// probar aquí: la tecla Esc de XCUITest no llega como Esc al simulador de iPadOS 27; ver `IPadKeyboardUITests`.)
    func testExploreWatchWithKeyboard() throws {
        // Pendiente (16 nov 2026, seis vueltas): la demo no trae una versión que arranque desde Buscar o Explorar con el acomodo de
        // la Mac. Sin banderas, el reproductor abre en «Todavía no está en la nube»; con `-demo-versions`, «Ver» no abre nada.
        // Falta una bandera de demo con un video que arranque para cualquier título; hasta entonces no se da por comprobado.
        try XCTSkipIf(true, "pendiente: la demo no tiene una versión que arranque para este título")
        launch(Self.canPlay)
        app.typeKey("2", modifierFlags: .command)
        sleep(3)
        let poster = app.buttons.matching(identifier: "title-link").element(boundBy: 2)
        XCTAssertTrue(poster.waitForExistence(timeout: 25), "Explorar sin pósters")
        let name = poster.label.components(separatedBy: ",").first ?? poster.label
        shot("explorar")
        poster.tap()
        playFromTitle()
        watchAndClose(withEscape: false)
        app.typeKey("1", modifierFlags: .command)
        sleep(2)
        shot("cmd1-tras-reproductor")
        XCTAssertTrue(app.buttons["Inicio"].firstMatch.isSelected, "⌘1 no llevó a Inicio después de cerrar el reproductor con Esc")
        continueRailHas(name)
    }

    // MARK: - 3. Guardar

    func testSaveFromTitle() {
        launch()
        searchAndOpen("matrix", expect: "The Matrix")
        let status = button("title-status", 25)
        XCTAssertTrue(status.label.contains("Guardar"), "la ficha no ofrece «Guardar»: \(status.label)")
        status.tap()
        wait("Guardada en Mi lista", 8)
        shot("guardada")
        // En la Mac las pestañas solo están en las pantallas de arriba (como la tele): desde la ficha, «Atrás» y luego Biblioteca.
        app.buttons["BackButton"].firstMatch.tap()
        sleep(1)
        openMyList()
        // El Trakt de la demo guarda lo nuevo con su IMDb por nombre (con Trakt de verdad llega «The Matrix»).
        let matrix = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Matrix' OR label CONTAINS 'tt0133093'")).firstMatch
        XCTAssertTrue(matrix.waitForExistence(timeout: 15), "Matrix no está en Biblioteca › Mi lista")
        shot("mi-lista-con-matrix")
    }

    /// Variación: desde el menú del póster en Explorar (clic secundario en la Mac).
    func testSaveFromPosterMenu() {
        launch()
        tab("Explorar")
        let posters = app.buttons.matching(identifier: "title-link")
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 25))
        var name = ""
        for index in 0..<min(posters.count, 12) {
            let poster = posters.element(boundBy: index)
            guard poster.isHittable else { continue }
            poster.press(forDuration: 1.2)
            let save = app.buttons["Guardar"].firstMatch
            if save.waitForExistence(timeout: 3) {
                name = poster.label.components(separatedBy: ",").first ?? poster.label
                shot("menu-poster")
                save.tap()
                break
            }
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])   // ya guardado: el menú dice «Quitar de Mi lista»
            sleep(1)
        }
        XCTAssertFalse(name.isEmpty, "ningún póster de Explorar ofreció «Guardar»")
        wait("Guardada en Mi lista", 8)
        openMyList()
        XCTAssertTrue(savedPoster(name).waitForExistence(timeout: 15), "«\(name)» no está en Biblioteca › Mi lista")
        shot("mi-lista-con-\(name)")
    }

    // MARK: - 4. Quitar

    /// Quitar de Mi lista con el menú del póster, «Deshacer», y quitar otra vez.
    func testRemoveFromMyListWithUndo() {
        launch()
        openMyList()
        let poster = savedPoster("Severance")
        XCTAssertTrue(poster.waitForExistence(timeout: 15), "Severance no está en Mi lista de la demo")
        poster.press(forDuration: 1.2)
        let remove = app.buttons["Quitar de Mi lista"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "el menú no trae «Quitar de Mi lista»")
        remove.tap()
        wait("Quitada de Mi lista", 8)
        XCTAssertTrue(gone(savedPoster("Severance")), "Severance sigue en Mi lista")
        shot("quitada")
        let undo = app.buttons["Deshacer"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "sin «Deshacer»")
        undo.tap()
        XCTAssertTrue(savedPoster("Severance").waitForExistence(timeout: 10), "«Deshacer» no la regresó")
        shot("deshecho")
    }

    /// Variación con teclado: ⌘1 a Inicio, quitar de «Seguir viendo», «Deshacer», quitar otra vez y, pasado el aviso, ⌘3 y ⌘1
    /// de ida y vuelta: sigue fuera.
    func testRemoveFromContinueWithKeyboard() {
        launch()
        app.typeKey("1", modifierFlags: .command)
        let head = app.buttons["home-all-continue"].firstMatch
        for _ in 0..<4 where !head.exists { app.swipeUp() }
        XCTAssertTrue(head.waitForExistence(timeout: 20), "sin «Seguir viendo» en la demo")
        // La tarjeta de «Seguir viendo» (la que lleva avance); The Office sale también en otras filas de Inicio.
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'The Office, Avance'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The Office no está en Seguir viendo")
        func remove() {
            card.press(forDuration: 1.2)
            let item = app.buttons["Quitar de Seguir viendo"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "el menú no trae «Quitar de Seguir viendo»")
            item.tap()
            XCTAssertTrue(gone(card), "The Office sigue en Seguir viendo")
        }
        remove()
        wait("Quitada de Seguir viendo", 5)
        shot("quitada-de-seguir-viendo")
        let undo = app.buttons["Deshacer"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "quitar de Seguir viendo no ofrece «Deshacer»")
        undo.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8), "«Deshacer» no la regresó")
        shot("deshecho-seguir-viendo")
        remove()
        sleep(12)   // pasa el aviso y el plazo para deshacer: ahora sí sale del aparato
        app.typeKey("3", modifierFlags: .command); sleep(2)
        app.typeKey("1", modifierFlags: .command); sleep(3)
        XCTAssertFalse(card.exists, "The Office volvió a Seguir viendo al regresar")
        shot("seguir-viendo-sin-the-office")
    }
}
