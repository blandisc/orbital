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
}
