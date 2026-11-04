import XCTest

/// La paridad TV ↔ iPhone del 4 nov 2026 (códigos PT, Fernando: «de acuerdo a tu recomendación»), como reglas del sistema de
/// diseño. Detalle en docs/sistema-de-diseno.md › «Paridad TV ↔ iPhone (PT, 4 nov 2026)».
extension DesignRulesTests {
    /// PT8: un tamaño se escribe con `ByteSize` («1,2 GB» en español, «1.2 GB» en inglés), nunca a mano ni con
    /// `ByteCountFormatter` (que sigue el idioma del teléfono y no el de la app).
    func testSizesAreWrittenWithByteSize() throws {
        let files = try sources(["Design", "Screens", "Platform", "App"])
        var problems = hits(#"ByteCountFormatter"#, in: files).map { $0 + " (usa ByteSize.text)" }
        problems += hits(#"%\.\d?f [GMT]B(?!/s)"#, in: files).map { $0 + " (usa ByteSize.text)" }
        check(problems, "Tamaño escrito a mano")
    }

    /// PT5: todo lo de Real-Debrid lleva la nube con flecha (`DS.Symbol.cloud`); la flecha sola es solo «Descargar» a este
    /// aparato. Nadie escribe el nombre del símbolo de la nube: sale del catálogo.
    func testRealDebridIsTheCloudArrow() throws {
        let files = try sources()
        var problems = hits(#""icloud\.and\.arrow\.down(\.fill)?""#, in: files).map { $0 + " (usa DS.Symbol.cloud)" }
        problems += hits(#"(Pedir a la nube|Por pedir|Bajando en la nube|La nube lo baja|Lo que no tiene, lo baja)[^\n]*arrow\.down\.circle"#, in: files)
            .map { $0 + " (lo de la nube lleva DS.Symbol.cloud)" }
        check(problems, "Real-Debrid con la flecha de descargar")
    }

    /// PT10: un ícono por estado y por acción de un pedido, el mismo en la TV: salen de `DebridRequestWords.Icon` (⊗ cancelar,
    /// basura quitar, reloj en cola, personas sin gente, triángulo solo para «Real-Debrid no lo dejó bajar»).
    func testRequestIconsComeFromTheCatalog() throws {
        let files = try sources().filter { ["DownloadsCloud.swift", "DebridRequests.swift", "TitleView+RealDebrid.swift", "Versions.swift"].contains($0.name) }
        XCTAssertEqual(files.count, 4, "faltan los archivos de los pedidos")
        check(hits(#""(trash|xmark\.circle|hourglass|nosign|clock|person\.2\.slash)""#, in: files).map { $0 + " (usa DebridRequestWords.Icon)" },
              "Ícono de un pedido escrito a mano")
    }

    /// PT11: «Bajando en la nube · 42 %» en todos lados, nunca «Bajando · 42 %» suelto.
    func testDownloadingInTheCloudIsNeverBare() throws {
        check(hits(#"Bajando · \\\([^)]*\) ?%|Bajando · %lld %"#, in: try sources()), "Va «Bajando en la nube · 42 %»")
        let catalog = try String(contentsOf: repo.appendingPathComponent("ios/App/Resources/Localizable.xcstrings"), encoding: .utf8)
        XCTAssertFalse(catalog.contains("\"Bajando · %lld %%\""), "el catálogo ya no lleva «Bajando · %lld %%»")
    }

    /// PT16: un complemento solo se marca «Apagado»; prendido es lo normal y no se dice.
    func testAddonsOnlySayOff() throws {
        let files = try sources().filter { ["AddonPieces.swift", "AddonsSettings.swift"].contains($0.name) }
        check(hits(#"Text\("Prendido"\)"#, in: files), "En la lista de complementos solo se marca «Apagado»")
    }
}
