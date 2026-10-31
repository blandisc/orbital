import XCTest
@testable import OrbitalCore

/// El filtro avanzado traducido a TMDB /discover: cada elección con su parámetro, por tipo.
final class AdvancedFilterTests: XCTestCase {
    func dict(_ p: [(String, String)]) -> [String: String] { Dictionary(p, uniquingKeysWith: { $1 }) }

    func testSinFiltrosEsLoPopularConUnPisoDeVotos() {
        let f = AdvancedFilter()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f.kinds, ["movie", "series"])
        let p = dict(f.params(kind: "movie"))
        XCTAssertEqual(p["sort_by"], "popularity.desc")
        XCTAssertEqual(p["vote_count.gte"], "100")
        XCTAssertNil(p["with_genres"])
    }

    func testDondeVerlaYElOrden() {
        var f = AdvancedFilter()
        f.providers = [337, 8]; f.region = "MX"; f.sort = .newest; f.today = "2026-10-30"
        XCTAssertEqual(f.activeCount, 1, "las plataformas cuentan; el orden no")
        let m = dict(f.params(kind: "movie"))
        XCTAssertEqual(m["with_watch_providers"], "8|337")
        XCTAssertEqual(m["watch_region"], "MX")
        XCTAssertEqual(m["with_watch_monetization_types"], "flatrate")
        XCTAssertEqual(m["sort_by"], "primary_release_date.desc")
        XCTAssertEqual(m["primary_release_date.lte"], "2026-10-30", "lo más nuevo, sin lo que aún no se estrena")
        f.sort = .rating
        XCTAssertEqual(dict(f.params(kind: "series"))["sort_by"], "vote_average.desc")
        XCTAssertEqual(dict(f.params(kind: "series"))["vote_count.gte"], "100", "mejor calificadas, pero con un piso de votos")
    }

    func testSeGuardaYSeRecupera() throws {
        var f = AdvancedFilter()
        f.genres = ["terror"]; f.years = 1980...1989; f.providers = [8]; f.hideWatched = false; f.sort = .rating
        let back = try JSONDecoder().decode(AdvancedFilter.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }

    func testGeneroEpocaYTiempoEnPeliculasYSeries() {
        var f = AdvancedFilter()
        f.genres = ["terror", "comedia"]; f.excluded = ["animacion"]
        f.years = 1990...1999; f.length = .short
        let m = dict(f.params(kind: "movie"))
        XCTAssertEqual(m["with_genres"], "27|35", "cualquiera de los dos")
        XCTAssertEqual(m["without_genres"], "16")
        XCTAssertEqual(m["primary_release_date.gte"], "1990-01-01")
        XCTAssertEqual(m["primary_release_date.lte"], "1999-12-31")
        XCTAssertEqual(m["with_runtime.lte"], "95")
        let s = dict(f.params(kind: "series"))
        XCTAssertEqual(s["with_genres"], "35", "Terror no tiene género de series en TMDB")
        XCTAssertEqual(s["first_air_date.gte"], "1990-01-01")
        XCTAssertEqual(s["with_runtime.lte"], "30", "en series se mide el capítulo")
        XCTAssertEqual(f.activeCount, 3)
    }

    func testSeriesEnEmisionYTerminadasSoloConFormatoSeries() {
        var f = AdvancedFilter()
        f.format = .series; f.seriesStatus = .airing
        XCTAssertEqual(f.kinds, ["series"])
        XCTAssertEqual(dict(f.params(kind: "series"))["with_status"], "0|2")
        f.seriesStatus = .ended
        XCTAssertEqual(dict(f.params(kind: "series"))["with_status"], "3|4")
        f.format = .all
        XCTAssertNil(dict(f.params(kind: "series"))["with_status"], "con «Todo» no aplica")
    }

    func testQueTanConocida() {
        var f = AdvancedFilter()
        f.fame = .gems
        let g = dict(f.params(kind: "movie"))
        XCTAssertEqual(g["vote_count.lte"], "2500")
        XCTAssertEqual(g["vote_average.gte"], "7.2")
        XCTAssertEqual(g["sort_by"], "vote_average.desc")
        f.fame = .blockbusters
        XCTAssertEqual(f.kinds, ["movie"], "las taquilleras son películas")
        XCTAssertEqual(dict(f.params(kind: "movie"))["sort_by"], "revenue.desc")
        f.fame = .niche
        XCTAssertEqual(dict(f.params(kind: "movie"))["vote_count.lte"], "300")
        f.minRating = 8
        f.fame = .gems
        XCTAssertEqual(dict(f.params(kind: "movie"))["vote_average.gte"], "8.0", "gana la calificación más alta")
    }

    func testOrigenYEstudios() {
        var f = AdvancedFilter()
        f.countries = ["MX", "ES"]; f.studios = [41077, 3]
        XCTAssertEqual(dict(f.params(kind: "movie"))["with_origin_country"], "ES|MX")
        XCTAssertEqual(dict(f.params(kind: "movie"))["with_companies"], "3|41077")
        XCTAssertNil(dict(f.params(kind: "series"))["with_companies"])
    }

    func testDiscoverIntercalaPeliculasYSeries() async throws {
        let http = FakeHTTP()
        let tmdb = Tmdb(http: http, key: "K")
        for (kind, ids) in [("movie", [1, 2, 3]), ("tv", [10, 20])] {
            http.prefix["https://api.themoviedb.org/3/discover/\(kind)"] = ["results": .array(ids.map { ["id": .int($0)] })]
        }
        let rows = try await tmdb.discover(AdvancedFilter())
        XCTAssertEqual(rows.map(\.id), [1, 10, 2, 20, 3])
    }

    func testGenerosSoloDePeliculasYLoRecienEstrenado() {
        var f = AdvancedFilter()
        f.genres = ["terror"]
        XCTAssertEqual(f.kinds, ["movie"], "Terror no existe en series: con «Todo» no salen series de otro género")
        f.genres = ["terror", "comedia"]
        XCTAssertEqual(f.kinds, ["movie", "series"])
        XCTAssertEqual(f.moviesOnlyGenres.map(\.slug), ["terror"])
        f.currentYear = 2026; f.years = 2026...2026
        XCTAssertEqual(dict(f.params(kind: "movie"))["vote_count.gte"], "30", "lo de este año aún tiene pocos votos")
    }

    func testQueAcabeAntesDeUnaHora() {
        var f = AdvancedFilter()
        f.length = .before; f.endsBy = 23.5; f.nowMinute = 21 * 60
        XCTAssertEqual(f.minutesLeft, 150)
        XCTAssertEqual(dict(f.params(kind: "movie"))["with_runtime.lte"], "150")
        f.endsBy = 1; f.nowMinute = 23 * 60
        XCTAssertEqual(f.minutesLeft, 120, "la 1 am después de las 11 pm es la de mañana")
        f.nowMinute = 99
        XCTAssertNotEqual(f, f.withoutClock)
        XCTAssertEqual(f.withoutClock, { var g = f; g.nowMinute = 5; return g.withoutClock }(), "la hora no cambia la búsqueda")
    }

    func testRepartidoPorDecadas() async throws {
        var f = AdvancedFilter()
        f.currentYear = 2026; f.years = 1985...2004
        XCTAssertEqual(f.decades, [1985...1989, 1990...1999, 2000...2004])
        f.years = nil
        XCTAssertEqual(f.decades.first, 1950...1959)
        XCTAssertEqual(f.decades.last, 2020...2026)
        f.spread = true; f.format = .movie; f.years = 1990...2009
        XCTAssertEqual(f.activeCount, 2)
        let http = FakeHTTP()
        let tmdb = Tmdb(http: http, key: "K")
        http.prefix["https://api.themoviedb.org/3/discover/movie"] = ["results": .array([["id": .int(7)]]), "total_results": .int(40)]
        let found = try await tmdb.discoverCounting(f)
        XCTAssertEqual(found.rows.count, 2, "una búsqueda por década")
        XCTAssertEqual(found.total, 80)
        XCTAssertEqual(dict(f.params(kind: "movie", years: 1990...1999))["primary_release_date.lte"], "1999-12-31")
    }

    func testPremiosSonSusGanadores() {
        var f = AdvancedFilter()
        f.awards = ["oscar"]
        XCTAssertEqual(f.activeCount, 1)
        let all = f.awardWinners()
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.allSatisfy { $0.kind == "movie" })
        f.years = 2010...2019
        XCTAssertTrue(f.awardWinners().allSatisfy { (2010...2019).contains($0.year ?? 0) })
        f.format = .series
        XCTAssertTrue(f.awardWinners().isEmpty, "el Óscar no tiene series")
        f.format = .all; f.awards = ["emmy"]; f.years = nil
        XCTAssertTrue(f.awardWinners().allSatisfy { $0.kind == "series" })
        let first = f.awardWinners()[0].imdb
        XCTAssertFalse(f.awardWinners(hiding: [first]).contains { $0.imdb == first }, "lo que ya viste no sale")
    }

    func testLoGuardadoDeAntesSeLeeIgual() throws {
        let old = #"{"format":"movie","seriesStatus":"any","genres":["terror"],"excluded":[],"length":"short","fame":"any","countries":[],"studios":[],"providers":[],"region":"MX","hideWatched":true,"sort":"popular"}"#
        let f = try JSONDecoder().decode(AdvancedFilter.self, from: Data(old.utf8))
        XCTAssertEqual(f.format, .movie); XCTAssertEqual(f.genres, ["terror"]); XCTAssertEqual(f.length, .short)
        XCTAssertTrue(f.awards.isEmpty); XCTAssertFalse(f.spread)
        var g = f; g.awards = ["palm"]; g.spread = true; g.years = 1990...1999
        let back = try JSONDecoder().decode(AdvancedFilter.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back.withoutClock, g.withoutClock)
    }
}
