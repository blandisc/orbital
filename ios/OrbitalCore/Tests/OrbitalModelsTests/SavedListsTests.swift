import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El «···» de tus listas (G4-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»).
@MainActor
final class SavedListsTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func movie(_ imdb: String) -> Suggestion { Suggestion(art: imdb, kind: "movie", title: imdb, year: nil, reason: .inWatchlist) }

    func testElOrdenAManoMandaYLoNuevoVaPrimero() {
        let items = ["a", "b", "c", "d"].map(movie)
        XCTAssertEqual(SavedModel.manualOrder(items, ["c", "a", "b"]).map(\.imdb), ["d", "c", "a", "b"])
        XCTAssertEqual(SavedModel.manualOrder(items, nil).map(\.imdb), ["a", "b", "c", "d"])
    }

    func testCambiarNombreYQuienLaVeEsUnPUT() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/me/lists/42"] = ["ids": ["trakt": 42]]
        let model = SavedModel(rig.services)
        model.appendList(SavedModel.SavedList(id: "list:42", name: "Viejo"))
        try await model.renameList("list:42", to: "  Terror  ")
        try await model.setPrivacy("list:42", "link")
        let bodies = rig.http.bodies("\(api)/users/me/lists/42").compactMap(JSON.parse)
        XCTAssertEqual(bodies.first?["name"]?.string, "Terror")
        XCTAssertEqual(bodies.last?["privacy"]?.string, "link")
        XCTAssertEqual(model.name(of: "list:42"), "Terror")
        XCTAssertEqual(model.privacies["list:42"], "link")
    }

    func testOrdenarAManoMandaLosRenglonesEnTuOrden() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/me/lists/42/items"] = [
            ["id": 7, "movie": ["ids": ["imdb": "tt1"]]], ["id": 8, "movie": ["ids": ["imdb": "tt2"]]], ["id": 9, "show": ["ids": ["imdb": "tt3"]]],
        ]
        rig.http.json["\(api)/users/me/lists/42/items/reorder"] = ["updated": 3]
        let model = SavedModel(rig.services)
        try await model.reorder("list:42", imdbs: ["tt3", "tt1"])
        let body = try XCTUnwrap(rig.http.bodies("\(api)/users/me/lists/42/items/reorder").first.flatMap(JSON.parse))
        XCTAssertEqual(body["rank"]?.array?.compactMap(\.intValue), [9, 7, 8], "lo que no ordenaste se queda al final")
    }

    func testBorrarLaQuitaDeTusListas() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/me/lists/42"] = [:]
        rig.http.statuses["\(api)/users/me/lists/42"] = 204
        let model = SavedModel(rig.services)
        model.appendList(SavedModel.SavedList(id: "list:42", name: "Terror"))
        try await model.deleteList("list:42")
        XCTAssertFalse(model.lists.contains { $0.id == "list:42" })
    }

    func testSinTraktNoSeTocaNada() async throws {
        let rig = try ServicesRig(traktLinked: false, traktClientID: "CID")
        let model = SavedModel(rig.services)
        model.appendList(SavedModel.SavedList(id: "list:42", name: "Terror"))
        do { try await model.renameList("list:42", to: "Otro"); XCTFail("debió fallar") } catch {}
        XCTAssertEqual(model.name(of: "list:42"), "Terror")
    }
}
