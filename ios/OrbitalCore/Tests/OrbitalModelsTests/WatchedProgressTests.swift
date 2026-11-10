import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Trakt dejó de mandar «seasons» en /sync/watched/shows (la sesión de la TV lo vio el 10 nov 2026 con la cuenta de
/// Fernando): sin esto, Guardado › Viendo y Vistas salían vacíos. Las recientes preguntan su avance; las demás, estimado.
@MainActor
final class WatchedProgressTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func show(_ imdb: String, aired: Int, plays: Int, last: String) -> JSON {
        ["plays": .int(plays), "last_watched_at": .string(last), "show": ["title": "S", "aired_episodes": .int(aired), "ids": ["imdb": .string(imdb)]]]
    }

    func testSinTemporadasPreguntaElAvanceOEstima() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/sync/watched/movies"] = []
        rig.http.prefix["\(api)/sync/watched/shows"] = [show("tt0000001", aired: 10, plays: 4, last: "2026-11-09T10:00:00.000Z"),
                                                       show("tt0000002", aired: 10, plays: 30, last: "2026-11-01T10:00:00.000Z")]
        rig.http.prefix["\(api)/shows/tt0000001/progress/watched"] = ["aired": 10, "completed": 6]
        rig.http.prefix["\(api)/shows/tt0000002/progress/watched"] = ["aired": 10, "completed": 10]
        let trakt = try XCTUnwrap(rig.services.trakt)
        let state = try await trakt.watchedState()
        XCTAssertEqual(state.shows["tt0000001"], 0.6, "a medias: 6 de 10 (no 0)")
        XCTAssertEqual(state.shows["tt0000002"], 1, "al día")
        XCTAssertEqual(state.completed, ["tt0000002"])
    }

    func testSinRespuestaQuedaElEstimado() {
        XCTAssertEqual(Trakt.showFraction(show("tt0000003", aired: 10, plays: 5, last: "")), 0.5)
        XCTAssertEqual(Trakt.showFraction(show("tt0000003", aired: 10, plays: 40, last: "")), 1)
    }
}
