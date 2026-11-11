import XCTest
@testable import OrbitalCore

/// Los siete ejemplos de la TV para pedir la llave sin volver a escanear (`/api/devices/upgrade`) y para el arte de los juegos
/// (`/api/art`): pasan por lo mismo que usa la app.
extension ContractFixturesTests {
    // MARK: pedir la llave (la TV pregunta «¿le doy llave?»)

    func testAskingForTheKeyWaitsForTheTV() async throws {
        let tv = try FixtureTV("devices_upgrade", replacing: ["<id>": "req1"])
        let answer = try await remote(tv, key: nil).upgrade(name: "iPhone de Fernando", platform: "iphone")
        XCTAssertEqual(answer, .pending(request: "req1"))
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(tv.sent.first?.body)))
        XCTAssertEqual(sent["name"]?.string, "iPhone de Fernando")
        XCTAssertEqual(sent["platform"]?.string, "iphone")
    }

    func testWhileTheTVHasNotAnsweredItKeepsWaiting() async throws {
        // La TV contesta 202 sin repetir el id: el iPhone sigue con el que ya tenía.
        let tv = try FixtureTV("devices_upgrade_waiting", replacing: ["<id>": "req1"])
        let answer = try await remote(tv, key: nil).upgradeStatus("req1")
        XCTAssertEqual(answer, .pending(request: "req1"))
        XCTAssertEqual(tv.sent.first?.url.path, "/api/devices/upgrade/req1")
    }

    func testWhenTheTVSaysYesTheIPhoneGetsItsKey() async throws {
        let tv = try FixtureTV("devices_upgrade_ok", replacing: ["<id>": "req1", "<key>": Self.key, "<device_id>": Self.deviceID])
        let answer = try await remote(tv, key: nil).upgradeStatus("req1")
        XCTAssertEqual(answer, .approved(OrbitalPairResult(deviceID: Self.deviceID, key: Self.key, tvName: "Orbital", tvID: "<tv_id>")))
    }

    func testWhenTheTVSaysNoOrTheRequestIsGone() async throws {
        let denied = try FixtureTV("devices_upgrade_denied", replacing: ["<id>": "req1"])
        let no = try await remote(denied, key: nil).upgradeStatus("req1")
        XCTAssertEqual(no, .denied)
        let gone = try FixtureTV("devices_upgrade_gone", replacing: ["<id>": "req1"])
        let expired = try await remote(gone, key: nil).upgradeStatus("req1")
        XCTAssertEqual(expired, .expired)
    }

    // MARK: el arte de los juegos

    /// La portada que pinta el iPhone: la ruta que arma la TV (`companion.game_now`) cae en la capacidad «art», con la misma
    /// ruta y el mismo `kind` del ejemplo, y la TV contesta una imagen que se puede guardar un día.
    func testGameCoverIsTheRouteTheTVServes() async throws {
        let fixture = try Fixtures.json("contract/art.json")
        let game = try XCTUnwrap(OrbitalRemote.Game.parse(JSON.parse(Data(#"""
        {"id": "steam:367520", "title": "Hollow Knight", "art": {"cover": "/api/art/steam:367520?kind=cover"}}
        """#.utf8))))
        let cover = try XCTUnwrap(game.cover.flatMap { URL(string: $0, relativeTo: URL(string: "http://tv.example:8710")) })
        XCTAssertEqual(cover.path, fixture["request"]?["path"]?.string)
        XCTAssertEqual(URLComponents(url: cover, resolvingAgainstBaseURL: true)?.queryItems?.first { $0.name == "kind" }?.value,
                       fixture["request"]?["query"]?["kind"]?.string)
        XCTAssertEqual(TVContract.capability(for: cover.path), "art")
        let tv = try FixtureTV("art")
        let response = try await tv.send(HTTPRequest(url: cover.absoluteURL))
        XCTAssertEqual(response.status, 200)
        let body = try XCTUnwrap(JSON.parse(response.data))
        XCTAssertEqual(body["content_type"]?.string?.hasPrefix("image/"), true)
        XCTAssertEqual(body["cache_control"]?.string, "max-age=86400")
        XCTAssertGreaterThan(body["bytes"]?.intValue ?? 0, 0)
    }

    /// El arte que la TV no tiene contesta 404: el iPhone no pinta nada (el cargador de imágenes solo acepta < 300). La ruta
    /// que arma el iPhone para una sesión jugada (`InboxItem`, con «:» escapado) es la misma que sirve la TV.
    func testMissingArtIsANotFoundOnTheSameRoute() async throws {
        let fixture = try Fixtures.json("contract/art_missing.json")
        XCTAssertEqual(fixture["request"]?["query"]?["kind"]?.string, "logo")
        let built = try XCTUnwrap(URL(string: "http://tv.example:8710/api/art/\(uriComponent("steam:367520"))?kind=logo"))
        XCTAssertEqual(built.path, fixture["request"]?["path"]?.string)
        let response = try await FixtureTV("art_missing").send(HTTPRequest(url: built))
        XCTAssertEqual(response.status, 404)
        XCTAssertEqual(JSON.parse(response.data)?["detail"]?.string, "Not Found")
    }
}
