import XCTest
@testable import OrbitalCore

/// El último respaldo del póster (23 nov 2026): si metahub da 404 y TMDB no lo tiene, la imagen del buscador de IMDb.
final class ImdbPosterTests: XCTestCase {
    private let sample = Data("""
    {"d":[{"i":{"imageUrl":"https://m.media-amazon.com/images/M/otro._V1_.jpg"},"id":"tt0000001","l":"Otro"},
          {"i":{"imageUrl":"https://m.media-amazon.com/images/M/MV5Babc._V1_.jpg","height":1500,"width":1000},"id":"tt4705944","l":"Batman: The Long Halloween"}]}
    """.utf8)

    func testReadsTheImageOfThatTitleOnly() {
        XCTAssertEqual(ImdbPoster.parse(sample, imdb: "tt4705944"), "https://m.media-amazon.com/images/M/MV5Babc._V1_.jpg")
        XCTAssertNil(ImdbPoster.parse(sample, imdb: "tt9999999"), "otro título parecido no cuenta")
        XCTAssertNil(ImdbPoster.parse(Data("{\"d\":[{\"id\":\"tt1\",\"l\":\"Sin imagen\"}]}".utf8), imdb: "tt1"))
        XCTAssertNil(ImdbPoster.lookupURL("../etc"), "solo ids de IMDb")
        XCTAssertEqual(ImdbPoster.lookupURL("tt4705944")?.absoluteString, "https://v3.sg.media-imdb.com/suggestion/x/tt4705944.json")
    }

    func testAsksForTheSizeThatIsShown() {
        XCTAssertEqual(ImdbPoster.sized("https://m.media-amazon.com/images/M/MV5Babc._V1_.jpg", width: 500),
                       "https://m.media-amazon.com/images/M/MV5Babc._V1_QL75_UX500_.jpg")
        XCTAssertEqual(ImdbPoster.sized("https://example.com/a.png", width: 500), "https://example.com/a.png")
    }

    func testRescuesAMetahubPosterAndRemembers() async {
        let calls = PosterCalls()
        let source = ImdbPoster { imdb in
            await calls.add()
            return imdb == "tt4705944" ? .some("https://m.media-amazon.com/images/M/MV5Babc._V1_.jpg") : .some(nil)
        }
        let url = await source.resolve("https://images.metahub.space/poster/small/tt4705944/img")
        XCTAssertEqual(url?.absoluteString, "https://m.media-amazon.com/images/M/MV5Babc._V1_QL75_UX300_.jpg")
        XCTAssertEqual(source.remembered("https://images.metahub.space/poster/medium/tt4705944/img")?.absoluteString,
                       "https://m.media-amazon.com/images/M/MV5Babc._V1_QL75_UX500_.jpg", "la próxima vez, directo")
        let missing = await source.resolve("https://images.metahub.space/poster/medium/tt0000002/img")
        XCTAssertNil(missing, "IMDb tampoco: el nombre sobre color")
        _ = await source.resolve("https://images.metahub.space/poster/medium/tt0000002/img")
        _ = await source.resolve("https://images.metahub.space/poster/large/tt4705944/img")
        let n = await calls.n
        XCTAssertEqual(n, 2, "lo sabido no se vuelve a preguntar")
        let notMetahub = await source.resolve("https://image.tmdb.org/t/p/w500/a.jpg")
        XCTAssertNil(notMetahub)
    }

    func testANetworkFailureIsAskedAgain() async {
        let calls = PosterCalls()
        let source = ImdbPoster { _ in await calls.add(); return nil }
        _ = await source.resolve("https://images.metahub.space/poster/medium/tt4705944/img")
        _ = await source.resolve("https://images.metahub.space/poster/medium/tt4705944/img")
        let n = await calls.n
        XCTAssertEqual(n, 2, "sin red no se anota «no la tiene»")
    }

    func testOneLookupWhenTwoSizesAskAtOnce() async {
        let calls = PosterCalls()
        let source = ImdbPoster { _ in
            await calls.add()
            try? await Task.sleep(nanoseconds: 20_000_000)
            return .some("https://m.media-amazon.com/images/M/x._V1_.jpg")
        }
        async let a = source.resolve("https://images.metahub.space/poster/small/tt4705944/img")
        async let b = source.resolve("https://images.metahub.space/poster/medium/tt4705944/img")
        let (small, medium) = await (a, b)
        XCTAssertNotNil(small); XCTAssertNotNil(medium)
        let n = await calls.n
        XCTAssertEqual(n, 1)
    }

    func testReadsTheRealClient() async {
        let http = StubImdbHTTP(data: sample)
        let url = await ImdbPoster(http: http).resolve("https://images.metahub.space/poster/medium/tt4705944/img")
        XCTAssertEqual(url?.absoluteString, "https://m.media-amazon.com/images/M/MV5Babc._V1_QL75_UX500_.jpg")
    }
}

private struct StubImdbHTTP: HTTPClient {
    let data: Data
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { HTTPResponse(status: 200, data: data) }
}
