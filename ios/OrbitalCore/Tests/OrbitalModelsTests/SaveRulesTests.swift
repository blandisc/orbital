import XCTest
import OrbitalCore
@testable import OrbitalModels

/// «Guardar»: adónde va por omisión (`SaveDestination`), qué hace un toque (`QuickSave`) y el orden y el espacio de
/// «Guardar en…» (`SaveSheetPlan`).
@MainActor
final class SaveRulesTests: XCTestCase {
    // MARK: lista por omisión
    /// Una sola lista fija: Mi lista (el teléfono, y tu watchlist de Trakt si está conectado). Ya no hay «Mi lista (Stremio)».
    func testMyListIsTheOnlyFixedDestination() {
        XCTAssertEqual(SaveDestination.preferred(traktLinked: true, metaID: "tt0386676"), .myList)
        XCTAssertEqual(SaveDestination.preferred(traktLinked: false, metaID: "kitsu:123"), .myList)
        XCTAssertEqual(SaveDestination.fixed(traktLinked: true, metaID: "tt1"), [.myList])
        XCTAssertEqual(SaveDestination.fixed(traktLinked: false, metaID: "tt1"), [.myList])
    }

    func testQuickSave() {
        XCTAssertEqual(QuickSave.decide(inList: false, inOtherLists: false), .add(.myList))
        XCTAssertEqual(QuickSave.decide(inList: true, inOtherLists: false), .remove(.myList))
        XCTAssertEqual(QuickSave.decide(inList: true, inOtherLists: true), .choose)
        XCTAssertEqual(QuickSave.decide(inList: false, inOtherLists: true), .choose)
    }

    func testTheTitleSavesToMyListAndTheWatchlistFromTheFirstTap() async throws {
        let rig = try ServicesRig(signedIn: false, traktLinked: true, traktClientID: "CID")
        rig.http.json["https://api.trakt.tv/sync/watchlist"] = [:]
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        XCTAssertEqual(title.saveDestination, .myList, "se sabe sin esperar a la red")
        await title.load()
        XCTAssertEqual(title.quickSave, .add(.myList))
        await title.toggle(.myList)
        XCTAssertTrue(title.isSaved(in: .myList))
        XCTAssertEqual(title.quickSave, .remove(.myList))
        let sent = try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/watchlist").first.flatMap(JSON.parse))
        XCTAssertEqual(sent["movies"]?.array?.first?["ids"]?["imdb"]?.string, "tt0816692")
    }

    func testWithoutTraktMyListStaysOnThePhone() async throws {
        let rig = try ServicesRig(signedIn: false)
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        await title.toggle(.myList)
        XCTAssertEqual(rig.services.library.entry("tt0816692")?.inList, true)
        XCTAssertEqual(rig.services.traktOutbox.pending.map(\.imdb), ["tt0816692"], "llega a Trakt cuando lo conectes")
    }

    // MARK: «Guardar en…»
    private func list(_ id: String, hoursAgo: Double?) -> SavedList {
        SavedList(id: id, name: id, contains: false, updatedAt: hoursAgo.map { Date(timeIntervalSince1970: 1_000_000 - $0 * 3600) })
    }

    func testRecentListsGoFirstAndUndatedOnesKeepTheirOrderAtTheEnd() {
        let lists = [list("viejo", hoursAgo: 900), list("sin-a", hoursAgo: nil), list("nuevo", hoursAgo: 1), list("sin-b", hoursAgo: nil), list("medio", hoursAgo: 30)]
        XCTAssertEqual(SaveSheetPlan.order(lists).map(\.id), ["nuevo", "medio", "viejo", "sin-a", "sin-b"])
    }

    func testSkeletonsWhileLoadingThenTheListsInTheSameRegion() {
        XCTAssertEqual(SaveSheetPlan.rows(lists: nil, expected: 3), [.skeleton(0), .skeleton(1), .skeleton(2)])
        XCTAssertEqual(SaveSheetPlan.rows(lists: nil, expected: 0), [.skeleton(0)], "al menos un renglón apartado")
        XCTAssertEqual(SaveSheetPlan.rows(lists: [], expected: 3), [.empty])
        XCTAssertEqual(SaveSheetPlan.rows(lists: [list("a", hoursAgo: 5), list("b", hoursAgo: 1)], expected: 2).map(\.id), ["list:b", "list:a"])
    }

    func testReservedRowsDoNotDependOnTheNetwork() {
        // Lo que se aparta al abrir: lo que ya llegó, si no lo de la última vez, si no el respaldo; entre 1 y el tope.
        XCTAssertEqual(SaveSheetPlan.reservedRows(loaded: nil, cached: 4, fallback: 3, cap: 5), 4)
        XCTAssertEqual(SaveSheetPlan.reservedRows(loaded: nil, cached: 0, fallback: 3, cap: 5), 3)
        XCTAssertEqual(SaveSheetPlan.reservedRows(loaded: 9, cached: 4, fallback: 3, cap: 5), 5)
        XCTAssertEqual(SaveSheetPlan.reservedRows(loaded: 0, cached: 4, fallback: 3, cap: 5), 1)
    }

    func testAListWithMoreThanAPageIsReadWhole() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let first: [JSON] = (0..<100).map { i in ["movie": ["ids": ["imdb": .string("tt\(1000000 + i)")]]] }
        let second: [JSON] = (0..<10).map { i in ["movie": ["ids": ["imdb": .string("tt\(2000000 + i)")]]] }
        rig.http.json["https://api.trakt.tv/users/me/lists/7/items"] = .array(first)
        rig.http.json["https://api.trakt.tv/users/me/lists/7/items?page=2&limit=100"] = .array(second)
        let members = try await XCTUnwrap(rig.services.trakt).listMembers("7")
        XCTAssertEqual(members.count, 110, "«Mi lista Stremio» tiene 210: la lista se lee completa, no solo la primera página")
    }

    func testLoadedListsComeRecentFirstAndANewListGoesOnTop() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["https://api.trakt.tv/users/me/lists"] = [
            ["name": "Viejas", "ids": ["trakt": 1], "updated_at": "2024-01-01T00:00:00.000Z"],
            ["name": "Recientes", "ids": ["trakt": 2], "updated_at": "2026-10-20T00:00:00.000Z"],
        ]
        rig.http.json["https://api.trakt.tv/users/me/lists/1/items"] = [["movie": ["ids": ["imdb": "tt0816692"]]]]
        rig.http.json["https://api.trakt.tv/users/me/lists/2/items"] = []
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        await title.loadLists()
        XCTAssertEqual(title.lists?.map(\.name), ["Recientes", "Viejas"])
        XCTAssertEqual(title.lists?.map(\.contains), [false, true])
        XCTAssertEqual(rig.services.traktOutbox.cachedLists.map(\.name), ["Recientes", "Viejas"], "se recuerdan en ese orden (sin red, igual)")
        XCTAssertEqual(title.expectedListCount, 2)
    }

    /// «Crear una lista» al final de Tus listas: va a Trakt, privada, con el nombre sin espacios de más.
    @MainActor
    func testCrearUnaListaDesdeTusListas() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["https://api.trakt.tv/users/me/lists"] = ["name": "Para el domingo", "ids": ["trakt": 42]]
        let model = ParaTiModel(rig.services)
        let problem = await model.createTraktList(named: "  Para el domingo ")
        XCTAssertNil(problem)
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/users/me/lists").first)))
        XCTAssertEqual(sent["name"]?.string, "Para el domingo")
        XCTAssertEqual(sent["privacy"]?.string, "private")
        let nameless = await model.createTraktList(named: "   ")
        XCTAssertNotNil(nameless, "sin nombre no se crea")
    }
}
