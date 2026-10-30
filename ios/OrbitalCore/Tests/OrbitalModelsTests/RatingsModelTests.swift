import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El recordatorio de calificar: qué entra a la fila, qué no vuelve y que calificar se vea al momento aunque Trakt tarde.
@MainActor
final class RatingsModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func play(_ imdb: String, _ kind: String = "movie", daysAgo: Double, _ title: String = "T") -> TraktPlay {
        TraktPlay(at: now.addingTimeInterval(-daysAgo * 86400), kind: kind, imdb: imdb, title: title, minutes: 100, genres: [])
    }

    func testEntranLasPeliculasRecientesYLasSeriesConVariosEpisodios() {
        let plays = [play("tt1", daysAgo: 1.5), play("tt2", daysAgo: 20), play("tt3", "series", daysAgo: 2),
                     play("tt4", "series", daysAgo: 1), play("tt4", "series", daysAgo: 2), play("tt4", "series", daysAgo: 3),
                     play("tt5", daysAgo: 0.5)]
        let queue = RatingsModel.reminders(plays: plays, rated: [], dismissed: [], now: now)
        XCTAssertEqual(queue.map(\.imdb), ["tt5", "tt4", "tt1"], "tt2 es de hace 20 días; tt3 lleva un solo episodio")
        XCTAssertEqual(queue.first?.poster, "https://images.metahub.space/poster/medium/tt5/img")
    }

    func testNoVuelveLoCalificadoNiLoDescartado() {
        let plays = [play("tt1", daysAgo: 1), play("tt2", daysAgo: 1), play("tt3", daysAgo: 1)]
        let queue = RatingsModel.reminders(plays: plays, rated: ["tt1"], dismissed: ["tt2"], now: now)
        XCTAssertEqual(queue.map(\.imdb), ["tt3"])
    }

    func testCalificarSeVeAlMomentoYSaleDeLaFila() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["https://api.trakt.tv/sync/ratings"] = ["added": ["movies": 1]]
        let model = RatingsModel(rig.services, clock: { [now] in now })
        await model.rate(imdb: "tt6751668", kind: "movie", stars: 4.5)
        XCTAssertEqual(model.stars("tt6751668"), 4.5)
        XCTAssertEqual(model.ratings["tt6751668"], 9)
        XCTAssertTrue(rig.services.traktOutbox.pendingRatings.isEmpty, "ya llegó a Trakt")
    }

    func testDescartarSeRecuerda() throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let model = RatingsModel(rig.services, clock: { [now] in now })
        model.dismiss("tt1")
        let again = RatingsModel(rig.services)
        again.dismiss("tt2")
        let saved = rig.kv.data(RatingsModel.dismissedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        XCTAssertEqual(saved, ["tt1", "tt2"])
    }
}
