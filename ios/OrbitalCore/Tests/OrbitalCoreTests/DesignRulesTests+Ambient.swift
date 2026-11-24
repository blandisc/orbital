import XCTest

/// En la Mac nada se mueve solo (Fernando, 22 nov 2026: «se siente súper lenta, ni siquiera la puedo mover… está inusable»).
/// El cielo, el muro de Explorar y los canales que se deslizan ponían al compositor de la Mac a 60–95 % con Orbital en reposo
/// (su monitor va a 165 Hz). Regla en `docs/ios-interfaz.md` § «En la Mac nada se mueve solo».
extension DesignRulesTests {
    /// Todo archivo con un adorno que se mueve sin que lo toques (un reloj de cuadros, una animación sin fin, el muro que baja)
    /// pregunta por `ThisDevice.ambientMotion`. Fuera: las lecciones y la bienvenida (se ven una vez), el reproductor, la
    /// ruleta y la luna de «actualizar» (corren solo mientras haces algo).
    func testAmbientMotionStaysStillOnTheMac() throws {
        let patterns = [#"TimelineView\(\.animation"#, #"CoreDrift\("#, #"SkySchedule\("#, #"repeatCount = \.infinity"#, #"\.repeatForever\("#, #"DS\.Timing\.mosaicDrift"#]
        let allowed = ["Lessons/", "Onboarding/", "Player", "Roulette", "RefreshOrbit", "Tokens+Lessons", "Brand", "MosaicBench"]
        var missing: [String] = []
        for file in try sources() where !allowed.contains(where: { file.path.contains($0) }) {
            let moves = patterns.contains { p in !hits(p, in: [file]).isEmpty }
            if moves, !file.lines.contains(where: { $0.contains("ThisDevice.ambientMotion") }) { missing.append(file.path) }
        }
        XCTAssertEqual(missing, [], "Se mueven solos sin preguntar por ThisDevice.ambientMotion (en la Mac, quietos)")
    }

    /// Cargar se ve igual en toda la app (Fernando, 23 nov 2026: en Descargas salía la ruedita del sistema y en Inicio la luna
    /// de Orbital): tirar para actualizar es siempre `orbitalRefreshable` (o `orbitalRefreshableList` en una lista), nunca
    /// `.refreshable` del sistema.
    func testPullToRefreshIsAlwaysTheOrbit() throws {
        let used = try sources().filter { !$0.path.contains("RefreshOrbit") }.flatMap { f in f.lines.filter { $0.contains(".refreshable {") || $0.contains(".refreshable{") }.map { "\(f.path): \($0)" } }
        XCTAssertEqual(used, [], "Tirar para actualizar con la ruedita del sistema: usa orbitalRefreshable / orbitalRefreshableList")
    }

    /// Las pestañas llevan el mismo encabezado (HB1, Fernando, 23 nov 2026: «Explorar es diferente a Biblioteca y Buscar…
    /// que los tres sean iguales»): el título del sistema, grande arriba y chico al centro al deslizar, nunca uno hecho a mano.
    func testTabsShareTheSystemHeader() throws {
        let files = try sources()
        XCTAssertTrue(files.allSatisfy { !$0.lines.contains { $0.contains("struct ScreenMark") } }, "Sin título a mano en las pestañas")
        let explore = try XCTUnwrap(files.first { $0.path.hasSuffix("ParaTiView.swift") }).lines.joined(separator: "\n")
        XCTAssertTrue(explore.contains(".dsNavigationTitle(!TopRow.tabsInLogoRow && m.mode == .lists ? \"Explorar\""), "Explorar con su título del sistema")
        XCTAssertTrue(explore.contains("? .inlineLarge : .inline)"), "Explorar grande arriba y chico al deslizar, como Biblioteca")
    }
}

extension DesignRulesTests {
    /// TN1 (25 nov 2026): el título de arriba de una pantalla sigue al idioma de la app aunque cambie con la pantalla abierta.
    /// Un título fijo va por `.dsNavigationTitle("…")`; `navigationTitle("…")` o `navigationTitle(Text("…"))` se quedaban en
    /// el idioma de antes («Idiomas» con la app en inglés).
    func testNavigationTitlesFollowTheLanguage() throws {
        let found = hits(#"\.navigationTitle\((Text\()?"[^"\\]*"\)?\)"#, in: try sources(["Design", "Screens", "App"]))
        XCTAssertEqual(found, [], "usa .dsNavigationTitle(\"…\") para que el título cambie con el idioma")
    }
}

extension DesignRulesTests {
    /// P4 (25 nov 2026): un póster en un marco alto va centrado; correrlo a la derecha es solo del marco ancho (el destacado).
    func testTallPostersStayCentered() throws {
        let posters = try XCTUnwrap(try sources(["Design"]).first { $0.path.hasSuffix("Posters.swift") }).lines.joined(separator: "\n")
        XCTAssertTrue(posters.contains("bleed && box.size.width > box.size.height"), "a la derecha solo en un marco ancho")
    }

    /// DO1 (25 nov 2026): tocar una película en una hoja abre su ficha cuando la hoja ya se cerró, no a la vez (se perdía).
    func testSheetsOpenTitlesAfterClosing() throws {
        let found = hits(#"dismiss\(\);\s*(env\.)?open\("#, in: try sources(["Design", "Screens"]))
        XCTAssertEqual(found, [], "cierra la hoja y abre después (como `go` en DecideView)")
    }
}
