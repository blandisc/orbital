import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Colecciones (Para ti › Listas): Mi lista con lo último que agregaste primero, los pósters de «Por año» (de los premios sin
/// pedir nada; si Trakt falla, se vuelve a pedir), el logo de cada estudio guardado en el iPhone, lo que ya viste pedido una
/// vez, y las calificaciones de IMDb recordadas.
@MainActor
final class CollectionsModelTests: XCTestCase {
    func add(_ rig: ServicesRig, _ id: String, kind: String, listed: Double?, poster: String? = nil) {
        rig.services.library.update(id, make: { LibraryEntry(metaID: id, kind: kind, name: "Título \(id)") }) { e in
            e.inList = listed != nil; e.listedAt = listed; e.poster = poster
        }
    }

    func testMiListaSoloPeliculasYSeriesYLoUltimoQueAgregastePrimero() async throws {
        let rig = try ServicesRig()
        add(rig, "tt1", kind: "movie", listed: 100, poster: "https://p/1.jpg")
        add(rig, "tt2", kind: "series", listed: 300)
        add(rig, "tt3", kind: "movie", listed: nil)              // la viste, pero no está en tu lista
        add(rig, "tv:canal", kind: "channel", listed: 200)        // ni películas ni series
        let model = CollectionsModel(rig.services)
        await model.loadMyList()
        XCTAssertEqual(model.myList.map(\.imdb), ["tt2", "tt1"])
        XCTAssertEqual(model.myList.last?.poster, "https://p/1.jpg", "el póster que ya tenías")
        model.resetAccount()
        XCTAssertTrue(model.myList.isEmpty, "otra cuenta: nada de la anterior se queda")
    }

    func testSinTraktLosPosteresDeUnAnoSalenDeLosPremiosSinPedirNada() async throws {
        let rig = try ServicesRig()
        let model = CollectionsModel(rig.services)
        let year = try XCTUnwrap(model.years.first { y in model.awards.contains { $0.kind == "movie" && $0.winners.contains { $0.year == y } } })
        await model.loadYearPosters(year)
        let posters = try XCTUnwrap(model.yearPosters[year])
        XCTAssertFalse(posters.isEmpty)
        XCTAssertLessThanOrEqual(posters.count, 4)
        XCTAssertEqual(Set(posters).count, posters.count, "sin repetir")
        XCTAssertFalse(model.traktLinked)
        let watched = await model.watchedIDs()
        XCTAssertTrue(watched.isEmpty, "sin Trakt, «Ocultar lo que ya vi» no oculta nada")
        let popular = await model.items(year: year, kind: "movie")
        XCTAssertTrue(popular.isEmpty)
        XCTAssertTrue(rig.http.calls.isEmpty, "sin Trakt no se pide nada: \(rig.http.calls)")
    }

    func testSiTraktFallaElAnoSeVuelveAPedir() async throws {
        let rig = try ServicesRig(traktClientID: "CID")
        let model = CollectionsModel(rig.services)
        let year = try XCTUnwrap(model.years.first { y in !model.awards.contains { $0.kind == "movie" && $0.winners.contains { $0.year == y } } },
                                 "hace falta un año sin ganadoras")
        rig.http.offline = true
        await model.loadYearPosters(year)
        XCTAssertNil(model.yearPosters[year], "no se guarda el vacío")
        rig.http.offline = false
        rig.http.prefix["https://api.trakt.tv/movies/popular"] = [
            ["title": "Una", "year": .int(year), "ids": ["imdb": "tt0000101", "trakt": 1]],
            ["title": "Otra", "year": .int(year), "ids": ["imdb": "tt0000102", "trakt": 2]],
        ]
        await model.loadYearPosters(year)
        XCTAssertEqual(model.yearPosters[year], [String(format: ForYou.metahubPoster, "tt0000101"), String(format: ForYou.metahubPoster, "tt0000102")])
    }

    func testElLogoDeUnEstudioSeGuardaEnElIPhone() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        let studio = try XCTUnwrap(Tmdb.studios.first).id
        rig.http.prefix["https://api.themoviedb.org/3/company/\(studio)?"] = ["id": .int(studio), "logo_path": "/logo.png"]
        let model = CollectionsModel(rig.services)
        await model.loadStudioLogo(studio)
        let logo = try XCTUnwrap(model.studioLogos[studio])
        XCTAssertTrue(logo.hasSuffix("/logo.png"), logo)
        // Otra vez (otra sesión, sin red): sale de lo guardado.
        rig.http.offline = true
        let again = CollectionsModel(rig.services)
        await again.loadStudioLogo(studio)
        XCTAssertEqual(again.studioLogos[studio], logo)
    }

    func testLoQueYaVisteSePideUnaVezHastaQueVesAlgo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["https://api.trakt.tv/sync/watched/movies"] = [["movie": ["title": "Dune", "ids": ["imdb": "tt1160419"]]]]
        rig.http.json["https://api.trakt.tv/sync/watched/shows?extended=noseasons"] = [["show": ["title": "The Office", "ids": ["imdb": "tt0386676"]]]]
        let model = CollectionsModel(rig.services)
        let first = await model.watchedIDs()
        XCTAssertEqual(first, ["tt1160419", "tt0386676"])
        let asked = rig.http.calls.filter { $0.contains("/sync/watched/") }.count
        _ = await model.watchedIDs()
        XCTAssertEqual(rig.http.calls.filter { $0.contains("/sync/watched/") }.count, asked, "la segunda vez, de lo recordado")
        model.forgetWatched()
        _ = await model.watchedIDs()
        XCTAssertGreaterThan(rig.http.calls.filter { $0.contains("/sync/watched/") }.count, asked, "viste algo: se vuelve a preguntar")
    }

    func testLasCalificacionesDeIMDbSeRecuerdanYLasQueNoTienenNoSalen() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://v3-cinemeta.strem.io/meta/movie/tt0000001.json"] = ["meta": ["id": "tt0000001", "type": "movie", "name": "Uno", "imdbRating": "7.8"]]
        rig.http.json["https://v3-cinemeta.strem.io/meta/movie/tt0000002.json"] = ["meta": ["id": "tt0000002", "type": "movie", "name": "Dos"]]
        let model = CollectionsModel(rig.services)
        let ratings = await model.imdbRatings([("movie", "tt0000001"), ("movie", "tt0000002"), ("movie", "tt0000001")])
        XCTAssertEqual(ratings, ["tt0000001": 7.8], "sin calificación no sale")
        let asked = rig.http.calls.count
        let again = await model.imdbRatings([("movie", "tt0000001"), ("movie", "tt0000002")])
        XCTAssertEqual(again, ratings)
        XCTAssertEqual(rig.http.calls.count, asked, "lo ya pedido no se vuelve a pedir")
    }
}
