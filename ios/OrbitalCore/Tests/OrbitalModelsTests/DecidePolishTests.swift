import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// DE1 (Fernando, 13 nov 2026: «Construye DE1 y DE2 para ver cómo se ven»): los fallos de la auditoría de «Decide por mí»
/// (`/tmp/orbital-mosaico/diagnostico.md`, F2–F13) con su prueba.
@MainActor
final class DecidePolishTests: XCTestCase {
    private func movie(_ id: String, minutes: Int, genres: [String] = ["Drama"], kind: String = "movie") -> Suggestion {
        var s = Suggestion(kind: kind, imdb: id, title: id, year: 2015, runtime: minutes, poster: "", wide: "", reason: .recommended)
        s.genres = genres
        return s
    }

    /// F3 · Un filtro que se ve puesto, filtra: sin elegir, el tiempo no se enseña puesto («Cualquier duración») ni quita
    /// nada; al elegirlo, filtra de verdad; «Cualquier duración» lo vuelve a quitar.
    func testElTiempoSoloSeVePuestoCuandoFiltra() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: [movie("tt1", minutes: 25), movie("tt2", minutes: 90), movie("tt3", minutes: 175)])
        XCTAssertNil(model.shownTime, "al abrir, «Cualquier duración»: el de la hora solo ordena")
        XCTAssertEqual(model.count(), 3, "y no quita nada")
        await model.chooseTime(.short)
        XCTAssertEqual(model.shownTime, .short)
        XCTAssertEqual(model.count(), 1, "elegido, filtra")
        XCTAssertEqual(model.picks.map(\.imdb), ["tt1"], "y solo propone lo que cabe")
        XCTAssertEqual(model.activeFilters, 1)
        await model.chooseTime(nil)
        XCTAssertNil(model.shownTime)
        XCTAssertEqual(model.count(), 3)
        XCTAssertEqual(model.activeFilters, 0)
        model.stop()
    }

    /// F4 · Con una o dos opciones no se baraja (no haría nada); con más, sí.
    func testConPocasOpcionesNoSeBaraja() async throws {
        let rig = try ServicesRig()
        let one = DecideModel(rig.services, pool: [movie("tt1", minutes: 90)])
        await one.quick()
        XCTAssertEqual(one.picks.count, 1)
        XCTAssertFalse(one.canShuffle, "una sola: «Barajar» apagado")
        one.stop()
        let many = DecideModel(rig.services, pool: (1...5).map { movie("tt\($0)", minutes: 90) })
        await many.quick()
        XCTAssertEqual(many.picks.count, 3)
        XCTAssertTrue(many.canShuffle)
        many.stop()
    }

    /// F5 · Lo que quitas se puede deshacer: «No me interesa» la aparta, «Deshacer» la regresa a su lugar y vuelve a
    /// sugerirse; a la TV solo se le avisa cuando ya no se puede deshacer (al cerrar).
    func testNoMeInteresaSeDeshaceYLaTVSeEnteraAlCerrar() async throws {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example"; $0.orbitalEnabled = true }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/foryou/dismiss"] = ["ok": true]
        let model = DecideModel(rig.services, pool: (1...5).map { movie("tt\($0)", minutes: 90) })
        await model.quick()
        let gone = try XCTUnwrap(model.pick)
        let place = try XCTUnwrap(model.picks.firstIndex { $0.imdb == gone.imdb })
        await model.notInterested()
        XCTAssertFalse(model.picks.contains { $0.imdb == gone.imdb })
        XCTAssertEqual(model.lastRemoval?.suggestion.imdb, gone.imdb)
        let dismissed = await rig.services.forYou.dismissedIDs()
        XCTAssertTrue(dismissed.contains(gone.imdb), "ya no se sugiere en Para ti")
        XCTAssertFalse(rig.http.calls.contains("https://tv.example/api/foryou/dismiss"), "a la TV todavía no: se puede deshacer")
        await model.undoRemoval()
        XCTAssertEqual(model.picks.firstIndex { $0.imdb == gone.imdb }, place, "vuelve a su lugar")
        XCTAssertEqual(model.pick?.imdb, gone.imdb, "y elegida")
        XCTAssertEqual(model.picks.count, 3)
        let after = await rig.services.forYou.dismissedIDs()
        XCTAssertFalse(after.contains(gone.imdb), "vuelve a sugerirse")
        XCTAssertNil(model.lastRemoval)
        // Otra vez, sin deshacer: al cerrar, la TV se entera.
        await model.notInterested()
        await model.commitDismissals()
        XCTAssertTrue(rig.http.calls.contains("https://tv.example/api/foryou/dismiss"))
        model.stop()
    }

    /// «Hoy no» también se deshace (y la que entró en su lugar puede volver a salir).
    func testHoyNoSeDeshace() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: (1...5).map { movie("tt\($0)", minutes: 90) })
        await model.quick()
        let gone = try XCTUnwrap(model.pick)
        await model.skipToday()
        XCTAssertEqual(model.lastRemoval?.dismissed, false)
        XCTAssertFalse(model.picks.contains { $0.imdb == gone.imdb })
        await model.undoRemoval()
        XCTAssertTrue(model.picks.contains { $0.imdb == gone.imdb })
        XCTAssertEqual(model.count(), 5, "ya no cuenta como apartada hoy")
        model.stop()
    }

    /// F2 · Sin red no se culpa a los filtros: sin nada que proponer dice que no hay conexión; con red y sin sugerencias,
    /// eso; solo con filtros puestos y nada que cumpla, los filtros.
    func testSinNadaDicePorQue() async throws {
        let rig = try ServicesRig()
        rig.services.isOnline = { false }
        let offline = DecideModel(rig.services, pool: [])
        await offline.quick()
        XCTAssertEqual(offline.empty, .offline, "sin red: «Sin conexión», no «Nada con 1 h»")
        rig.services.isOnline = { true }
        XCTAssertEqual(offline.empty, .nothingSuggested)
        await offline.retry(pool: [movie("tt1", minutes: 90)], sources: [])
        XCTAssertNil(offline.empty, "Reintentar trae lo sugerido y propone")
        XCTAssertEqual(offline.pick?.imdb, "tt1")
        offline.stop()
        let filtered = DecideModel(rig.services, pool: [movie("tt1", minutes: 90, genres: ["Drama"])])
        filtered.genres = ["horror"]
        await filtered.apply()
        XCTAssertEqual(filtered.empty, .filters, "con un filtro que no deja nada, sí son los filtros")
        filtered.stop()
    }

    /// F7 · «Mi lista», Favoritos, «Tus series» y tus listas van bajo «Tus listas», no bajo «Sugerencias».
    func testMiListaVaBajoLoTuyo() {
        for id in ["watchlist", ForYou.favoritesList, "mine", "list:123", "lb:terror"] {
            XCTAssertEqual(DecideModel.origin(ofShelf: id), DecideModel.yoursOrigin, id)
        }
        for id in ["recs", "trend", "chart:netflix", "because", "new"] {
            XCTAssertEqual(DecideModel.origin(ofShelf: id), DecideModel.suggestedOrigin, id)
        }
    }

    /// F13 · Una opción que no deja nada no se puede tocar (salvo para quitarla si ya estaba puesta).
    func testOpcionesEnCeroNoSeOfrecen() throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: [movie("tt1", minutes: 90, genres: ["Drama"])])
        model.time = .long
        let documentaries = model.count { $0.genres = ["documentary"] }
        XCTAssertEqual(documentaries, 0)
        XCTAssertFalse(DecideModel.offered(documentaries, selected: false), "«Documental · 0» no se toca")
        XCTAssertTrue(DecideModel.offered(documentaries, selected: true), "pero si ya estaba puesto, se puede quitar")
        XCTAssertTrue(DecideModel.offered(model.count { $0.genres = ["drama"] }, selected: false))
        model.stop()
    }

    /// F5 en el mazo · «Paso» se deshace: la carta vuelve arriba y ya no cuenta como descartada.
    func testPasoSeDeshaceEnElMazo() async throws {
        let rig = try ServicesRig()
        let pool = (1...3).map { movie("tt\($0)", minutes: 90) }
        let model = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await model.load()
        let top = try XCTUnwrap(model.cards.first)
        model.discard(top)
        XCTAssertFalse(model.cards.contains { $0.imdb == top.imdb })
        model.undoDiscard(top)
        XCTAssertEqual(model.cards.first?.imdb, top.imdb, "vuelve arriba")
        let again = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await again.load()
        XCTAssertTrue(again.cards.contains { $0.imdb == top.imdb }, "y ya no está descartada")
    }

    /// F5 en el mazo · «Para hoy» se deshace: sale de Mi lista y de «Para hoy», y la carta vuelve.
    func testParaHoySeDeshaceEnElMazo() async throws {
        let rig = try ServicesRig()
        let pool = (1...3).map { movie("tt\($0)", minutes: 90) }
        let model = MatchDeckModel(rig.services, pool: pool, watched: { [] })
        await model.load()
        let top = try XCTUnwrap(model.cards.first)
        await model.saveForTonight(top)
        XCTAssertTrue(ParaHoy.ids(kv: rig.kv, now: rig.services.now()).contains(top.imdb))
        await model.undo(top)
        XCTAssertFalse(ParaHoy.ids(kv: rig.kv, now: rig.services.now()).contains(top.imdb))
        XCTAssertEqual(model.cards.first?.imdb, top.imdb)
    }
}
