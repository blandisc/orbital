import XCTest

/// Los idiomas en un solo lugar (ID-A, Fernando, 22 nov 2026: «que tú puedas seleccionar en el elemento del menú el idioma que
/// quieres en el contenido, el idioma del app y el idioma de los metadatos»). Un renglón «Idiomas» en Ajustes y, adentro, la
/// app, los títulos y sinopsis, el audio, los subtítulos y el país. Regla en `docs/ios-interfaz.md` § «Idiomas en un solo lugar».
extension DesignRulesTests {
    func testLanguagesLiveInOnePlace() throws {
        let files = try sources(["Screens", "Design"])
        let text = files.map { $0.lines.joined(separator: "\n") }.joined(separator: "\n")
        // Ningún otro renglón suelto de idioma en Ajustes.
        XCTAssertFalse(text.contains("SettingsRow(title: \"Idioma de la app\""), "El idioma de la app vive en la página «Idiomas»")
        XCTAssertFalse(text.contains("case .appLanguage"), "Sin página aparte para el idioma de la app")
        let page = try XCTUnwrap(files.first { $0.name == "SettingsView+Idiomas.swift" }).lines.joined(separator: "\n")
        for id in ["languages-app", "languages-titles", "YourLanguagesView(settings: settings, embedded: true)", "settings-subtitles", "languages-region"] {
            XCTAssertTrue(page.contains(id), "La página «Idiomas» lleva \(id)")
        }
        // El país ya no vive en Avanzado.
        let settings = try XCTUnwrap(files.first { $0.name == "SettingsView.swift" }).lines.joined(separator: "\n")
        XCTAssertFalse(settings.contains("Picker(\"País"), "El país va en «Idiomas»")
    }

    /// Un ajuste de pocas opciones se lee en un renglón: su nombre (y qué cambia) a la izquierda y el selector a la derecha
    /// (`SettingsChoiceRow`). Solo en su tarjeta, con el nombre arriba y la explicación abajo, en la Mac quedaba medio renglón
    /// vacío y la explicación se pegaba al grupo de abajo (Fernando, 23 nov 2026: «una pulida con ojo experto»).
    func testSettingsChoicesSitInARowWithTheirName() throws {
        let pages = try sources(["Screens"]).filter { $0.name.hasPrefix("SettingsView") }
        let lone = pages.flatMap { file in file.lines.filter { $0.contains("DSSelector(") }.map { "\(file.name): \($0.trimmingCharacters(in: .whitespaces))" } }
        XCTAssertEqual(lone, [], "En Ajustes un selector va en SettingsChoiceRow, con su nombre a la izquierda")
    }
}
