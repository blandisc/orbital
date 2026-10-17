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

    func testShelvesFollowTheTVOrder() {
        let ids = ShelfPlanner.plan(overview).map(\.id)
        XCTAssertEqual(ids, ["recs", "mine", "watchlist", "list:7", "trend", "popular", "tv:movies", "chart:netflix", "jw:disney", "netflix", "hbo"],
                       "el orden de foryou.py; Seguir viendo y Mi lista viven en Inicio")
    }

    func testEachListIsItsOwnShelfLikeTheTV() {
        let plan = ShelfPlanner.plan(overview)
        XCTAssertTrue(plan.allSatisfy { $0.listIDs.count == 1 }, "sin «Lo tuyo»: Tus series y Tu watchlist van aparte, como en la TV")
        XCTAssertEqual(plan.first { $0.id == "watchlist" }?.title, "Tu watchlist")
    }

    func testTMDBFallbackIsMarkedWhenTheBrandHasARankedList() {
        let plan = Dictionary(uniqueKeysWithValues: ShelfPlanner.plan(overview).map { ($0.id, $0) })
        XCTAssertEqual(plan["netflix"]?.isFallback, true, "hay Top 10 de Netflix: el respaldo solo se ve si ese llega vacío")
        XCTAssertEqual(plan["hbo"]?.isFallback, false, "no hay jw:hbo: el respaldo de TMDB es el estante de HBO")
    }

    func testTheCalendarListIsNotAShelfOfItsOwn() {
        let ids = ShelfPlanner.plan(overview + [list("estrenos", title: "Próximos estrenos", group: .mine)]).map(\.id)
        XCTAssertFalse(ids.contains("estrenos"), "los estrenos salen de `airings`: su estante es el de calendario, justo después del destacado")
    }

    func testStylesTop10PlatformAndPlain() {
        let styles = Dictionary(uniqueKeysWithValues: ShelfPlanner.plan(overview).map { ($0.id, $0.style) })
        XCTAssertEqual(styles["chart:netflix"], .top10)
        XCTAssertEqual(styles["jw:disney"], .top10, "JustWatch también trae puesto: cifra grande, como RankedCard en la TV")
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
        XCTAssertEqual(ShelfPlanner.featuredSlides(shelves, rotation: 1)?.items.map(\.imdb), ["tt3", "tt2"],
                       "el carrusel: las de arte ancho de esa misma lista, empezando por la que toca")
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
        rig.services.forYouFromConsole = true   // la ruta de la consola (en la app, Para ti se calcula en el iPhone)
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
        XCTAssertEqual(model.shelves.map(\.id), ["watchlist", "cat:x", "chart:netflix"], "el orden de la TV")
        XCTAssertEqual(model.visibleShelves.map(\.id), ["watchlist", "chart:netflix"], "el estante vacío se descarta")
        XCTAssertTrue(model.hasKindSplit)
        let chart = try XCTUnwrap(model.shelves.first { $0.id == "chart:netflix" })
        XCTAssertEqual(model.kind, "all", "«Todo» de entrada: series y películas alternadas")
        XCTAssertEqual(model.items(for: chart).map(\.imdb), ["tt1000001", "tt2000001"])
        XCTAssertEqual(model.items(for: chart).first?.rank, 1)
        await model.setKind("series")
        XCTAssertEqual(model.items(for: chart).map(\.imdb), ["tt1000001"])
        let before = rig.http.calls.filter { $0.contains("id=watchlist") }.count
        await model.setKind("movie")
        XCTAssertEqual(model.items(for: chart).map(\.imdb), ["tt2000001"])
        XCTAssertEqual(rig.http.calls.filter { $0.contains("id=watchlist") }.count, before, "Lo tuyo no tiene split: no se vuelve a pedir")
        XCTAssertEqual(model.items(for: try XCTUnwrap(model.shelves.first)).map(\.imdb), ["tt3000001"])
        let chartList = try XCTUnwrap(model.lists.first { $0.id == "chart:netflix" })
        XCTAssertEqual(chartList.meta, "Esta semana en México")
        XCTAssertEqual(chartList.source, "Netflix")
    }

    func testTheFallbackShowsOnlyWhenTheRankedListOfItsBrandIsEmpty() async throws {
        let rig = try consoleRig()
        func row(_ id: String) -> JSON { ["key": .string("video:\(id)"), "kind": "series", "meta_id": .string(id), "title": .string(id), "image": "https://p.jpg", "video_id": .string(id)] }
        rig.http.json["https://tv.example/api/foryou"] = [
            "lists": [["id": "chart:netflix", "title": "Top 10 en Netflix", "split": true, "brand": "netflix"],
                      ["id": "jw:disney", "title": "Tendencias en Disney+", "split": true, "brand": "disney"],
                      ["id": "netflix", "title": "Netflix", "split": true, "brand": "netflix"],
                      ["id": "disney", "title": "Disney+", "split": true, "brand": "disney"]],
            "mosaic": [row("tt0000001")],
        ]
        rig.http.json["https://tv.example/api/foryou/list?id=jw:disney&kind=series"] = ["items": []]   // JustWatch no trajo nada
        rig.http.json["https://tv.example/api/foryou/list?id=netflix&kind=series"] = ["items": [row("tt5")]]
        rig.http.json["https://tv.example/api/foryou/list?id=disney&kind=series"] = ["items": [row("tt6")]]
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.visibleShelves.map(\.id), ["chart:netflix", "disney"],
                       "Netflix ya tiene Top 10 (su respaldo no); Disney+ sin JustWatch: su respaldo sí, para que no desaparezca")
    }

    func testTheOverviewIsAskedOnceEvenThoughListsAndMosaicNeedIt() async throws {
        let rig = try consoleRig()
        rig.http.delays["https://tv.example/api/foryou"] = 100   // las dos peticiones se cruzan
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(rig.http.calls.filter { $0 == "https://tv.example/api/foryou" }.count, 1,
                       "el mosaico y las listas esperan la misma petición (dos idénticas duplicaban la espera)")
        XCTAssertFalse(model.shelves.isEmpty, "y sí cargó de la consola")
    }

    func testAShelfThatFailedIsAskedAgainOnTheNextLoad() async throws {
        let rig = try consoleRig()
        let url = "https://tv.example/api/foryou/list?id=watchlist&kind=series"
        let saved = rig.http.json[url]
        rig.http.json[url] = nil   // la consola no contesta ese estante (404)
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertFalse(model.visibleShelves.contains { $0.id == "watchlist" })
        rig.http.json[url] = saved
        await model.load()
        XCTAssertEqual(model.items(for: try XCTUnwrap(model.shelves.first { $0.id == "watchlist" })).map(\.imdb), ["tt3000001"],
                       "un fallo no se guarda como estante vacío: la siguiente carga lo vuelve a pedir")
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

final class DecideRulesTests: XCTestCase {
    func testTimeAndMoodRules() {
        XCTAssertTrue(DecideModel.fits(30, .short)); XCTAssertFalse(DecideModel.fits(58, .short))
        XCTAssertTrue(DecideModel.fits(58, .hour)); XCTAssertFalse(DecideModel.fits(140, .hour)); XCTAssertTrue(DecideModel.fits(140, .long))
        XCTAssertFalse(DecideModel.fits(nil, .short), "sin duración, no para «30 min»")
        XCTAssertTrue(DecideModel.matches(["Comedy"], .light), "los de Cinemeta")
        XCTAssertTrue(DecideModel.matches(["science-fiction"], .think), "y los de Trakt")
        XCTAssertFalse(DecideModel.matches(["horror"], .together))
        XCTAssertTrue(DecideModel.matches(["Science Fiction"], picked: ["sci-fi"]), "géneros elegidos: el mismo con otro nombre")
    }
}
