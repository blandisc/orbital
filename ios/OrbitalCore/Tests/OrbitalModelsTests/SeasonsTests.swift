import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// BOCETO: «Por temporada» elige la colección por la fecha; «Lo mejor del género» ordena por calificación.
final class SeasonsTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    private func first(_ y: Int, _ m: Int, _ d: Int) -> String { Seasons.ordered(on: date(y, m, d), calendar: calendar).first!.id }

    func testTheSeasonOfTodayGoesFirst() {
        XCTAssertEqual(first(2026, 10, 23), "halloween")
        XCTAssertEqual(first(2026, 11, 2), "muertos")
        XCTAssertEqual(first(2026, 12, 24), "navidad")
        XCTAssertEqual(first(2027, 1, 3), "navidad", "Navidad cruza el año nuevo")
        XCTAssertEqual(first(2027, 2, 14), "sanvalentin")
        XCTAssertEqual(first(2027, 7, 15), "verano")
    }

    func testBetweenSeasonsTheNextOneGoesFirst() {
        XCTAssertNil(Seasons.current(on: date(2027, 4, 10), calendar: calendar))
        XCTAssertEqual(first(2027, 4, 10), "verano")
        XCTAssertEqual(first(2026, 11, 15), "navidad")
        XCTAssertEqual(first(2026, 9, 10), "halloween")
    }

    func testTheRestFollowInCalendarOrder() {
        XCTAssertEqual(Seasons.ordered(on: date(2026, 10, 23), calendar: calendar).map(\.id), ["halloween", "muertos", "navidad", "sanvalentin", "verano"])
    }

    func testForcedSeasonGoesFirst() {
        XCTAssertEqual(Seasons.ordered(on: date(2026, 10, 23), calendar: calendar, forced: "sanvalentin").map(\.id).first, "sanvalentin")
        XCTAssertEqual(Seasons.ordered(on: date(2026, 10, 23), calendar: calendar, forced: "nada").first?.id, "halloween")
    }

    func testSeasonsDoNotOverlap() {
        for day in 0..<365 {
            let d = calendar.date(byAdding: .day, value: day, to: date(2027, 1, 1))!
            XCTAssertLessThanOrEqual(Seasons.all.filter { $0.contains(Seasons.monthDay(d, calendar: calendar)) }.count, 1)
        }
    }

    func testGenreTopSortsByRating() {
        func item(_ id: String) -> CatalogItem { CatalogItem(kind: "movie", metaID: id, title: id, originalTitle: id, poster: nil, year: "") }
        let ranked = GenreTop.rank([(item("a"), 7.1), (item("b"), nil), (item("c"), 8.9), (item("a"), 9.9), (item("d"), 7.1)])
        XCTAssertEqual(ranked.map(\.metaID), ["c", "a", "d", "b"], "mayor primero, sin calificación al final, sin repetidos")
    }
}
