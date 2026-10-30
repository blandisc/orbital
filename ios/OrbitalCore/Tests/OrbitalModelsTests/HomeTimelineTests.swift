import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Lo nuevo de lo tuyo»: lo que salió y lo que viene en una sola línea, sin repetir y en orden.
final class HomeTimelineTests: XCTestCase {
    func airing(_ imdb: String, _ title: String, daysFromNow: Double) -> Airing {
        let at = Date(timeIntervalSince1970: 1_800_000_000 + daysFromNow * 86400)
        let series = Suggestion(kind: "series", imdb: imdb, title: title, poster: "", wide: "", reason: .watching)
        return Airing(series: series, season: 1, first: 1, last: 1, count: 1, episodeTitle: "", aired: at,
                      day: Calendar.current.startOfDay(for: at), network: "", atDawn: false)
    }

    func testJuntaLoQueSalioYLoQueVieneEnOrden() {
        let recent = [airing("tt2", "B", daysFromNow: -1), airing("tt1", "A", daysFromNow: -3)]
        let upcoming = [airing("tt3", "C", daysFromNow: 2), airing("tt4", "D", daysFromNow: 0)]
        XCTAssertEqual(HomeModel.timeline(recent: recent, upcoming: upcoming).map(\.series.imdb), ["tt1", "tt2", "tt4", "tt3"])
    }

    func testNoRepiteElMismoDia() {
        let today = airing("tt1", "A", daysFromNow: 0)
        XCTAssertEqual(HomeModel.timeline(recent: [today], upcoming: [today]).count, 1)
    }
}
