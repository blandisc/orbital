import XCTest

/// Los botones de los avisos («Ver», «Reintentar», «Ver ahora») no se pierden: se registran todos juntos, en un solo lugar
/// (`NotificationButtons.register`). Cada aviso registraba los suyos leyendo los de los demás y al arrancar el último borraba
/// a los otros (28 nov 2026). Regla en `docs/ios-interfaz.md` § «Los botones de los avisos van juntos».
extension DesignRulesTests {
    func testNoticeButtonsAreRegisteredTogether() throws {
        var places: [String] = []
        for source in try sources(["App", "Platform", "Screens", "Design", "Support"]) {
            for (i, line) in source.lines.enumerated() where line.contains("setNotificationCategories(") { places.append("\(source.name):\(i + 1)") }
        }
        XCTAssertEqual(places.count, 1, "un solo setNotificationCategories, el de NotificationButtons.register: \(places)")
    }
}
