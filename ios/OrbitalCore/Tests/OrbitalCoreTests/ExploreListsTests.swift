import XCTest
@testable import OrbitalCore

/// «Esta semana» en Explorar: la tabla de `listas/explorar.json` se lee bien, cada lista tiene una sola fuente y sus fechas, las
/// de temporada salen en su temporada (también las que cruzan el año) y las demás rotan sin repetirse hasta dar la vuelta.
final class ExploreListsTests: XCTestCase {
    /// La tabla de verdad, la del repositorio (la misma que lee la TV).
    func repoTable() throws -> ExploreTable {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent("listas/explorar.json").path) {
            url.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: url.appendingPathComponent("listas/explorar.json"))
        return try XCTUnwrap(ExploreTable.parse(data), "listas/explorar.json no se lee")
    }

    func day(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func testLaTablaDelRepositorioEstaBien() throws {
        let table = try repoTable()
        XCTAssertGreaterThan(table.rotate, 0)
        XCTAssertEqual(Set(table.lists.map(\.id)).count, table.lists.count, "ids repetidos")
        let canon = Set(Canon.lists.map(\.id) + Canon.awards().map(\.id))
        for list in table.lists {
            XCTAssertFalse(canon.contains(list.id), "\(list.id) choca con una colección")
            let sources = [list.mdblist != nil, list.trakt != nil, list.items != nil].filter { $0 }.count
            XCTAssertEqual(sources, 1, "\(list.id): una sola fuente")
            if let s = list.mdblist ?? list.trakt { XCTAssertEqual(s.split(separator: "/").count, 2, "\(list.id): usuario/lista") }
            XCTAssertEqual(list.from == nil, list.to == nil, "\(list.id): las dos fechas o ninguna")
            if let from = list.from, let to = list.to {
                XCTAssertNotNil(ExploreList.monthDay(from), "\(list.id): \(from)"); XCTAssertNotNil(ExploreList.monthDay(to), "\(list.id): \(to)")
            }
            XCTAssertFalse(list.title.isEmpty || list.about.isEmpty, "\(list.id): nombre y de qué se trata")
            for e in list.items ?? [] {
                XCTAssertTrue(e.id.range(of: "^tt\\d+(:\\d+:\\d+)?$", options: .regularExpression) != nil, "\(list.id): \(e.id)")
                XCTAssertEqual(e.kind == "episode", e.id.contains(":"), "\(list.id): \(e.id) y su tipo")
            }
        }
        XCTAssertTrue(table.lists.contains { !$0.dated }, "hay listas que rotan")
    }

    func testLasDeTemporadaSalenEnSuTemporadaYPrimero() throws {
        let table = try repoTable()
        let october = table.thisWeek(day("2026-10-15"), calendar: utc).map(\.id)
        XCTAssertEqual(october.first, "simpsons-halloween")
        XCTAssertFalse(october.contains("simpsons-navidad"))
        // Cruza el año: del 1 de diciembre al 6 de enero.
        XCTAssertTrue(table.thisWeek(day("2027-01-03"), calendar: utc).map(\.id).contains("simpsons-navidad"))
        XCTAssertFalse(table.thisWeek(day("2026-11-23"), calendar: utc).contains { $0.dated })
    }

    func testLasDemasRotanYPasanTodasAntesDeRepetir() {
        let wheel = (1...6).map { ExploreList(id: "l\($0)", title: "L\($0)", about: "x", mdblist: "u/l\($0)") }
        let table = ExploreTable(rotate: 4, lists: wheel)
        let monday = day("2026-11-23")
        let thisWeek = table.thisWeek(monday, calendar: utc).map(\.id)
        XCTAssertEqual(thisWeek.count, 4)
        XCTAssertEqual(table.thisWeek(monday.addingTimeInterval(6 * 86400), calendar: utc).map(\.id), thisWeek, "igual toda la semana")
        let next = table.thisWeek(monday.addingTimeInterval(7 * 86400), calendar: utc).map(\.id)
        XCTAssertNotEqual(next, thisWeek)
        XCTAssertEqual(Set(thisWeek + next), Set(wheel.map(\.id)), "en dos semanas pasan las seis")
    }

    /// La misma rueda que la TV (`tests/test_weekly.py`): el lunes 23 nov 2026 es la semana 2968 → empieza en la quinta.
    func testIgualQueLaTV() {
        let table = ExploreTable(rotate: 4, lists: (0..<6).map { ExploreList(id: "l\($0)", title: "L", about: "x", mdblist: "u/l") })
        XCTAssertEqual(table.thisWeek(day("2026-11-23"), calendar: utc).map(\.id), ["l4", "l5", "l0", "l1"])
    }

    func testUnCapituloAbreSuSerieYLlevaSuPoster() {
        let item = CanonCollection.Item(imdb: "tt0096697:2:3", kind: "episode", title: "La casita del horror I", year: 1990)
        XCTAssertEqual(item.episode?.show, "tt0096697")
        XCTAssertEqual(item.episode?.video, "tt0096697:2:3")
        XCTAssertEqual(item.poster, String(format: ForYou.metahubPoster, "tt0096697"))
        XCTAssertNil(CanonCollection.Item(imdb: "tt0111161", kind: "movie", title: "Sueño de fuga", year: 1994).episode)
    }
}
