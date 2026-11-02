import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Dejar de seguir una serie: sale de tus estrenos (y de los avisos) al momento, Trakt la oculta de tu calendario y tu
/// progreso, y se puede volver a seguir.
@MainActor
final class FollowModelTests: XCTestCase {
    func testDejarDeSeguirLaQuitaDeTusEstrenosYVaATrakt() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let now = rig.clock.now
        let cal = Calendar.current
        let start = ForYou.dayString(cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!, calendar: cal)
        let aired = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3 * 3600))
        func row(_ imdb: String) -> JSON {
            ["first_aired": .string(aired), "episode": ["season": 1, "number": 1, "title": "Piloto"], "show": ["title": "Serie", "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        rig.http.json["https://api.trakt.tv/calendars/my/shows/\(start)/4?extended=full"] = [row("tt0000001"), row("tt0000002")]
        rig.http.json["https://api.trakt.tv/users/hidden/calendar"] = ["added": ["shows": 1]]
        rig.http.json["https://api.trakt.tv/users/hidden/progress_watched"] = ["added": ["shows": 1]]
        let model = FollowModel(rig.services)
        XCTAssertTrue(model.isFollowing("tt0000001"))
        let problem = await model.setFollowing("tt0000001", false)
        XCTAssertNil(problem)
        XCTAssertFalse(model.isFollowing("tt0000001"))
        let sent = try XCTUnwrap(JSON.parse(try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/users/hidden/calendar").first)))
        XCTAssertEqual(sent["shows"]?.array?.first?["ids"]?["imdb"]?.string, "tt0000001")
        XCTAssertFalse(rig.http.bodies("https://api.trakt.tv/users/hidden/progress_watched").isEmpty, "también sale de tu progreso")
        let airings = try await rig.services.forYou.calendar(skip: -1, days: 2)
        XCTAssertEqual(Set(airings.map(\.series.imdb)), ["tt0000002"], "ni en tus estrenos ni en los avisos")
        XCTAssertFalse(FollowModel(rig.services).isFollowing("tt0000001"), "se recuerda")

        rig.http.json["https://api.trakt.tv/users/hidden/calendar/remove"] = ["deleted": ["shows": 1]]
        rig.http.json["https://api.trakt.tv/users/hidden/progress_watched/remove"] = ["deleted": ["shows": 1]]
        let back = await model.setFollowing("tt0000001", true)
        XCTAssertNil(back)
        XCTAssertTrue(model.isFollowing("tt0000001"))
    }

    func testSiTraktNoContestaRegresa() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.statuses["https://api.trakt.tv/users/hidden/calendar"] = 500
        let model = FollowModel(rig.services)
        let problem = await model.setFollowing("tt0000001", false)
        XCTAssertNotNil(problem)
        XCTAssertTrue(model.isFollowing("tt0000001"), "regresa como estaba")
    }
}
