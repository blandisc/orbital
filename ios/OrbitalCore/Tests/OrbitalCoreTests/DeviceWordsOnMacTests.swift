import XCTest

/// IOS-12 · en la Mac la app de iPad («Diseñada para iPad») se presenta como iPad: la variante por aparato del catálogo de
/// textos le diría «Solo de este iPad». Las frases de «este iPhone» que también ve la Mac (Real-Debrid) eligen la palabra en el
/// código con `ThisDevice.platform` (que sí sabe que es «mac») y cada versión de Mac está en el catálogo, en inglés también.
final class DeviceWordsOnMacTests: XCTestCase {
    private var ios: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent("App/Sources/\(path)"), encoding: .utf8)
    }

    static let macPairs = [
        ("Solo de este iPhone", "Solo de esta Mac"),
        ("Seguir con la de este iPhone", "Seguir con la de esta Mac"),
        ("Sale de real-debrid.com/apitoken. Se guarda en este iPhone y, si usas el llavero de iCloud, también lo ven tus otros aparatos Apple.",
         "Sale de real-debrid.com/apitoken. Se guarda en esta Mac y, si usas el llavero de iCloud, también lo ven tus otros aparatos Apple."),
    ]

    func testTheMacWordIsChosenInCode() throws {
        let device = try source("Platform/DeviceInfo.swift")
        XCTAssertTrue(device.contains(#"ThisDevice.platform == "mac" ? Text(mac) : Text(key)"#), "la palabra de la Mac la elige el código")
        let screens = try source("Screens/DebridAccountView.swift") + source("Screens/DebridSharedSection.swift")
        for (iphone, mac) in Self.macPairs {
            XCTAssertTrue(screens.contains("DeviceWords.text(\"\(iphone)\"") && screens.contains("mac: \"\(mac)\""), "«\(iphone)» sin su versión de Mac en el código")
        }
    }

    func testEveryMacSentenceIsTranslated() throws {
        let data = try Data(contentsOf: ios.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        for (_, mac) in Self.macPairs {
            let entry = try XCTUnwrap(strings[mac] as? [String: Any], "«\(mac)» no está en el catálogo")
            let english = ((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            XCTAssertNotNil(english?["value"], "«\(mac)» sin inglés")
        }
    }

    /// La Mac lee su propia versión de cada texto (26 nov 2026). Una app del iPad en la Mac recibía la variante «ipad» del
    /// catálogo: «Como el iPad» en Apariencia, «Toca uno» en Complementos. `MacStrings` (solo en la Mac) busca primero la
    /// variante «mac»; aquí se cuida que esté instalado y que todo texto por aparato tenga su versión de Mac, que diga «haz
    /// clic» y no «toca». (Antes, MT1 pedía que la variante del iPad dijera «dispositivo» porque era la que veía la Mac.)
    func testTheMacReadsItsOwnVariant() throws {
        XCTAssertTrue(try source("OrbitalApp.swift").contains("MacStrings.install()"), "la app instala los textos de la Mac al arrancar")
        let mac = try source("Platform/MacStrings.swift")
        XCTAssertTrue(mac.contains("guard ProcessInfo.processInfo.isiOSAppOnMac"), "solo en la Mac")
        XCTAssertTrue(mac.contains(#"device["mac"]"#), "lee la variante «mac» del catálogo")
        let data = try Data(contentsOf: ios.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        var missing: [String] = [], touch: [String] = []
        for (key, entry) in strings {
            for (language, loc) in ((entry as? [String: Any])?["localizations"] as? [String: Any]) ?? [:] {
                guard let device = ((loc as? [String: Any])?["variations"] as? [String: Any])?["device"] as? [String: Any] else { continue }
                guard let value = ((device["mac"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String else {
                    missing.append("\(language): \(key)"); continue
                }
                if value.range(of: #"\b([Tt]oca|[Tt]ocas|[Tt]ap)\b"#, options: .regularExpression) != nil { touch.append(value) }
            }
        }
        XCTAssertEqual(missing, [], "todo texto por aparato trae su versión de Mac")
        XCTAssertEqual(touch, [], "en la Mac se hace clic, no se toca")
    }

    /// La Mac no tiene datos móviles: no se ofrece calidad «Con datos móviles» ni «Solo con Wi‑Fi» al bajar.
    func testTheMacOffersNoCellular() throws {
        let settings = try source("Screens/SettingsView.swift"), downloads = try source("Screens/DownloadsView.swift")
        for (code, row) in [(settings, "SettingsChoiceRow(title: \"Con datos móviles\""), (settings, "DSToggleRow(\"Solo con Wi‑Fi\""),
                            (downloads, "DSToggleRow(\"Solo con Wi‑Fi\"")] {
            let lines = code.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains(row) {
                let before = lines[max(0, i - 2)...i].joined(separator: "\n")
                XCTAssertTrue(before.contains("!ThisDevice.isMac"), "«\(row)» no sale en la Mac")
            }
        }
    }
}
