import XCTest
@testable import OrbitalCore

/// «¿Cuándo la viste?» (31 oct 2026): una temporada o una serie viajan a Trakt en una sola petición, cada episodio con su
/// fecha; «No sé cuándo» va como `unknown` y, si Trakt no lo acepta, como la fecha de estreno.
final class TraktHistoryBatchTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func makeTrakt(_ http: FakeHTTP) -> Trakt {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(Date().timeIntervalSince1970 + 7 * 86400)}"#)
        return Trakt(http: http, secrets: secrets, clientID: "CID", pause: { _ in })
    }

    func testUnaTemporadaVaEnUnaSolaPeticion() async throws {
        let http = FakeHTTP()
        http.json["\(api)/sync/history"] = ["added": ["episodes": 3]]
        let d = Date(timeIntervalSince1970: 1_130_000_000)
        try await makeTrakt(http).addToHistory([(TraktTarget(imdb: "tt0386676", season: 2, episode: 1), d),
                                                (TraktTarget(imdb: "tt0386676", season: 2, episode: 2), d),
                                                (TraktTarget(imdb: "tt0386676", season: 1, episode: 6), Trakt.unknownDate)])
        let bodies = http.bodies(for: "\(api)/sync/history")
        XCTAssertEqual(bodies.count, 1, "una sola petición")
        let body = try XCTUnwrap(bodies.first.flatMap(JSON.parse))
        let show = try XCTUnwrap(body["shows"]?.array?.first)
        XCTAssertEqual(show["ids"]?["imdb"]?.string, "tt0386676")
        XCTAssertEqual(show["seasons"]?.array?.map { $0["number"]?.intValue }, [1, 2])
        XCTAssertEqual(show["seasons"]?.array?.first?["episodes"]?.array?.first?["watched_at"]?.string, "unknown")
        XCTAssertNil(body["movies"])
    }

    func testSiTraktNoConoceUnknownUsaElEstreno() async throws {
        let http = FakeHTTP()
        http.statuses["\(api)/sync/history"] = 400
        let trakt = makeTrakt(http)
        do { try await trakt.addToHistory([(TraktTarget(imdb: "tt6751668"), Trakt.unknownDate)]) } catch {}
        let bodies = http.bodies(for: "\(api)/sync/history").compactMap(JSON.parse)
        XCTAssertEqual(bodies.count, 2, "un segundo intento")
        XCTAssertEqual(bodies.last?["movies"]?.array?.first?["watched_at"]?.string, "released")
    }
}
