import XCTest

/// Nada flota encima de una barra de abajo. «¿Qué tal…?» tapaba «Quitar» al elegir varios en el Duo (27 nov 2026): toda barra
/// de abajo de una pantalla lleva `holdsBottomBar()` y, mientras se ve, la pastilla se aparta. Las hojas ya van encima.
extension DesignRulesTests {
    func testBottomBarsKeepTheReminderAway() throws {
        let sheets: Set<String> = ["Guide.swift", "AdvancedFilterSheet.swift", "DecideFilterPages.swift", "LessonView.swift"]
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) where !sheets.contains(source.name) {
            let text = source.lines.joined(separator: "\n")
            guard text.contains("safeAreaBar(edge: .bottom)") else { continue }
            if !text.contains(".holdsBottomBar()") && !text.contains("SavedSelectionBar(") { offenders.append(source.name) }
        }
        XCTAssertEqual(offenders, [], "una barra de abajo lleva `holdsBottomBar()`")
        let bar = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "SavedSelectionBar.swift" })
        XCTAssertTrue(bar.lines.contains { $0.contains(".holdsBottomBar()") }, "la barra de elegir varios")
    }
}
