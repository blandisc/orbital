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
