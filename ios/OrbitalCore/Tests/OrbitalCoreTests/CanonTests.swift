import XCTest
@testable import OrbitalCore

/// Colecciones: los premios como repisa (una serie que ganó varios años va una vez), las listas de MDBList, los grupos y
/// «La siguiente».
final class CanonTests: XCTestCase {
    func testLosPremiosSalenDeLoQueTraeLaApp() {
        let all = Canon.awards()
        XCTAssertEqual(all.map(\.id), ["oscar", "palm", "ariel", "globe", "bafta", "emmy"])
        let emmy = try! XCTUnwrap(all.first { $0.id == "emmy" })
        let madMen = try! XCTUnwrap(emmy.items.first { $0.title == "Mad Men" })
        XCTAssertEqual(madMen.year, 2008)
        XCTAssertEqual(madMen.lastYear, 2011, "ganó de 2008 a 2011: una sola vez en la repisa")
        XCTAssertEqual(Set(emmy.items.map(\.imdb)).count, emmy.items.count)
    }

    func testGruposPorDecadaYDeDiezEnDiez() {
        let c = CanonCollection(id: "x", family: .award, grouping: .awardDecade, items: [
            .init(imdb: "tt1", kind: "movie", title: "A", year: 2025), .init(imdb: "tt2", kind: "movie", title: "B", year: 2019),
            .init(imdb: "tt3", kind: "movie", title: "C", year: 2021), .init(imdb: "tt4", kind: "movie", title: "D", year: 1999)])
        XCTAssertEqual(c.groups().map(\.title), ["Los 2020", "Los 2010", "Los 90"])
        XCTAssertEqual(c.groups().first?.items.map(\.imdb), ["tt1", "tt3"])
        XCTAssertEqual(c.groups(newestFirst: false).first?.title, "Los 90")
        let top = CanonCollection(id: "t", family: .list, grouping: .rank, items: (1...23).map { .init(imdb: "tt\($0)", kind: "movie", title: "", year: nil, rank: $0) })
        XCTAssertEqual(top.groups().map(\.title), ["1 – 10", "11 – 20", "21 – 23"])
    }

    func testLaSiguiente() {
        let items: [CanonCollection.Item] = [.init(imdb: "tt1", kind: "movie", title: "A", year: 2025, rank: 3),
                                             .init(imdb: "tt2", kind: "movie", title: "B", year: 1960, rank: 1),
                                             .init(imdb: "tt3", kind: "movie", title: "C", year: 2000, rank: 2)]
        XCTAssertEqual(CanonCollection(id: "a", family: .award, grouping: .awardDecade, items: items).next(["tt1"])?.imdb, "tt3", "la más reciente que falta")
        XCTAssertEqual(CanonCollection(id: "t", family: .list, grouping: .rank, items: items).next(["tt2"])?.imdb, "tt3", "el mejor lugar que falta")
        XCTAssertEqual(CanonCollection(id: "c", family: .list, grouping: .releaseDecade, items: items).next([])?.imdb, "tt2", "la más clásica")
        XCTAssertEqual(CanonCollection(id: "a", family: .award, grouping: .awardDecade, items: items).seen(["tt1", "tt9"]), 1)
    }

    func testUnaListaDeMDBList() async throws {
        let http = FakeHTTP()
        http.json["https://mdblist.com/lists/u/s/json"] = [["rank": 1000, "title": "Sueño de fuga", "imdb_id": "tt0111161", "mediatype": "movie", "release_year": 1994],
                                                           ["rank": 2000, "title": "Sin IMDb", "imdb_id": "", "mediatype": "movie"],
                                                           ["rank": 3000, "title": "Serie", "imdb_id": "tt9", "mediatype": "show", "release_year": 2010]]
        let items = try await Canon.list(http: http, user: "u", slug: "s")
        XCTAssertEqual(items.map(\.imdb), ["tt0111161", "tt9"])
        XCTAssertEqual(items.map(\.kind), ["movie", "series"])
        XCTAssertEqual(items.first?.year, 1994)
    }
}
