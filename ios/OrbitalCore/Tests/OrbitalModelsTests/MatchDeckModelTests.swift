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

    func testSinVistoNiDescartado() {
        let pool = [s("tt1", ["comedy"]), s("tt2", ["horror"]), s("tt3", ["comedy"]), s("tt1", ["comedy"]), s("tt4", ["drama"])]
        let all = MatchDeckModel.deck(pool, watched: ["tt3"], discarded: ["tt4"], day: 1)
        XCTAssertEqual(Set(all.map(\.imdb)), ["tt1", "tt2"], "sin repetir, sin lo visto ni lo descartado")
    }

    /// Películas o series y un género (Fernando, 3 nov 2026); «sci-fi» y «science-fiction» son el mismo género.
    func testFiltraPorTipoYGenero() async throws {
        var serie = s("tt3", ["science-fiction"]); serie.kind = "series"
        let rig = try ServicesRig()
        let model = MatchDeckModel(rig.services, pool: [s("tt1", ["comedy"]), s("tt2", ["sci-fi", "comedy"]), s("tt4", ["Comedy"]), serie], watched: { [] })
        await model.load()
        XCTAssertEqual(model.genres.first, "Comedia", "el que más sale, primero")
        model.genre = "Ciencia ficción"
        XCTAssertEqual(Set(model.cards.map(\.imdb)), ["tt2", "tt3"])
        model.kind = "series"
        XCTAssertEqual(model.cards.map(\.imdb), ["tt3"])
        XCTAssertEqual(model.genres, ["Ciencia ficción"], "los géneros, solo de lo que hay del tipo elegido")
        model.genre = "Comedia"
        XCTAssertNil(model.genre, "un género que ya no hay vuelve a todos")
        XCTAssertEqual(model.cards.map(\.imdb), ["tt3"])
    }

    func testElOrdenEsElMismoEnElDiaYCambiaAlOtro() {
        let pool = (1...12).map { s("tt\($0)", ["drama"]) }
        let a = MatchDeckModel.deck(pool, watched: [], discarded: [], day: 100).map(\.imdb)
        XCTAssertEqual(a, MatchDeckModel.deck(pool, watched: [], discarded: [], day: 100).map(\.imdb))
        XCTAssertNotEqual(a, MatchDeckModel.deck(pool, watched: [], discarded: [], day: 101).map(\.imdb))
    }

    /// Al volver a abrir el mazo (otro día o el mismo), lo que guardaste no sale otra vez, ni lo que ya está en Mi lista.
    func testLoGuardadoNoVuelveAlAbrirOtraVez() async throws {
        let rig = try ServicesRig()
        let pool = [s("tt1", ["drama"]), s("tt2", ["drama"]), s("tt3", ["drama"])]
        let first = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await first.load()
        let top = try XCTUnwrap(first.cards.first)
        await first.save(top)
        await rig.services.watch.setInLibrary(kind: "movie", metaID: "tt3", title: "tt3", poster: nil, add: true)
        let again = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await again.load()
        XCTAssertFalse(again.cards.contains { $0.imdb == top.imdb }, "la que guardaste ya no sale")
        XCTAssertFalse(again.cards.contains { $0.imdb == "tt3" }, "ni la que ya está en Mi lista")
    }

    func testDeshacerRegresaLaCartaArribaYLaSacaDeLoGuardado() async throws {
        let rig = try ServicesRig()
        let pool = [s("tt1", ["drama"]), s("tt2", ["drama"])]
        let model = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await model.load()
        let top = try XCTUnwrap(model.cards.first)
        await model.save(top)
        XCTAssertEqual(model.saved.map(\.imdb), [top.imdb])
        await model.undo(top)
        XCTAssertTrue(model.saved.isEmpty)
        XCTAssertEqual(model.cards.first?.imdb, top.imdb)
        XCTAssertEqual(model.cards.count, 2)
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
    /// El domingo la semana empieza vacía: se cae en el primer periodo con algo y se sabe qué fue lo último.
    func testElPrimerPeriodoConAlgo() async throws {
        let rig = try ServicesRig()
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 1; cal.timeZone = TimeZone(identifier: "UTC")!
        let sunday = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!   // un domingo
        let model = WatchingModel(rig.services, clock: { sunday }, calendar: cal)
        model.preload([TraktPlay(at: sunday.addingTimeInterval(-20 * 3600), kind: "series", imdb: "tt0096697", title: "Los Simpson", minutes: 22, genres: ["comedy"]),
                       TraktPlay(at: sunday.addingTimeInterval(-40 * 86400), kind: "movie", imdb: "tt0111161", title: "Sueño de fuga", minutes: 142, genres: ["drama"])])
        XCTAssertTrue(model.stats(.week).isEmpty, "el sábado ya es la semana pasada")
        XCTAssertEqual(model.firstPeriodWithData(), .year, "noviembre empezó hoy: tampoco hay en el mes")
        XCTAssertEqual(model.lastPlay?.title, "Los Simpson")
        XCTAssertEqual(model.start(of: .week), cal.startOfDay(for: sunday))
    }

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

    func testSinRedYSinNadaGuardadoEsUnError() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        let model = WatchingModel(rig.services)
        await model.load()
        XCTAssertTrue(model.loaded)
        XCTAssertTrue(model.failed, "sin red no es «nada en este periodo»")
        rig.http.offline = false
        rig.http.prefix["https://api.trakt.tv/sync/history"] = []
        await model.load(force: true)
        XCTAssertFalse(model.failed)
    }

    func testUnaListaFamosaQueNoLlegaSeMarca() async throws {
        let rig = try ServicesRig()
        rig.http.offline = true
        let model = RepisaModel(rig.services, watched: { [] })
        await model.load()
        XCTAssertEqual(model.failedLists, Set(Canon.lists.map(\.id)), "sin red fallan todas las listas famosas")
        rig.http.offline = false
        rig.http.prefix["https://mdblist.com/lists/"] = [["title": "Uno", "imdb_id": "tt1", "mediatype": "movie", "release_year": 2000]]
        await model.load()
        // Las de MDBList ya llegaron; la de tus listas de Trakt (`.mine`) depende de tu cuenta, que aquí no la tiene.
        let mdblist = Set(Canon.lists.filter { if case .mdblist = $0.source { true } else { false } }.map(\.id))
        XCTAssertTrue(model.failedLists.isDisjoint(with: mdblist), "\(model.failedLists)")
    }
}

/// «Para hoy» (arriba o la ★): queda primero en Mi lista solo ese día.
final class ParaHoyTests: XCTestCase {
    func testParaHoyVaPrimeroSoloEseDia() {
        let kv = InMemoryKeyValueStore()
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        func s(_ id: String) -> Suggestion { Suggestion(kind: "movie", imdb: id, title: id, poster: "", wide: "", reason: .inList("Mi lista")) }
        let list = [s("tt1"), s("tt2"), s("tt3")]
        ParaHoy.mark("tt3", kv: kv, now: today)
        ParaHoy.mark("tt2", kv: kv, now: today)
        XCTAssertEqual(ParaHoy.first(list, kv: kv, now: today).map(\.imdb), ["tt2", "tt3", "tt1"], "lo último que marcaste, primero")
        XCTAssertEqual(ParaHoy.first(list, kv: kv, now: today.addingTimeInterval(86_400)).map(\.imdb), ["tt1", "tt2", "tt3"], "al día siguiente, a su lugar")
        ParaHoy.unmark("tt2", kv: kv)
        XCTAssertEqual(ParaHoy.ids(kv: kv, now: today), ["tt3"])
    }
}
