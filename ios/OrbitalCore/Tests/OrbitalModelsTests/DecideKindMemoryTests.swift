import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Todo · Películas · Series sin volver a barajar (Fernando, 13 nov 2026): ir y volver de tipo regresa los mismos tres;
/// solo «Barajar» o cambiar otro filtro barajan.
@MainActor
final class DecideKindMemoryTests: XCTestCase {
    private func title(_ id: String, kind: String) -> Suggestion {
        var s = Suggestion(kind: kind, imdb: id, title: id, year: 2015, runtime: 90, poster: "", wide: "", reason: .recommended)
        s.genres = ["Drama"]
        return s
    }

    private func pool() -> [Suggestion] {
        (1...12).map { title("tm\($0)", kind: "movie") } + (1...12).map { title("ts\($0)", kind: "series") }
    }

    func testCambiarDeTipoYRegresarDejaLosMismosTres() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: pool())
        await model.quick()
        let all = model.picks.map(\.imdb), chosen = try XCTUnwrap(model.pick?.imdb)
        XCTAssertEqual(all.count, 3)
        await model.setKind("movie")
        let movies = model.picks.map(\.imdb)
        XCTAssertTrue(movies.allSatisfy { $0.hasPrefix("tm") }, "solo películas")
        await model.setKind("series")
        let series = model.picks.map(\.imdb)
        XCTAssertTrue(series.allSatisfy { $0.hasPrefix("ts") }, "solo series")
        await model.setKind("movie")
        XCTAssertEqual(model.picks.map(\.imdb), movies, "Películas otra vez: las mismas tres")
        await model.setKind(nil)
        XCTAssertEqual(model.picks.map(\.imdb), all, "Todo otra vez: las mismas tres")
        XCTAssertEqual(model.pick?.imdb, chosen, "y la misma elegida")
        model.stop()
    }

    func testBarajarYCambiarUnFiltroSiBarajan() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: pool())
        await model.quick()
        await model.setKind("movie")
        let movies = model.picks.map(\.imdb)
        await model.next()   // «Barajar» en Películas
        let shuffled = model.picks.map(\.imdb)
        XCTAssertNotEqual(shuffled, movies, "«Barajar» trae otras")
        await model.setKind(nil)
        await model.setKind("movie")
        XCTAssertEqual(model.picks.map(\.imdb), shuffled, "lo barajado también se recuerda")
        model.minRating = 6
        await model.apply()   // otro filtro: ya no hay memoria de los tipos
        XCTAssertTrue(model.kindMemory.isEmpty, "cambiar un filtro olvida lo recordado por tipo")
        model.stop()
    }
}
