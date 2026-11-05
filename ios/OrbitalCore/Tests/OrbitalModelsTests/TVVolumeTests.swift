import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El volumen de la TV desde el control (31 oct 2026, «que sea más fluido»): varios toques seguidos no hacen fila (se juntan
/// en la siguiente orden) y la barra se mueve al momento.
@MainActor
final class TVVolumeTests: XCTestCase {
    private func connected() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example"; $0.orbitalEnabled = true }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/companion/player"] = ["ok": true]
        return rig
    }

    func testRapidPressesAreSentTogetherNotQueued() async throws {
        let rig = try connected()
        let model = TVNowModel(rig.services)
        // Tres toques casi a la vez: el primero sale solo y los otros dos se juntan en la siguiente orden.
        async let a: Void = model.changeVolume(by: 5)
        async let b: Void = model.changeVolume(by: 5)
        async let c: Void = model.changeVolume(by: 5)
        _ = await (a, b, c)
        let deltas = rig.http.bodies("https://tv.example/api/companion/player").compactMap { JSON.parse($0)?["delta"]?.doubleValue }
        XCTAssertEqual(deltas.reduce(0, +), 15, "la TV recibe todo lo que tocaste")
        XCTAssertLessThanOrEqual(deltas.count, 2, "sin una orden por toque esperando su turno")
    }

    /// V4-A: con un video la consola manda el Extra y la barra dice lo mismo que la cápsula de la TV; sin él, como siempre.
    func testTheExtraFromTheTVIsWhatTheBarShows() {
        let extra = OrbitalRemote.Volume.parse(["level": 100, "muted": false, "extra": 150])
        XCTAssertEqual(extra?.extra, 150)
        XCTAssertEqual(extra?.shown, 150, "pasado el 100, el número es el del Extra")
        let normal = OrbitalRemote.Volume.parse(["level": 80, "muted": false, "extra": 100])
        XCTAssertEqual(normal?.shown, 80, "sin Extra, el de Windows")
        XCTAssertNil(OrbitalRemote.Volume.parse(["level": 80, "muted": false])?.extra, "sin video o una consola de antes: sin Extra")
        XCTAssertEqual(OrbitalRemote.Volume.parse(["level": 100, "extra": 999])?.extra, 200, "nunca pasa del tope de la TV")
    }
}
