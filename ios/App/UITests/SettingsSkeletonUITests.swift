import XCTest

/// PA1-A y PA6-A (23 nov 2026) en el iPhone: Ajustes con el esqueleto de la TV (Idiomas · Reproducción · Avisos · Cuentas ·
/// Complementos y abajo «En este aparato»), OneDrive y la clave de TMDB dentro de Cuentas, y Diagnóstico de ida y vuelta.
///   xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OrbitalUITests/SettingsSkeletonUITests
final class SettingsSkeletonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "solo en iPhone")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-open", "settings", "-demo-rd", "premium", "-demo-trakt", "-demo-no-tv"]
        app.launch()
    }

    private func row(_ title: String) -> XCUIElement { app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch }

    private func back() { app.navigationBars.buttons.firstMatch.tap() }

    func testTheRootFollowsTheTVAndDiagnosticsGoesAndComesBack() {
        let languages = app.buttons["settings-languages"]
        XCTAssertTrue(languages.waitForExistence(timeout: 30), "Ajustes abre")
        // El orden de arriba abajo, medido: Idiomas, Reproducción, Avisos, Cuentas, Complementos; luego Apariencia y Descargas.
        var lastY: CGFloat = -1
        for title in ["Idiomas", "Reproducción", "Avisos", "Cuentas", "Complementos", "Apariencia", "Descargas"] {
            let r = row(title)
            for _ in 0..<4 where !(r.exists && r.isHittable) { app.swipeUp() }
            XCTAssertTrue(r.exists, "falta «\(title)»")
            if title == "Apariencia" { lastY = -1 }   // al deslizar, la medida vuelve a empezar
            XCTAssertGreaterThan(r.frame.minY, lastY, "«\(title)» fuera de orden")
            lastY = r.frame.minY
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "En este aparato")).firstMatch.exists, "el encabezado «En este aparato»")
        XCTAssertFalse(row("Avanzado").exists, "sin «Avanzado»")
        XCTAssertFalse(row("OneDrive").exists, "OneDrive ya no va suelto")

        // Diagnóstico: de ida (sus grupos) y de vuelta.
        let diagnostics = app.buttons["settings-diagnostics"]
        for _ in 0..<4 where !(diagnostics.exists && diagnostics.isHittable) { app.swipeUp() }
        diagnostics.tap()
        XCTAssertTrue(app.buttons["diagnostics-trakt"].waitForExistence(timeout: 10), "Diagnóstico › Trakt")
        XCTAssertTrue(app.buttons["diagnostics-cloud"].exists, "Diagnóstico › Tu nube")
        app.swipeUp()
        XCTAssertTrue(app.buttons["diagnostics-addons"].waitForExistence(timeout: 5), "Diagnóstico › Complementos")
        XCTAssertTrue(app.buttons["diagnostics-speed"].exists, "Diagnóstico › Velocidad")
        XCTAssertFalse(app.buttons["diagnostics-tv"].exists, "sin tu Orbital prendida, sin el grupo de la TV")
        app.swipeDown()
        app.buttons["diagnostics-trakt"].tap()
        XCTAssertTrue(app.navigationBars["Trakt"].waitForExistence(timeout: 5), "Trakt abre desde Diagnóstico")
        back()
        app.buttons["diagnostics-cloud"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["debrid-account"].waitForExistence(timeout: 10), "Tu nube abre desde Diagnóstico")
        back()
        XCTAssertTrue(app.buttons["diagnostics-trakt"].waitForExistence(timeout: 5))
        back()
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5), "regresa a Ajustes")
    }

    func testOneDriveAndTheTMDBKeyLiveInAccounts() {
        let accounts = row("Cuentas")
        XCTAssertTrue(accounts.waitForExistence(timeout: 30))
        accounts.tap()
        let oneDrive = app.buttons["settings-onedrive"]
        for _ in 0..<4 where !(oneDrive.exists && oneDrive.isHittable) { app.swipeUp() }
        XCTAssertTrue(oneDrive.exists, "OneDrive en Cuentas")
        oneDrive.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        back()
        let key = app.secureTextFields["settings-tmdb-key"]
        for _ in 0..<4 where !(key.exists && key.isHittable) { app.swipeUp() }
        XCTAssertTrue(key.exists, "la clave de TMDB en Cuentas")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Claves de Explorar")).firstMatch.exists, "su encabezado")
    }
}
