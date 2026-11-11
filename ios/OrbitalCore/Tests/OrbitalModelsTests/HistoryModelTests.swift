import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// F5 (revisión del 10 nov 2026): el Historial y «Tus vistas» salieron de las pantallas a `HistoryModel` y `ViewingsModel`.
/// Aquí, lo que la pasada de pulido de la ola 3 (0474ae0d) arregló a mano, para que no regrese sin que una prueba falle.
@MainActor
final class HistoryModelTests: XCTestCase {
    let api = "https://api.trakt.tv"

    private func row(_ id: Int, _ at: String, imdb: String = "tt1160419", title: String = "Dune") -> JSON {
        ["id": .int(id), "watched_at": .string(at), "movie": ["title": .string(title), "ids": ["imdb": .string(imdb)]]]
    }

    private func page(_ n: Int) -> String { "\(api)/sync/history?page=\(n)&limit=100" }

    private func model(_ rig: ServicesRig) -> HistoryModel {
        HistoryModel(rig.services) { date in
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
            return ["", "Enero", "Febrero", "Marzo"][calendar.component(.month, from: date) % 4]
        }
    }

    func testLaPrimeraPaginaEsDeCienYVerMasSaleSiVinoLlena() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = .array((1...100).map { row($0, "2025-03-14T21:12:00.000Z", imdb: "tt\($0)") })
        let history = model(rig)
        await history.loadIfNeeded()
        XCTAssertTrue(rig.http.calls.contains(page(1)), "de 100 en 100")
        XCTAssertEqual(history.entries.count, 100)
        XCTAssertTrue(history.more, "vino llena: hay «Ver más»")
        rig.http.json[page(2)] = .array([row(101, "2025-01-02T18:30:00.000Z", imdb: "tt101"), row(100, "2025-03-14T21:12:00.000Z", imdb: "tt100")])
        await history.loadMore()
        XCTAssertEqual(history.entries.count, 101, "lo que ya estaba no se repite")
        XCTAssertFalse(history.more, "la segunda no vino llena: ya no hay más")
    }

    func testVerMasCuentaAntesDeQuitarLoBorradoAqui() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = .array((1...100).map { row($0, "2025-03-14T21:12:00.000Z", imdb: "tt\($0)") })
        var work = PendingWork(); work.traktViewingRemovals = [1, 2]   // borradas sin red: ya no se enseñan
        rig.pending.save(work)
        rig.http.offline = true
        let history = model(rig)
        rig.http.offline = false
        // La cola no puede vaciarse (Trakt no contesta el borrado): siguen escondidas.
        rig.http.statuses["\(api)/sync/history/remove"] = 503
        await history.loadMore()
        XCTAssertEqual(history.entries.count, 98)
        XCTAssertTrue(history.more, "la página vino llena aunque se enseñen 98")
    }

    func testBorrarDelHistorialNoDejaComoNoVistaLoQueTieneVistasViejasEnOtraPagina() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = [row(901, "2025-03-14T21:12:00.000Z")]
        rig.http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": "tt1160419"]]]]
        rig.http.prefix["\(api)/sync/history/movies/42"] = [["id": 900, "watched_at": "2024-01-02T18:30:00.000Z"]]   // la vieja, en otra página
        rig.http.json["\(api)/sync/history/remove"] = ["deleted": ["movies": 1]]
        await rig.services.watch.addViewing(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", at: Date(timeIntervalSince1970: 1_700_000_000))
        let history = model(rig)
        await history.loadMore()
        let send = history.remove(try XCTUnwrap(history.entries.first))
        XCTAssertTrue(history.entries.isEmpty, "sale de la lista al momento")
        await send()
        let seen = await rig.services.watch.isSeen(metaID: "tt1160419", videoID: "tt1160419"); XCTAssertTrue(seen, "le quedan vistas en Trakt: sigue vista")
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history/remove").first.flatMap(JSON.parse)?["ids"]?.array?.compactMap(\.intValue), [901])
    }

    func testDeshacerRegresaLaMismaVistaConSuFecha() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = [row(901, "2025-03-14T21:12:00.000Z")]
        rig.http.offline = true
        let history = model(rig)
        rig.http.offline = false
        await history.loadMore()
        let entry = try XCTUnwrap(history.entries.first)
        rig.http.offline = true
        await history.remove(entry)()
        await history.undoRemove(entry)
        let work = await rig.services.watch.pending.load()
        XCTAssertEqual(work.traktRewatched.map(\.at), [entry.at.timeIntervalSince1970], "la misma fecha, no la de ahora")
        let seen = await rig.services.watch.isSeen(metaID: "tt1160419", videoID: "tt1160419"); XCTAssertTrue(seen)
    }

    func testCambiarLaFechaDesdeElHistorialNoPierdeLaVistaSiTraktRechazaLaNueva() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = [row(901, "2025-03-14T21:12:00.000Z")]
        stubDune(rig)   // Trakt sabe decir qué vistas tiene (sin eso, ver `TraktQueueTests`)
        let history = model(rig)
        await history.loadMore()
        rig.http.statuses["\(api)/sync/history"] = 422
        await history.move(try XCTUnwrap(history.entries.first), to: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(rig.http.bodies("\(api)/sync/history/remove").isEmpty, "la vieja no se borra")
    }

    func testRepetidasYMesesSeArmanUnaVezPorCambio() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[page(1)] = [row(3, "2025-03-14T22:00:00.000Z"), row(2, "2025-03-14T21:30:00.000Z"), row(1, "2025-01-02T18:30:00.000Z")]
        rig.http.json["\(api)/sync/history/remove"] = ["deleted": ["movies": 1]]
        let history = model(rig)
        await history.loadMore()
        XCTAssertEqual(history.months.map(\.id), ["Marzo", "Enero"])
        XCTAssertEqual(history.months.map { $0.entries.map(\.id) }, [[3, 2], [1]])
        XCTAssertEqual(history.repeats, [3], "menos de una hora de otra: se queda la primera")
        let (count, send) = history.removeRepeats()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(history.entries.map(\.id), [2, 1])
        XCTAssertTrue(history.repeats.isEmpty)
        await send()
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history/remove").first.flatMap(JSON.parse)?["ids"]?.array?.compactMap(\.intValue), [3])
        history.monthName = { _ in "Todo" }
        XCTAssertEqual(history.months.map(\.id), ["Todo"], "otro idioma: los meses se rearman")
    }

    func testSinRedDiceQueNoPudoYReintentaDesdeDondeIba() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let history = model(rig)
        rig.http.offline = true
        await history.loadMore()
        XCTAssertTrue(history.failed)
        XCTAssertFalse(history.loading)
        rig.http.offline = false
        rig.http.json[page(1)] = [row(1, "2025-01-02T18:30:00.000Z")]
        await history.loadMore()
        XCTAssertFalse(history.failed)
        XCTAssertEqual(history.entries.map(\.id), [1], "la primera página, no la segunda")
    }

    // MARK: «Tus vistas» (ViewingsModel)

    private func stubDune(_ rig: ServicesRig) {
        rig.http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": "tt1160419"]]]]
        rig.http.prefix["\(api)/sync/history/movies/42"] = [
            ["id": 900, "watched_at": "2024-01-02T18:30:00.000Z"], ["id": 901, "watched_at": "2025-03-14T21:12:00.000Z"],
        ]
        rig.http.json["\(api)/sync/history/remove"] = ["deleted": ["movies": 1]]
        rig.http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
    }

    private func dune(_ rig: ServicesRig) -> ViewingsModel {
        ViewingsModel(rig.services, kind: "movie", metaID: "tt1160419", videoID: "tt1160419", title: "Dune")
    }

    func testTusVistasLaMasNuevaPrimeroYDeCienEnCien() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        let viewings = dune(rig)
        XCTAssertNil(viewings.count, "mientras carga no dice «0 veces»")
        await viewings.load()
        XCTAssertEqual(viewings.viewings.map(\.id), [901, 900])
        XCTAssertEqual(viewings.count, 2)
        XCTAssertEqual(viewings.last?.id, 901)
        XCTAssertFalse(viewings.offline)
        XCTAssertTrue(rig.http.calls.contains { $0.contains("/sync/history/movies/42") && $0.contains("limit=100") })
    }

    func testTusVistasSinInternetAbreConLoQueEsperaYLoDice() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        let viewings = dune(rig)
        await viewings.add(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(viewings.offline)
        XCTAssertEqual(viewings.viewings.map(\.id), [0], "la de la cola, con id 0 («Espera a que haya internet»)")
        XCTAssertFalse(viewings.loading)
    }

    func testCambiarLaFechaNoPierdeLaVista() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        rig.http.statuses["\(api)/sync/history"] = 422
        let viewings = dune(rig)
        await viewings.load()
        await viewings.move(try XCTUnwrap(viewings.viewings.last), to: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(rig.http.bodies("\(api)/sync/history/remove").isEmpty, "la vieja se queda hasta que la nueva llegue")
    }

    func testLaViOtraVezSinRedYQuitarDeVistasNoRegresaElTitulo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        await dune(rig).add(at: Date())
        await rig.services.watch.unmarkWatched(kind: "movie", metaID: "tt1160419", videoID: "tt1160419")
        let work = await rig.services.watch.pending.load()
        XCTAssertTrue(work.traktRewatched.isEmpty, "si no, Trakt la regresaría")
    }

    func testBorrarLaUnicaVistaLaDejaDeContarYDeshacerLaRegresa() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        rig.http.prefix["\(api)/sync/history/movies/42"] = [["id": 901, "watched_at": "2025-03-14T21:12:00.000Z"]]
        await rig.services.watch.addViewing(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", at: Date(timeIntervalSince1970: 1_700_000_000))
        let viewings = dune(rig)
        await viewings.load()
        let only = try XCTUnwrap(viewings.viewings.first { $0.id == 901 })
        await viewings.remove(only)()
        XCTAssertFalse(viewings.viewings.contains(only))
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history/remove").last.flatMap(JSON.parse)?["ids"]?.array?.compactMap(\.intValue), [901], "solo esa")
        await viewings.undoRemove(only)
        let seen = await rig.services.watch.isSeen(metaID: "tt1160419", videoID: "tt1160419"); XCTAssertTrue(seen)
    }
}
