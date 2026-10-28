import XCTest
@testable import OrbitalCore

/// Los favoritos de Trakt (el corazón de la ficha): leerlos (películas y series juntas, lo último primero, con caché corta
/// y la marca de `last_activities`), agregar, quitar y el tope de 100 (420).
final class TraktFavoritesTests: XCTestCase {
    let api = "https://api.trakt.tv"
    var moviesURL: String { "\(api)/sync/favorites/movies?extended=full" }
    var showsURL: String { "\(api)/sync/favorites/shows?extended=full" }
    var stampURL: String { "\(api)/sync/last_activities" }

    func makeTrakt(_ http: FakeHTTP, clock: Clock = Clock()) -> Trakt {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 7 * 86400)}"#)
        return Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
    }

    func serve(_ http: FakeHTTP, stamp: String = "2026-10-20T00:00:00.000Z") {
        http.json[moviesURL] = [
            ["rank": 1, "listed_at": "2026-01-01T00:00:00.000Z", "type": "movie", "movie": ["title": "Interstellar", "year": 2014, "ids": ["trakt": 1, "imdb": "tt0816692"]]],
            ["rank": 2, "listed_at": "2026-09-01T00:00:00.000Z", "type": "movie", "movie": ["title": "Sin IMDb", "ids": ["trakt": 2]]]]
        http.json[showsURL] = [
            ["rank": 1, "listed_at": "2026-06-01T00:00:00.000Z", "type": "show", "show": ["title": "Los Simpson", "year": 1989, "ids": ["trakt": 3, "imdb": "tt0096697"]]]]
        http.json[stampURL] = ["all": "2026-10-20T00:00:00.000Z", "favorites": ["updated_at": .string(stamp)]]
    }

    func testFavoritesJoinMoviesAndShowsNewestFirst() async throws {
        let http = FakeHTTP()
        serve(http)
        let found = try await makeTrakt(http).favorites()
        XCTAssertEqual(found.map(\.title), ["Los Simpson", "Interstellar"], "lo último que marcaste primero; sin IMDb no entra")
        XCTAssertEqual(found.map(\.kind), ["series", "movie"])
        XCTAssertEqual(found.last?.year, 2014)
    }

    func testFavoritesAreCachedAndOnlyReloadedWhenTraktSaysTheyChanged() async throws {
        let http = FakeHTTP(), clock = Clock()
        serve(http)
        let trakt = makeTrakt(http, clock: clock)
        func listCalls() -> Int { http.calls.filter { $0 == moviesURL }.count }
        _ = try await trakt.favorites()
        _ = try await trakt.favorites()
        XCTAssertEqual(listCalls(), 1, "dentro del minuto sale de lo guardado")
        clock.now = clock.now.addingTimeInterval(61)
        _ = try await trakt.favorites()
        XCTAssertEqual(listCalls(), 1, "pasado el minuto, la marca no cambió: no se bajan otra vez")
        clock.now = clock.now.addingTimeInterval(61)
        serve(http, stamp: "2026-10-28T00:00:00.000Z")
        _ = try await trakt.favorites()
        XCTAssertEqual(listCalls(), 2, "cambiaron en otro dispositivo: se bajan")
        _ = try await trakt.favorites(fresh: true)
        XCTAssertEqual(listCalls(), 3)
    }

    func testAddAndRemoveSendTheIMDbIdAndForgetTheCache() async throws {
        let http = FakeHTTP()
        serve(http)
        http.json["\(api)/sync/favorites"] = ["added": ["movies": 1]]
        http.json["\(api)/sync/favorites/remove"] = ["deleted": ["shows": 1]]
        let trakt = makeTrakt(http)
        _ = try await trakt.favorites()
        try await trakt.setFavorite(imdb: "tt0816692", series: false, add: true)
        let added = try XCTUnwrap(http.bodies(for: "\(api)/sync/favorites").first.flatMap(JSON.parse))
        XCTAssertEqual(added["movies"]?.array?.first?["ids"]?["imdb"]?.string, "tt0816692")
        XCTAssertNil(added["shows"])
        try await trakt.setFavorite(imdb: "tt0096697", series: true, add: false)
        let removed = try XCTUnwrap(http.bodies(for: "\(api)/sync/favorites/remove").first.flatMap(JSON.parse))
        XCTAssertEqual(removed["shows"]?.array?.first?["ids"]?["imdb"]?.string, "tt0096697")
        XCTAssertNil(removed["movies"])
        _ = try await trakt.favorites()
        XCTAssertEqual(http.calls.filter { $0 == moviesURL }.count, 2, "tras cambiarlos, la lectura es nueva")
    }

    func testTheHundredLimitSaysWhatToDo() async {
        let http = FakeHTTP()
        http.json["\(api)/sync/favorites"] = [:]
        http.statuses["\(api)/sync/favorites"] = 420
        do {
            try await makeTrakt(http).setFavorite(imdb: "tt0816692", series: false, add: true)
            XCTFail("con 100 ya no cabe")
        } catch {
            XCTAssertEqual("\(error)", "Llegaste a 100 favoritos en Trakt: quita uno para agregar otro.")
            XCTAssertEqual("\(error)", Trakt.favoritesFullMessage)
        }
    }

    func testOtherFailuresAndBadIdsThrow() async {
        let http = FakeHTTP()
        http.json["\(api)/sync/favorites/remove"] = [:]
        http.statuses["\(api)/sync/favorites/remove"] = 500
        let trakt = makeTrakt(http)
        do { try await trakt.setFavorite(imdb: "tt1", series: false, add: false); XCTFail() } catch { XCTAssertTrue("\(error)".contains("500")) }
        do { try await trakt.setFavorite(imdb: "../users", series: false, add: true); XCTFail() } catch { XCTAssertTrue(http.bodies(for: "\(api)/sync/favorites").isEmpty) }
    }
}
