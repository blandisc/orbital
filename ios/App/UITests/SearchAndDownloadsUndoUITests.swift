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
        XCTAssertTrue(app.buttons.matching(identifier: "title-link").firstMatch.label.hasPrefix("The Matrix"),
                      "«Mejor resultado»: \(app.buttons.matching(identifier: "title-link").firstMatch.label)")
    }

    func testDeletingADownloadCanBeUndone() {
        launch(["-demo-tab", "3", "-demo-downloads", "-demo-library", "downloads"])
        let row = app.cells.containing(NSPredicate(format: "label BEGINSWITH 'Dune' AND NOT (label CONTAINS 'Parte')")).firstMatch
        let rowByText = app.staticTexts.matching(NSPredicate(format: "label == 'Dune'")).firstMatch
        XCTAssertTrue(rowByText.waitForExistence(timeout: 20), "Dune en Descargas")
        (row.exists ? row : rowByText).swipeLeft()
        let delete = app.buttons["Borrar"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "«Borrar» al deslizar")
        delete.tap()
        XCTAssertTrue(any("Descarga borrada").waitForExistence(timeout: 5), "el aviso «Descarga borrada»")
        // El aviso también dice «Dune»: se mira solo dentro de la lista.
        let inList = app.cells.containing(NSPredicate(format: "label == 'Dune'"))
        XCTAssertEqual(inList.count, 0, "sale de la lista al instante")
        let undo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deshacer'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "con «Deshacer»")
        undo.tap()
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label == 'Dune'")).firstMatch.waitForExistence(timeout: 5), "«Deshacer» la regresa")
    }
}
