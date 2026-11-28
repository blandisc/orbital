import XCTest

/// El Inicio del Duo cerrado (Fernando, 27 nov 2026). Que se toque de verdad lo prueba `DuoHomeBarUITests`; esto cuida que el
/// código siga diciendo lo mismo.
extension DesignRulesTests {
    private func text(_ name: String, in files: [Source]) throws -> String {
        try XCTUnwrap(files.first { $0.name == name }, name).lines.joined(separator: "\n")
    }

    /// LD2-B: en el Duo el encabezado de Inicio va en el renglón de la hora, con el logo completo («orbital») y el control y tu
    /// foto a la izquierda (a la derecha iOS los escondía en «…»). Solo en el iPhone ancho y bajo: el 17 Pro no cambia.
    func testDuoHomeSharesTheClockRow() throws {
        let files = try sources(["Screens"])
        let bar = try text("HomeView+BarHeader.swift", in: files)
        XCTAssertTrue(bar.contains("static var headerInBar: Bool { WindowMetrics.shortPhone }"), "solo en el iPhone ancho y bajo (el Duo cerrado)")
        XCTAssertTrue(bar.contains("AppMark(small: true)"), "con el logo completo, no solo el ícono")
        XCTAssertFalse(bar.contains(".topBarTrailing"), "nada del lado de la hora: iOS lo mete en «…»")
        XCTAssertTrue(bar.contains("if Self.headerInBar {\n            DSKindFilter(kind: kindBinding, menu: true"), "HB1-B: el filtro de Inicio, en la portada del Duo")
    }

    /// El carrusel de Inicio en un marco ancho (el Duo) recorta al centro, sin correrse hacia las caras: corrido se veía chueco.
    func testWideHomeCarouselIsCentered() throws {
        let slide = try text("HomeHeroSlide.swift", in: try sources(["Screens"]))
        XCTAssertTrue(slide.contains(".environment(\\.artCentered, Double(aspect) >= ArtFit.tallBelow)"), "el carrusel ancho va al centro")
        let posters = try text("Posters.swift", in: try sources(["Design"]))
        XCTAssertTrue(posters.contains("!centered && ArtFit.needsFocus"), "y el recorte respeta artCentered")
    }

    /// La ficha en el Duo cerrado: el arte cede (más bajito) hasta que «Guardar · Descargar · Vista · Tráiler» queden a la
    /// vista sobre las pestañas y sobre «¿Qué tal…?». Antes la pastilla los tapaba y tocar «Vista» no hacía nada.
    func testTitleActionsClearTheTabBarOnTheDuo() throws {
        let title = try text("TitleView.swift", in: try sources(["Screens"]))
        XCTAssertTrue(title.contains("WindowMetrics.shortPhone ? DS.TitleAction.heroAspectMaxShortPhone"), "en el Duo el arte puede ser más bajito")
        XCTAssertTrue(title.contains("- env.ui.ratingReminderHeight"), "y le deja su lugar a «¿Qué tal…?»")
    }
}
