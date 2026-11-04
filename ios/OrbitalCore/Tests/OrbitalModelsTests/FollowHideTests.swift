import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Esconder» una serie (SS1-A, Fernando, 3 nov 2026: «Vamos con SS1A»): sale de «Series que sigues», de tus estrenos, de
/// «Sigue viendo», de los widgets y de los avisos, aquí y en Trakt; «Deshacer» la regresa como estaba y «Escondidas» la muestra
/// otra vez. Lo que viste no se toca.
@MainActor
final class FollowHideTests: XCTestCase {
    let api = "https://api.trakt.tv"
    var watchedURL: String { "\(api)/sync/watched/shows?extended=noseasons" }
    var hiddenURL: String { "\(api)/users/hidden/progress_watched?type=show&limit=1000" }

    func show(_ imdb: String, _ title: String, hoursAgo: Double = 1) -> JSON {
        ["last_watched_at": .string(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_760_000_000 - hoursAgo * 3600))),
         "show": ["title": .string(title), "ids": ["imdb": .string(imdb), "trakt": 1]]]
    }
    func hiddenRow(_ imdb: String, _ title: String) -> JSON { ["type": "show", "show": ["title": .string(title), "ids": ["imdb": .string(imdb), "trakt": 2]]] }
    func sentIDs(_ rig: ServicesRig, _ path: String) -> [String] {
        rig.http.bodies("\(api)\(path)").compactMap { JSON.parse($0)?["shows"]?.array?.first?["ids"]?["imdb"]?.string }
    }

    func linkedRig() throws -> ServicesRig {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        for path in ["calendar", "progress_watched"] {
            rig.http.json["\(api)/users/hidden/\(path)"] = ["added": ["shows": 1]]
            rig.http.json["\(api)/users/hidden/\(path)/remove"] = ["deleted": ["shows": 1]]
        }
        rig.http.json[watchedURL] = [show("tt0000001", "Lost"), show("tt0000002", "The Office", hoursAgo: 2)]
        rig.http.json[hiddenURL] = []
        return rig
    }

    func testEsconderLaSacaDeLaListaDeTusEstrenosYVaATrakt() async throws {
        let rig = try linkedRig()
        let cal = Calendar.current
        let start = ForYou.dayString(cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: rig.clock.now))!, calendar: cal)
        let aired = ISO8601DateFormatter().string(from: rig.clock.now.addingTimeInterval(-3 * 3600))
        func airing(_ imdb: String) -> JSON {
            ["first_aired": .string(aired), "episode": ["season": 1, "number": 1, "title": "Piloto"], "show": ["title": "Serie", "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        rig.http.json["\(api)/calendars/my/shows/\(start)/4?extended=full"] = [airing("tt0000001"), airing("tt0000002")]
        let model = FollowModel(rig.services)
        await model.loadSeries()
        XCTAssertEqual(model.visibleSeries.map(\.imdb), ["tt0000001", "tt0000002"])

        let problem = await model.hide("tt0000001")
        XCTAssertNil(problem)
        XCTAssertEqual(sentIDs(rig, "/users/hidden/progress_watched"), ["tt0000001"], "Trakt la quita de tu progreso («Sigue viendo»)")
        XCTAssertEqual(sentIDs(rig, "/users/hidden/calendar"), ["tt0000001"], "y de tu calendario (estrenos y avisos)")
        XCTAssertEqual(model.visibleSeries.map(\.imdb), ["tt0000002"], "sale de la lista")
        XCTAssertEqual(model.hiddenSeries.map(\.title), ["Lost"], "y entra a «Escondidas»")
        XCTAssertFalse(model.isFollowing("tt0000001"), "también deja de seguirla")
        let airings = try await rig.services.forYou.calendar(skip: -1, days: 2)
        XCTAssertEqual(airings.map(\.series.imdb), ["tt0000002"], "ni en tus estrenos ni en los avisos")
        XCTAssertEqual(FollowModel(rig.services).hidden, ["tt0000001"], "se recuerda")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/sync/history/remove") }, "lo que viste se queda")
    }

    func testDeshacerLaRegresaComoEstaba() async throws {
        let rig = try linkedRig()
        let model = FollowModel(rig.services)
        await model.loadSeries()
        _ = await model.setFollowing("tt0000001", false)   // ya estaba apagada
        _ = await model.hide("tt0000001")
        let problem = await model.undoHide()
        XCTAssertNil(problem)
        XCTAssertTrue(model.hidden.isEmpty)
        XCTAssertEqual(model.visibleSeries.map(\.imdb), ["tt0000001", "tt0000002"], "regresa a la lista")
        XCTAssertFalse(model.isFollowing("tt0000001"), "apagada, como estaba")
        XCTAssertEqual(sentIDs(rig, "/users/hidden/progress_watched/remove"), ["tt0000001"], "vuelve a tu progreso en Trakt")
        XCTAssertTrue(sentIDs(rig, "/users/hidden/calendar/remove").isEmpty, "pero sigue fuera de tu calendario: no te avisa")
        XCTAssertNil(model.lastHidden)
        let again = await model.undoHide()
        XCTAssertNil(again, "deshacer dos veces no hace nada")
    }

    func testMostrarOtraVezLaRegresaYLaVuelveASeguir() async throws {
        let rig = try linkedRig()
        let model = FollowModel(rig.services)
        await model.loadSeries()
        _ = await model.hide("tt0000002")
        let problem = await model.unhide("tt0000002")
        XCTAssertNil(problem)
        XCTAssertTrue(model.hiddenSeries.isEmpty)
        XCTAssertTrue(model.isFollowing("tt0000002"))
        XCTAssertEqual(sentIDs(rig, "/users/hidden/progress_watched/remove"), ["tt0000002"])
        XCTAssertEqual(sentIDs(rig, "/users/hidden/calendar/remove"), ["tt0000002"])
    }

    func testSiTraktNoContestaNoSeEsconde() async throws {
        let rig = try linkedRig()
        rig.http.statuses["\(api)/users/hidden/calendar"] = 500
        let model = FollowModel(rig.services)
        await model.loadSeries()
        let problem = await model.hide("tt0000001")
        XCTAssertNotNil(problem)
        XCTAssertTrue(model.hidden.isEmpty, "regresa como estaba")
        XCTAssertTrue(model.isFollowing("tt0000001"))
        XCTAssertTrue(ForYou.hidden(rig.kv).isEmpty)
    }

    /// Trakt manda: lo que escondiste en la TV o en trakt.tv se va de aquí, y lo que mostraste allá regresa. La que solo apagaste
    /// con el interruptor (que también la oculta en Trakt) se queda en tu lista.
    func testLoQueEscondisteEnOtroAparatoTambienSeVa() async throws {
        let rig = try linkedRig()
        rig.http.json[watchedURL] = [show("tt0000001", "Lost"), show("tt0000002", "The Office"), show("tt0000004", "Dark")]
        rig.http.json[hiddenURL] = [hiddenRow("tt0000002", "The Office"), hiddenRow("tt0000003", "Chernobyl")]
        ForYou.setUnfollowed(["tt0000002"], kv: rig.kv)   // apagada aquí con el interruptor
        ForYou.setHidden(["tt0000004"], kv: rig.kv)         // escondida aquí, mostrada otra vez en la TV
        let model = FollowModel(rig.services)
        await model.loadSeries()
        XCTAssertEqual(model.hidden, ["tt0000003"])
        XCTAssertEqual(model.hiddenSeries.map(\.title), ["Chernobyl"], "con el nombre que da Trakt aunque no salga en lo que viste")
        XCTAssertEqual(Set(model.visibleSeries.map(\.imdb)), ["tt0000001", "tt0000002", "tt0000004"])
        XCTAssertEqual(ForYou.hidden(rig.kv), ["tt0000003"], "lo leen tus estrenos, «Sigue viendo» y los widgets")
    }

    func testSeguirlaDesdeSuFichaLaSacaDeEscondidas() async throws {
        let rig = try linkedRig()
        let model = FollowModel(rig.services)
        await model.loadSeries()
        _ = await model.hide("tt0000001")
        _ = await model.setFollowing("tt0000001", true)
        XCTAssertTrue(model.hidden.isEmpty)
        XCTAssertEqual(model.visibleSeries.count, 2)
    }

    /// «Sigue viendo» en Inicio y el widget: sin la escondida, también la que venía guardada de antes.
    func testSigueViendoYElWidgetNoLaEnsenan() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": [
            ["_id": "tt0386676", "name": "The Office", "type": "series", "removed": true, "temp": true, "state": ["video_id": "tt0386676:2:5", "timeOffset": 600_000, "duration": 1_320_000, "lastWatched": "2025-01-02T00:00:00.000Z"]]]]
        var published: [WidgetSnapshot] = []
        rig.services.onWidgetSnapshot = { published.append($0) }
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(home.continueWatching.map(\.metaID), ["tt0386676"])
        let follow = FollowModel(rig.services)
        _ = await follow.hide("tt0386676")   // sin Trakt: solo aquí
        XCTAssertTrue(published.last?.items.isEmpty ?? false, "el widget se rearma sin ella")
        await home.showLibrary()
        XCTAssertTrue(home.continueWatching.isEmpty, "Inicio tampoco")
        XCTAssertTrue(HomeModel(rig.services).continueWatching.isEmpty, "ni lo guardado de la vez pasada")
    }

    func testElWidgetTampocoEnsenaSusEstrenos() throws {
        let rig = try ServicesRig()
        var published: [WidgetSnapshot] = []
        rig.services.onWidgetSnapshot = { published.append($0) }
        func airing(_ id: String) -> Airing {
            let date = Date(timeIntervalSince1970: 1_760_000_000 + 3600)
            return Airing(series: Suggestion(kind: "series", imdb: id, title: id, poster: "", wide: "", reason: .popular), season: 1, first: 1, last: 1, count: 1,
                          episodeTitle: "", aired: date, day: date, network: "", atDawn: false)
        }
        ForYou.setHidden(["b"], kv: rig.kv)
        rig.services.publishWidget(airings: [airing("a"), airing("b")])
        XCTAssertEqual(published.last?.upcoming?.map(\.metaID), ["a"])
    }
}
