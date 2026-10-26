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

    /// Emparejar con el QR teniendo ya las claves (nada nuevo que traer): antes no se avisaba a nadie y el control no aparecía
    /// («Orbital no conectado») hasta mandar la app a segundo plano y volver.
    func testPairingWithNothingNewStartsPollingAtOnce() async throws {
        let rig = try ServicesRig()  // sin dirección ni token
        rig.http.json["https://tv.example/api/ping"] = .object(["ok": .bool(true)])
        rig.http.json["https://tv.example/api/companion"] = .object([:])
        let playing: JSON = .object(["kind": .string("movie"), "live": .bool(false), "title": .string("Interstellar"),
                                     "position": .int(10), "duration": .int(100), "paused": .bool(false)])
        rig.http.json["https://tv.example/api/companion/now"] = .object(["playing": playing])
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        var told = 0
        let watch = model.onChange { told += 1 }
        model.setActive(true)   // la app ya estaba al frente: sin configuración, no sondea
        let generation = rig.services.generation
        try await rig.services.connectOrbital(address: "tv.example", token: "secreto")
        XCTAssertEqual(rig.services.generation, generation)   // no se rearmó nada…
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertGreaterThan(told, 0)                          // …pero el control se enteró
        XCTAssertEqual(model.now?.title, "Interstellar")       // y ya sondea
        model.setActive(false)
        _ = watch
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

    /// El control completo: cada tecla y el texto van a la consola como si fueran del mando.
    func testTheFullRemoteSendsKeysAndText() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/companion/input"] = ["ok": true, "target": "ui"]
        rig.http.json["https://tv.example/api/companion/text"] = ["ok": true]
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        await model.press(.right)
        await model.press(.select)
        await model.type("dune", submit: true)
        let sent = rig.http.bodies("https://tv.example/api/companion/input").compactMap { JSON.parse($0)?["action"]?.string }
        XCTAssertEqual(sent, ["right", "select"])
        let text = try XCTUnwrap(rig.http.bodies("https://tv.example/api/companion/text").first.flatMap { JSON.parse($0) })
        XCTAssertEqual(text["text"]?.string, "dune")
        XCTAssertEqual(text["submit"]?.bool, true)
        XCTAssertFalse(model.remoteOutdated)
    }

    /// Una consola de antes (sin la ruta): el pad se esconde y se avisa que hay que actualizarla.
    func testAnOlderOrbitalHidesThePad() async throws {
        let rig = try connected()   // /api/companion/input no se registra: 404, como una versión anterior
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        await model.press(.up)
        XCTAssertTrue(model.remoteOutdated)
    }
}
