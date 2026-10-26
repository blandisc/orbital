import XCTest
import OrbitalCore
@testable import OrbitalModels

/// «Guardar»: adónde va por omisión (`SaveDestination`), qué hace un toque (`QuickSave`) y el orden y el espacio de
/// «Guardar en…» (`SaveSheetPlan`).
@MainActor
final class SaveRulesTests: XCTestCase {
    // MARK: lista por omisión
    func testTraktWatchlistIsTheDefaultWhenTraktIsLinked() {
        XCTAssertEqual(SaveDestination.preferred(traktLinked: true, metaID: "tt0386676"), .traktWatchlist)
        XCTAssertEqual(SaveDestination.preferred(traktLinked: false, metaID: "tt0386676"), .stremioLibrary, "sin Trakt, Mi lista como siempre")
        XCTAssertEqual(SaveDestination.preferred(traktLinked: true, metaID: "kitsu:123"), .stremioLibrary, "Trakt no conoce lo que no tiene IMDb")
    }

    func testFixedDestinationsPutTheDefaultFirst() {
        XCTAssertEqual(SaveDestination.fixed(traktLinked: true, metaID: "tt1"), [.traktWatchlist, .stremioLibrary])
        XCTAssertEqual(SaveDestination.fixed(traktLinked: false, metaID: "tt1"), [.stremioLibrary])
    }

    func testQuickSave() {
        let w = SaveDestination.traktWatchlist, s = SaveDestination.stremioLibrary
        XCTAssertEqual(QuickSave.decide(preferred: w, inLibrary: false, inWatchlist: false, inOtherLists: false), .add(w))
        XCTAssertEqual(QuickSave.decide(preferred: w, inLibrary: false, inWatchlist: true, inOtherLists: false), .remove(w))
        XCTAssertEqual(QuickSave.decide(preferred: w, inLibrary: true, inWatchlist: false, inOtherLists: false), .choose, "ya está en Mi lista: que elija")
        XCTAssertEqual(QuickSave.decide(preferred: w, inLibrary: false, inWatchlist: true, inOtherLists: true), .choose)
        XCTAssertEqual(QuickSave.decide(preferred: s, inLibrary: false, inWatchlist: false, inOtherLists: false), .add(s))
        XCTAssertEqual(QuickSave.decide(preferred: s, inLibrary: true, inWatchlist: false, inOtherLists: false), .remove(s))
    }

    func testTheTitleSavesToTheWatchlistFromTheFirstTap() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json["https://api.trakt.tv/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = []
        rig.http.json["https://api.trakt.tv/sync/watchlist"] = [:]
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        XCTAssertEqual(title.saveDestination, .traktWatchlist, "se sabe sin esperar a la red")
        await title.load()
        XCTAssertEqual(title.quickSave, .add(.traktWatchlist))
        await title.toggle(.traktWatchlist)
        XCTAssertTrue(title.isSaved(in: .traktWatchlist))
        XCTAssertFalse(title.inLibrary, "Mi lista no se toca")
        XCTAssertEqual(title.quickSave, .remove(.traktWatchlist))
        let sent = try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/watchlist").first.flatMap(JSON.parse))
        XCTAssertEqual(sent["movies"]?.array?.first?["ids"]?["imdb"]?.string, "tt0816692")
    }

    func testWithoutTraktTheTitleSavesToMyList() throws {
        let rig = try ServicesRig()
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        XCTAssertEqual(title.saveDestination, .stremioLibrary)
        XCTAssertEqual(title.fixedDestinations, [.stremioLibrary])
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
}
