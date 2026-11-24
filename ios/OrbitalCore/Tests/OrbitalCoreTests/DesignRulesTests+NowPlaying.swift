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

/// La misma regla para todo póster y portada (23 nov 2026, Fernando: «encontramos cosas raras» sin imagen en Buscar y en
/// Inicio «algunas no cargan»): una imagen que falta busca otra antes de enseñar el nombre sobre color, y mientras se decide
/// cuál va, el marco espera quieto. Regla en `docs/ios-interfaz.md` § «Una imagen que falta busca otra».
extension DesignRulesTests {
    /// El póster prueba TMDB, metahub e IMDb, en ese orden, antes de rendirse.
    func testPosterTriesEverySourceBeforeTheName() throws {
        let pipeline = try XCTUnwrap(try sources(["Platform"]).first { $0.name == "ImagePipeline.swift" })
        let body = pipeline.lines.drop { !$0.contains("private func posterData(") }.prefix { !$0.hasPrefix("    }") }.joined(separator: "\n")
        let order = ["posters.resolve", "data(url, urgent: urgent)", "imdb.resolve"].map { body.range(of: $0)?.lowerBound }
        XCTAssertFalse(order.contains(nil), "`posterData` debe probar TMDB (`posters.resolve`), metahub y al final IMDb (`imdb.resolve`)")
        if let a = order[0], let b = order[1], let c = order[2] { XCTAssertTrue(a < b && b < c, "el orden es TMDB, metahub, IMDb") }
        let environment = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/AppEnvironment.swift"), encoding: .utf8)
        XCTAssertTrue(environment.contains("setImdbPoster(ImdbPoster("), "la app conecta el respaldo de IMDb")
    }

    /// Una portada a sangre hecha de un fondo («.wide», «.background») lleva el póster de respaldo: si el fondo no existe, se
    /// ve el póster y no el nombre sobre color.
    func testWideArtFallsBackToThePoster() throws {
        let missing = hits(#"BleedArt\(url: [a-z.]*(wide|background),"#, in: try sources(["Screens"]), unless: "fallback:")
        XCTAssertEqual(missing, [], "Portada de un fondo sin `fallback:` (el póster)")
    }

    /// Mientras el arte a sangre decide entre su póster alto y su fondo, el marco espera quieto (`waiting:`), sin el nombre.
    func testArtWaitsQuietlyWhileDeciding() throws {
        let art = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Art.swift" })
        XCTAssertTrue(art.lines.contains { $0.contains("waiting: art == nil && url != nil") }, "`BleedArt` pasa `waiting:` a `PosterView`")
        let posters = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Posters.swift" })
        XCTAssertTrue(posters.lines.contains { $0.contains("else if !waiting { PosterStandIn(") }, "`PosterView` no pinta el nombre mientras espera")
    }

    /// Un episodio sin imagen (23 nov 2026, Fernando: «no aparece centrado, no se ve bien»): en una caja ancha el respaldo es
    /// la película centrada, sin el nombre (va al lado o abajo); el de póster vertical la subía y dejaba el número en la esquina.
    func testAWideStandInIsCentered() throws {
        let posters = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Posters.swift" })
        let text = posters.lines.joined(separator: "\n")
        let wide = try XCTUnwrap(text.range(of: "if box.size.width > box.size.height {"), "`PosterStandIn` distingue la caja ancha")
        let branch = String(text[wide.upperBound...].prefix(while: { $0 != "}" }))
        XCTAssertTrue(branch.contains("missingWideIconShare") && branch.contains("alignment: .center"), "ancha: la película centrada")
        XCTAssertFalse(branch.contains("Text(") || branch.contains(".padding(.bottom"), "ancha: sin nombre y sin subirla")
    }
}
