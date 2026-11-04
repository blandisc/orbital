import XCTest
@testable import OrbitalCore

final class SimpsonsOfTheDayTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!; return c }

    /// La tanda del día no cambia en el día, no repite episodios y, día tras día, no vuelve uno hasta recorrerlos todos.
    func testDailyBatchHasNoRepeatsUntilAllAreSeen() {
        let count = 240, take = 16, start = Date(timeIntervalSince1970: 1_793_600_000)
        let morning = SimpsonsOfTheDay.indices(for: start, count: count, take: take, calendar: calendar)
        XCTAssertEqual(morning, SimpsonsOfTheDay.indices(for: start.addingTimeInterval(3 * 3600), count: count, take: take, calendar: calendar))
        XCTAssertEqual(Set(morning).count, take)
        XCTAssertTrue(zip(morning, morning.dropFirst()).allSatisfy { abs($0 - $1) > 1 }, "dos seguidos no son episodios vecinos")
        let days = count / take
        let all = (0..<days).flatMap { SimpsonsOfTheDay.indices(for: start.addingTimeInterval(Double($0) * 86_400), count: count, take: take, calendar: calendar) }
        XCTAssertEqual(Set(all).count, count)
        XCTAssertEqual(SimpsonsOfTheDay.indices(for: start, count: 5, take: take, calendar: calendar).count, 5, "con pocos episodios, todos")
    }

    /// La tele cambia de episodio cada media hora, a la hora y a la media, y recorre la tanda en orden.
    func testEpisodeChangesEveryTurnAndCycles() throws {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_793_600_000))
        let episodes = (1...3).map { SimpsonsOfTheDay.Episode(season: 6, episode: $0, title: "E\($0)", videoID: "tt0096697:6:\($0)", still: "s") }
        let week = SimpsonsOfTheDay(episodes: episodes, day: day, seasons: [6])
        func at(_ minutes: Double) -> Int? { week.episode(at: day.addingTimeInterval(minutes * 60), minutes: 30, calendar: calendar)?.episode }
        XCTAssertEqual(at(0), at(29))
        XCTAssertNotEqual(at(29), at(30))
        XCTAssertEqual(Set([at(0), at(30), at(60)].compactMap { $0 }), [1, 2, 3])
        XCTAssertEqual(at(0), at(90), "al acabarse la tanda vuelve a empezar")
        let turn = SimpsonsOfTheDay.turn(for: day.addingTimeInterval(45 * 60), minutes: 30, calendar: calendar)
        XCTAssertEqual(SimpsonsOfTheDay.start(ofTurn: turn, minutes: 30, calendar: calendar), day.addingTimeInterval(30 * 60))
        XCTAssertEqual(week.episodes.first?.link, WidgetLink.play(kind: "series", id: "tt0096697", video: "tt0096697:6:1"))
        XCTAssertEqual(SimpsonsOfTheDay.decode(try week.encoded()), week)
        XCTAssertNil(SimpsonsOfTheDay(episodes: [], day: day, seasons: [6]).episode(at: day, minutes: 30, calendar: calendar))
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
