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
        source.flush()   // se escribe con retraso; aquí, ya
        let again = PosterSource(store: store) { _ in XCTFail("ya estaba guardado"); return nil }
        XCTAssertEqual(again.known("https://images.metahub.space/poster/large/tt0361243/img")?.absoluteString, "https://image.tmdb.org/t/p/w780/clone.jpg")
    }

    /// A12: dos tamaños del mismo póster a la vez preguntan una sola vez, y nunca más de `concurrentLookups` títulos a la vez.
    func testOneLookupPerTitleAndAQueue() async {
        let calls = PosterCalls()
        let source = PosterSource(store: InMemoryKeyValueStore()) { imdb in
            await calls.start()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await calls.end()
            return .some("/\(imdb).jpg")
        }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<12 {
                for size in ["small", "medium"] {
                    group.addTask { _ = await source.resolve("https://images.metahub.space/poster/\(size)/tt\(1000000 + i)/img") }
                }
            }
        }
        let n = await calls.n, peak = await calls.peak
        XCTAssertEqual(n, 12, "una consulta por título")
        XCTAssertLessThanOrEqual(peak, PosterSource.concurrentLookups)
        XCTAssertEqual(source.known("https://images.metahub.space/poster/medium/tt1000003/img")?.absoluteString, "https://image.tmdb.org/t/p/w500/tt1000003.jpg")
    }

    /// A12: lo de UserDefaults se pasa al archivo una vez y se borra de UserDefaults; lo nuevo se escribe en el archivo.
    func testMovesTheOldMapFromUserDefaultsToAFile() async throws {
        let legacy = InMemoryKeyValueStore()
        let old = PosterSource(store: legacy) { _ in .some("/viejo.jpg") }
        _ = await old.resolve("https://images.metahub.space/poster/medium/tt0361243/img")
        old.flush()
        XCTAssertNotNil(legacy.data(PosterSource.storeKey))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(UUID().uuidString)/poster-source.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let moved = PosterSource(file: file, legacy: legacy) { nil }
        XCTAssertEqual(moved.known("https://images.metahub.space/poster/medium/tt0361243/img")?.lastPathComponent, "viejo.jpg")
        XCTAssertNil(legacy.data(PosterSource.storeKey), "ya no vive en UserDefaults")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testWithoutAnswerKeepsMetahubAndAsksLater() async {
        let source = PosterSource(store: InMemoryKeyValueStore()) { _ in nil }
        let none = await source.resolve("https://images.metahub.space/poster/medium/tt0361243/img")
        XCTAssertNil(none)
        XCTAssertNil(source.known("https://images.metahub.space/poster/medium/tt0361243/img"))
    }
}

private actor PosterCalls {
    var n = 0, now = 0, peak = 0
    func add() { n += 1 }
    func start() { n += 1; now += 1; peak = max(peak, now) }
    func end() { now -= 1 }
}
