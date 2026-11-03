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
}
