import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La Mac no habla con tu Orbital (`Services(allowsOrbital: false)`): aunque el llavero traiga dirección y token, la conexión no
/// queda configurada y emparejar no guarda nada. El iPhone y el iPad (`allowsOrbital` por omisión) siguen igual.
@MainActor
final class OrbitalOffTests: XCTestCase {
    private func services(_ rig: ServicesRig, allowsOrbital: Bool) -> Services {
        Services(http: rig.http, secrets: rig.secrets, kv: InMemoryKeyValueStore(), pending: InMemoryPendingStore(),
                 downloadTransport: FakeDownloadTransport(), downloadsRoot: rig.root, freeSpace: { 50_000_000_000 },
                 allowsOrbital: allowsOrbital)
    }

    func testTheMacNeverConnectsEvenWithATokenInTheKeychain() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://tv.example/api/ping"] = .object(["ok": .bool(true)])
        rig.http.json["https://tv.example/api/companion"] = .object([:])
        try await rig.services.connectOrbital(address: "tv.example", token: "secreto")   // el iPhone, emparejado
        XCTAssertTrue(services(rig, allowsOrbital: true).orbital.isConfigured, "el iPad con el mismo llavero sí conecta")
        let mac = services(rig, allowsOrbital: false)
        XCTAssertFalse(mac.orbital.isConfigured, "la Mac no usa la dirección ni el token del llavero")
        XCTAssertFalse(TVNowModel(mac).isConfigured, "sin control ni «En la TV» en la Mac")
    }

    func testPairingOnTheMacStoresNothing() async throws {
        let rig = try ServicesRig()
        let mac = services(rig, allowsOrbital: false)
        let got = try await mac.connectOrbital(address: "tv.example", token: "secreto")
        XCTAssertEqual(got, [])
        XCTAssertNil(rig.secrets.get(SecretKey.orbitalToken), "no guarda el token")
        XCTAssertEqual(mac.appSettings.orbitalAddress, "", "ni la dirección")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("tv.example") }, "ni le pregunta nada a la consola")
    }

    /// «Usar con tu Orbital» viene apagado: la app es de una sola pieza y no se ve ni se le pregunta nada a la consola.
    func testOrbitalComesOffAndPairingTurnsItOn() async throws {
        let rig = try ServicesRig()
        XCTAssertFalse(rig.services.orbitalOn, "apagado por omisión")
        XCTAssertFalse(rig.services.orbital.isConfigured)
        let atLaunch = try await rig.services.connectOrbital()
        XCTAssertEqual(atLaunch, [], "apagado, al abrir no se le pregunta a la consola")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/api/") })
        rig.http.json["https://tv.example/api/ping"] = .object(["ok": .bool(true)])
        rig.http.json["https://tv.example/api/companion"] = .object([:])
        try await rig.services.connectOrbital(address: "tv.example", token: "secreto")   // el QR o «Conectar a mano»
        XCTAssertTrue(rig.services.orbitalOn, "emparejar la prende")
        XCTAssertTrue(rig.services.orbital.isConfigured)
    }

    /// Apagarla deja la app sola otra vez: se olvidan la dirección y el token, también del llavero (reinstalar no la revive).
    func testTurningItOffForgetsTheConsole() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://tv.example/api/ping"] = .object(["ok": .bool(true)])
        rig.http.json["https://tv.example/api/companion"] = .object([:])
        try await rig.services.connectOrbital(address: "tv.example", token: "secreto")
        rig.services.turnOffOrbital()
        XCTAssertFalse(rig.services.orbitalOn)
        XCTAssertFalse(rig.services.orbital.isConfigured)
        XCTAssertFalse(TVNowModel(rig.services).isConfigured, "sin control ni «En la TV»")
        XCTAssertNil(rig.secrets.get(SecretKey.orbitalToken))
        XCTAssertNil(rig.secrets.get(SecretKey.orbitalAddress))
        XCTAssertEqual(rig.services.appSettings.orbitalAddress, "")
    }

    /// Quien ya tenía su consola emparejada (ajustes de antes, sin el interruptor) la sigue teniendo prendida.
    func testSettingsFromBeforeWithAConsoleStayOn() throws {
        let before = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"orbitalAddress":"tv.example"}"#.utf8))
        XCTAssertTrue(before.orbitalEnabled)
        let fresh = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(fresh.orbitalEnabled)
    }
}

/// La hoja de «Usar con tu Orbital»: conectar (el código o a mano) y luego el tutorial de tres páginas.
@MainActor
final class OrbitalSetupModelTests: XCTestCase {
    func testScanningTheTVCodeConnectsAndThenTheTutorial() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://tv.example/api/ping"] = .object(["ok": .bool(true)])
        rig.http.json["https://tv.example/api/companion"] = .object([:])
        let setup = OrbitalSetupModel(rig.services)
        XCTAssertEqual(setup.stage, .connect)
        await setup.scanned("https://ejemplo.com/otra-cosa")
        XCTAssertNotNil(setup.problem, "un código que no es de Orbital se dice")
        XCTAssertFalse(rig.services.orbitalOn)
        await setup.scanned("orbital-ios://pair?u=https%3A%2F%2Ftv.example&t=secreto")
        XCTAssertNil(setup.problem)
        XCTAssertEqual(setup.stage, .connected)
        XCTAssertTrue(rig.services.orbitalOn)
        XCTAssertEqual(setup.host, "tv.example")
        XCTAssertEqual(setup.advance(), .tutorial(1))
        XCTAssertEqual(setup.advance(), .tutorial(2))
        XCTAssertEqual(setup.advance(), .tutorial(3))
        XCTAssertNil(setup.advance(), "después de la tercera, se cierra")
    }

    func testAConsoleThatDoesNotAnswerLeavesItOff() async throws {
        let rig = try ServicesRig()   // sin respuesta en /api/ping
        let setup = OrbitalSetupModel(rig.services)
        await setup.connectByHand(address: "", token: "")
        XCTAssertNotNil(setup.problem)
        await setup.connectByHand(address: "tv.example", token: "secreto")
        XCTAssertNotNil(setup.problem, "no contestó")
        XCTAssertEqual(setup.stage, .connect)
        XCTAssertFalse(rig.services.orbitalOn, "se queda apagada, como estaba")
        XCTAssertNil(rig.secrets.get(SecretKey.orbitalToken))
        XCTAssertEqual(OrbitalSetupModel(rig.services, tutorialOnly: true).stage, .tutorial(1), "«Qué puedes hacer con la TV»")
    }
}

/// La clave de TMDB incluida en la app (de `Secrets.xcconfig`): la app sola tiene fichas en español; la tuya gana.
@MainActor
final class BuiltInTMDBKeyTests: XCTestCase {
    func testTheBuiltInKeyIsUsedUntilYouPasteYours() throws {
        let rig = try ServicesRig()
        let services = Services(http: rig.http, secrets: rig.secrets, kv: InMemoryKeyValueStore(), pending: InMemoryPendingStore(),
                                downloadTransport: FakeDownloadTransport(), downloadsRoot: rig.root, freeSpace: { 50_000_000_000 },
                                builtInTMDBKey: "INCLUIDA")
        XCTAssertTrue(services.hasTMDBKey)
        XCTAssertTrue(services.usesBuiltInTMDBKey)
        XCTAssertTrue(services.tmdb.configured, "sin consola ni Ajustes, las fichas ya salen")
        XCTAssertEqual(Services.tmdbKey(secrets: rig.secrets, builtIn: "INCLUIDA"), "INCLUIDA")
        rig.secrets.set(SecretKey.tmdbKey, "MIA")
        XCTAssertEqual(Services.tmdbKey(secrets: rig.secrets, builtIn: "INCLUIDA"), "MIA", "la tuya gana")
        XCTAssertFalse(services.usesBuiltInTMDBKey)
    }
}
