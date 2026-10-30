import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El mazo de «¿Qué vemos hoy?»: sin lo visto ni lo descartado, por ánimo y en un orden fijo del día.
@MainActor
final class MatchDeckModelTests: XCTestCase {
    func s(_ imdb: String, _ genres: [String]) -> Suggestion {
        var x = Suggestion(kind: "movie", imdb: imdb, title: imdb, poster: "", wide: "", reason: .popular)
        x.genres = genres
        return x
    }

    func testSinVistoNiDescartadoYPorAnimo() {
        let pool = [s("tt1", ["comedy"]), s("tt2", ["horror"]), s("tt3", ["comedy"]), s("tt1", ["comedy"]), s("tt4", ["drama"])]
        let all = MatchDeckModel.deck(pool, watched: ["tt3"], discarded: ["tt4"], mood: nil, day: 1)
        XCTAssertEqual(Set(all.map(\.imdb)), ["tt1", "tt2"], "sin repetir, sin lo visto ni lo descartado")
        XCTAssertEqual(MatchDeckModel.deck(pool, watched: [], discarded: [], mood: .intense, day: 1).map(\.imdb), ["tt2"])
    }

    func testElOrdenEsElMismoEnElDiaYCambiaAlOtro() {
        let pool = (1...12).map { s("tt\($0)", ["drama"]) }
        let a = MatchDeckModel.deck(pool, watched: [], discarded: [], mood: nil, day: 100).map(\.imdb)
        XCTAssertEqual(a, MatchDeckModel.deck(pool, watched: [], discarded: [], mood: nil, day: 100).map(\.imdb))
        XCTAssertNotEqual(a, MatchDeckModel.deck(pool, watched: [], discarded: [], mood: nil, day: 101).map(\.imdb))
    }

    func testLoGuardadoNoVuelveAlCambiarDeAnimo() async throws {
        let rig = try ServicesRig()
        let pool = [s("tt1", ["comedy"]), s("tt2", ["comedy"])]
        let model = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await model.load()
        await model.save(pool[0])
        model.mood = .light
        model.mood = nil
        XCTAssertEqual(model.cards.map(\.imdb), ["tt2"])
    }

    func testDescartarNoVuelveEnUnMes() async throws {
        let rig = try ServicesRig()
        let clock = rig.clock
        let pool = [s("tt1", ["drama"]), s("tt2", ["drama"])]
        let model = MatchDeckModel(rig.services, pool: pool, watched: { [] }, clock: { clock.now })
        await model.load()
        model.discard(pool[0])
        let again = MatchDeckModel(rig.services, pool: pool, watched: { [] }, clock: { clock.now })
        await again.load()
        XCTAssertEqual(again.cards.map(\.imdb), ["tt2"])
        clock.now = clock.now.addingTimeInterval(MatchDeckModel.discardFor + 1)
        let later = MatchDeckModel(rig.services, pool: pool, watched: { [] }, clock: { clock.now })
        await later.load()
        XCTAssertEqual(later.cards.count, 2)
    }
}

/// Lo que ves: la tarjeta pide solo la semana, la pantalla los diez años una vez, y luego solo lo nuevo (guardado en el iPhone).
@MainActor
final class WatchingModelTests: XCTestCase {
    func testLaSemanaYLuegoSoloLoNuevo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let clock = rig.clock
        rig.http.prefix["https://api.trakt.tv/sync/history"] = [["type": "movie", "watched_at": "2025-10-08T20:00:00.000Z",
                                                                 "movie": ["title": "Dune", "runtime": 155, "genres": ["science-fiction"], "ids": ["imdb": "tt1160419"]]]]
        let model = WatchingModel(rig.services, clock: { clock.now })
        await model.load()
        XCTAssertEqual(model.plays.count, 1)
        let calls = rig.http.calls.filter { $0.contains("/sync/history") }.count
        await model.load()
        XCTAssertEqual(rig.http.calls.filter { $0.contains("/sync/history") }.count, calls, "dentro de los 10 minutos no pregunta")
        let again = WatchingModel(rig.services, clock: { clock.now })
        XCTAssertEqual(again.plays.count, 1, "lo traído se guardó en el iPhone")
        XCTAssertTrue(again.loaded)
    }
}
