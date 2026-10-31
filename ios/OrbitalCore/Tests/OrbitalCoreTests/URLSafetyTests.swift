import XCTest
@testable import OrbitalCore

/// Un id raro (con espacio, «?», «#» o acentos) ya no tumba la app al armar la dirección: se codifica en la ruta o se
/// responde con error (auditoría, 31 oct 2026, C3; antes eran `URLComponents(string:)!` y `components.url!`).
final class URLSafetyTests: XCTestCase {
    func testTmdbEncodesAWeirdIdInThePath() throws {
        let url = try XCTUnwrap(Tmdb.url("/find/tt 12?x#y é", [("external_source", "imdb_id")]))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/3/find/tt 12?x#y é", "la ruta completa, sin cortarse en «?» ni en «#»")
        XCTAssertEqual(components.queryItems?.first?.value, "imdb_id", "y la consulta intacta")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://api.themoviedb.org/3/find/tt%2012%3Fx%23y%20%C3%A9?"))
    }

    func testTmdbAsksForTheEncodedAddressInsteadOfCrashing() async {
        let http = FakeHTTP()
        let tmdb = Tmdb(http: http, key: "clave")
        _ = try? await tmdb.companyLogo(0)
        _ = try? await tmdb.get("/company/a b?c")
        XCTAssertTrue(http.calls.contains { $0.hasPrefix("https://api.themoviedb.org/3/company/a%20b%3Fc?") }, "\(http.calls)")
    }

    func testTraktEncodesAWeirdPath() throws {
        let url = try XCTUnwrap(Trakt.url("/shows/un show?#/seasons", [("extended", "full")]))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://api.trakt.tv/shows/un%20show%3F%23/seasons?extended=full"), url.absoluteString)
    }

    func testStremioDatesWithoutForcedUnwraps() {
        XCTAssertEqual(StremioLibrary.iso(0), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(StremioLibrary.iso(1_700_000_000.25), "2023-11-14T22:13:20.250Z")
    }
}
