import XCTest
@testable import OrbitalCore

/// Revisión del 11 nov 2026: el iPhone lee el número `api` de la TV. Si falta algo y la TV es MÁS NUEVA que el iPhone, quien
/// debe actualizarse es el iPhone (antes siempre se culpaba a la TV).
final class TVContractVersionTests: XCTestCase {
    func remote(api: Int, capabilities: [String]) async throws -> (OrbitalRemote, FakeHTTP) {
        let http = FakeHTTP()
        http.json["https://tv.example/api/ping"] = ["ok": true, "api": .int(api), "capabilities": .array(capabilities.map { .string($0) })]
        var remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        remote.contracts = TVContractBook()
        try await remote.check()
        return (remote, http)
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body(); return nil }
        catch OrbitalRemote.Failure.refused(let why) { return why }
        catch { return "\(error)" }
    }

    func testUnaTVMasNuevaQueElIPhonePideActualizarElIPhone() async throws {
        let (remote, http) = try await remote(api: TVContract.supportedAPI + 1, capabilities: ["now_playing"])
        XCTAssertTrue(remote.contract.isNewerThanThisPhone)
        let why = await refusal { _ = try await remote.voice("pon dune") }
        XCTAssertEqual(why, "Actualiza Orbital en este iPhone para usar esto.")
        XCTAssertFalse(http.calls.contains("https://tv.example/api/voice"), "lo que no anuncia no se pide")
    }

    func testUnaTVMasViejaPideActualizarLaTV() async throws {
        let (remote, _) = try await remote(api: TVContract.supportedAPI, capabilities: ["now_playing"])
        XCTAssertFalse(remote.contract.isNewerThanThisPhone)
        let why = await refusal { _ = try await remote.voice("pon dune") }
        XCTAssertEqual(why, "Tu Orbital de la tele necesita actualizarse para esto.")
    }

    /// Una ruta que la TV anuncia pero ya no existe (404 de FastAPI): con una TV más nueva, también es el iPhone.
    func testUnaRutaQueYaNoExisteEnUnaTVMasNuevaEsCulpaDelIPhone() async throws {
        let (remote, http) = try await remote(api: TVContract.supportedAPI + 1, capabilities: ["voice"])
        http.json["https://tv.example/api/voice"] = ["detail": "Not Found"]; http.statuses["https://tv.example/api/voice"] = 404
        let why = await refusal { _ = try await remote.voice("pon dune") }
        XCTAssertEqual(why, OrbitalRemote.phoneUpdateLine)
        XCTAssertTrue(OrbitalRemote.isUpdateLine(why ?? ""), "quien toma «no lo tiene» como nada (resumen, para ti) reconoce los dos avisos")
    }

    func testLosDosAvisosEstanEnElCatalogoConIngles() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let strings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        for line in [OrbitalRemote.updateLine, OrbitalRemote.phoneUpdateLine] {
            let entry = try XCTUnwrap(strings[line] as? [String: Any], "«\(line)» no está en el catálogo")
            let english = ((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            XCTAssertNotNil(english?["value"], "«\(line)» sin inglés")
        }
    }
}
