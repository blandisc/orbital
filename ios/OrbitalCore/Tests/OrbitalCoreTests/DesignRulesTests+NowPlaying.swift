import XCTest

/// Lo que suena en la tele siempre enseña su póster (Fernando, 13 nov 2026: «no se ve en la pastilla de la película que está
/// reproduciendo en la tele el póster»): donde se pinta el arte de la TV, si no carga, va el póster de metahub
/// (`artFallback`). Regla en `docs/ios-interfaz.md` § «Lo que suena en la tele».
extension DesignRulesTests {
    func testNowPlayingArtFallsBackToThePoster() throws {
        var missing: [String] = []
        for file in try sources(["Design", "Screens"]) {
            for (i, line) in file.lines.enumerated() where line.contains("PosterView(url: now.art") && !line.contains("fallback: now.artFallback") {
                missing.append("\(file.name):\(i + 1)")
            }
        }
        XCTAssertEqual(missing, [], "El arte de lo que suena en la tele, sin `fallback: now.artFallback`")
    }
}
