import XCTest

/// OI-4 (auditoría de diseño del 20 nov 2026): una sola negrita por pantalla. La negrita es del título más grande (`display`) y
/// de las placas y cifras (`badge`, `stat`), y vive en `DS.TextRecipe` (D2-B). Fuera de receta había 12: el título de las
/// tarjetas de arte (escondido tras un ternario), Letterboxd, la pestaña elegida, el nombre del sitio en la guía, las lecciones…
/// Todo eso va en seminegrita. Los íconos (`Image`) no cuentan: su peso es el trazo, no letra.
extension DesignRulesTests {
    func testBoldLivesOnlyInRecipes() throws {
        let files = try sources()
        let heavy = #"\.bold\(\)|(weight|fontWeight)\([^)]*\.(bold|heavy|black)\b"#
        // El iPod, el reproductor y el arte tienen sus reglas (un aparato, letra sobre el video); los tokens son las recetas.
        let skip = { (f: Source) in self.isTokens(f) || self.isPlayer(f) || self.isArt(f) || f.name.hasPrefix("IPod") }
        let problems = hits(heavy, in: files, skip: skip, unless: #"^\s*Image\(|\{\s*Image\(|\.dsFeedback\("#)
        check(problems, "Negrita fuera de receta (usa .semibold, o la receta display, badge o stat)")
    }

    /// En los widgets la cifra o el título grande pueden ir en negrita (es lo más grande del widget); un rótulo chico, nunca.
    func testWidgetLabelsAreNotBold() throws {
        let widgets = repo.appendingPathComponent("ios/App/Widgets")
        let found = try XCTUnwrap(FileManager.default.enumerator(at: widgets, includingPropertiesForKeys: nil)).allObjects
        var files: [Source] = []
        for case let file as URL in found where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            files.append(Source(path: "../Widgets/" + file.lastPathComponent, lines: text.components(separatedBy: "\n")))
        }
        XCTAssertFalse(files.isEmpty, "se leyeron los widgets")
        let problems = hits(#"DS\.font\(\.sm, weight: \.(bold|heavy|black)\)"#, in: files, unless: #"Image\("#)
        check(problems, "Rótulo chico de widget en negrita (va en .semibold)")
    }
}
