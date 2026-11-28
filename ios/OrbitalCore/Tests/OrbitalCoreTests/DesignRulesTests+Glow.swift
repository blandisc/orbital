import XCTest

/// Un brillo nunca se ve como un segundo fondo. Un resplandor que flota detrás de algo usa `DSGlow`, que se desvanece antes de
/// su orilla; un `RadialGradient` suelto se cortaba en cuadro dentro de la hoja de «Decide por mí» (Fernando, 27 nov 2026:
/// «tiene como que doble fondo»). Solo quedan los que llenan toda la pantalla o se recortan en su propia forma.
extension DesignRulesTests {
    func testFloatingGlowsFadeBeforeTheirEdge() throws {
        let allowed: Set<String> = [
            "Backdrop.swift", "SimpsonsRoulette.swift",   // toda la pantalla
            "PlatformFan.swift", "LessonScenes+TV.swift", "BrandGuideWin.swift",   // dentro de su tarjeta, de un círculo o de una máscara
        ]
        var offenders: [String] = []
        for source in try sources(["Design", "Screens"]) where !allowed.contains(source.name) {
            if source.lines.contains(where: { $0.contains("RadialGradient(") }) { offenders.append(source.name) }
        }
        XCTAssertEqual(offenders, [], "un resplandor que flota es `DSGlow` (se desvanece antes de su orilla)")
        let decide = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "DecideView.swift" })
        XCTAssertTrue(decide.lines.contains { $0.contains("DSGlow(") }, "el resplandor de los tres de «Decide por mí»")
    }
}
