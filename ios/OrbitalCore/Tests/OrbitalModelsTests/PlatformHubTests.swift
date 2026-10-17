import XCTest
import OrbitalCore
@testable import OrbitalModels

final class PlatformHubTests: XCTestCase {
    func testPlatformsGroupTheirRealRankingsAndUsePopularOnlyWithoutOne() {
        let lists = [
            ForYouList(id: "recs", title: "", group: .discover, splitsKinds: true),
            ForYouList(id: "chart:netflix", title: "Top 10 en Netflix", group: .platforms, brand: "netflix", logo: "n.png", splitsKinds: true),
            ForYouList(id: "jw:disney", title: "Tendencias en Disney+", group: .platforms, brand: "disney", logo: "d.png", splitsKinds: true),
            ForYouList(id: "tmdb:disney", title: "Disney+", group: .platforms, brand: "disney", splitsKinds: true),
            ForYouList(id: "tmdb:hbo", title: "HBO Max", group: .platforms, brand: "hbo", splitsKinds: true),
        ]
        let hubs = PlatformPlanner.hubs(lists)
        XCTAssertEqual(hubs.map(\.brand), ["netflix", "disney", "hbo"], "en el orden en que llegan")
        XCTAssertEqual(hubs[0].name, "Netflix")
        XCTAssertEqual(hubs[0].rankings.map(\.id), ["chart:netflix:series", "chart:netflix:movie"])
        XCTAssertEqual(hubs[0].rankings.first?.source, .netflixTop10)
        XCTAssertEqual(hubs[1].rankings.map(\.source), [.justWatch, .justWatch], "Disney+ tiene ranking: lo popular de TMDB no entra")
        XCTAssertEqual(hubs[2].rankings.map(\.source), [.popular, .popular], "HBO Max sin ranking: lo popular")
        XCTAssertEqual(hubs[1].logo, "d.png")
    }
}
