import XCTest

/// Si tu idioma existe, la app te lo dice aunque no arranque al instante; y si un complemento no contestó, también (Fernando,
/// 12 nov 2026, Los Simpson T11E2: «me salen puros episodios en inglés… Me salieron todas de Comet»). Regla en
/// `docs/ios-interfaz.md` § «Tu idioma, aunque haya que pedirlo». Lo que hace la lista lo cuidan `LatinoNubeModelTests` y
/// `LatinoNubeFinderTests`; esta prueba cuida que «Versión» lo enseñe con sus piezas del catálogo.
extension DesignRulesTests {
    func testVersionSaysYourLanguageExistsAndWhoDidNotAnswer() throws {
        let files = try sources(["Design", "Screens"])
        let sheet = try XCTUnwrap(files.first { $0.name == "SourcesSheet.swift" }).lines.joined(separator: "\n")
        // 1 · «Hay latino, pero hay que pedirlo a la nube»: lo arma la lista (`yoursToRequest`) y lo pinta una sola pieza.
        XCTAssertNotNil(sheet.range(of: #"model\.yoursToRequest[\s\S]{0,300}VersionYoursAside\("#, options: .regularExpression),
                        "«Versión» enseña `VersionYoursAside` cuando la lista dice que tu idioma hay que pedirlo (`yoursToRequest`)")
        check(hits(#"struct VersionYoursAside"#, in: files) { $0.name == "VersionRequests.swift" },
              "`VersionYoursAside` es pieza del catálogo (Design/VersionRequests.swift)")
        check(hits(#"pero hay que pedirlo a la nube"#, in: files) { $0.name == "VersionRequests.swift" },
              "«Hay …, pero hay que pedirlo a la nube» se dice en un solo lugar")
        // 2 · Un complemento que no contestó se nombra, siempre con «Reintentar».
        XCTAssertNotNil(sheet.range(of: #"AddonQuietLine\(names: model\.quiet\)\s*\{[^}]*retryQuiet"#, options: .regularExpression),
                        "«No contestó a tiempo: …» en «Versión» lleva «Reintentar» (`model.retryQuiet`)")
        let quietLines = hits(#"AddonQuietLine\("#, in: files) { $0.name == "AddonPieces.swift" }
        check(quietLines.filter { !$0.contains("retry") }, "Cada «No contestó a tiempo» ofrece «Reintentar»")
    }

    /// 13 nov 2026 (la ruleta de Los Simpson, el widget y el Centro de control abren el reproductor directo): «Versión» del
    /// reproductor dice lo mismo que la de la ficha, con la misma pieza, y el aviso «No está en … al instante» lleva a ella.
    func testThePlayerSaysYourLanguageMustBeRequestedToo() throws {
        let files = try sources(["Design", "Screens"])
        let panel = try XCTUnwrap(files.first { $0.name == "PlayerScreen+Panel.swift" }).lines.joined(separator: "\n")
        XCTAssertNotNil(panel.range(of: #"model\.yoursToRequest[\s\S]{0,300}VersionYoursAside\("#, options: .regularExpression),
                        "«Versión» del reproductor enseña `VersionYoursAside` cuando el modelo dice que tu idioma hay que pedirlo")
        let notices = try XCTUnwrap(files.first { $0.name == "PlayerScreen+RealDebrid.swift" }).lines.joined(separator: "\n")
        XCTAssertNotNil(notices.range(of: #"\.yoursOnlyByRequest[\s\S]{0,400}opensVersion: true"#, options: .regularExpression),
                        "«No está en … al instante» lleva a «Versión» (la acción que ya existe), no es un texto sin salida")
        let gestures = try XCTUnwrap(files.first { $0.name == "PlayerScreen+Gestos.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(gestures.contains("notice.opensVersion ? { openDock(version: true) }"), "el botón del aviso abre «Versión»")
    }
}
