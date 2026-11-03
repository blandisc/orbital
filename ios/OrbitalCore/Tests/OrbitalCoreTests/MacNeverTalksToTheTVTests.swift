import XCTest

/// CX1-B (Fernando, 3 nov: «La Mac no se conecta con la TV. La Mac no habla con la TV… para nada»): en la Mac no hay
/// emparejar, invitación, «Tu Orbital», «Pasar a la TV», «Usar la de la TV», la lista de la TV ni «Ver en la TV». Solo le llega
/// tu clave de Real-Debrid por iCloud (CX2-A). Lo de dentro lo cuida `ConnectWithOrWithoutIPhoneTests` (con `allowsOrbital`
/// apagado no sale ni una petición a la TV); esta prueba cuida que la app arme `Services` así en la Mac.
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
        XCTAssertEqual(composition.components(separatedBy: "allowsOrbital: ThisDevice.talksToOrbital").count - 1, built,
                       "cada `Services` (también el de la demostración) con `allowsOrbital: ThisDevice.talksToOrbital`")
        XCTAssertEqual(composition.components(separatedBy: "platform: ThisDevice.platform").count - 1, built)
    }

    func testTheTVPartsOfSettingsHideOnTheMac() throws {
        let settings = try source("Screens/SettingsView.swift")
        let gate = try XCTUnwrap(settings.range(of: "if env.services.allowsOrbital {"))
        let block = settings[gate.upperBound...].prefix(400)
        XCTAssertTrue(block.contains("IPadInviteCard"), "la invitación del iPhone, solo donde se habla con la TV")
        XCTAssertTrue(block.contains("orbitalSettings(model)"), "«Orbital en la TV» y «Tu Orbital», nunca en la Mac")
        for (file, gate) in [("App/AppDelegate.swift", "ThisDevice.talksToOrbital"), ("Platform/OrbitalIntents.swift", "ThisDevice.talksToOrbital"),
                             ("Screens/RootView.swift", "env.services.allowsOrbital"), ("Screens/AppCommands.swift", "ThisDevice.talksToOrbital")] {
            XCTAssertTrue(try source(file).contains(gate), "\(file): sin su guardia de la Mac")
        }
    }
}
