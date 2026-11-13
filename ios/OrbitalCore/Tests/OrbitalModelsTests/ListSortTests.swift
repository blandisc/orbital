import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Agregadas: más recientes / más viejas» (Fernando, 13 nov 2026: «Que en mis listas también pueda ordenar por agregadas más
/// recientemente o menos recientemente a la lista»). Regla: toda lista tuya ofrece los mismos órdenes; uno que no aplica no
/// aparece (docs/ios-interfaz.md).
final class ListSortTests: XCTestCase {
    private func item(_ imdb: String, added: Double?) -> Suggestion {
        var s = Suggestion(art: imdb, kind: "movie", title: imdb, year: nil, reason: .inWatchlist)
        s.addedAt = added.map(Date.init(timeIntervalSince1970:))
        return s
    }

    func testAgregadasMasRecientesYMasViejas() {
        let list = [item("tt1", added: 200), item("tt2", added: nil), item("tt3", added: 300), item("tt4", added: 100), item("tt5", added: nil)]
        XCTAssertEqual(ListSort.byAdded(list, newestFirst: true).map(\.imdb), ["tt3", "tt1", "tt4", "tt2", "tt5"])
        XCTAssertEqual(ListSort.byAdded(list, newestFirst: false).map(\.imdb), ["tt4", "tt1", "tt3", "tt2", "tt5"],
                       "lo que no trae fecha va al final las dos veces, en el orden en que venía")
    }

    func testLosEmpatesConservanSuOrden() {
        let list = [item("tt1", added: 100), item("tt2", added: 100), item("tt3", added: 100)]
        XCTAssertEqual(ListSort.byAdded(list, newestFirst: true).map(\.imdb), ["tt1", "tt2", "tt3"])
        XCTAssertEqual(ListSort.byAdded(list, newestFirst: false).map(\.imdb), ["tt1", "tt2", "tt3"])
    }

    func testSoloSeOfreceDondeHayFechaDeAgregado() {
        let mine = ListSort.offered(for: [item("tt1", added: 100), item("tt2", added: nil)], imdbAvailable: true)
        XCTAssertEqual(Array(mine.prefix(2)), [.addedNewest, .addedOldest], "en tus listas, arriba del menú")
        let other = ListSort.offered(for: [item("tt1", added: nil)], imdbAvailable: true)
        XCTAssertFalse(other.contains(.addedNewest)); XCTAssertFalse(other.contains(.addedOldest))
        XCTAssertFalse(other.contains(.added), "«Como viene» nunca es una opción (elegir otra vez la puesta lo quita)")
    }

    func testViendoVistasYLasDejeNoTienenAgregada() {
        var dune = item("tt1", added: 100); dune.kind = "series"
        let watched = TraktWatchedState(shows: ["tt1": 0.5], info: ["tt1": .init(kind: "series", title: "Dune: Prophecy")])
        let board = SavedBoard.build(watchlist: [dune], watched: watched, hidden: [])
        XCTAssertEqual(board.inList.first?.addedAt, Date(timeIntervalSince1970: 100), "Mi lista sí")
        XCTAssertEqual(board.watching.map(\.imdb), ["tt1"])
        XCTAssertNil(board.watching.first?.addedAt, "Viendo no ofrece «Agregadas»")
        XCTAssertFalse(ListSort.offered(for: board.watching, imdbAvailable: true).contains(.addedNewest))
    }

    func testCadaListaRecuerdaSuOrden() throws {
        let suite = "list-sort-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ListSort.saved(listID: "saved:watchlist", defaults: defaults), .added, "sin elegir, como viene")
        ListSort.remember(.addedOldest, listID: "saved:watchlist", defaults: defaults)
        ListSort.remember(.title, listID: "saved:list:77", defaults: defaults)
        XCTAssertEqual(ListSort.saved(listID: "saved:watchlist", defaults: defaults), .addedOldest)
        XCTAssertEqual(ListSort.saved(listID: "saved:list:77", defaults: defaults), .title)
        XCTAssertEqual(defaults.string(forKey: "list-sort.saved:list:77"), "title", "la misma llave de siempre: lo elegido antes se conserva")
        defaults.set("se-quito", forKey: "list-sort.x")
        XCTAssertEqual(ListSort.saved(listID: "x", defaults: defaults), .added, "un orden que ya no existe: como viene")
    }

    /// Ordenar por agregadas solo cambia lo que ves: el orden a mano guardado (el de Trakt) no se toca.
    func testOrdenarPorAgregadasNoCambiaElOrdenAMano() {
        let manual = ["tt3", "tt1", "tt2"]
        let items = SavedModel.manualOrder([item("tt1", added: 300), item("tt2", added: 100), item("tt3", added: 200)], manual)
        XCTAssertEqual(items.map(\.imdb), manual)
        XCTAssertEqual(ListSort.byAdded(items, newestFirst: true).map(\.imdb), ["tt1", "tt3", "tt2"])
        XCTAssertEqual(items.map(\.imdb), manual, "la lista (y lo que se manda a Trakt) sigue en tu orden")
    }

    /// Mi lista del teléfono (sin Trakt) trae cuándo la guardaste.
    @MainActor func testMiListaDelTelefonoTraeLaFecha() async throws {
        let rig = try ServicesRig()
        for (id, listed) in [("tt1", 100.0), ("tt2", 300.0)] {
            rig.services.library.update(id, make: { LibraryEntry(metaID: id, kind: "movie", name: id) }) { e in e.inList = true; e.listedAt = listed }
        }
        let model = CollectionsModel(rig.services)
        await model.loadMyList()
        XCTAssertEqual(model.myList.map(\.addedAt), [Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 100)])
        XCTAssertEqual(ListSort.byAdded(model.myList, newestFirst: false).map(\.imdb), ["tt1", "tt2"])
    }
}
