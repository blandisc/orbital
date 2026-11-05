import XCTest
@testable import OrbitalCore

/// Fernando, 5 nov: «prueba de forma muy rigurosa… que no afecten mi calidad de vista». Lo que el reproductor recibe por el
/// intermediario tiene que ser exactamente el archivo, byte por byte, en todo lo que el motor hace: leer de corrido, saltar,
/// abandonar una lectura a medias, leer el final (el índice de un MKV), varios lectores a la vez, y con un origen que falla.
final class ParallelStreamStressTests: XCTestCase {
    /// Un origen que a veces contesta 503 y con tiempos al azar, como Real-Debrid en una mala noche.
    final class FlakyOrigin: @unchecked Sendable {
        let bytes: Data
        let lock = NSLock()
        var rng = SystemRandomNumberGenerator()
        var failRate: Double
        var open = 0, most = 0, requests = 0
        init(size: Int, failRate: Double) {
            var g = SystemRandomNumberGenerator()
            bytes = Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &g) })
            self.failRate = failRate
        }
        var fetch: ParallelStream.Fetch {
            { [self] _, range in
                let (fail, delay): (Bool, UInt64) = lock.withLock {
                    open += 1; most = max(most, open); requests += 1
                    return (Double.random(in: 0..<1, using: &rng) < failRate, UInt64.random(in: 0...25_000_000, using: &rng))
                }
                defer { lock.withLock { open -= 1 } }
                try await Task.sleep(nanoseconds: delay)
                if fail { throw ParallelStream.Failure.refused(503) }
                let end = min(range.upperBound, bytes.count - 1)
                return .init(data: bytes.subdata(in: range.lowerBound..<(end + 1)), total: bytes.count, finalURL: nil)
            }
        }
    }

    let config = ParallelStream.Config(connections: 8, chunkBytes: 1 << 20, aheadSeconds: 120, fallbackAheadBytes: 8 << 20, behindBytes: 2 << 20)

    func make(_ origin: FlakyOrigin) -> (ParallelStream, LocalStreamProxy, URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stress-\(UUID())")
        let stream = ParallelStream(url: URL(string: "https://rd.example/v.mkv")!, config: config, folder: folder, fetch: origin.fetch)
        let proxy = LocalStreamProxy()
        return (stream, proxy, proxy.serve(stream, name: "v.mkv")!, folder)
    }

    static func get(_ url: URL, _ range: String?) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: 60)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// 200 lecturas al azar (de corrido, saltos, el final, los últimos n), de a 4 a la vez, con 5 % de fallas del origen.
    func testRandomReadsAreByteExactEvenWhenTheOriginFails() async throws {
        let size = 48 << 20, origin = FlakyOrigin(size: size, failRate: 0.05)
        let (_, proxy, url, _) = make(origin)
        defer { proxy.release(url) }
        var g = SystemRandomNumberGenerator()
        var cases: [(String?, ClosedRange<Int>)] = []
        for _ in 0..<200 {
            switch Int.random(in: 0..<4, using: &g) {
            case 0: let a = Int.random(in: 0..<size, using: &g); let b = min(size - 1, a + Int.random(in: 0..<(3 << 20), using: &g)); cases.append(("bytes=\(a)-\(b)", a...b))
            case 1: let n = Int.random(in: 1..<(2 << 20), using: &g); cases.append(("bytes=-\(n)", (size - n)...(size - 1)))
            case 2: let a = size - Int.random(in: 1..<(1 << 20), using: &g); cases.append(("bytes=\(a)-", a...(size - 1)))
            default: let a = Int.random(in: 0..<(size - 10), using: &g); cases.append(("bytes=\(a)-\(a + 9)", a...(a + 9)))
            }
        }
        for batch in stride(from: 0, to: cases.count, by: 4) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (header, range) in cases[batch..<min(batch + 4, cases.count)] {
                    group.addTask {
                        let (status, data): (Int, Data)
                        do { (status, data) = try await Self.get(url, header) } catch { XCTFail("\(header ?? ""): \(error) · intermediario: \(proxy.lastError ?? "-")"); return }
                        XCTAssertEqual(status, 206, header ?? "")
                        XCTAssertEqual(data, origin.bytes.subdata(in: range.lowerBound..<(range.upperBound + 1)), "byte por byte: \(header ?? "")")
                    }
                }
                try await group.waitForAll()
            }
        }
        XCTAssertLessThanOrEqual(origin.most, 8, "nunca más de 8 conexiones")
        XCTAssertNil(proxy.lastError)
    }

    /// El motor abandona lecturas a medias al saltar: el intermediario no se traba y la siguiente lectura sale bien.
    func testAbandonedReadsDoNotBreakTheNextOnes() async throws {
        let size = 32 << 20, origin = FlakyOrigin(size: size, failRate: 0)
        let (_, proxy, url, _) = make(origin)
        defer { proxy.release(url) }
        for start in [0, 20 << 20, 5 << 20, 30 << 20, 1 << 20] {
            var request = URLRequest(url: url); request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var got = Data()
            for try await b in bytes { got.append(b); if got.count >= 200_000 { break } }   // se va a otro lado a la mitad
            XCTAssertEqual(got, origin.bytes.subdata(in: start..<(start + 200_000)))
        }
        let (_, tail) = try await Self.get(url, "bytes=\(size - 1000)-")
        XCTAssertEqual(tail, origin.bytes.suffix(1000))
    }

    /// Una película entera de corrido: lo que ocupa en disco nunca pasa del colchón de adelante, el de atrás y lo que va
    /// en camino (más un margen), aunque el archivo sea mucho más grande.
    func testDiskStaysWithinTheBufferWhileWatchingAWholeFile() async throws {
        let size = 64 << 20, origin = FlakyOrigin(size: size, failRate: 0.02)
        let (stream, proxy, url, folder) = make(origin)
        defer { proxy.release(url) }
        let cap = config.fallbackAheadBytes + config.behindBytes + (config.connections * config.runChunks + 3) * config.chunkBytes
        var most = 0, at = 0
        while at < size {
            let piece = try await stream.read(offset: at, maxLength: size - at, reader: 7)
            XCTAssertEqual(piece, origin.bytes.subdata(in: at..<(at + piece.count)))
            at += piece.count
            let used = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
                .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            most = max(most, used)
        }
        XCTAssertLessThanOrEqual(most, cap, "en disco a lo más el colchón (\(most >> 20) MB de \(cap >> 20) MB)")
        let fetched = await stream.fetched
        XCTAssertLessThan(fetched, Int(Double(size / config.chunkBytes) * 1.3), "casi sin pedir dos veces lo mismo")
    }

    /// Si el origen no deja leer por pedazos (contesta 200 o falla siempre), el intermediario lo dice con un error y el
    /// reproductor abre directo (`AetherEnginePlayer`): no se queda colgado.
    func testAnOriginThatAlwaysFailsEndsQuicklyWithAnError() async throws {
        let origin = FlakyOrigin(size: 4 << 20, failRate: 1)
        let (_, proxy, url, _) = make(origin)
        defer { proxy.release(url) }
        let started = Date()
        let result = try? await Self.get(url, "bytes=0-99")
        XCTAssertNotEqual(result?.0, 206)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "falla pronto, no espera para siempre")
    }
}
