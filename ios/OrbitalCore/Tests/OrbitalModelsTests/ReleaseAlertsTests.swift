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

/// La revisión de estrenos de verdad (Trakt y complementos de mentira): un episodio sin fuentes todavía (su complemento no
/// contesta) ya no se come el tiempo del que sí tiene fuente.
@MainActor
final class ReleaseAlertsCheckTests: XCTestCase {
    func testASlowEpisodeNoLongerHidesOneThatHasASource() async throws {
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
        // El primero: el complemento tarda (como uno que no tiene nada y no contesta); el segundo ya tiene fuente.
        rig.http.delays["https://a.example/stream/series/tt0000001%3A2%3A1.json"] = 3_000
        rig.http.json["https://a.example/stream/series/tt0000001%3A2%3A1.json"] = ["streams": []]
        rig.http.json["https://a.example/stream/series/tt0000002%3A2%3A1.json"] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "Show.S02E01.1080p.WEB-DL\n💾 2 GB", "url": "https://rd.example/e.mkv"]]]
        let alerts = ReleaseAlerts(rig.services)
        alerts.budget = 0.5
        let started = Date()
        let due = await alerts.due()
        XCTAssertEqual(due.map(\.id), ["tt0000002:2:1"], "el que tiene fuente se avisa")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "no espera al lento: cabe en el tiempo de iOS")
        XCTAssertEqual(alerts.report.pending.sorted(), ["tt0000001:2:1", "tt0000002:2:1"])
        XCTAssertEqual(alerts.report.timedOut, ["tt0000001:2:1"], "la bitácora dice cuál no contestó a tiempo")
    }
}
