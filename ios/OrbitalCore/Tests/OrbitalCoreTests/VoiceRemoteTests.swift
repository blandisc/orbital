import XCTest
@testable import OrbitalCore

/// Falla siempre con ese error (sin internet, sin conexión con el túnel…).
private struct ThrowingHTTP: HTTPClient {
    let error: Error
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw error }
}

/// El modo voz del iPhone: lo que trae la respuesta de la consola, las frases del momento y por qué no se llega a tu Orbital.
final class VoiceRemoteTests: XCTestCase {
    func testTheReplySaysWhichOneItPickedTheGuideAndTheHints() async throws {
        let http = FakeHTTP()
        let dune: JSON = ["id": "b", "title": "Dune", "kind": "movie", "meta_id": "tt1160419"]
        http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Poniendo Dune.", "choices": .array([dune]), "picked": "tt1160419",
                                                     "guide": true, "hints": ["pausa", " ", "pon subtítulos", "sube el volumen"]]
        let reply = try await OrbitalRemote(http: http, address: "tv.example", token: "x").voice("pon Dune")
        XCTAssertEqual(reply.picked, "tt1160419")
        XCTAssertTrue(reply.guide)
        XCTAssertEqual(reply.hints, ["pausa", "pon subtítulos", "sube el volumen"], "las vacías no cuentan")
    }

    func testAPlainReplyHasNoPickNoGuideAndNoHints() async throws {
        let http = FakeHTTP()
        http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Encontré varias.", "picked": ""]
        let reply = try await OrbitalRemote(http: http, address: "tv.example", token: "x").voice("busca Dune")
        XCTAssertNil(reply.picked)
        XCTAssertFalse(reply.guide)
        XCTAssertEqual(reply.hints, [])
    }

    func testHintsOfTheMomentAndAnOldConsole() async throws {
        let http = FakeHTTP()
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        do { _ = try await remote.voiceHints(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .outdated) }
        http.json["https://tv.example/api/voice/hints"] = ["moment": "series", "hints": ["pausa", "siguiente episodio", "pon subtítulos"]]
        let hints = try await remote.voiceHints()
        XCTAssertEqual(hints, .init(moment: "series", hints: ["pausa", "siguiente episodio", "pon subtítulos"]))
        XCTAssertEqual(http.headers.last?["Authorization"], "Bearer x")
    }

    func testDiagnoseSaysWhatIsWrong() async throws {
        let http = FakeHTTP()
        let remote = OrbitalRemote(http: http, address: "tv.example", token: "x")
        let ping = "https://tv.example/api/ping"
        http.json[ping] = ["ok": true, "service": "orbital"]
        let fine = await remote.diagnose()
        XCTAssertNil(fine)
        XCTAssertEqual(http.headers.last?["Authorization"], "Bearer x", "siempre con token: sin él cuenta como intento fallido")
        for status in [502, 503, 504] {
            http.statuses[ping] = status
            let issue = await remote.diagnose()
            XCTAssertEqual(issue, .orbitalDown, "\(status)")
        }
        http.statuses[ping] = 401
        let token = await remote.diagnose()
        XCTAssertEqual(token, .tokenChanged)
        http.statuses[ping] = 530
        let tunnel = await remote.diagnose()
        XCTAssertEqual(tunnel, .tunnelDown)
    }

    func testDiagnoseTellsNoInternetFromATunnelThatDoesNotAnswer() async {
        func diagnose(_ error: Error) async -> ConnectionIssue? {
            await OrbitalRemote(http: ThrowingHTTP(error: error), address: "tv.example", token: "x").diagnose()
        }
        let offline = await diagnose(URLError(.notConnectedToInternet))
        XCTAssertEqual(offline, .noInternet)
        let wrapped = await diagnose(NetworkError("sin internet", code: .notConnectedToInternet))
        XCTAssertEqual(wrapped, .noInternet, "como lo deja URLSessionHTTPClient")
        for code: URLError.Code in [.cannotConnectToHost, .cannotFindHost, .secureConnectionFailed, .timedOut] {
            let issue = await diagnose(URLError(code))
            XCTAssertEqual(issue, .tunnelDown, "\(code)")
        }
        let unknown = await diagnose(NetworkError("Tiempo agotado"))
        XCTAssertEqual(unknown, .tunnelDown)
        let unconfigured = await OrbitalRemote(http: FakeHTTP(), address: "", token: "").diagnose()
        XCTAssertNil(unconfigured)
    }
}
