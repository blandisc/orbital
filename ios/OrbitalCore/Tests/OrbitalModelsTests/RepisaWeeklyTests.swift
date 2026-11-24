import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Esta semana»: la tabla llega y se guarda un día, las listas escritas salen al instante, las de MDBList cuando llegan, la
/// que no llega no deja una tarjeta vacía y sin red se usa la última tabla.
@MainActor
final class RepisaWeeklyTests: XCTestCase {
    let table = ExploreTable(rotate: 4, lists: [
        ExploreList(id: "escrita", title: "Escrita", about: "x", items: [.init(id: "tt0096697:2:3", kind: "episode", title: "La casita del horror I", year: 1990)]),
        ExploreList(id: "famosa", title: "Famosa", about: "x", mdblist: "u/famosa"),
        ExploreList(id: "perdida", title: "Perdida", about: "x", mdblist: "u/perdida"),
    ])

    func stock(_ rig: ServicesRig) throws {
        rig.http.json[ExploreTable.url.absoluteString] = try XCTUnwrap(JSON.parse(JSONEncoder().encode(table)))
        rig.http.json["https://mdblist.com/lists/u/famosa/json"] = [["title": "Uno", "imdb_id": "tt1", "mediatype": "movie", "release_year": 2001]]
    }

    func testLaTablaLlegaYCadaListaSaleCuandoTieneTitulos() async throws {
        let rig = try ServicesRig()
        try stock(rig)
        let clock = rig.clock
        let model = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        XCTAssertTrue(model.weekly.isEmpty)
        await model.loadWeekly()
        XCTAssertEqual(model.weekly.map(\.id), ["escrita", "famosa"], "la que no llegó no sale")
        XCTAssertEqual(model.collection("escrita")?.items.first?.episode?.show, "tt0096697")
        XCTAssertEqual(model.collection("famosa")?.items.map(\.imdb), ["tt1"])
        XCTAssertEqual(model.weeklyList("famosa")?.title, "Famosa")
        // Otra sesión, sin red: la tabla y la lista guardadas salen al abrir.
        rig.http.offline = true
        clock.now = clock.now.addingTimeInterval(2 * 86400)
        let again = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        XCTAssertEqual(again.weekly.filter { !$0.items.isEmpty }.map(\.id), ["escrita", "famosa"])
        await again.loadWeekly()
        XCTAssertEqual(again.weekly.map(\.id), ["escrita", "famosa"])
    }

    /// Volver a Explorar al rato no vuelve a leer ni a pedir nada (cada visita congelaba la Mac ~0.2 s, 23 nov 2026); pasados
    /// diez minutos, sí.
    func testVolverAExplorarAlRatoNoVuelveACargar() async throws {
        let rig = try ServicesRig()
        try stock(rig)
        let clock = rig.clock
        let model = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        await model.loadWeekly()
        let asked = rig.http.calls.count
        var changes = 0
        let watch = model.onChange { changes += 1 }
        clock.now = clock.now.addingTimeInterval(RepisaModel.weeklyMaxAge - 60)
        await model.loadWeekly()
        XCTAssertEqual(rig.http.calls.count, asked, "nada a la red")
        XCTAssertEqual(changes, 0, "ni repinta Explorar")
        clock.now = clock.now.addingTimeInterval(120)
        await model.loadWeekly()
        XCTAssertGreaterThan(changes, 0, "ya caducó: se vuelve a armar")
        watch.cancel()
    }

    /// Un capítulo que ya viste (tu avance en Trakt) cuenta como visto en su lista, igual que una película.
    func testLosCapitulosQueYaVisteCuentan() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        try stock(rig)
        rig.http.json["https://api.trakt.tv/shows/tt0096697/progress/watched?hidden=false&specials=false"] =
            ["seasons": [["number": 2, "episodes": [["number": 3, "completed": true]]]]]
        let clock = rig.clock
        let model = RepisaModel(rig.services, watched: { [] }, clock: { clock.now })
        await model.loadWeekly()
        XCTAssertTrue(model.watched.contains("tt0096697:2:3"))
        XCTAssertEqual(model.collection("escrita").map { $0.seen(model.watched) }, 1)
        await model.load()
        XCTAssertTrue(model.watched.contains("tt0096697:2:3"), "al volver a leer lo visto no se pierde")
    }
}
