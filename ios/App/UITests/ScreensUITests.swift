import XCTest

/// Lo que el usuario vio fallar en su iPhone, con la app de verdad en el simulador (modo demo).
final class ScreensUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Para ti › Listas con tu Orbital: el Top 10 de Netflix y las tendencias de Disney+ llevan la cifra grande.
    /// «Tus plataformas»: cada una en su tarjeta (Netflix y Disney+); al tocar Netflix, sus rankings con la cifra grande.
    func testPlatformsOpenTheirRankingsWithTheBigNumbers() {
        app.launchArguments = ["-demo", "-demo-console", "-demo-tab", "1", "-demo-mode", "lists", "-demo-no-idle"]
        app.launch()
        let netflix = app.buttons["platform-netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 20), "la tarjeta de Netflix")
        XCTAssertTrue(app.buttons["platform-disney"].waitForExistence(timeout: 10), "y la de Disney+")
        netflix.tap()
        let ranked = app.descendants(matching: .any).matching(identifier: "ranked-poster")
        XCTAssertTrue(ranked.firstMatch.waitForExistence(timeout: 20), "sus rankings, con la cifra grande")
    }

    /// Buscar › Explora: cada género con su imagen fija (sin esperar a la red) y al tocarlo, su lista aparece pronto.
    func testExploreGenresHaveArtAndOpenQuickly() {
        app.launchArguments = ["-demo", "-demo-tab", "2"]
        app.launch()
        let action = app.descendants(matching: .any)["art-tile-genre-action"]
        if !action.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(action.waitForExistence(timeout: 10), "el género Acción con su arte fijo")
        for genre in ["comedy", "drama", "scifi", "horror", "thriller"] {
            XCTAssertTrue(app.descendants(matching: .any)["art-tile-genre-\(genre)"].exists, "\(genre) con su arte")
        }
        action.tap()
        let start = Date()
        XCTAssertTrue(app.buttons["title-link"].firstMatch.waitForExistence(timeout: 15), "la lista del género aparece")
        print("GENRE-OPEN \(Date().timeIntervalSince(start)) s")
    }
}
