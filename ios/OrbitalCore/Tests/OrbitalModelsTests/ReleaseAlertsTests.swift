import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Ya está para ver»: qué estrenos se avisan y cuándo (no a medianoche).
final class ReleaseAlertsTests: XCTestCase {
    let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!; return c }()

    func airing(_ imdb: String, aired: Date, first: Int = 2, last: Int = 2) -> Airing {
        let s = Suggestion(kind: "series", imdb: imdb, title: "Show", poster: "", wide: "", reason: .watching)
        return Airing(series: s, season: 4, first: first, last: last, count: last - first + 1, episodeTitle: "Bolognese", aired: aired,
                      day: calendar.startOfDay(for: aired), network: "FX", atDawn: false)
    }

    func testOnlyWhatAlreadyAiredWithinTheWindowAndNotSent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let list = [
            airing("tt1", aired: now.addingTimeInterval(-3600)),                       // salió hace una hora
            airing("tt2", aired: now.addingTimeInterval(3600)),                        // todavía no sale
            airing("tt3", aired: now.addingTimeInterval(-ReleaseAlerts.window - 60)),  // ya no es estreno
            airing("tt4", aired: now.addingTimeInterval(-60), first: 1, last: 3),      // tres episodios de golpe
        ]
        let ids = ReleaseAlerts.pending(list, sent: ["tt4:4:2"], now: now).map(\.id)
        XCTAssertEqual(ids, ["tt1:4:2", "tt4:4:1", "tt4:4:3"])
    }

    func testQuietHoursWaitUntilEightInTheMorning() {
        func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: hour, minute: 30))! }
        XCTAssertNil(ReleaseAlerts.deliverAt(now: at(21), calendar: calendar))
        let late = ReleaseAlerts.deliverAt(now: at(23), calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: late), 19)
        XCTAssertEqual(calendar.component(.hour, from: late), 8)
        let early = ReleaseAlerts.deliverAt(now: at(3), calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: early), 18)
        XCTAssertEqual(calendar.component(.hour, from: early), 8)
    }
}

/// La revisión de estrenos de verdad (Trakt de mentira): se avisa en cuanto sale, tenga o no fuente en Real-Debrid
/// (Fernando, 1 nov 2026), y sin preguntar a los complementos.
@MainActor
final class ReleaseAlertsCheckTests: XCTestCase {
    func testSeAvisaEnCuantoSaleAunqueRealDebridNoLoTenga() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.services.settings.update { $0.releaseAlerts = true }
        let now = rig.clock.now
        let cal = Calendar.current
        let start = ForYou.dayString(cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!, calendar: cal)
        let aired = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3 * 3600))
        func row(_ imdb: String, _ title: String) -> JSON {
            ["first_aired": .string(aired), "episode": ["season": 2, "number": 1, "title": "Estreno"],
             "show": ["title": .string(title), "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        rig.http.json["https://api.trakt.tv/calendars/my/shows/\(start)/4?extended=full"] = [row("tt0000001", "Sin fuentes aún"), row("tt0000002", "Ya tiene")]
        let alerts = ReleaseAlerts(rig.services)
        let due = await alerts.due()
        XCTAssertEqual(due.map(\.id).sorted(), ["tt0000001:2:1", "tt0000002:2:1"], "los dos: salir basta")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/stream/") }, "no se pregunta por fuentes")
        alerts.markSent(due.map(\.id))
        let again = await alerts.due()
        XCTAssertTrue(again.isEmpty, "una sola vez")
    }

    /// Dos episodios el mismo día: cada uno con su aviso, su nombre y su imagen (Trakt trae un solo nombre por estreno y
    /// ninguna imagen; salía «4 estrenos ya para ver» en una lista y el segundo sin nombre, 30 oct).
    func testEachEpisodeBringsItsOwnNameAndStill() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.services.settings.update { $0.releaseAlerts = true }
        let now = rig.clock.now
        let cal = Calendar.current
        let start = ForYou.dayString(cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!, calendar: cal)
        let aired = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3 * 3600))
        func row(_ number: Int, _ title: String) -> JSON {
            ["first_aired": .string(aired), "episode": ["season": 1, "number": .int(number), "title": .string(title)],
             "show": ["title": "Avatar", "ids": ["imdb": "tt0000003", "trakt": 3]]]
        }
        rig.http.json["https://api.trakt.tv/calendars/my/shows/\(start)/4?extended=full"] = [row(10, "Ghosts and Spirits"), row(11, "Battle of the Ruins")]
        for n in [10, 11] {
            rig.http.json["https://a.example/stream/series/tt0000003%3A1%3A\(n).json"] = ["streams": [
                ["name": "T\n1080p [RD+]", "title": .string("Avatar.S01E\(n).1080p.WEB-DL\n💾 1 GB"), "url": .string("https://rd.example/\(n).mkv")]]]
        }
        rig.http.json["https://v3-cinemeta.strem.io/meta/series/tt0000003.json"] = ["meta": ["id": "tt0000003", "name": "Avatar", "type": "series", "videos": [
            ["id": "tt0000003:1:10", "season": 1, "episode": 10, "name": "Ghosts and Spirits", "thumbnail": "https://episodes.example/10.jpg"],
            ["id": "tt0000003:1:11", "season": 1, "episode": 11, "name": "Battle of the Ruins", "thumbnail": "https://episodes.example/11.jpg"],
        ]]]
        let alerts = ReleaseAlerts(rig.services)
        let due = await alerts.due().sorted { $0.episode < $1.episode }
        XCTAssertEqual(due.map(\.id), ["tt0000003:1:10", "tt0000003:1:11"], "uno por episodio")
        XCTAssertEqual(due.map(\.episodeTitle), ["Ghosts and Spirits", "Battle of the Ruins"])
        XCTAssertEqual(due.map(\.still), ["https://episodes.example/10.jpg", "https://episodes.example/11.jpg"])
    }
}
