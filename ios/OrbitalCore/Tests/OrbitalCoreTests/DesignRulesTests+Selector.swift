import XCTest

/// Un solo selector en toda la app (SL1, Fernando, 13 nov 2026: «vamos con el selector unificado»; KT1: «que muestre que estás
/// filtrando películas o series, con letras»). Para elegir qué ves, `DSSelector` (o su tamaño compacto `DSKindFilter` para el
/// tipo); las pestañas subrayadas (`DSTextTabs`) solo para moverte entre partes de una pantalla. Antes eran cinco caras.
/// Regla en `docs/ios-interfaz.md` § «Un solo selector».
extension DesignRulesTests {
    func testOneSelectorEverywhere() throws {
        let files = try sources(["Design", "Screens"])
        check(hits(#"\bDSCountTabs\b|\bDSSegmented\b|\.pickerStyle\(\.segmented\)"#, in: files),
              "Selector de antes: usa `DSSelector` (o `DSKindFilter` para el tipo)")
        // Las pestañas subrayadas solo donde mueven entre partes: la Biblioteca, la ficha y el reproductor.
        let navigation: Set<String> = ["DownloadsView.swift", "TitleView.swift", "PlayerScreen+DockData.swift"]
        var stray: [String] = []
        for file in files where !file.name.hasPrefix("Filters") && !navigation.contains(file.name) {
            for (i, line) in file.lines.enumerated() where line.contains("DSTextTabs(") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                stray.append("\(file.name):\(i + 1)")
            }
        }
        XCTAssertEqual(stray, [], "Pestañas subrayadas para elegir qué ves: eso es `DSSelector` (las pestañas son para moverte entre partes)")
        // KT1: la pastilla de tipo dice el nombre de lo elegido donde vive abierta.
        let filters = try XCTUnwrap(files.first { $0.name == "Filters.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(filters.contains("private var chosenName: some View") && filters.contains("Text($0.1).hidden()"),
                      "La pastilla de tipo dice «Películas» o «Series» a su izquierda, con su lugar apartado: los íconos no se mueven (KT1)")
    }

    /// El renglón de controles de una lista decide con el ancho que le dan (con «Series» en la pastilla, un `HStack` a mano se
    /// salía de la pantalla y arrastraba los pósters, 13 nov 2026). Regla en `docs/ios-interfaz.md`.
    func testListControlsUseTheMeasuredRow() throws {
        let files = try sources(["Screens"])
        for name in ["SavedPileContent.swift", "SavedListScreen.swift"] {
            let text = try XCTUnwrap(files.first { $0.name == name }).lines.joined(separator: "\n")
            XCTAssertTrue(text.contains("ListControlsRow(") || text.contains("ListControlsRow {"), "\(name): el renglón de controles va en `ListControlsRow`")
            // Las pestañas de Guardado apartan el mismo lugar a la derecha: la pastilla no brinca al cambiar de pestaña.
            XCTAssertTrue(text.contains("ListControlsRow(reservedIcons: header == nil ? 0 : 3)"), "\(name): en Guardado, el renglón aparta sus íconos")
            XCTAssertTrue(text.contains("dense: true"), "\(name): la pastilla del renglón, compacta")
        }
    }

    /// Cambiar de pestaña en Guardado no regresa Todo · Películas · Series a «Todo» (Fernando, 13 nov 2026): el tipo vive en
    /// `LibrarySavedView` y cada pestaña con pastilla recibe el mismo.
    func testSavedTabsShareTheKindFilter() throws {
        let files = try sources(["Screens"])
        let saved = try XCTUnwrap(files.first { $0.name == "LibrarySavedView.swift" }).lines.joined(separator: "\n")
        let tabs = saved.components(separatedBy: "SavedListContent(").count - 1 + saved.components(separatedBy: "SavedPileContent(").count - 1
        XCTAssertGreaterThan(tabs, 0)
        XCTAssertEqual(saved.components(separatedBy: "sharedKind: $kind").count - 1, tabs, "cada pestaña de Guardado recibe el mismo tipo")
        for name in ["SavedPileContent.swift", "SavedListScreen.swift"] {
            let text = try XCTUnwrap(files.first { $0.name == name }).lines.joined(separator: "\n")
            XCTAssertFalse(text.contains("@State private var kind"), "\(name): el tipo de Guardado no vive en cada pestaña")
        }
    }
}
