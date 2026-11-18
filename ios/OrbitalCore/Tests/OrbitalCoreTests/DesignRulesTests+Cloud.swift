import XCTest

/// DN1 · tu nube (Fernando, 18 nov 2026: Real-Debrid, TorBox o AllDebrid, «y también modificar el onboarding, las pantallas
/// de ajustes, todo»). Regla en `docs/ios-interfaz.md` § «Tu nube: nunca Real-Debrid a secas».
extension DesignRulesTests {
    /// Ningún texto de la app dice «Real-Debrid» a secas: dice tu nube (`service.name`, `Text(_:cloud:locale:)`,
    /// `DebridService.spoken`). Se vale cuando el texto nombra las tres, cuando es algo que solo Real-Debrid tiene (el código
    /// de real-debrid.com/device, canjear puntos, la prueba de velocidad) y se marca `// solo Real-Debrid`, o con la marca
    /// de la edición (`edición:`), que ya dice que esa pieza solo sale con Real-Debrid.
    func testNoScreenSaysRealDebridAlone() throws {
        let files = try sources(["Design", "Screens"])
        let found = hits("\"[^\"]*Real-Debrid[^\"]*\"", in: files,
                         unless: "TorBox|AllDebrid|real-debrid\\.com/device|solo Real-Debrid|cloud:|spoken\\(|cloudSpoken|\\.name")
        XCTAssertEqual(found, [], "di tu nube, no «Real-Debrid» (DN1):\n" + found.joined(separator: "\n"))
    }

    /// La hoja «Tu nube» de la guía es la misma página de Ajustes › Cuentas (no una copia que se quede atrás), y la guía
    /// abre esa hoja: no conecta Real-Debrid por su cuenta.
    func testTheGuideOpensTheCloudSheet() throws {
        let files = try sources(["Screens"])
        let file = try XCTUnwrap(files.first { $0.path.hasSuffix("Onboarding/OnboardingDebrid.swift") }).lines.joined(separator: "\n")
        let guide = try XCTUnwrap(file.components(separatedBy: "struct DebridCodeConnect").first)   // solo la página de la guía
        XCTAssertTrue(guide.contains("DebridCloudSheet(debrid: model)"), "la guía abre «Tu nube»")
        XCTAssertFalse(guide.contains("connectWithCode()"), "la guía no conecta Real-Debrid sin preguntar cuál nube")
        let sheet = try XCTUnwrap(files.first { $0.name == "DebridCloudViews.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(sheet.contains("DebridAccountView(debrid: debrid)"), "la hoja es la página de Ajustes › Cuentas")
    }
}
