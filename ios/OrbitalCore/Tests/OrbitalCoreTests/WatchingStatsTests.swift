import XCTest
@testable import OrbitalCore

/// «Lo que ves»: el historial contado por periodo (horas, títulos, rachas, barras, géneros y lo que más viste).
final class WatchingStatsTests: XCTestCase {
    var calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T20:00:00Z")! }
    func play(_ day: String, _ imdb: String, _ kind: String = "movie", minutes: Int = 120, genres: [String] = ["drama"]) -> TraktPlay {
        TraktPlay(at: date(day), kind: kind, imdb: imdb, title: imdb, minutes: minutes, genres: genres)
    }

    func testLaSemanaCuentaDesdeElLunes() {
        let now = date("2026-10-29")   // jueves
        let plays = [play("2026-10-26", "tt1"), play("2026-10-27", "tt2", "series", minutes: 45, genres: ["comedy"]),
                     play("2026-10-28", "tt2", "series", minutes: 45, genres: ["comedy"]), play("2026-10-29", "tt2", "series", minutes: 45, genres: ["comedy"]),
                     play("2026-10-20", "tt9")]   // la semana pasada: no cuenta
        let s = WatchingStats.make(plays, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(s.minutes, 255)
        XCTAssertEqual(s.movies, 1); XCTAssertEqual(s.episodes, 3); XCTAssertEqual(s.titles, 2)
        XCTAssertEqual(s.currentStreak, 4); XCTAssertEqual(s.longestStreak, 4)
        XCTAssertEqual(s.buckets.count, 4, "lunes a jueves")
        XCTAssertEqual(s.genres.first?.name, "comedy")
        XCTAssertEqual(s.top.first?.imdb, "tt2", "lo que más tiempo te llevó")
        XCTAssertEqual(s.busiestDay?.minutes, 120)
    }

    func testElAnoPorMesesYLaRachaDeHoy() {
        let now = date("2026-03-10")
        let plays = [play("2026-01-05", "tt1"), play("2026-03-08", "tt2"), play("2026-03-09", "tt3")]
        let s = WatchingStats.make(plays, period: .year, now: now, calendar: calendar)
        XCTAssertEqual(s.buckets.map(\.minutes), [120, 0, 240])
        XCTAssertEqual(s.currentStreak, 2, "ayer y antier: hoy aún no ves nada y la racha sigue viva")
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(WatchingStats.make([], period: .month, now: now, calendar: calendar).isEmpty)
    }

    func testSiempreEmpiezaEnLoMasViejo() {
        let now = date("2026-03-10")
        let s = WatchingStats.make([play("2024-05-01", "tt1"), play("2026-01-01", "tt2")], period: .all, now: now, calendar: calendar)
        XCTAssertEqual(s.buckets.count, 3, "2024, 2025 y 2026")
        XCTAssertEqual(s.titles, 2)
    }
}
