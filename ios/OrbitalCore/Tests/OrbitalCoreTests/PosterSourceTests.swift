import XCTest
@testable import OrbitalCore

/// P1 (Fernando, 8 nov): primero el póster de TMDB; sin él, el de metahub.
final class PosterSourceTests: XCTestCase {
    func testReadsMetahubPosters() {
        XCTAssertEqual(PosterSource.metahub("https://images.metahub.space/poster/medium/tt0361243/img")?.imdb, "tt0361243")
        XCTAssertNil(PosterSource.metahub("https://images.metahub.space/background/medium/tt0361243/img"))
        XCTAssertNil(PosterSource.metahub("https://image.tmdb.org/t/p/w500/a.jpg"))
    }

    func testPrefersTMDBAndRemembers() async {
        let store = InMemoryKeyValueStore()
        let calls = PosterCalls()
        let source = PosterSource(store: store) { imdb in await calls.add(); return imdb == "tt0361243" ? .some("/clone.jpg") : .some(nil) }
        let url = await source.resolve("https://images.metahub.space/poster/small/tt0361243/img")
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w342/clone.jpg")
        let missing = await source.resolve("https://images.metahub.space/poster/medium/tt9999999/img")
        XCTAssertNil(missing, "TMDB no lo tiene: metahub")
        _ = await source.resolve("https://images.metahub.space/poster/medium/tt0361243/img")
        _ = await source.resolve("https://images.metahub.space/poster/medium/tt9999999/img")
        let n = await calls.n
        XCTAssertEqual(n, 2, "lo sabido no se vuelve a preguntar")
        let again = PosterSource(store: store) { _ in XCTFail("ya estaba guardado"); return nil }
        XCTAssertEqual(again.known("https://images.metahub.space/poster/large/tt0361243/img")?.absoluteString, "https://image.tmdb.org/t/p/w780/clone.jpg")
    }

    func testWithoutAnswerKeepsMetahubAndAsksLater() async {
        let source = PosterSource(store: InMemoryKeyValueStore()) { _ in nil }
        let none = await source.resolve("https://images.metahub.space/poster/medium/tt0361243/img")
        XCTAssertNil(none)
        XCTAssertNil(source.known("https://images.metahub.space/poster/medium/tt0361243/img"))
    }
}

private actor PosterCalls { var n = 0; func add() { n += 1 } }
