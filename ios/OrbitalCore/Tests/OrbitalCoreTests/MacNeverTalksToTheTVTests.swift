import XCTest

/// CX1-B (Fernando, 3 nov: «La Mac no se conecta con la TV. La Mac no habla con la TV… para nada») y PA5-A (23 nov: «El iPad
/// no se conecta a la TV»): en la Mac y en el iPad no hay emparejar, «Tu Orbital», «Pasar a la TV», «Usar la de la TV», la lista
/// de la TV, el control, la voz ni «Ver en la TV». Solo les llega tu clave de Real-Debrid por iCloud (CX2-A). Lo de dentro lo cuida `ConnectWithOrWithoutIPhoneTests` (con la consola
/// apagada en `Capabilities` no sale ni una petición a la TV); esta prueba cuida que la app arme `Services` así en la Mac.
final class MacNeverTalksToTheTVTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try String(contentsOf: url.appendingPathComponent("ios/App/Sources/\(path)"), encoding: .utf8)
    }

    func testOnlyTheIPhoneTalksToTheTV() throws {
        let device = try source("Platform/DeviceInfo.swift")
        XCTAssertTrue(device.contains("static let talksToOrbital = !ProcessInfo.onMac && !runsOnIPad"),
                      "ni la Mac ni el iPad hablan con tu TV")
        XCTAssertTrue(device.contains(#"return machine.hasPrefix("iPad")"#) && device.contains(#"simulated.hasPrefix("iPad")"#),
                      "el iPad se reconoce por su modelo (también en el simulador)")
        XCTAssertTrue(device.contains(#"ProcessInfo.onMac ? "mac""#), "la Mac se presenta como «mac», no como iPad")
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
        XCTAssertTrue(settings.contains("if entries.orbital { orbitalSettings(model) }"), "«Usar con tu Orbital» y «Tu Orbital», solo en el iPhone")
        // PA5-A: sin la invitación «Conectar tu iPad» (era para conectar el iPad a la TV).
        for file in ["Screens/SettingsView.swift", "Screens/OrbitalConnectViews.swift", "Screens/OrbitalDevicesSection.swift",
                     "Screens/Onboarding/OnboardingFinish.swift", "Screens/RootView.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("IPadInviteCard") || text.contains("InviteIPadRow") || text.contains("takeInviteToShow"),
                           "\(file): la invitación del iPad ya no existe")
        }
        for (file, gate) in [("App/AppDelegate.swift", "ThisDevice.capabilities.console"), ("Platform/OrbitalIntents.swift", "ThisDevice.capabilities.console"),
                             ("Screens/RootView.swift", "env.services.capabilities.console"), ("Screens/AppCommands.swift", "ThisDevice.capabilities.console")] {
            XCTAssertTrue(try source(file).contains(gate), "\(file): sin su guardia de la Mac")
        }
    }
}
