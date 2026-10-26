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

    /// La órbita de «Buscando la mejor versión» cuenta lo real: a quién se le pregunta y cuántas versiones con enlace trajo
    /// cada complemento (la de torrent sin Real-Debrid no cuenta); y quien llega tarde recibe lo que ya pasó.
    func testTheSearchTellsWhoWasAskedAndWhatEachOneFound() async throws {
        let http = FakeHTTP()
        let finder = makeFinder(http)
        http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [
            ["name": "T\n1080p", "title": "Peli 1080p", "url": "https://rd.example/a"],
            ["name": "T\n720p", "title": "Peli 720p", "infoHash": "abcdef0123456789abcdef0123456789abcdef01"]]]
        http.json["https://b.example/stream/movie/tt1.json"] = ["streams": [["name": "O\n1080p", "title": "Peli 1080p", "url": "https://rd.example/b"]]]
        http.delays["https://b.example/stream/movie/tt1.json"] = 40
        let events = await finder.events(kind: "movie", videoID: "tt1")
        func firstThree(_ stream: AsyncStream<SearchEvent>) -> Task<[SearchEvent], Never> {
            Task { var out: [SearchEvent] = []; for await event in stream { out.append(event); if out.count == 3 { break } }; return out }
        }
        let reading = firstThree(events)
        let search = Task { try await finder.find(kind: "movie", videoID: "tt1", prefs: Preferences(audio: "es", quality: "1080p")) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let late = await finder.events(kind: "movie", videoID: "tt1")   // el reproductor, después de la ficha
        let lateReading = firstThree(late)
        _ = try await search.value
        let seen = await reading.value, lateSeen = await lateReading.value
        XCTAssertEqual(seen, [.asking(["Torrentio", "Otro"]), .answered(addon: "Torrentio", found: 1), .answered(addon: "Otro", found: 1)])
        XCTAssertEqual(lateSeen, seen, "quien llega tarde ve también a quién se le preguntó")
    }

    func testAStreamingPlaylistCanBeWatchedButNotDownloaded() async throws {
        let http = FakeHTTP()
        let finder = makeFinder(http)
        http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "Peli 1080p\n💾 2.1 GB", "url": "https://cdn.example/master.m3u8"],
            ["name": "T\n720p [RD+]", "title": "Peli 720p\n💾 900 MB", "url": "https://rd.example/peli.mkv"]]]
        let watch = try await finder.find(kind: "movie", videoID: "tt1", prefs: Preferences())
        XCTAssertEqual(watch.count, 2)
        let download = try await finder.find(kind: "movie", videoID: "tt1", prefs: Preferences(), purpose: .download)
        XCTAssertEqual(download.map { $0.playbackURL?.lastPathComponent }, ["peli.mkv"], "una lista HLS no es un archivo que se pueda guardar")
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
        // Sin red (ningún complemento contesta): se dice que es la red, no «no hay», y no se recuerda.
        http.failing = ["https://a.example/stream/movie/tt9.json", "https://b.example/stream/movie/tt9.json"]
        do { _ = try await finder.find(kind: "movie", videoID: "tt9", prefs: Preferences()); XCTFail("sin red debe avisar") }
        catch { XCTAssertTrue(error is StreamFinderError) }
        http.failing = []
        // Un 404 sí es «no tiene ese video»: lista vacía, sin error.
        let none = try await finder.find(kind: "movie", videoID: "tt8", prefs: Preferences())
        XCTAssertTrue(none.isEmpty)
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

final class FileFingerprintTests: XCTestCase {
    func testOpenSubtitlesHashIsSizePlusHeadAndTailSums() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fp-\(UUID().uuidString).bin")
        var data = Data(count: 200_000)
        data[0] = 1          // primer bloque: +1
        data[199_992] = 2    // último bloque: +2 (en el byte menos significativo de su palabra)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let fp = try XCTUnwrap(FileFingerprint.of(url))
        XCTAssertEqual(fp.size, 200_000)
        XCTAssertEqual(fp.hash, String(format: "%016llx", UInt64(200_000 + 1 + 2)))
        let small = FileManager.default.temporaryDirectory.appendingPathComponent("fp-small.bin")
        try Data(count: 10).write(to: small)
        XCTAssertNil(FileFingerprint.of(small))
    }

    /// El video en línea: la misma huella con dos pedidos chicos (el principio y el final), sin bajarlo.
    func testRemoteFingerprintMatchesLocalWithTwoRangeRequests() async throws {
        var data = Data(count: 200_000)
        data[0] = 1; data[199_992] = 2
        let http = RangeHTTP(data)
        let remote = await FileFingerprint.ofRemote(URL(string: "https://cdn.example/v.mkv")!, http: http)
        let fp = try XCTUnwrap(remote)
        XCTAssertEqual(fp.size, 200_000)
        XCTAssertEqual(fp.hash, String(format: "%016llx", UInt64(200_000 + 1 + 2)))
        XCTAssertEqual(http.ranges, ["bytes=0-65535", "bytes=134464-199999"])
        // Un servidor sin pedidos por partes (200): no hay huella, y no se baja el video entero.
        http.honorsRange = false
        let none = await FileFingerprint.ofRemote(URL(string: "https://cdn.example/v.mkv")!, http: http)
        XCTAssertNil(none)
    }
}

/// Un servidor que contesta pedidos por partes (Range) de unos bytes fijos.
final class RangeHTTP: HTTPClient, @unchecked Sendable {
    let data: Data
    var ranges: [String] = []
    var honorsRange = true
    init(_ data: Data) { self.data = data }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let range = request.headers["Range"] ?? ""
        ranges.append(range)
        guard honorsRange, let spec = range.split(separator: "=").last?.split(separator: "-"), spec.count == 2,
              let a = Int(spec[0]), let b = Int(spec[1]) else { return HTTPResponse(status: 200, data: Data()) }
        return HTTPResponse(status: 206, data: data.subdata(in: a..<(b + 1)), headers: ["content-range": "bytes \(a)-\(b)/\(data.count)"])
    }
}
