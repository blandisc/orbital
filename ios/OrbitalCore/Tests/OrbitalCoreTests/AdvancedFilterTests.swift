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
}
