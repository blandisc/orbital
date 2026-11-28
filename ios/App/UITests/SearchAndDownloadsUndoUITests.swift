import XCTest

/// S1-A y D1-A (Fernando, 16 nov 2026), con toques: «matrix» da de «Mejor resultado» la película, no la serie de 1993; y
/// «Borrar» una descarga avisa con «Deshacer», que la regresa.
final class SearchAndDownloadsUndoUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func launch(_ extra: [String]) {
        app.launchArguments = ["-demo", "-demo-mute", "-demo-no-idle", "-demo-no-tv"] + extra
        app.launch()
    }

    func any(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    func testMatrixBestResultIsTheMovie() {
        launch(["-demo-tab", "2"])
        let field = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields["Películas y series"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "el campo de Buscar")
        field.tap()
        field.typeText("matrix")
        let first = app.buttons.matching(identifier: "title-link").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 25), "resultados de «matrix»")
        sleep(3)   // la ficha de las dos exactas (tope de 1.5 s) y se reacomoda
        XCTAssertTrue(app.buttons.matching(identifier: "title-link").firstMatch.label.range(of: #"^(The )?Matrix\b"#, options: .regularExpression) != nil,   // con títulos en español, «Matrix»
                     
                      "«Mejor resultado»: \(app.buttons.matching(identifier: "title-link").firstMatch.label)")
    }

    func testDeletingADownloadCanBeUndone() {
        launch(["-demo-tab", "3", "-demo-downloads", "-demo-library", "downloads"])
        let row = app.cells.containing(NSPredicate(format: "(label BEGINSWITH 'Dune' OR label BEGINSWITH 'Duna') AND NOT (label CONTAINS 'Parte')")).firstMatch
        let rowByText = app.staticTexts.matching(NSPredicate(format: "label == 'Dune' OR label == 'Duna'")).firstMatch
        XCTAssertTrue(rowByText.waitForExistence(timeout: 20), "Duna (Dune) en Descargas: el nombre sale en español")
        (row.exists ? row : rowByText).swipeLeft()
        let delete = app.buttons["Borrar"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "«Borrar» al deslizar")
        delete.tap()
        XCTAssertTrue(any("Descarga borrada").waitForExistence(timeout: 5), "el aviso «Descarga borrada»")
        // El aviso también dice «Dune»: se mira solo dentro de la lista.
        let inList = app.cells.containing(NSPredicate(format: "label == 'Dune' OR label == 'Duna'"))
        XCTAssertEqual(inList.count, 0, "sale de la lista al instante")
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deshacer'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "con «Deshacer»")
        undo.tap()
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label == 'Dune' OR label == 'Duna'")).firstMatch.waitForExistence(timeout: 5), "«Deshacer» la regresa")
    }

    /// Borrar el último episodio de una serie descargada te regresa a Descargas, no a una página en blanco (revisión del 27 nov 2026).
    func testDeletingTheLastEpisodeGoesBackToDownloads() {
        launch(["-demo-tab", "3", "-demo-downloads", "-demo-library", "downloads"])
        let office = app.staticTexts.matching(NSPredicate(format: "label == 'The Office' OR label == 'La Oficina'")).firstMatch
        XCTAssertTrue(office.waitForExistence(timeout: 20), "La Oficina en Descargas")
        office.tap()
        for episode in ["T2 · E5", "T2 · E6"] {
            let row = app.staticTexts[episode].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(episode) en la serie")
            row.swipeLeft()
            let delete = app.buttons["Borrar"].firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
        }
        let dune = app.staticTexts.matching(NSPredicate(format: "label == 'Dune' OR label == 'Duna'")).firstMatch
        XCTAssertTrue(dune.waitForExistence(timeout: 5), "de vuelta en Descargas, con lo demás")
    }
}
