import XCTest
@testable import OrbitalCore

/// «Agregadas: más recientes / más viejas» (Fernando, 13 nov 2026): cuándo agregaste cada título viaja de Trakt (`listed_at`)
/// hasta la lista, se guarda en el teléfono y lo guardado antes (sin fecha) no se rompe.
extension ForYouTests {
    private func at(_ text: String) -> Date { TraktParsing.date(text)! }

    func testMiListaYTusListasTraenCuandoAgregasteCadaTitulo() async throws {
        let http = FakeHTTP(); stubTrakt(http)
        http.json["\(api)/users/me/lists/77/items?extended=full"] = [
            ["type": "movie", "listed_at": "2025-03-01T10:00:00.000Z", "movie": ["title": "Hereditary", "ids": ["imdb": "tt7784604"]]],
            ["type": "movie", "listed_at": "2025-04-02T08:30:00Z", "movie": ["title": "Talk to Me", "ids": ["imdb": "tt10638522"]]],   // sin milésimas
            ["type": "show", "listed_at": "ayer", "show": ["title": "Chucky", "ids": ["imdb": "tt8388390"]]]]                          // fecha rota
        let forYou = makeForYou(http)
        let mine = try await forYou.items(listID: "watchlist")
        XCTAssertEqual(mine.map(\.addedAt), [at("2025-06-01T00:00:00.000Z"), at("2025-05-01T00:00:00.000Z")])
        let list = try await forYou.items(listID: "list:77")
        XCTAssertEqual(list.map(\.imdb), ["tt7784604", "tt10638522", "tt8388390"], "el orden de la lista no cambia por traer la fecha")
        XCTAssertEqual(list[0].addedAt, at("2025-03-01T10:00:00.000Z"))
        XCTAssertEqual(list[1].addedAt, at("2025-04-02T08:30:00.000Z"))
        XCTAssertNil(list[2].addedAt, "una fecha que no se entiende queda sin fecha (no rompe la lista)")
    }

    func testLaListaDeOtraPersonaNoTraeFechaDeAgregado() async throws {
        let http = FakeHTTP()
        http.json["\(api)/users/alguien/lists/terror/items?extended=full"] = [
            ["type": "movie", "listed_at": "2025-03-01T10:00:00.000Z", "movie": ["title": "Hereditary", "ids": ["imdb": "tt7784604"]]]]
        let trakt = Trakt(http: http, secrets: InMemorySecrets(), clientID: "CID", pause: { _ in })
        let items = try await trakt.publicListItems(user: "alguien", slug: "terror")
        XCTAssertEqual(items.map(\.imdb), ["tt7784604"])
        XCTAssertNil(items[0].listedAt, "no es tuya: no se ofrece «Agregadas»")
    }

    func testLaFechaSeGuardaEnElTelefonoYLoGuardadoAntesSeLeeSinElla() throws {
        var s = Suggestion(kind: "movie", imdb: "tt1", title: "Uno", poster: "p", wide: "w", reason: .inWatchlist)
        s.addedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ForYou.decode(ForYou.encode([s])).first?.addedAt, s.addedAt)
        // Una caché de antes de que viajara la fecha: se lee igual, sin fecha.
        let old = #"[{"kind":"movie","imdb":"tt2","title":"Dos","overview":"","poster":"p","wide":"w","reason":"inWatchlist","isNew":false}]"#
        let back = ForYou.decode(Data(old.utf8))
        XCTAssertEqual(back.map(\.imdb), ["tt2"])
        XCTAssertNil(back.first?.addedAt)
    }

    /// Mi lista del teléfono toma la fecha de Trakt (antes, una marca por puesto); sin fecha, la de siempre.
    func testMiListaDelTelefonoTomaLaFechaDeTrakt() {
        var entries: [String: LibraryEntry] = [:]
        var dated = TraktEntry(kind: "movie", imdb: "tt3", title: "C", year: nil, runtime: nil, episodes: nil, overview: "", traktID: nil)
        dated.listedAt = Date(timeIntervalSince1970: 5_000)
        let undated = TraktEntry(kind: "movie", imdb: "tt4", title: "D", year: nil, runtime: nil, episodes: nil, overview: "", traktID: nil)
        LibraryMerge.watchlist(&entries, trakt: [dated, undated], pending: [:], now: 10_000)
        XCTAssertEqual(entries["tt3"]?.listedAt, 5_000)
        XCTAssertEqual(entries["tt4"]?.listedAt, 10_000 - 1, "sin fecha: su puesto, como antes")
    }
}
