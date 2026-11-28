import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Elegir varios (G3-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»): un solo envío a Trakt por lista, no uno por título.
@MainActor
final class SavedBatchTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func movie(_ imdb: String) -> Suggestion { Suggestion(art: imdb, kind: "movie", title: imdb, year: nil, reason: .inWatchlist) }
    func show(_ imdb: String) -> Suggestion { Suggestion(art: imdb, kind: "series", title: imdb, year: nil, reason: .inWatchlist) }

    func testQuitarVariosDeMiListaEsUnSoloEnvio() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/sync/watchlist/remove"] = ["deleted": ["movies": 2]]
        let model = SavedModel(rig.services)
        await model.setMany([movie("tt0000001"), movie("tt0000002"), show("tt0000003")], in: SavedModel.watchlist, add: false)
        let bodies = rig.http.bodies("\(api)/sync/watchlist/remove")
        XCTAssertEqual(bodies.count, 1, "un solo envío")
        let body = try XCTUnwrap(bodies.first.flatMap(JSON.parse))
        XCTAssertEqual(body["movies"]?.array?.count, 2)
        XCTAssertEqual(body["shows"]?.array?.count, 1)
        XCTAssertTrue(rig.services.traktOutbox.pending.isEmpty)
    }

    func testSinInternetEsperanYLleganJuntas() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/me/lists/42/items"] = ["added": ["movies": 3]]
        rig.http.offline = true
        let model = SavedModel(rig.services)
        await model.setMany([movie("tt0000001"), movie("tt0000002"), movie("tt0000003")], in: "list:42", add: true)
        XCTAssertEqual(rig.services.traktOutbox.pending.count, 3, "esperan")
        rig.http.offline = false
        let sent = await rig.services.traktOutbox.flush(rig.services.trakt)
        XCTAssertEqual(sent, 3)
        XCTAssertEqual(rig.http.bodies("\(api)/users/me/lists/42/items").count, 1, "llegan en un solo envío")
    }

    func testLaBarraOfreceLoQueTieneSentidoEnCadaLugar() {
        XCTAssertEqual(SavedModel.batchActions(listID: "watchlist", pile: nil), [.watched, .drop, .moveToList, .remove])
        XCTAssertEqual(SavedModel.batchActions(listID: nil, pile: .watched), [.toWatchlist, .moveToList], "en Vistas no se quita: borraría la fecha")
        XCTAssertEqual(SavedModel.batchActions(listID: nil, pile: .dropped), [.resume, .toWatchlist])
    }

    func testDejarVariasSeriesEsUnEnvioPorSeccion() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        for path in ["calendar", "progress_watched", "dropped"] { rig.http.json["\(api)/users/hidden/\(path)"] = ["added": ["shows": 2]] }
        let follow = FollowModel(rig.services)
        let problem = await follow.hide(["tt0000001", "tt0000002"])
        XCTAssertNil(problem)
        XCTAssertEqual(follow.hidden, ["tt0000001", "tt0000002"])
        XCTAssertEqual(rig.http.bodies("\(api)/users/hidden/dropped").count, 1)
        XCTAssertEqual(rig.http.bodies("\(api)/users/hidden/dropped").first.flatMap(JSON.parse)?["shows"]?.array?.count, 2)
    }

    /// «Vistas» con una película que ya habías visto: no suma otra vista en Trakt (revisión del 27 nov 2026: su «Deshacer»
    /// borraba de Trakt todas sus vistas).
    func testMarcarVistaUnaYaVistaNoSumaOtra() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
        let model = SavedModel(rig.services)
        await model.markMoviesWatched([movie("tt0000001")])
        let marks = { rig.http.calls.filter { $0.contains("cinemeta") }.count }   // cada vista marcada se pide a Cinemeta
        let first = marks()
        XCTAssertGreaterThan(first, 0, "la primera sí llega a Trakt")
        XCTAssertEqual(model.state(of: movie("tt0000001")), .watched)
        await model.markMoviesWatched([movie("tt0000001")])
        XCTAssertEqual(marks(), first, "ya vista: no se marca otra vez")
    }

    /// La cuenta de una lista sube solo con lo que llega a Trakt (un título sin id de IMDb no se manda ni cuenta).
    func testLaCuentaDeUnaListaSoloSumaLoQueSeManda() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        let model = SavedModel(rig.services)
        model.listCounts["list:42"] = 5
        let local = Suggestion(art: "od:abc", kind: "movie", title: "Video casero", year: nil, reason: .inWatchlist)
        await model.setMany([movie("tt0000001"), local], in: "list:42", add: true)
        XCTAssertEqual(model.listCounts["list:42"], 6)
    }
}

