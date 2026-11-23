import XCTest

/// Girar el iPhone con el reproductor encima no cierra la app (Fernando, 23 nov 2026: «tronó cuando cambié de orientación»;
/// la 2480 se acabó la pila rearmando la ficha de abajo). Regla en `docs/ios-interfaz.md` § «Las fechas ISO…».
extension DesignRulesTests {
    func testTitleLayoutsBuildInTheirOwnView() throws {
        let title = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "TitleView.swift" })
        let text = title.lines.joined(separator: "\n")
        XCTAssertTrue(text.contains("TitleLayoutHost { AnyView(wideLayout(model)) }"), "La ficha ancha se arma en su propia vista")
        XCTAssertTrue(text.contains("TitleLayoutHost { AnyView(oneColumnLayout(model)) }"), "La ficha de una columna se arma en su propia vista")
        XCTAssertFalse(text.contains("{ wideLayout(model) }") || text.contains("{ oneColumnLayout(model) }"),
                       "Llamar las formas directo en el cuerpo de TitleView vuelve a gastar la pila al girar")
    }
}
