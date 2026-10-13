import XCTest
@testable import OrbitalCore

final class StreamFinderTests: XCTestCase {
    func makeFinder(_ http: FakeHTTP, clock: Clock = Clock()) -> StreamFinder {
        http.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream", "subtitles"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        http.json["https://b.example/manifest.json"] = ["name": "Otro", "resources": ["stream"], "types": ["movie"]]
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://a.example", "https://b.example"] }, clock: { clock.now })
        return StreamFinder(http: http, registry: registry, clock: { clock.now })
    }

    func testFindsRanksAndHidesInfoHashSources() async throws {
        let http = FakeHTTP()
        let finder = makeFinder(http)
        http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "Peli 1080p x265 Latino\n👤 100 💾 2.1 GB 🇲🇽", "url": "https://rd.example/a"],
            ["name": "T\n720p", "title": "Peli 720p", "infoHash": "abcdef0123456789abcdef0123456789abcdef01"],
            ["name": "T\n4k", "title": "Peli 2160p REMUX\n💾 58 GB", "url": "https://rd.example/c"], "raro", ["sin": "url"]]]
        http.json["https://b.example/stream/movie/tt1.json"] = ["streams": [["name": "O\n1080p", "title": "Peli 1080p WEB-DL\n💾 3.4 GB", "url": "https://rd.example/b"]]]
        let found = try await finder.find(kind: "movie", videoID: "tt1", prefs: Preferences(audio: "es", quality: "1080p"))
        XCTAssertEqual(found.count, 3, "la fuente infoHash no se ofrece en iOS")
        XCTAssertEqual(found.first?.playbackURL?.absoluteString, "https://rd.example/a", "la de Real-Debrid en español primero")
        let all = try await finder.find(kind: "movie", videoID: "tt1", prefs: Preferences(audio: "es", quality: "1080p"), onlyPlayable: false)
        XCTAssertEqual(all.count, 4)
    }

    func testResultsAreCachedAndExpire() async throws {
        let http = FakeHTTP(), clock = Clock()
        let finder = makeFinder(http, clock: clock)
        http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [["name": "T", "url": "https://rd.example/a"]]]
        let prefs = Preferences()
        _ = try await finder.find(kind: "movie", videoID: "tt1", prefs: prefs)
        _ = try await finder.find(kind: "movie", videoID: "tt1", prefs: prefs)
        XCTAssertEqual(http.calls.filter { $0.contains("/stream/") }.count, 2, "una pregunta por complemento, no por búsqueda")
        clock.now.addTimeInterval(StreamFinder.cacheSeconds + 1)
        _ = try await finder.find(kind: "movie", videoID: "tt1", prefs: prefs)
        XCTAssertEqual(http.calls.filter { $0.contains("/stream/") }.count, 4, "los enlaces de Real-Debrid caducan")
    }

    func testBingeGroupKeepsTheSameQualityInTheNextEpisode() async throws {
        let http = FakeHTTP()
        let finder = makeFinder(http)
        http.json["https://a.example/stream/series/tt1%3A1%3A2.json"] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "S01E02 1080p\n💾 1 GB", "url": "https://rd.example/x", "behaviorHints": ["bingeGroup": "a-1080"]],
            ["name": "T\n1080p [RD+]", "title": "S01E02 1080p\n💾 1 GB\n👤 400", "url": "https://rd.example/y", "behaviorHints": ["bingeGroup": "b-1080"]]]]
        let prefs = Preferences(audio: "en", quality: "1080p")
        let plain = try await finder.best(kind: "series", videoID: "tt1:1:2", prefs: prefs)
        XCTAssertEqual(plain?.binge, "b-1080")
        let same = try await finder.best(kind: "series", videoID: "tt1:1:2", prefs: prefs, binge: "a-1080")
        XCTAssertEqual(same?.binge, "a-1080")
        let skipped = try await finder.best(kind: "series", videoID: "tt1:1:2", prefs: prefs, skip: [plain!.index])
        XCTAssertNotEqual(skipped?.index, plain?.index)
    }

    func testNetworkFailureIsNotRememberedAsEmpty() async throws {
        let http = FakeHTTP(), clock = Clock()
        let finder = makeFinder(http, clock: clock)
        // Los dos complementos fallan (404 = sin JSON): lista vacía pero no se recuerda como «no hay»
        let first = try await finder.find(kind: "movie", videoID: "tt9", prefs: Preferences())
        XCTAssertTrue(first.isEmpty)
        http.json["https://a.example/stream/movie/tt9.json"] = ["streams": [["name": "T", "url": "https://rd.example/z"]]]
        clock.now.addTimeInterval(StreamFinder.retryFailed + 1)
        let second = try await finder.find(kind: "movie", videoID: "tt9", prefs: Preferences())
        XCTAssertEqual(second.count, 1)
    }

    func testSubtitlesFilterByLanguageAndScheme() async throws {
        let http = FakeHTTP()
        let finder = makeFinder(http)
        http.json["https://a.example/subtitles/movie/tt1.json"] = ["subtitles": [
            ["url": "https://s.example/es.srt", "lang": "spa"], ["url": "https://s.example/en.srt", "lang": "eng"],
            ["url": "file:///etc/passwd", "lang": "spa"], ["url": "https://s.example/es2.srt", "lang": "es"]]]
        let subs = await finder.subtitles(kind: "movie", videoID: "tt1", language: "es")
        XCTAssertEqual(subs.map(\.absoluteString), ["https://s.example/es.srt", "https://s.example/es2.srt"])
    }
}
