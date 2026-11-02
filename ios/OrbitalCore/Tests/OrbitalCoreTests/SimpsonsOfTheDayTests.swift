import XCTest
@testable import OrbitalCore

final class SimpsonsOfTheDayTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!; return c }

    /// El mismo día da el mismo episodio a cualquier hora, y no se repite uno hasta recorrer todos.
    func testOneEpisodePerDayWithoutRepeatsUntilAllAreSeen() {
        let count = 242, start = Date(timeIntervalSince1970: 1_793_600_000)
        let morning = SimpsonsOfTheDay.index(for: start, count: count, calendar: calendar)
        XCTAssertEqual(morning, SimpsonsOfTheDay.index(for: start.addingTimeInterval(3 * 3600), count: count, calendar: calendar))
        let picks = (0..<count).map { SimpsonsOfTheDay.index(for: start.addingTimeInterval(Double($0) * 86_400), count: count, calendar: calendar) }
        XCTAssertEqual(Set(picks).count, count)
        XCTAssertTrue(zip(picks, picks.dropFirst()).allSatisfy { abs($0 - $1) > 1 }, "dos días seguidos no caen en episodios vecinos")
    }

    func testDayFallsBackToTheLastOneBuilt() throws {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_793_600_000))
        let week = SimpsonsOfTheDay(days: [.init(day: day, season: 6, episode: 12, title: "Homer the Great", videoID: "tt0096697:6:12", still: "s")], seasons: [6])
        XCTAssertEqual(week.day(for: day.addingTimeInterval(3 * 86_400), calendar: calendar)?.episode, 12)
        XCTAssertEqual(week.days.first?.link, WidgetLink.play(kind: "series", id: "tt0096697", video: "tt0096697:6:12"))
        XCTAssertEqual(SimpsonsOfTheDay.decode(try week.encoded()), week)
    }
}

final class WidgetListsTests: XCTestCase {
    /// Sin listas vacías, con tope de listas y de pósters; si la elegida ya no existe, la primera.
    func testListsAreTrimmedAndFallBackToTheFirst() throws {
        func poster(_ i: Int) -> WidgetLists.Poster { .init(kind: "movie", metaID: "tt\(i)", title: "T\(i)", poster: "p\(i)") }
        let lists = (0..<15).map { WidgetLists.List(id: "l\($0)", title: "Lista \($0)", posters: $0 == 1 ? [] : (0..<30).map(poster)) }
        let model = WidgetLists(lists: lists)
        XCTAssertEqual(model.lists.count, WidgetLists.maxLists)
        XCTAssertFalse(model.lists.contains { $0.id == "l1" })
        XCTAssertEqual(model.lists.first?.posters.count, WidgetLists.maxPosters)
        XCTAssertEqual(model.list("l3")?.title, "Lista 3")
        XCTAssertEqual(model.list("ya-no")?.id, "l0")
        XCTAssertEqual(WidgetLists.imageFileName(for: "tt1:2"), "tt1_2.jpg")
        XCTAssertEqual(WidgetLists.decode(try model.encoded()), model)
    }
}
