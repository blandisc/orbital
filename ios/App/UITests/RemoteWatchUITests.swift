import XCTest

/// El control se acomoda a lo que ves (Fernando, 26 nov 2026: IV-A, IV-B y CT-A de docs/producto/control-iphone/), con
/// toques de verdad contra la TV de mentira (`DemoTVWatch`):
/// - IV-B: un toque en Idioma pasa al siguiente audio y otro en Subtítulos los quita o los pone, sin abrir nada.
/// - IV-A: mantener Idioma (o tocar Versión) abre «Cómo lo ves»: elegir ahí cambia la pista, y una versión se pone en la TV.
/// - CT-A: con la TV en su Inicio, arriba del pad sale lo enfocado con su botón; un juego, sin IMDb, también.
final class RemoteWatchUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-appearance", "dark"] + extra
        app.launch()
        return app
    }

    /// Lo puesto en una tecla de pista (su valor para VoiceOver: «Español latino»).
    private func value(_ app: XCUIApplication, _ id: String) -> String { app.buttons[id].value as? String ?? "" }

    /// Espera a que la pista de una tecla diga algo (la TV contesta y el control se repinta).
    private func waitLabel(_ app: XCUIApplication, _ id: String, contains text: String, _ message: String) {
        let key = app.buttons[id]
        expectation(for: NSPredicate(format: "value CONTAINS %@", text), evaluatedWith: key)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(value(app, id).contains(text), message)
    }

    func testOneTapChangesLanguageAndSubtitles() {
        let app = launch(["-demo-tv-horror", "-demo-open", "remote-full"])
        let audio = app.buttons["remote-audio"], subs = app.buttons["remote-subtitles"]
        XCTAssertTrue(audio.waitForExistence(timeout: 20), "la tecla de idioma")
        XCTAssertTrue(app.buttons["remote-version"].exists, "y la de versión")
        XCTAssertFalse(app.buttons["remote-options"].exists, "una película no lleva Episodios")
        XCTAssertTrue(value(app, "remote-audio").contains("Inglés"), "empieza en inglés: \(value(app, "remote-audio"))")
        audio.tap()
        waitLabel(app, "remote-audio", contains: "latino", "un toque pasa a español latino")
        audio.tap()
        waitLabel(app, "remote-audio", contains: "Inglés", "otro toque da la vuelta al inglés")
        XCTAssertTrue(value(app, "remote-subtitles").contains("Español"), "subtítulos en español al empezar")
        subs.tap()
        waitLabel(app, "remote-subtitles", contains: "Sin subtítulos", "un toque los quita")
        subs.tap()
        waitLabel(app, "remote-subtitles", contains: "Español", "otro los pone, en tu idioma")
        // Las teclas de la fila, del mismo alto (un nombre largo no la parte en dos renglones).
        let heights = ["remote-audio", "remote-subtitles", "remote-version"].map { app.buttons[$0].frame.height }
        XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 1, "la fila mide parejo: \(heights)")
    }

    func testHoldingLanguageOpensHowYouWatchAndItsChoicesWork() {
        let app = launch(["-demo-tv-horror", "-demo-open", "remote-full"])
        let audio = app.buttons["remote-audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 20))
        audio.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["Cómo lo ves"].waitForExistence(timeout: 5), "mantener abre la hoja")
        XCTAssertTrue(app.buttons["watch-audio-2"].exists || app.otherElements["watch-audio-2"].exists, "con los idiomas")
        let latino = app.descendants(matching: .any)["watch-audio-2"]
        latino.tap()
        let subsOff = app.descendants(matching: .any)["watch-subs-no"]
        XCTAssertTrue(subsOff.waitForExistence(timeout: 5), "y «Sin subtítulos»")
        subsOff.tap()
        // Las versiones llegan de la TV: la primera es la que pondría ella.
        let first = app.descendants(matching: .any)["watch-version-0"]
        for _ in 0..<4 where !(first.exists && first.isHittable) { app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 8), "las versiones de la TV")
        XCTAssertTrue(app.staticTexts["Ultra HD 4K"].exists, "con su calidad en palabras")
        let second = app.descendants(matching: .any)["watch-version-1"]
        second.tap()
        XCTAssertTrue(audio.waitForExistence(timeout: 6), "elegir una versión cierra la hoja")
        // Lo elegido en la hoja ya se ve en las teclas, y la TV puso la otra versión (la demo lo dice en el audio).
        waitLabel(app, "remote-subtitles", contains: "Sin subtítulos", "lo de la hoja se ve en la tecla")
        audio.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["Cómo lo ves"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["watch-audio-1"].tap()
        XCTAssertTrue(app.staticTexts["5.1 · 1080p"].waitForExistence(timeout: 6), "la TV quedó en la versión 1080p")
    }

    func testVersionKeyOpensTheSheet() {
        let app = launch(["-demo-tv-horror", "-demo-open", "remote-full"])
        let version = app.buttons["remote-version"]
        XCTAssertTrue(version.waitForExistence(timeout: 20))
        version.tap()
        XCTAssertTrue(app.staticTexts["Cómo lo ves"].waitForExistence(timeout: 5), "Versión abre la hoja, no el panel de la TV")
        XCTAssertFalse(app.descendants(matching: .any)["Pad de la TV"].isHittable, "sin el pad")
    }

    func testTheRemoteShowsWhatIsFocusedOnTheTV() {
        let app = launch(["-demo-tv-focus", "-demo-open", "remote-idle"])
        let card = app.descendants(matching: .any)["remote-focus"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "la tarjeta de lo enfocado")
        XCTAssertTrue(app.staticTexts["Dune: Parte dos"].exists, "con su nombre")
        XCTAssertTrue(app.staticTexts["2024 · Ciencia ficción"].exists, "y de qué es")
        let select = app.buttons["remote-focus-select"]
        XCTAssertTrue(select.label.contains("Ver"), "su botón dice lo que dice la TV: \(select.label)")
        select.tap()   // la demo acepta la tecla
        XCTAssertFalse(app.buttons["remote-focus-alt"].exists, "el atajo no se repite en la tarjeta (ya está abajo)")
        XCTAssertTrue(app.descendants(matching: .any)["Pad de la TV"].exists, "el pad sigue abajo")
        // Arriba del pad, sin taparlo.
        XCTAssertLessThan(card.frame.maxY, app.descendants(matching: .any)["Pad de la TV"].frame.minY + 1)
    }

    func testAGameIsFocusedToo() {
        let app = launch(["-demo-tv-focus", "game", "-demo-open", "remote-idle"])
        XCTAssertTrue(app.staticTexts["Elden Ring"].waitForExistence(timeout: 20), "un juego también")
        XCTAssertTrue(app.buttons["remote-focus-select"].label.contains("Jugar"))
    }

    func testWithNothingFocusedThereIsNoCard() {
        let app = launch(["-demo-open", "remote-idle"])
        XCTAssertTrue(app.descendants(matching: .any)["Pad de la TV"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["remote-focus"].exists, "sin nada enfocado, sin tarjeta")
    }
}
