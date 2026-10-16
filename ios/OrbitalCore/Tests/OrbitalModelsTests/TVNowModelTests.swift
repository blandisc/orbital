import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

@MainActor
final class TVNowModelTests: XCTestCase {
    func connected() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "secreto")
        return rig
    }

    func testWithoutOrbitalConfiguredThereIsNothingToPoll() async throws {
        let rig = try ServicesRig()  // sin dirección ni token
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.setActive(true)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.now)
        model.setActive(false)
    }

    func testPollsWhileActiveAndStopsWhenNot() async throws {
        let rig = try connected()
        let playing: JSON = .object(["kind": .string("movie"), "live": .bool(false), "title": .string("Interstellar"),
                                     "position": .int(10), "duration": .int(100), "paused": .bool(false)])
        rig.http.json["https://tv.example/api/companion/now"] = .object(["playing": playing])
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.setActive(true)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.now?.title, "Interstellar")
        model.setActive(false)
        // La petición que ya iba en camino al parar puede llegar un instante después: se deja aterrizar antes de contar.
        try await Task.sleep(nanoseconds: 10_000_000)
        let callsAtStop = rig.http.calls.count
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(rig.http.calls.count, callsAtStop)  // ya no sondea
    }

    func testBadTokenHidesTheCardAndFlagsTheProblem() async throws {
        let rig = try connected()
        rig.http.statuses["https://tv.example/api/companion/now"] = 401
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.setActive(true)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.now)
        XCTAssertTrue(model.tokenProblem)
        model.setActive(false)
    }

    func testUnreachableOrbitalHidesTheCardWithoutError() async throws {
        let rig = try connected()
        // Sin JSON para esa URL: FakeHTTP contesta 404 (como una Orbital de otra versión).
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.setActive(true)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.now)
        XCTAssertFalse(model.tokenProblem)
        model.setActive(false)
    }

    func testControlUpdatesAtOnceAndIgnoresASecondTapWhileBusy() async throws {
        let rig = try connected()
        let playing: JSON = .object(["kind": .string("movie"), "live": .bool(false), "title": .string("Interstellar"),
                                     "position": .int(10), "duration": .int(100), "paused": .bool(true)])
        rig.http.json["https://tv.example/api/companion/player"] = .object(["playing": playing])
        rig.http.delays["https://tv.example/api/companion/player"] = 30
        let model = TVNowModel(rig.services)
        async let first: Void = model.control("toggle")
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertTrue(model.busy)
        await model.control("toggle")  // llega mientras la primera sigue en vuelo: se ignora
        await first
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.now?.paused, true)
        XCTAssertEqual(rig.http.bodies("https://tv.example/api/companion/player").count, 1)
    }
}
