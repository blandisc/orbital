import XCTest
@testable import OrbitalCore

/// ST6 + ST2 (Fernando, 5 nov): el video en pedazos con varias conexiones y con colchón, servido al reproductor por el
/// intermediario local. Con un origen falso que cuenta cuántas peticiones lleva a la vez.
final class ParallelStreamTests: XCTestCase {
    final class Origin: @unchecked Sendable {
        let bytes: Data
        let lock = NSLock()
        var open = 0, most = 0, ranges: [ClosedRange<Int>] = []
        var failNext = 0
        init(size: Int) { bytes = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) }) }

        var fetch: ParallelStream.Fetch {
            { [self] _, range in
                let fail: Bool = lock.withLock { open += 1; most = max(most, open); ranges.append(range); if failNext > 0 { failNext -= 1; return true }; return false }
                try? await Task.sleep(nanoseconds: 20_000_000)
                lock.withLock { open -= 1 }
                if fail { throw ParallelStream.Failure.refused(503) }
                let end = min(range.upperBound, bytes.count - 1)
                return .init(data: bytes.subdata(in: range.lowerBound..<(end + 1)), total: bytes.count, finalURL: URL(string: "https://rd.example/final.mkv"))
            }
        }
    }

    func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)") }
    let small = ParallelStream.Config(connections: 4, chunkBytes: 1 << 20, aheadSeconds: 120, fallbackAheadBytes: 8 << 20, behindBytes: 1 << 20)

    func testReadsTheSameBytesWithSeveralConnectionsAtOnce() async throws {
        let origin = Origin(size: 30 << 20), dir = folder()
        let stream = ParallelStream(url: URL(string: "https://torrentio.example/resolve/x")!, config: small, folder: dir, fetch: origin.fetch)
        let size = try await stream.size()
        XCTAssertEqual(size, 30 << 20)
        var got = Data(), at = 0
        while at < 12 << 20 { let piece = try await stream.read(offset: at, maxLength: 12 << 20 - at, reader: 1); got.append(piece); at += piece.count }
        XCTAssertEqual(got, origin.bytes.subdata(in: 0..<(12 << 20)), "byte por byte, lo mismo que el origen")
        XCTAssertGreaterThan(origin.most, 1, "varias conexiones a la vez")
        XCTAssertLessThanOrEqual(origin.most, 4, "nunca más de las pedidas")
        await stream.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "al cerrar se borra lo bajado")
    }

    func testAJumpReadsThereAndOldPiecesAreDeleted() async throws {
        let origin = Origin(size: 40 << 20), dir = folder()
        let stream = ParallelStream(url: URL(string: "https://o.example/v")!, config: small, folder: dir, fetch: origin.fetch)
        _ = try await stream.read(offset: 0, maxLength: 1000, reader: 1)
        let far = 35 << 20 + 123
        let piece = try await stream.read(offset: far, maxLength: 1000, reader: 1)
        XCTAssertEqual(piece, origin.bytes.subdata(in: far..<(far + 1000)))
        try? await Task.sleep(nanoseconds: 200_000_000)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertFalse(left.contains("0.part"), "lo de atrás, lejos de donde vas, se borra")
        await stream.close()
    }

    func testRealDebridSayingTooManyLowersTheConnectionsAndRetries() async throws {
        let origin = Origin(size: 8 << 20)
        origin.failNext = 1
        let stream = ParallelStream(url: URL(string: "https://o.example/v")!, config: small, folder: folder(), fetch: origin.fetch)
        let piece = try await stream.read(offset: 0, maxLength: 10, reader: 1)
        XCTAssertEqual(piece, origin.bytes.prefix(10))
        await stream.close()
    }

    func testTheBufferFollowsTheSecondsOnceTheDurationIsKnown() async throws {
        let origin = Origin(size: 100 << 20)
        let config = ParallelStream.Config(connections: 8, chunkBytes: 1 << 20, aheadSeconds: 10, fallbackAheadBytes: 50 << 20, behindBytes: 0)
        let stream = ParallelStream(url: URL(string: "https://o.example/v")!, config: config, folder: folder(), fetch: origin.fetch)
        _ = try await stream.size()
        let before = await stream.aheadBytes
        XCTAssertEqual(before, 50 << 20)
        await stream.setDuration(100)   // 1 MB por segundo: 10 s son 10 MB
        let after = await stream.aheadBytes
        XCTAssertEqual(after, 10 << 20)
        await stream.close()
    }

    func testRanges() {
        XCTAssertEqual(LocalStreamProxy.byteRange(nil, total: 100), 0...99)
        XCTAssertEqual(LocalStreamProxy.byteRange("bytes=10-", total: 100), 10...99)
        XCTAssertEqual(LocalStreamProxy.byteRange("bytes=10-19", total: 100), 10...19)
        XCTAssertEqual(LocalStreamProxy.byteRange("bytes=-10", total: 100), 90...99)
        XCTAssertEqual(LocalStreamProxy.byteRange("bytes=95-500", total: 100), 95...99)
        XCTAssertNil(LocalStreamProxy.byteRange("bytes=100-", total: 100))
        XCTAssertEqual(LocalStreamProxy.parse("GET /s/abc/v.mkv HTTP/1.1\r\nHost: x\r\nRange: bytes=5-9"),
                       .init(method: "GET", path: "/s/abc/v.mkv", range: "bytes=5-9"))
    }

    /// De punta a punta: el reproductor (aquí URLSession) pide al intermediario local, con saltos, y recibe lo del origen.
    func testTheLocalProxyServesRangesLikeTheOrigin() async throws {
        let origin = Origin(size: 10 << 20)
        let stream = ParallelStream(url: URL(string: "https://o.example/v")!, config: small, folder: folder(), fetch: origin.fetch)
        let proxy = LocalStreamProxy()
        let url = try XCTUnwrap(proxy.serve(stream, name: "Dune.mkv"))
        XCTAssertEqual(url.host, "127.0.0.1")
        var request = URLRequest(url: url)
        request.setValue("bytes=3000000-3999999", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 3000000-3999999/\(10 << 20)")
        XCTAssertEqual(data, origin.bytes.subdata(in: 3_000_000..<4_000_000))
        var head = URLRequest(url: url); head.httpMethod = "HEAD"
        let (_, headResponse) = try await URLSession.shared.data(for: head)
        XCTAssertEqual((headResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"), "\(10 << 20)")
        let (whole, _) = try await URLSession.shared.data(from: url)
        XCTAssertEqual(whole, origin.bytes, "sin Range, el archivo entero")
        proxy.release(url)
    }
}

/// Con un origen real por la red (solo con ORBITAL_LIVE_STREAM=<dirección>): un servidor que, como Real-Debrid, da los
/// pedazos que se le piden y tiene un tope por conexión. Por el intermediario, el reproductor lee lo mismo y más rápido.
/// (Los archivos de prueba públicos, OVH y Hetzner, castigan varias conexiones a la vez: no sirven para esto.)
final class ParallelStreamLiveTests: XCTestCase {
    func testLiveThroughputAgainstOneConnection() async throws {
        guard let text = ProcessInfo.processInfo.environment["ORBITAL_LIVE_STREAM"], let origin = URL(string: text) else { throw XCTSkip("sin origen") }
        let want = 48 << 20
        var direct = URLRequest(url: origin); direct.setValue("bytes=0-\(want - 1)", forHTTPHeaderField: "Range")
        var t = Date()
        let (one, _) = try await URLSession.shared.data(for: direct)
        let single = Double(one.count) / Date().timeIntervalSince(t)
        let stream = ParallelStream(url: origin, config: .wifi, folder: FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID())"),
                                    fetch: ParallelStream.urlSessionFetch(headers: [:]))
        let proxy = LocalStreamProxy()
        let url = try XCTUnwrap(proxy.serve(stream))
        var request = URLRequest(url: url); request.setValue("bytes=0-\(want - 1)", forHTTPHeaderField: "Range")
        t = Date()
        let (many, _) = try await URLSession.shared.data(for: request)
        let parallel = Double(many.count) / Date().timeIntervalSince(t)
        print(String(format: "EN VIVO: una conexión %.1f MB/s · intermediario %.1f MB/s", single / 1e6, parallel / 1e6))
        XCTAssertEqual(many, one)
        XCTAssertGreaterThan(parallel, single * 2)
        proxy.release(url)
    }
}

final class StreamWarmupTests: XCTestCase {
    func testOncePerLinkEveryTenMinutes() {
        let url = URL(string: "https://torrentio.example/resolve/realdebrid/K/\(UUID())/x.mkv")!, now = Date()
        XCTAssertTrue(StreamWarmup.warm(url, now: now))
        XCTAssertFalse(StreamWarmup.warm(url, now: now.addingTimeInterval(60)), "no se repite al volver a la ficha")
        XCTAssertTrue(StreamWarmup.warm(url, now: now.addingTimeInterval(601)))
        XCTAssertFalse(StreamWarmup.warm(URL(fileURLWithPath: "/tmp/x.mkv")), "tus descargas, no")
    }

    func testTheEngineWarmsWhenTheAppSetsItExceptFor4K() {
        let seen = Box()
        StreamWarmup.engineWarm = { url, _ in seen.add(url) }
        defer { StreamWarmup.engineWarm = nil }
        let a = URL(string: "https://torrentio.example/engine/a.mkv")!, b = URL(string: "https://torrentio.example/engine/b.mkv")!
        XCTAssertTrue(StreamWarmup.warm(a))
        XCTAssertTrue(StreamWarmup.warm(b, parallel: true))
        XCTAssertEqual(seen.urls, [a], "el 4K va por el intermediario: el motor no lo calienta")
    }

    final class Box: @unchecked Sendable {
        let lock = NSLock(); var urls: [URL] = []
        func add(_ url: URL) { lock.withLock { urls.append(url) } }
    }

    func testTheSpanishVariantTrackIsRememberedByLinkThenTitle() {
        let defaults = UserDefaults(suiteName: "variant-\(UUID())")!
        let memory = AudioVariantMemory(defaults: defaults)
        XCTAssertNil(memory.index(variant: "es-419", keys: ["https://x/1.mkv", "tt1"]))
        memory.remember(2, variant: "es-419", keys: ["https://x/1.mkv", "tt1"])
        XCTAssertEqual(memory.index(variant: "es-419", keys: ["https://x/2.mkv", "tt1"]), 2, "otro episodio: lo del título")
        memory.remember(3, variant: "es-419", keys: ["https://x/2.mkv"])
        XCTAssertEqual(memory.index(variant: "es-419", keys: ["https://x/2.mkv", "tt1"]), 3, "el enlace antes que el título")
        XCTAssertNil(memory.index(variant: "es-ES", keys: ["https://x/1.mkv", "tt1"]), "cada variante, la suya")
    }
}
