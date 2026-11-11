import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// F10: los errores con tipo (red, Trakt, Real-Debrid, descargas) se traducen por su clave, sin reconocer el texto por su forma.
/// Esta prueba cuida que cada clave exista en el catálogo con su traducción, que el español sea el de siempre, y lista lo que
/// todavía se traduce por la forma (lo que falta pasar a tipos).
final class UserTextTests: XCTestCase {
    var catalog: [String: Any] {
        get throws {
            var url = URL(fileURLWithPath: #filePath)
            for _ in 0..<4 { url.deleteLastPathComponent() }
            let data = try Data(contentsOf: url.appendingPathComponent("App/Resources/Localizable.xcstrings"))
            return try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        }
    }

    func english(_ key: String, in strings: [String: Any]) -> String? {
        let entry = strings[key] as? [String: Any]
        let en = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
        return (en?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// Los textos fijos de cada familia (los de datos libres, como lo que dice el sistema, no tienen clave propia).
    var typed: [UserFacingError] {
        [TraktError.network("x"), TraktError.http(503),
         DebridError.malformedToken, DebridError.invalidToken, DebridError.network("x"), DebridError.unexpected, DebridError.notEnoughPoints,
         DownloadError.notEnoughSpace(needed: 2_500_000_000, free: 1_000_000_000), DownloadError.alreadyDownloaded, DownloadError.noURL,
         DownloadError.unsafePath]
    }

    func testEveryTypedKeyIsInTheCatalogWithItsTranslation() throws {
        let strings = try catalog
        let missing = typed.map(\.userText.key).filter { english($0, in: strings) == nil }
        XCTAssertEqual(missing, [], "una clave de error sin traducción en el catálogo")
    }

    func testTheSpanishIsTheSameAsBefore() {
        XCTAssertEqual("\(TraktError.network("sin red"))", "No pude conectar con Trakt: sin red")
        XCTAssertEqual("\(TraktError.http(503))", "Trakt respondió HTTP 503")
        XCTAssertEqual("\(TraktError.auth("Vuelve a conectar Trakt."))", "Vuelve a conectar Trakt.")
        XCTAssertEqual("\(DownloadError.notEnoughSpace(needed: 2_500_000_000, free: 1_000_000_000))", "Hacen falta 2500 MB y hay 1000 MB libres.")
        XCTAssertEqual("\(DownloadError.noURL)", "Esta versión no tiene un enlace para descargar.")
        XCTAssertEqual("\(DebridError.network("x"))", "No pude hablar con Real-Debrid. Revisa tu conexión.")
        XCTAssertEqual("\(NetworkError("Tiempo agotado"))", "Tiempo agotado")
        XCTAssertEqual(UserText("No pude conectar con Trakt: %@", .nested(UserText("Tiempo agotado"))).description,
                       "No pude conectar con Trakt: Tiempo agotado")
    }

    /// Lo que la app todavía traduce reconociendo el texto por su forma (`Strings.message`): los errores con causa que arman
    /// los modelos en español («No pude …: <la causa>»). Cada uno que pase a un tipo sale de esta lista; uno nuevo con esa
    /// forma tiene que entrar aquí a propósito (mejor: que nazca con tipo).
    func testWhatIsStillTranslatedByItsShape() throws {
        let strings = try catalog
        let byType = Set(typed.map(\.userText.key))
        let shapes = strings.keys.filter { key in
            key.hasSuffix(": %@") && english(key, in: strings) != nil
                && ["No pude", "No contest", "Infuse no pudo"].contains(where: key.hasPrefix)
        }
        XCTAssertEqual(shapes.filter { !byType.contains($0) }.sorted(), Self.stillByShape)
        XCTAssertTrue(byType.contains("No pude conectar con Trakt: %@"), "lo de las familias ya no depende de la forma")
    }

    static let stillByShape = [
        "Infuse no pudo reproducirlo: %@",
        "No contestaron a tiempo: %@",
        "No contestó a tiempo: %@",
        "No pude cambiar tu lista de Trakt: %@",
        "No pude cambiar tus favoritos de Trakt: %@",
        "No pude crear la lista: %@",
        "No pude guardar el archivo: %@",
        "No pude leer el catálogo: %@",
        "No pude marcarlo: %@",
        "No pude pedir las fuentes: %@",
    ]
}
