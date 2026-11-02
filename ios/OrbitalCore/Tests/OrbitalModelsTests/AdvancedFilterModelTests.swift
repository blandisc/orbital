import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El cajón del filtro avanzado: «Ver resultados» busca en TMDB sin lo que ya viste, lo elegido y el número de resultados se
/// recuerdan al cerrar la app, «Limpiar» deja tus preferencias, sin red o sin clave de TMDB se dice (sin pedir nada), y los
/// premios salen de los ganadores que trae la app.
@MainActor
final class AdvancedFilterModelTests: XCTestCase {
    let tmdb = "https://api.themoviedb.org/3"

    /// Tres películas en TMDB (la 2 ya la viste) y sus fichas con IMDb.
    func stockTMDB(_ rig: ServicesRig) {
        rig.http.prefix["\(tmdb)/discover/movie"] = ["results": [["id": 1, "vote_average": .double(8.1)], ["id": 2], ["id": 3]], "total_results": 3]
        for id in 1...3 {
            rig.http.prefix["\(tmdb)/movie/\(id)?"] = ["id": .int(id), "title": .string("Película \(id)"), "imdb_id": .string("tt000000\(id)"), "release_date": "2020-05-01"]
        }
    }

    func movies() -> AdvancedFilter { var f = AdvancedFilter(); f.format = .movie; return f }

    func testVerResultadosBuscaSinLoQueYaViste() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        let model = AdvancedFilterModel(rig.services, watched: { ["tt0000002"] })
        model.filter = movies()
        XCTAssertTrue(model.available)
        XCTAssertNil(model.total, "sin buscar aún no hay número")
        await model.search()
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.results.map(\.imdb), ["tt0000001", "tt0000003"], "lo que ya viste no sale")
        XCTAssertEqual(model.results.first?.tmdbRating, 8.1)
        XCTAssertEqual(model.total, 3, "el número que dice la puerta de Buscar")
        XCTAssertEqual(model.count, FilterCount(movies: 3, series: 0))
        let again = AdvancedFilterModel(rig.services, watched: { [] })
        XCTAssertEqual(again.count, model.count, "se recuerda al cerrar la app, con el desglose")
        let asked = rig.http.calls.count
        await model.search()
        XCTAssertEqual(rig.http.calls.count, asked, "el mismo filtro no vuelve a pedir")
    }

    /// Si lo de la primera página ya lo viste, pide las que siguen (antes paraba ahí y la cuadrícula quedaba casi vacía).
    func testSiYaVisteTodaLaPaginaPideLasQueSiguen() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        let model = AdvancedFilterModel(rig.services, watched: { ["tt0000001", "tt0000002", "tt0000003"] })
        model.filter = movies()
        await model.search()
        let pages = rig.http.calls.filter { $0.hasPrefix("\(tmdb)/discover/movie") }.count
        XCTAssertGreaterThan(pages, 1, "siguió buscando títulos que no has visto")
        XCTAssertLessThanOrEqual(pages, 5, "pero con tope")
        XCTAssertFalse(model.isLoading)
    }

    /// Los resultados salen de a poco y en orden (cada uno en cuanto llega su ficha); el que no tiene IMDb se salta, y si
    /// quien recibe dice «basta» (cambió el filtro), no se entrega nada más.
    func testLosResultadosLleganEnOrdenYSePuedenCortar() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        rig.http.prefix["\(tmdb)/movie/2?"] = ["id": 2, "title": "Sin IMDb"]
        let rows = (1...3).map { TmdbRow(kind: "movie", id: $0) }
        var got: [String] = []
        let finished = await ForYou.streamSuggestions(rows, reason: .popular, tmdb: rig.services.tmdb) { batch in
            got += batch.map(\.imdb); return true
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(got, ["tt0000001", "tt0000003"])
        var calls = 0
        let stopped = await ForYou.streamSuggestions(rows, reason: .popular, tmdb: rig.services.tmdb) { _ in calls += 1; return false }
        XCTAssertFalse(stopped)
        XCTAssertEqual(calls, 1, "al decir basta, ya no llega nada")
    }

    func testLoElegidoYElNumeroSeRecuerdanAlVolverAAbrir() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        let model = AdvancedFilterModel(rig.services)
        var f = movies(); f.minRating = 7; f.genres = ["comedia"]
        model.filter = f
        await model.search()
        let again = AdvancedFilterModel(rig.services)
        XCTAssertEqual(again.filter.format, .movie)
        XCTAssertEqual(again.filter.minRating, 7)
        XCTAssertEqual(again.filter.genres, ["comedia"])
        XCTAssertEqual(again.total, 3)
        // Otro filtro: el número viejo ya no aplica (tampoco al volver a abrir).
        again.filter.minRating = 8
        XCTAssertNil(again.total)
        XCTAssertNil(AdvancedFilterModel(rig.services).total)
    }

    func testLimpiarQuitaTodoMenosTusPreferencias() throws {
        let rig = try ServicesRig(tmdbKey: "K")
        let model = AdvancedFilterModel(rig.services)
        var f = movies()
        f.region = "ES"; f.hideWatched = false; f.sort = .rating
        f.genres = ["drama"]; f.minRating = 6; f.awards = ["oscar"]; f.years = 1990...1999
        model.filter = f
        model.clear()
        XCTAssertEqual(model.filter.format, .all)
        XCTAssertTrue(model.filter.genres.isEmpty)
        XCTAssertNil(model.filter.minRating)
        XCTAssertNil(model.filter.years)
        XCTAssertTrue(model.filter.awards.isEmpty)
        XCTAssertEqual(model.filter.region, "ES", "tu país se queda")
        XCTAssertFalse(model.filter.hideWatched, "y si ocultas lo visto")
        XCTAssertEqual(model.filter.sort, .rating, "y el orden")
        model.filter.sort = .letterboxd
        model.clear()
        XCTAssertEqual(model.filter.sort, .popular, "salvo el de Letterboxd, que escondía las series")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.total)
    }

    func testSinRedLaBusquedaFallaSinQuedarseCargando() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        rig.http.offline = true
        let model = AdvancedFilterModel(rig.services)
        model.filter = movies()
        await model.search()
        XCTAssertTrue(model.failed, "la pantalla dice que no se pudo")
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.results.isEmpty)
        // Vuelve la red: «Reintentar» (el mismo filtro) sí busca.
        rig.http.offline = false
        stockTMDB(rig)
        await model.search()
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.results.count, 3)
    }

    func testSinClaveDeTMDBNoSePideNada() async throws {
        let rig = try ServicesRig()
        let model = AdvancedFilterModel(rig.services)
        XCTAssertFalse(model.available, "la pantalla lleva a Ajustes")
        await model.search()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.failed)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("themoviedb") })
    }

    func testLosPremiosSalenDeLosGanadoresSinPedirATMDB() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        let model = AdvancedFilterModel(rig.services)
        var f = movies(); f.awards = ["oscar"]; f.hideWatched = false
        model.filter = f
        await model.search()
        XCTAssertFalse(model.results.isEmpty)
        XCTAssertEqual(model.results.map(\.imdb), f.awardWinners().map(\.imdb))
        XCTAssertEqual(model.total, model.results.count)
        XCTAssertTrue(model.exhausted, "una sola página")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("themoviedb") })
    }

    /// Los premios vienen con la app: sin clave de TMDB, «Óscar» también da sus ganadores (antes, cero resultados).
    func testLosPremiosSalenAunqueNoHayaClaveDeTMDB() async throws {
        let rig = try ServicesRig()
        let model = AdvancedFilterModel(rig.services)
        XCTAssertFalse(model.available)
        var f = movies(); f.awards = ["oscar"]; f.hideWatched = false
        model.filter = f
        await model.search()
        XCTAssertEqual(model.results.map(\.imdb), f.awardWinners().map(\.imdb))
        XCTAssertFalse(model.results.isEmpty)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("themoviedb") })
    }

    /// Con «Calificación en Letterboxd», cada película se pregunta ahí: las que no llegan no salen y la página va en su orden.
    func testConLetterboxdSePreguntaYSeOrdena() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        func page(_ avg: String) -> Data { Data(#"<meta property="og:url" content="https://letterboxd.com/film/x/" /><meta name="twitter:data2" content="\#(avg) out of 5" /><body data-tmdb-id="1">"#.utf8) }
        rig.http.raw["https://letterboxd.com/imdb/tt0000001/"] = page("3.2")
        rig.http.raw["https://letterboxd.com/imdb/tt0000002/"] = page("4.6")
        rig.http.raw["https://letterboxd.com/imdb/tt0000003/"] = page("4.1")
        let model = AdvancedFilterModel(rig.services, watched: { [] })
        var f = movies(); f.minLetterboxd = 4; f.sort = .letterboxd
        model.filter = f
        await model.search()
        XCTAssertEqual(model.results.map(\.imdb), ["tt0000002", "tt0000003"], "sin la de 3.2 y en orden de Letterboxd")
        XCTAssertEqual(model.results.first?.letterboxdRating, 4.6)
    }

    /// «Series» con Letterboxd puesto (de antes, o el orden «Mejor calificadas en Letterboxd», que se queda al limpiar) sí
    /// busca: antes no pedía nada y salía «Nada con esos filtros» (Fernando, 1 nov 2026: Animación, 7 o más, cero).
    func testSeriesConLetterboxdSiBusca() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        rig.http.prefix["\(tmdb)/discover/tv"] = ["results": [["id": 7, "vote_average": .double(8.4)]], "total_results": 1]
        rig.http.prefix["\(tmdb)/tv/7?"] = ["id": 7, "name": "Una serie", "external_ids": ["imdb_id": "tt0000007"], "first_air_date": "2019-01-01"]
        let model = AdvancedFilterModel(rig.services, watched: { [] })
        var f = AdvancedFilter(); f.format = .series; f.genres = ["animacion"]; f.minRating = 7; f.minLetterboxd = 2; f.sort = .letterboxd
        model.filter = f
        await model.search()
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.results.map(\.imdb), ["tt0000007"])
        XCTAssertFalse(rig.http.calls.contains { $0.contains("letterboxd.com") }, "en series no se pregunta a Letterboxd")
    }

    /// «Todo»: el número se parte en películas y series, cada uno con lo que dice TMDB de su búsqueda.
    func testElNumeroSeParteEnPeliculasYSeries() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        rig.http.prefix["\(tmdb)/discover/tv"] = ["results": [], "total_results": 380]
        rig.http.prefix["\(tmdb)/discover/movie"] = ["results": [["id": 1]], "total_results": 860]
        let model = AdvancedFilterModel(rig.services, watched: { [] })
        var f = AdvancedFilter(); f.genres = ["comedia"]
        model.filter = f
        await model.search()
        XCTAssertEqual(model.count, FilterCount(movies: 860, series: 380))
        XCTAssertEqual(model.total, 1240)
    }

    /// Si Letterboxd no contesta, se dice: antes se tiraban todas como de 0 estrellas y salía «Nada con esos filtros».
    func testLetterboxdQueNoContestaSeDice() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        stockTMDB(rig)
        let model = AdvancedFilterModel(rig.services, watched: { [] })
        var f = movies(); f.minLetterboxd = 3
        model.filter = f
        await model.search()
        XCTAssertTrue(model.letterboxdDown)
        XCTAssertTrue(model.failed)
        XCTAssertTrue(model.results.isEmpty)
    }
}
