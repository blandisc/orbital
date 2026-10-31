import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La repisa de Colecciones: los premios al instante, las listas famosas guardadas una semana (al volver a abrir salen sin
/// esperar a la red y no se vuelven a pedir), una copia vieja se sigue mostrando si la red falla, lo visto se cuenta una vez
/// por título y lo que marcas se pinta al momento. (Que sin red y sin copia se marquen ya lo cuida
/// `WatchingModelTests.testUnaListaFamosaQueNoLlegaSeMarca`.)
@MainActor
final class RepisaModelSavedTests: XCTestCase {
    let mdblist = Canon.lists.filter { if case .mdblist = $0.source { true } else { false } }

    func url(_ list: (id: String, user: String, slug: String, total: Int, grouping: CanonCollection.Grouping, source: Canon.ListSource)) -> String {
        "https://mdblist.com/lists/\(list.user)/\(list.slug)/json"
    }

    /// Cada lista de MDBList con dos títulos propios (`<id>-1`, `<id>-2`) y uno de premios compartido.
    func stock(_ rig: ServicesRig, shared: String) {
        for list in mdblist {
            rig.http.json[url(list)] = [
                ["title": "Uno", "imdb_id": .string("tt\(list.id)1"), "mediatype": "movie", "release_year": 2001],
                ["title": "Dos", "imdb_id": .string("tt\(list.id)2"), "mediatype": "show", "release_year": 2002],
                ["title": "Premiada", "imdb_id": .string(shared), "mediatype": "movie", "release_year": 1999],
            ]
        }
    }

    func mdblistCalls(_ rig: ServicesRig) -> Int { rig.http.calls.filter { $0.hasPrefix("https://mdblist.com/") }.count }

    func testLosPremiosEstanAlInstanteSinPedirNada() throws {
        let rig = try ServicesRig()
        let model = RepisaModel(rig.services, watched: { [] })
        let oscar = try XCTUnwrap(model.collection("oscar"))
        XCTAssertFalse(oscar.items.isEmpty, "vienen con la app")
        XCTAssertFalse(model.loaded)
        XCTAssertTrue(model.collection("criterion")?.items.isEmpty ?? false, "las listas famosas, aún no")
        XCTAssertTrue(rig.http.calls.isEmpty)
    }

    func testLasListasLleganSeGuardanYAlVolverSalenSinEsperarALaRed() async throws {
        let rig = try ServicesRig()
        let clock = rig.clock
        let shared = try XCTUnwrap(Canon.awards().first { $0.id == "oscar" }?.items.first?.imdb)
        stock(rig, shared: shared)
        let model = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        await model.load()
        XCTAssertTrue(model.loaded)
        for list in mdblist {
            XCTAssertEqual(model.collection(list.id)?.items.map(\.rank), [1, 2, 3], "en su orden: \(list.id)")
            XCTAssertEqual(model.collection(list.id)?.items[1].kind, "series")
        }
        XCTAssertTrue(model.failedLists.isDisjoint(with: Set(mdblist.map(\.id))))
        let asked = mdblistCalls(rig)
        // Otra vez (otra sesión, sin red): las listas guardadas salen al abrir, y en la semana no se vuelven a pedir.
        rig.http.offline = true
        clock.now = clock.now.addingTimeInterval(3 * 86400)
        let again = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        for list in mdblist { XCTAssertEqual(again.collection(list.id)?.items.count, 3, "al instante: \(list.id)") }
        rig.http.offline = false
        await again.load()
        XCTAssertEqual(mdblistCalls(rig), asked, "aún no caduca")
    }

    func testPasadaLaSemanaSeVuelveAPedirYSinRedQuedaLaCopiaVieja() async throws {
        let rig = try ServicesRig()
        let clock = rig.clock
        stock(rig, shared: "tt9999999")
        await RepisaModel(rig.services, watched: { [] }, clock: { clock.now }).load()
        let asked = mdblistCalls(rig)
        clock.now = clock.now.addingTimeInterval(RepisaModel.listTTL + 60)
        rig.http.offline = true
        let model = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        await model.load()
        for list in mdblist {
            XCTAssertEqual(model.collection(list.id)?.items.count, 3, "la copia vieja se sigue mostrando: \(list.id)")
            XCTAssertFalse(model.failedLists.contains(list.id), "con copia no se ofrece «Reintentar»")
        }
        rig.http.offline = false
        await model.load()
        XCTAssertEqual(mdblistCalls(rig), asked + mdblist.count, "ya caducó: se vuelve a pedir")
    }

    func testLoVistoCuentaUnaVezPorTituloYLoQueMarcasSeVeAlMomento() async throws {
        let rig = try ServicesRig()
        let shared = try XCTUnwrap(Canon.awards().first { $0.id == "oscar" }?.items.first?.imdb)
        stock(rig, shared: shared)
        let model = RepisaModel(rig.services, watched: { [shared] })
        await model.load()
        XCTAssertEqual(model.watched, [shared])
        XCTAssertEqual(model.seenTotal, 1, "está en el Óscar y en cada lista: cuenta una vez")
        let others = model.others(shared, besides: "oscar")
        let otherAwards = Canon.awards().filter { $0.id != "oscar" && $0.items.contains { $0.imdb == shared } }.map(\.id)   // también ganó otro premio
        XCTAssertEqual(Set(others), Set(mdblist.map(\.id) + otherAwards), "«También en…»")
        XCTAssertFalse(others.contains("oscar"))
        let first = try XCTUnwrap(mdblist.first)
        model.markSeen("tt\(first.id)1")
        XCTAssertEqual(model.seenTotal, 2, "sin esperar a Trakt")
    }
}
