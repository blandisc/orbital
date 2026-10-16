import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// CEN-50: «Para ti › Listas» como feed de estantes (orden, fusión de «Lo tuyo», respaldo de TMDB, Series · Películas, destacado).
@MainActor
final class ShelfPlanTests: XCTestCase {
    private func list(_ id: String, title: String = "", group: ForYouGroup = .discover, brand: String? = nil, split: Bool = false) -> ForYouList {
        ForYouList(id: id, title: title, group: group, brand: brand, logo: brand.map { "https://logo/\($0).png" }, splitsKinds: split, source: "", meta: "")
    }

    /// Un overview de ejemplo de la consola, en el desorden en que puede llegar.
    private var overview: [ForYouList] {
        [list("trend", title: "En tendencia", split: true), list("tv:movies", title: "Películas de TV"),
         list("jw:disney", title: "Lo más visto en Disney+", group: .platforms, brand: "disney", split: true),
         list("netflix", title: "Netflix", group: .platforms, brand: "netflix", split: true),   // respaldo de TMDB: ya hay Top 10
         list("hbo", title: "HBO Max", group: .platforms, brand: "hbo", split: true),           // respaldo de TMDB: no hay jw de hbo
         list("chart:netflix", title: "Top 10 en Netflix", group: .platforms, brand: "netflix", split: true),
         list("mine", title: "Tus series", group: .mine), list("continue", title: "Seguir viendo", group: .mine),
         list("popular", title: "Lo más popular", split: true), list("recs", title: "Recomendadas", split: true),
         list("watchlist", title: "Tu watchlist", group: .mine), list("list:7", title: "Mi lista de terror", group: .mine),
         list("mylist", title: "Mi lista", group: .mine)]
    }

    func testShelvesFollowTheBriefOrder() {
        let ids = ShelfPlanner.plan(overview).map(\.id)
        XCTAssertEqual(ids, ["mine", "recs", "list:7", "chart:netflix", "jw:disney", "hbo", "trend", "popular", "tv:movies"],
                       "Lo tuyo → Top 10 → plataformas → tendencia/popular → complementos; Seguir viendo y Mi lista viven en Inicio")
    }

    func testMineMergesWatchlistAndYourSeriesIntoOneShelf() throws {
        let plan = ShelfPlanner.plan(overview)
        let mine = try XCTUnwrap(plan.first)
        XCTAssertEqual(mine.listIDs, ["watchlist", "mine"], "la watchlist primero, luego «Tus series»")
        XCTAssertEqual(mine.title, "", "la interfaz lo nombra «Lo tuyo»")
        XCTAssertEqual(plan.filter { $0.listIDs.contains("watchlist") }.count, 1, "no se repite como estante aparte")
        XCTAssertEqual(plan.filter { $0.listIDs.contains("mine") }.count, 1)
        XCTAssertEqual(ShelfPlanner.plan([list("mine", group: .mine)]).first?.listIDs, ["mine"], "con solo una de las dos, también hay «Lo tuyo»")
        XCTAssertTrue(ShelfPlanner.plan([list("trend")]).allSatisfy { $0.id != "mine" }, "sin Trakt no hay «Lo tuyo»")
    }

    func testTMDBFallbackOnlyWhenThereIsNoJustWatchOrChartOfThatBrand() {
        let ids = ShelfPlanner.plan(overview).map(\.id)
        XCTAssertFalse(ids.contains("netflix"), "ya hay Top 10 de Netflix")
        XCTAssertTrue(ids.contains("hbo"), "no hay jw:hbo: el respaldo de TMDB entra")
        let disney = ShelfPlanner.plan([list("disney", title: "Disney+", group: .platforms, brand: "disney", split: true),
                                        list("jw:disney", group: .platforms, brand: "disney", split: true)])
        XCTAssertEqual(disney.map(\.id), ["jw:disney"], "con jw:disney, el respaldo no se pinta aparte")
    }

    func testStylesTop10PlatformAndPlain() {
        let styles = Dictionary(uniqueKeysWithValues: ShelfPlanner.plan(overview).map { ($0.id, $0.style) })
        XCTAssertEqual(styles["chart:netflix"], .top10)
        XCTAssertEqual(styles["jw:disney"], .platform)
        XCTAssertEqual(styles["hbo"], .platform)
        XCTAssertEqual(styles["trend"], .plain)
    }

    private func suggestion(_ id: String, wide: String = "https://w/1.jpg", reason: SuggestionReason = .popular, rank: Int? = nil) -> Suggestion {
        Suggestion(kind: "movie", imdb: id, title: id, poster: "https://p.jpg", wide: wide, reason: reason, rank: rank)
    }

    func testFeaturedIsTheFirstWideSuggestionOfTheFirstShelfAndRotates() throws {
        let plans = ShelfPlanner.plan(overview)
        let by = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let shelves: [(plan: ShelfPlan, items: [Suggestion])] = [
            (try XCTUnwrap(by["mine"]), []),                                                    // vacío: se salta
            (try XCTUnwrap(by["recs"]), [suggestion("tt1", wide: ""), suggestion("tt2", reason: .recommended), suggestion("tt3")]),
            (try XCTUnwrap(by["chart:netflix"]), [suggestion("tt9", rank: 1)]),
        ]
        XCTAssertEqual(ShelfPlanner.featured(shelves, rotation: 0)?.item.imdb, "tt2", "la primera con arte ancho (tt1 no tiene)")
        XCTAssertEqual(ShelfPlanner.featured(shelves, rotation: 1)?.item.imdb, "tt3", "«Actualizar» pasa a la siguiente")
        XCTAssertEqual(ShelfPlanner.featured(shelves, rotation: 2)?.item.imdb, "tt2", "y vuelve a empezar")
        XCTAssertNil(ShelfPlanner.featured([(try XCTUnwrap(by["mine"]), [suggestion("x", wide: "")])], rotation: 0))
    }

    func testFeaturedReasonNamesTheSource() throws {
        let plans = ShelfPlanner.plan(overview)
        let chart = try XCTUnwrap(plans.first { $0.id == "chart:netflix" }), recs = try XCTUnwrap(plans.first { $0.id == "recs" })
        XCTAssertEqual(ParaTiModel.reason(of: suggestion("a", rank: 1), in: chart), .rank(1, platform: "Netflix"))
        XCTAssertEqual(ParaTiModel.reason(of: suggestion("a", reason: .recommended), in: recs), .recommendedByTrakt)
        XCTAssertEqual(ParaTiModel.reason(of: suggestion("a", reason: .trending), in: recs), .trending)
        XCTAssertEqual(ParaTiModel.reason(of: suggestion("a", reason: .inWatchlist), in: recs), .other(.inWatchlist))
    }

    // MARK: contra una consola de mentira
    private func consoleRig() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        func row(_ id: String, rank: Int? = nil) -> JSON {
            var r: [String: JSON] = ["key": .string("video:\(id)"), "kind": "movie", "meta_id": .string(id), "title": .string(id), "year": 2021, "why": "En Netflix",
                                     "image": "https://p.jpg", "hero": "https://h.jpg", "overview": "", "video_id": .string(id)]
            if let rank { r["rank"] = .int(rank) }
            return .object(r)
        }
        rig.http.json["https://tv.example/api/foryou"] = [
            "lists": [["id": "chart:netflix", "title": "Top 10 en Netflix", "source": "Netflix", "meta": "Esta semana en México", "split": true, "brand": "netflix", "logo": "https://logo/n.png"],
                      ["id": "watchlist", "title": "Tu watchlist", "source": "Trakt", "meta": "Lo que dejaste pendiente"],
                      ["id": "cat:x", "title": "Un catálogo", "source": "Stremio", "meta": "De un complemento", "split": false]],
            "mosaic": [row("tt0000001")],
        ]
        rig.http.json["https://tv.example/api/foryou/list?id=chart:netflix&kind=series"] = ["items": [row("tt1000001", rank: 1)]]
        rig.http.json["https://tv.example/api/foryou/list?id=chart:netflix&kind=movie"] = ["items": [row("tt2000001", rank: 1)]]
        rig.http.json["https://tv.example/api/foryou/list?id=watchlist&kind=series"] = ["items": [row("tt3000001")]]
        rig.http.json["https://tv.example/api/foryou/list?id=cat:x&kind=series"] = ["items": []]   // vacío: no se pinta
        return rig
    }

    func testKindSelectorOnlyReloadsTheShelvesThatSplit() async throws {
        let rig = try consoleRig()
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.shelves.map(\.id), ["mine", "chart:netflix", "cat:x"])
        XCTAssertEqual(model.visibleShelves.map(\.id), ["mine", "chart:netflix"], "el estante vacío se descarta")
        XCTAssertTrue(model.hasKindSplit)
        let chart = try XCTUnwrap(model.shelves.first { $0.id == "chart:netflix" })
        XCTAssertEqual(model.items(for: chart).map(\.imdb), ["tt1000001"])
        XCTAssertEqual(model.items(for: chart).first?.rank, 1)
        let before = rig.http.calls.filter { $0.contains("id=watchlist") }.count
        await model.setKind("movie")
        XCTAssertEqual(model.items(for: chart).map(\.imdb), ["tt2000001"])
        XCTAssertEqual(rig.http.calls.filter { $0.contains("id=watchlist") }.count, before, "Lo tuyo no tiene split: no se vuelve a pedir")
        XCTAssertEqual(model.items(for: try XCTUnwrap(model.shelves.first)).map(\.imdb), ["tt3000001"])
        let chartList = try XCTUnwrap(model.lists.first { $0.id == "chart:netflix" })
        XCTAssertEqual(chartList.meta, "Esta semana en México")
        XCTAssertEqual(chartList.source, "Netflix")
    }

    func testEmptyFeedFallsBackToPopularAndInvitesToConnectSources() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top.json"] = ["metas": [["id": "tt0386676", "type": "series", "name": "The Office", "poster": "https://p/poster/small/1.jpg", "background": "https://b/1.jpg"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top.json"] = ["metas": []]
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertTrue(model.feedIsEmpty)
        XCTAssertTrue(model.needsSources)
        XCTAssertEqual(model.featured?.item.imdb, "tt0386676", "el destacado sale de lo popular de Stremio")
        XCTAssertNil(model.featured?.shelfID)
    }
}
