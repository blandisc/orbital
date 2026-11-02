import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Decide por mí con los filtros que tenía solo el avanzado (Fernando, 2 nov 2026): Letterboxd en Calificación, «Qué tan
/// conocida» y Premios, resueltos sobre tus listas.
@MainActor
final class DecideNewFiltersTests: XCTestCase {
    private func item(_ id: String, kind: String = "movie") -> Suggestion {
        var s = Suggestion(kind: kind, imdb: id, title: id, year: 2015, runtime: 90, poster: "", wide: "", reason: .recommended)
        s.genres = ["Drama"]
        return s
    }

    func testPremiosSonSusGanadores() throws {
        let rig = try ServicesRig()
        let winner = try XCTUnwrap(Awards.all.first { $0.id == "oscar" }?.winners.first?.imdb)
        let model = DecideModel(rig.services, pool: [item(winner), item("tt0000001")])
        model.time = .long
        XCTAssertEqual(model.count(), 2)
        model.awards = ["oscar"]
        XCTAssertEqual(model.count(), 1, "solo la ganadora del Óscar")
        XCTAssertEqual(model.moreFilters, 1)
        model.awards = ["emmy"]
        XCTAssertEqual(model.relaxations().first?.relax, .awards, "ninguna: quitar el premio")
        model.stop()
    }

    func testQueTanConocidaConLosVotosDeTMDB() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        let tmdb = "https://api.themoviedb.org/3/find"
        rig.http.prefix["\(tmdb)/tt1?"] = ["movie_results": [["vote_average": .double(7.6), "vote_count": 1200]]]    // joya: buena y poco votada
        rig.http.prefix["\(tmdb)/tt2?"] = ["movie_results": [["vote_average": .double(8.1), "vote_count": 25000]]]   // de siempre
        rig.http.prefix["\(tmdb)/tt3?"] = ["movie_results": [["vote_average": .double(5.9), "vote_count": 40]]]
        let model = DecideModel(rig.services, pool: [item("tt1"), item("tt2"), item("tt3")])
        model.time = .long
        model.fame = .gems
        XCTAssertFalse(model.fameReady)
        XCTAssertEqual(model.count(), 0, "aún no se sabe")
        model.fetchFameInBackground()
        await model.statsTMDB?.value
        XCTAssertTrue(model.fameReady)
        XCTAssertEqual(model.count(), 1, "solo la joya")
        XCTAssertEqual(model.count { $0.fame = .classics }, 1)
        XCTAssertEqual(model.count { $0.fame = .blockbusters }, 1)
        model.stop()
    }

    func testLetterboxdDejaSoloPeliculasSalvoConSeries() async throws {
        let rig = try ServicesRig()
        func page(_ avg: String) -> Data { Data(#"<meta property="og:url" content="https://letterboxd.com/film/x/" /><meta name="twitter:data2" content="\#(avg) out of 5" /><body data-tmdb-id="1">"#.utf8) }
        rig.http.raw["https://letterboxd.com/imdb/tt1/"] = page("4.2")
        rig.http.raw["https://letterboxd.com/imdb/tt2/"] = page("3.1")
        let model = DecideModel(rig.services, pool: [item("tt1"), item("tt2"), item("tt9", kind: "series")])
        model.time = .long
        model.minLetterboxd = 4
        model.fetchLetterboxdInBackground()
        await model.ratingLetterboxd?.value
        XCTAssertTrue(model.letterboxdReady)
        XCTAssertEqual(model.count(), 1, "la de 4.2; la serie no sale (Letterboxd no califica series)")
        XCTAssertEqual(model.count { $0.kind = "series" }, 1, "con «Series», Letterboxd no cuenta")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("tt9") }, "a Letterboxd no se le pregunta por series")
        model.stop()
    }

    func testFamaComparteLosRangosDelFiltroAvanzado() {
        XCTAssertTrue(AdvancedFilter.Fame.gems.matches(average: 7.4, votes: 900, series: false))
        XCTAssertFalse(AdvancedFilter.Fame.gems.matches(average: 7.4, votes: 9000, series: false), "con muchos votos ya no es joya oculta")
        XCTAssertTrue(AdvancedFilter.Fame.classics.matches(average: 7.6, votes: 900, series: true), "en series el piso es más bajo")
        XCTAssertFalse(AdvancedFilter.Fame.classics.matches(average: 7.6, votes: 900, series: false))
        XCTAssertTrue(AdvancedFilter.Fame.niche.matches(average: 6.8, votes: 120, series: false))
    }
}
