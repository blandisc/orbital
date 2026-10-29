import XCTest
@testable import OrbitalCore

/// Responde a TMDB por ruta y cuenta las consultas.
private final class ArtTMDB: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var failing = false
    var calls: Int { lock.withLock { _calls } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _calls += 1 }
        if lock.withLock({ failing }) { throw URLError(.notConnectedToInternet) }
        let path = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.path ?? ""
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body: JSON
        if path.hasSuffix("/find/tt0816692") { body = ["movie_results": .array([["id": .int(157336)]]), "tv_results": .array([])] }
        else if path.hasSuffix("/find/tt0000001") { body = ["movie_results": .array([]), "tv_results": .array([])] }
        else if path.hasSuffix("/movie/157336/images") {
            XCTAssertEqual(query.first { $0.name == "include_image_language" }?.value, "null", "solo los sin texto")
            body = ["posters": .array([
                ["file_path": "/con-titulo.jpg", "iso_639_1": "en", "vote_average": .double(9)],
                ["file_path": "/pareja.jpg", "iso_639_1": .null, "vote_average": .double(5.2)],
                ["file_path": "/astronauta.jpg", "iso_639_1": .null, "vote_average": .double(5.6)],
            ])]
        } else { return HTTPResponse(status: 404, data: Data()) }
        return HTTPResponse(status: 200, data: body.serialized())
    }
}

final class TallArtTests: XCTestCase {
    func testPicksTheBestPosterWithoutTextAndRemembersIt() async {
        let http = ArtTMDB(), store = InMemoryKeyValueStore()
        let art = TallArt(tmdb: { Tmdb(http: http, key: "clave") }, store: store)
        XCTAssertEqual(art.known(imdb: "tt0816692", kind: "movie"), .unknown)
        let url = await art.poster(imdb: "tt0816692", kind: "movie")
        XCTAssertEqual(url, "https://image.tmdb.org/t/p/w780/astronauta.jpg", "el sin texto mejor votado, nunca uno con el título")
        XCTAssertEqual(art.known(imdb: "tt0816692", kind: "movie"), .poster("https://image.tmdb.org/t/p/w780/astronauta.jpg"))
        let calls = http.calls
        _ = await art.poster(imdb: "tt0816692", kind: "movie")
        XCTAssertEqual(http.calls, calls, "la segunda vez, sin preguntar")
    }

    func testATitleWithoutPosterIsRememberedAsNone() async {
        let http = ArtTMDB()
        let art = TallArt(tmdb: { Tmdb(http: http, key: "clave") })
        let url = await art.poster(imdb: "tt0000001", kind: "movie")
        XCTAssertNil(url)
        XCTAssertEqual(art.known(imdb: "tt0000001", kind: "movie"), .none)
    }

    func testANetworkFailureIsNotRemembered() async {
        let http = ArtTMDB(); http.failing = true
        let art = TallArt(tmdb: { Tmdb(http: http, key: "clave") })
        let url = await art.poster(imdb: "tt0816692", kind: "movie")
        XCTAssertNil(url)
        XCTAssertEqual(art.known(imdb: "tt0816692", kind: "movie"), .unknown, "se vuelve a intentar")
    }

    func testWithoutKeyOrImdbThereIsNoPoster() async {
        let http = ArtTMDB()
        let art = TallArt(tmdb: { Tmdb(http: http, key: "") })
        let url = await art.poster(imdb: "tt0816692", kind: "movie")
        XCTAssertNil(url)
        XCTAssertEqual(http.calls, 0)
        XCTAssertEqual(art.known(imdb: "onedrive:abc", kind: "movie"), .none)
    }
}
