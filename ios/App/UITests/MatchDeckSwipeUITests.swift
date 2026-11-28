import XCTest

/// El mazo («Una por una», dentro de «Decide por mí») se desliza a los dos lados (Fernando, 31 oct 2026: «lo intenté dar a la derecha y no funciona»).
final class MatchDeckSwipeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testElMazoGuardaAlDeslizarALaDerecha() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because", "-demo-tab", "1",
                               "-demo-mode", "lists", "-demo-appearance", "dark", "-demo-no-idle", "-demo-open", "match"]
        app.launch()
        let deck = app.descendants(matching: .any).matching(identifier: "match-deck").firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 25))
        sleep(4)
        let shot = { (n: String) in let a = XCTAttachment(screenshot: app.screenshot()); a.name = n; a.lifetime = .keepAlways; self.add(a) }
        shot("antes")
        let count = app.descendants(matching: .any).matching(identifier: "match-saved-count").firstMatch
        let before = count.exists ? count.label : ""
        // Desde la carta misma: en una pantalla baja (el Duo cerrado) la carta es angosta y queda al centro, y un arrastre que
        // empieza a un lado de ella no la mueve.
        let info = app.descendants(matching: .any)["match-info"]
        let cardY = info.exists ? (info.frame.minY - 60) / app.frame.height : 0.45
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: cardY))
        mid.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: cardY + 0.02)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2)
        shot("derecha")
        let after = count.exists ? count.label : ""
        XCTAssertNotEqual(before, after, "a la derecha guarda (antes «\(before)», después «\(after)»)")
    }
}
