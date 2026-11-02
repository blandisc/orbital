import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Corte D de «Desacoplar Stremio»: lo popular de Buscar y Para ti sale de Trakt («En tendencia»), y Buscar le pregunta
/// primero a Trakt (Cinemeta queda de respaldo).
@MainActor
final class TraktPublicListsTests: XCTestCase {
    /// Lo que contesta `/movies/trending` y `/shows/trending` (nil: ese tipo no contesta).
    static func trending(_ rig: ServicesRig, series: [(String, String, Int)]?, movies: [(String, String, Int)]?, limit: Int = 30, genres: String? = nil) {
        func rows(_ items: [(String, String, Int)], key: String) -> JSON {
            .array(items.map { id, title, year in
                .object(["watchers": 10, key: .object(["title": .string(title), "year": .int(year), "runtime": 155, "ids": .object(["trakt": 1, "imdb": .string(id)])])])
            })
        }
        let extra = genres.map { "&genres=\($0)" } ?? ""
        if let series { rig.http.json["https://api.trakt.tv/shows/trending?limit=\(limit)&extended=full\(extra)"] = rows(series, key: "show") }
        if let movies { rig.http.json["https://api.trakt.tv/movies/trending?limit=\(limit)&extended=full\(extra)"] = rows(movies, key: "movie") }
    }

    func testPopularTodayComesFromTraktTrendingAlternatingKinds() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        Self.trending(rig, series: [("tt0386676", "The Office", 2005)], movies: [("tt1160419", "Dune", 2021), ("tt0816692", "Interstellar", 2014)], limit: 50)
        let model = CatalogModel(rig.services)
        await model.load()
        XCTAssertNil(model.degraded)
        XCTAssertEqual(model.popular.map(\.metaID), ["tt1160419", "tt0386676", "tt0816692"], "películas y series alternadas")
        XCTAssertEqual(model.popular.first?.poster, String(format: ForYou.metahubPoster, "tt1160419"))
        XCTAssertEqual(model.popular.first?.year, "2021")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("cinemeta") }, "lo popular ya no sale de Cinemeta")
    }

    func testPopularTodayKeepsTheSavedCopyWhenTraktDoesNotAnswer() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        Self.trending(rig, series: [("tt0386676", "The Office", 2005)], movies: [("tt1160419", "Dune", 2021)], limit: 50)
        await CatalogModel(rig.services).load()
        rig.http.offline = true
        let again = CatalogModel(rig.services)
        await again.load()
        XCTAssertEqual(again.popular.map(\.metaID), ["tt1160419", "tt0386676"], "la última copia")
        XCTAssertNil(again.degraded, "con copia no hay aviso")
        let empty = CatalogModel(try ServicesRig(traktClientID: "cid").services)
        await empty.load()
        XCTAssertEqual(empty.degraded, .down(.trakt), "con internet, es Trakt el que no contesta (no «revisa tu conexión»)")
    }

    /// Modo degradado: la causa de verdad de que no haya lo popular.
    func testPopularSaysWhyItIsMissing() async throws {
        let unlinked = CatalogModel(try ServicesRig().services)
        await unlinked.load()
        XCTAssertEqual(unlinked.degraded, .notConnected(.trakt), "sin Trakt: conectarlo, no revisar la conexión")
        let rig = try ServicesRig(traktClientID: "cid")
        rig.services.isOnline = { false }
        let offline = CatalogModel(rig.services)
        await offline.load()
        XCTAssertEqual(offline.degraded, .offline)
    }

    func testGenreUsesTrendingAndTopsUpWithRecentPopular() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        Self.trending(rig, series: [], movies: [("tt1", "A", 2025)], genres: "science-fiction")
        let year = Calendar(identifier: .gregorian).component(.year, from: rig.clock.now)
        let popular: JSON = .array([.object(["title": "A", "year": 2025, "ids": .object(["trakt": 1, "imdb": "tt1"])]),
                                    .object(["title": "B", "year": 2024, "ids": .object(["trakt": 2, "imdb": "tt2"])])])
        rig.http.json["https://api.trakt.tv/movies/popular?limit=30&extended=full&years=\(year - 2)-\(year)&genres=science-fiction"] = popular
        let model = CatalogModel(rig.services)
        var last: [CatalogItem] = []
        await model.genre("Sci-Fi") { last = $0 }
        XCTAssertEqual(last.map(\.metaID), ["tt1", "tt2"], "lo de tendencia primero; lo popular reciente completa, sin repetir")
    }

    /// Con clave de TMDB, «Por género» es lo popular del género de cualquier año (TMDB), no solo lo de esta semana de Trakt;
    /// Biografía (que TMDB no tiene) sigue en Trakt.
    func testGenreComesFromTMDBWhenThereIsAKey() async throws {
        let rig = try ServicesRig(traktClientID: "cid", tmdbKey: "K")
        let tmdb = "https://api.themoviedb.org/3"
        rig.http.prefix["\(tmdb)/discover/movie"] = ["results": [["id": 238]], "total_results": 1]
        rig.http.prefix["\(tmdb)/discover/tv"] = ["results": [], "total_results": 0]
        rig.http.prefix["\(tmdb)/movie/238?"] = ["id": 238, "title": "El padrino", "imdb_id": "tt0068646", "release_date": "1972-03-14"]
        let model = CatalogModel(rig.services)
        var last: [CatalogItem] = []
        await model.genre("Drama") { last = $0 }
        XCTAssertEqual(last.map(\.metaID), ["tt0068646"], "un clásico del género, de TMDB")
        XCTAssertTrue(rig.http.calls.contains { $0.contains("/discover/movie") && $0.contains("with_genres=18") })
        XCTAssertFalse(rig.http.calls.contains { $0.contains("trakt.tv/movies/trending") }, "con TMDB no se pregunta a Trakt")
        XCTAssertNil(CatalogModel.tmdbGenres["Biography"], "Biografía no es género de TMDB: Trakt")
    }

    /// Se pregunta a los dos a la vez: manda el orden de Cinemeta (lo más conocido) y Trakt suma lo que falte, sin repetir.
    func testSearchAsksBothAndCinemetaOrderLeads() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        rig.http.json["https://api.trakt.tv/search/movie,show?query=dune&limit=50&extended=full"] = .array([
            .object(["type": "show", "show": .object(["title": "Dune: Prophecy", "year": 2024, "ids": .object(["trakt": 2, "imdb": "tt10466872"])])]),
            .object(["type": "movie", "movie": .object(["title": "Dune", "year": 2021, "ids": .object(["trakt": 1, "imdb": "tt1160419"])])])])
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=dune.json"] = ["metas": [["id": "tt1160419", "type": "movie", "name": "Dune"],
                                                                                                      ["id": "tt0087182", "type": "movie", "name": "Dune"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=dune.json"] = ["metas": []]
        let search = SearchModel(rig.services)
        await search.search("dune")
        XCTAssertEqual(search.results.map(\.metaID), ["tt1160419", "tt0087182", "tt10466872"], "Cinemeta en su orden y luego lo que solo trajo Trakt")
        XCTAssertEqual(search.results.map(\.kind), ["movie", "movie", "series"])
    }

    /// Si una fuente falla, lo que llegó se enseña pero no se recuerda: al volver a buscar se pregunta otra vez.
    func testIncompleteSearchIsNotRemembered() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        rig.http.json["https://api.trakt.tv/search/movie,show?query=fargo&limit=50&extended=full"] = .array([
            .object(["type": "show", "show": .object(["title": "Fargo", "year": 2014, "ids": .object(["trakt": 3, "imdb": "tt2802850"])])])])
        let search = SearchModel(rig.services)
        await search.search("fargo")
        XCTAssertEqual(search.results.map(\.metaID), ["tt2802850"], "Cinemeta no contestó: lo de Trakt")
        let asked = rig.http.calls.filter { $0.contains("cinemeta") }.count
        await search.search("fargo")
        XCTAssertGreaterThan(rig.http.calls.filter { $0.contains("cinemeta") }.count, asked, "estaba incompleta: se vuelve a preguntar")
    }

    func testSearchFallsBackToCinemetaWhenTraktFindsNothingOrFails() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        rig.http.json["https://api.trakt.tv/search/movie,show?query=ofice&limit=50&extended=full"] = .array([])
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=ofice.json"] = ["metas": [["id": "tt0386676", "type": "series", "name": "The Office"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=ofice.json"] = ["metas": []]
        let search = SearchModel(rig.services)
        await search.search("ofice")
        XCTAssertEqual(search.results.map(\.metaID), ["tt0386676"], "Trakt no encontró nada: lo de Cinemeta")
        XCTAssertNil(search.error)

        rig.http.offline = true
        await search.search("nada")
        XCTAssertEqual(search.error, "No pude buscar. Revisa tu conexión.")
    }
}
