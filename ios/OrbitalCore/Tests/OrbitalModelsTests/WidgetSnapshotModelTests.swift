import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

@MainActor
final class WidgetSnapshotModelTests: XCTestCase {
    private func item(_ id: String, kind: String = "series", season: Int? = 2, episode: Int? = 6, progress: Double? = 0.4, left: Int = 20, nextUp: Bool = false) -> HomeItem {
        HomeItem(metaID: id, kind: kind, title: "Título \(id)", originalTitle: id, poster: "https://img/\(id)", background: nil, videoID: "\(id):2:6",
                 progress: progress, season: season, episode: episode, timeLeft: "", leftMinutes: left, nextUp: nextUp)
    }

    func testSnapshotTakesTheFirstThreeOfContinueWatchingWithTheirLabels() {
        let snapshot = WidgetSnapshot.make(continueWatching: [item("a"), item("b", season: nil, episode: nil, left: 100), item("c", left: 0, nextUp: true), item("d")],
                                           labels: .spanish, language: "es")
        XCTAssertEqual(snapshot.items.map(\.metaID), ["a", "b", "c"])
        XCTAssertEqual(snapshot.items[0].detail, "T2 · E6 · quedan 20 min")
        XCTAssertEqual(snapshot.items[0].progress, 0.4)
        XCTAssertEqual(snapshot.items[1].detail, "quedan 1 h 40 min", "una película no lleva episodio")
        XCTAssertEqual(snapshot.items[2].detail, "Sigue: T2 · E6")
        XCTAssertNil(snapshot.items[2].progress, "el siguiente episodio no tiene avance")
        XCTAssertNil(snapshot.upcoming, "el calendario aún no existe")
    }

    func testHomeRefreshPublishesTheSnapshotAndDismissingUpdatesIt() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": [
            ["_id": "tt0386676", "name": "The Office", "type": "series", "removed": true, "temp": true, "state": ["video_id": "tt0386676:2:5", "timeOffset": 600_000, "duration": 1_320_000, "lastWatched": "2025-01-02T00:00:00.000Z"]]]]
        var published: [WidgetSnapshot] = []
        rig.services.onWidgetSnapshot = { published.append($0) }
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(published.last?.items.map(\.metaID), ["tt0386676"])
        XCTAssertEqual(published.last?.items.first?.detail, "T2 · E5 · quedan 12 min")
        XCTAssertEqual(published.last?.items.first?.videoID, "tt0386676:2:5")
        await home.dismiss(try XCTUnwrap(home.continueWatching.first))
        XCTAssertEqual(published.last?.items.count, 0)
    }

    func testUpcomingTakesTheTwoNearestAiringsAndPublishKeepsBothHalves() throws {
        func airing(_ id: String, _ title: String, day: Double) -> Airing {
            let date = Date(timeIntervalSince1970: day)
            return Airing(series: Suggestion(kind: "series", imdb: id, title: title, poster: "", wide: "", reason: .popular), season: 3, first: 4, last: 4, count: 1,
                          episodeTitle: "", aired: date, day: date, network: "", atDawn: false)
        }
        let airings = [airing("a", "Severance", day: 1_760_000_000), airing("b", "Andor", day: 1_760_086_400), airing("c", "Fallout", day: 1_760_172_800)]
        let upcoming = WidgetSnapshot.upcoming(from: airings)
        XCTAssertEqual(upcoming.map(\.title), ["Severance", "Andor"])
        XCTAssertEqual(upcoming.first?.episodeLabel, "T3 E4")

        let rig = try ServicesRig()
        var published: [WidgetSnapshot] = []
        rig.services.onWidgetSnapshot = { published.append($0) }
        rig.services.publishWidget(continueWatching: [item("x")])
        XCTAssertNil(published.last?.upcoming)
        rig.services.publishWidget(airings: airings)
        XCTAssertEqual(published.last?.items.map(\.metaID), ["x"], "se conserva «Seguir viendo»")
        XCTAssertEqual(published.last?.upcoming?.map(\.title), ["Severance", "Andor", "Fallout"], "lo que ya salió también va (es «Lo nuevo de lo tuyo»)")
        XCTAssertEqual(published.last?.upcoming?.first?.metaID, "a", "con la serie para abrir su ficha")
    }

    /// La línea del widget: lo último que salió (hasta 3) y lo que viene (hasta 6), en orden de hora y sin repetir.
    func testTimelineKeepsTheLastThreeOutAndTheNextSix() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        func airing(_ id: String, hours: Double) -> Airing {
            let date = now.addingTimeInterval(hours * 3600)
            return Airing(series: Suggestion(kind: "series", imdb: id, title: id, poster: "p\(id)", wide: "", reason: .popular), season: 1, first: 1, last: 1,
                          count: 1, episodeTitle: "", aired: date, day: Calendar.current.startOfDay(for: date), network: "", atDawn: false)
        }
        let recent = (1...5).map { airing("r\($0)", hours: -Double($0) * 24) }
        let upcoming = (1...8).map { airing("u\($0)", hours: Double($0) * 5) } + [airing("r1", hours: -24)]
        let line = WidgetSnapshot.timeline(recent: recent, upcoming: upcoming, now: now)
        XCTAssertEqual(line.map(\.metaID), ["r3", "r2", "r1", "u1", "u2", "u3", "u4", "u5", "u6"])
        XCTAssertEqual(line.filter { $0.isOut(at: now) }.count, 3)
        XCTAssertEqual(line.first?.poster, "pr3")
        XCTAssertEqual(line.first?.link, WidgetLink.title(kind: "series", id: "r3"))
    }
}
