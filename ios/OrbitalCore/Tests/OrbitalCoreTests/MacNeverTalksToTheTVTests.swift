import XCTest

/// CX1-B (Fernando, 3 nov: «La Mac no se conecta con la TV. La Mac no habla con la TV… para nada»): en la Mac no hay
/// emparejar, invitación, «Tu Orbital», «Pasar a la TV», «Usar la de la TV», la lista de la TV ni «Ver en la TV». Solo le llega
/// tu clave de Real-Debrid por iCloud (CX2-A). Lo de dentro lo cuida `ConnectWithOrWithoutIPhoneTests` (con la consola
/// apagada en `Capabilities` no sale ni una petición a la TV); esta prueba cuida que la app arme `Services` así en la Mac.
final class MacNeverTalksToTheTVTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try String(contentsOf: url.appendingPathComponent("ios/App/Sources/\(path)"), encoding: .utf8)
    }

    func testTheMacIsTheOnlyDeviceThatDoesNotTalkToTheTV() throws {
        let device = try source("Platform/DeviceInfo.swift")
        XCTAssertTrue(device.contains("static let talksToOrbital = !ProcessInfo.processInfo.isiOSAppOnMac"), "la Mac no habla con tu TV")
        XCTAssertTrue(device.contains(#"ProcessInfo.processInfo.isiOSAppOnMac ? "mac""#), "la Mac se presenta como «mac», no como iPad")
    }

    func testEveryServicesTheAppBuildsAsksThisDevice() throws {
        let composition = try source("App/AppComposition.swift")
        let built = composition.components(separatedBy: "let services = Services(").count - 1
        XCTAssertGreaterThan(built, 0)
        XCTAssertEqual(composition.components(separatedBy: "capabilities: ThisDevice.capabilities").count - 1, built,
                       "cada `Services` (también el de la demostración) con `capabilities: ThisDevice.capabilities`")
        let device = try source("Platform/DeviceInfo.swift")
        XCTAssertTrue(device.contains("Capabilities(edition: .bundled(), talksToOrbital: talksToOrbital)"),
                      "las capacidades de la app salen de la versión y de si este aparato habla con la TV")
        XCTAssertEqual(composition.components(separatedBy: "platform: ThisDevice.platform").count - 1, built)
    }

    func testTheTVPartsOfSettingsHideOnTheMac() throws {
        let settings = try source("Screens/SettingsView.swift")
        // IOS-10: la invitación va arriba de Ajustes y «Orbital en la TV» más abajo; cada una con su guardia.
        XCTAssertTrue(settings.contains("if entries.orbital { IPadInviteCard"), "la invitación del iPhone, solo donde se habla con la TV")
        XCTAssertTrue(settings.contains("if entries.orbital { orbitalSettings(model) }"), "«Orbital en la TV» y «Tu Orbital», nunca en la Mac")
        XCTAssertFalse(settings.replacingOccurrences(of: "if entries.orbital { IPadInviteCard", with: "").contains("IPadInviteCard {"),
                       "la invitación no sale en ningún otro lado de Ajustes sin su guardia")
        for (file, gate) in [("App/AppDelegate.swift", "ThisDevice.capabilities.console"), ("Platform/OrbitalIntents.swift", "ThisDevice.capabilities.console"),
                             ("Screens/RootView.swift", "env.services.capabilities.console"), ("Screens/AppCommands.swift", "ThisDevice.capabilities.console")] {
            XCTAssertTrue(try source(file).contains(gate), "\(file): sin su guardia de la Mac")
        }
    }
}
