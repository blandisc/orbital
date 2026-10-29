import XCTest
@testable import OrbitalCore

/// Las listas con puesto calculadas en el iPhone: la misma cuenta que `orbital/library/charts.py` en la TV.
final class ChartsTests: XCTestCase {
    private func html(_ name: String) throws -> Data { try Data(contentsOf: Fixtures.root.appendingPathComponent("charts/\(name)")) }

    private func charts(_ http: FakeHTTP, kv: KeyValueStore = InMemoryKeyValueStore(), clock: Clock = Clock()) -> Charts {
        Charts(http: http, tmdb: nil, cinemeta: Cinemeta(http: http), kv: kv, region: { "MX" }, clock: { clock.now })
    }

    func testParsesTheNetflixPageTableAndItsWeeks() throws {
        let page = Charts.parseNetflixPage(String(decoding: try html("netflix_mexico_tv.html"), as: UTF8.self))
        XCTAssertEqual(page.rows.count, 10)
        XCTAssertEqual(page.rows.first?.rank, 1)
        XCTAssertEqual(page.rows.first?.title, "Below: Limited Series")
        XCTAssertEqual(page.weeks.last, "2026-10-11", "la semana que enseña la página")
        XCTAssertEqual(page.weeks.dropLast().last, "2026-10-04", "y la anterior, para el sube y baja")
    }

    func testTheSeasonIsTakenOffToFindTheShow() {
        XCTAssertEqual(Charts.showTitle("Below: Limited Series"), "Below")
        XCTAssertEqual(Charts.showTitle("Physical 100: Mexico: Season 1"), "Physical 100: Mexico")
        XCTAssertEqual(Charts.showTitle("Monster: The Lizzie Borden Story: Season 1"), "Monster: The Lizzie Borden Story")
        XCTAssertEqual(Charts.showTitle("Animals"), "Animals")
    }

    func testMovementAgainstTheWeekBeforeLikeTheTV() {
        let latest = [Charts.NetflixRow(rank: 1, title: "A", weeks: 1), Charts.NetflixRow(rank: 2, title: "B", weeks: 3), Charts.NetflixRow(rank: 3, title: "C", weeks: 2)]
        let previous = [Charts.NetflixRow(rank: 1, title: "B", weeks: 2), Charts.NetflixRow(rank: 5, title: "C", weeks: 1)]
        let marked = Charts.withMovement(latest, previous: previous)
        XCTAssertEqual(marked.map(\.movement), [nil, -1, 2])
        XCTAssertEqual(marked.map(\.isNew), [true, false, false], "nuevo: primera semana, o no estaba la semana pasada")
        XCTAssertEqual(Charts.withMovement(latest, previous: nil).map(\.movement), [nil, nil, nil], "sin semana pasada no se inventan flechas")
    }

    func testNetflixTop10WithIMDbFromCinemetaWhenThereIsNoTMDB() async throws {
        let http = FakeHTTP()
        http.raw["https://www.netflix.com/tudum/top10/mexico/tv"] = try html("netflix_mexico_tv.html")
        http.raw["https://www.netflix.com/tudum/top10/mexico/tv?week=2026-10-04"] = try html("netflix_mexico_tv_prev.html")
        http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=Below.json"] = ["metas": [["id": "tt9000001", "name": "Below", "type": "series", "poster": "https://p"]]]
        let found = try await charts(http).netflix(kind: "series")
        XCTAssertEqual(found.first?.imdb, "tt9000001", "el n.º 1 resuelto a IMDb")
        XCTAssertEqual(found.first?.rank, 1)
        XCTAssertEqual(found.first?.title, "Below")
        XCTAssertTrue(found.allSatisfy { $0.imdb.hasPrefix("tt") }, "los que no se encuentran se omiten")
    }

    func testNetflixIsKeptOnDiskAndNotDownloadedAgain() async throws {
        let http = FakeHTTP(), kv = InMemoryKeyValueStore(), clock = Clock()
        http.raw["https://www.netflix.com/tudum/top10/mexico/tv"] = try html("netflix_mexico_tv.html")
        http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=Below.json"] = ["metas": [["id": "tt9000001", "name": "Below", "type": "series", "poster": "https://p"]]]
        _ = try await charts(http, kv: kv, clock: clock).netflix(kind: "series")
        let before = http.calls.count
        let again = try await charts(http, kv: kv, clock: clock).netflix(kind: "series")   // otra sesión de la app
        XCTAssertEqual(http.calls.count, before, "dentro de las 12 h sale del disco")
        XCTAssertEqual(again.first?.imdb, "tt9000001")
    }

    func testJustWatchKeepsOnlyTitlesWithIMDbAndRanksThemWithinThePlatform() throws {
        let entries = Charts.parseJustWatch(try Fixtures.json("charts/justwatch_disney_series.json"))
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.map(\.rank), Array(1...entries.count), "el lugar en la plataforma, 1…n")
        XCTAssertTrue(entries.allSatisfy { $0.imdb.hasPrefix("tt") })
        XCTAssertFalse(entries.contains { $0.title == "Dragon Ball Super: Beerus" }, "sin IMDb, fuera")
    }

    func testJustWatchMovementComesFromYesterdaysSnapshot() {
        let kv = InMemoryKeyValueStore(), snapshots = ChartSnapshots(kv: kv)
        let day1 = Date(timeIntervalSince1970: 1_760_000_000), day2 = day1.addingTimeInterval(86_400)
        let first = snapshots.annotate(listID: "jw:disney", kind: "series", entries: [ChartEntry(imdb: "tt1", title: "A", rank: 1), ChartEntry(imdb: "tt2", title: "B", rank: 2)], today: day1)
        XCTAssertEqual(first.map(\.movement), [nil, nil], "el primer día no hay con qué comparar")
        XCTAssertEqual(first.map(\.isNew), [false, false])
        let second = snapshots.annotate(listID: "jw:disney", kind: "series", entries: [ChartEntry(imdb: "tt2", title: "B", rank: 1), ChartEntry(imdb: "tt3", title: "C", rank: 2)], today: day2)
        XCTAssertEqual(second.map(\.movement), [1, nil])
        XCTAssertEqual(second.map(\.isNew), [false, true])
    }

    func testPlatformBrandIsFoundByNameOrById() {
        XCTAssertEqual(Charts.brand(named: "Prime Video"), "prime")
        XCTAssertEqual(Charts.brand(named: "Prime"), "prime", "así llegaba Prime Video a la píldora de Para ti")
        XCTAssertEqual(Charts.brand(named: "Paramount+"), "paramount")
        XCTAssertEqual(Charts.brand(named: "Top 10 en Netflix"), "netflix")
        XCTAssertNil(Charts.brand(named: "Lo más visto"))
    }
}
