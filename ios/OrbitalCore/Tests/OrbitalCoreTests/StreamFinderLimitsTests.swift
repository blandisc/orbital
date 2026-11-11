import XCTest
@testable import OrbitalCore

/// Fernando, 9 nov (Los Simpson, build 1940): 5x16 dijo «No hay versiones en Real-Debrid» aunque Torrentio sí tenía, y
/// 8x3 y 7x2 se quedaron buscando para siempre.
final class StreamFinderLimitsTests: XCTestCase {
    static let small = SearchLimits(perAddon: 0.5, origin: 0.5, readyLink: 0.5, total: 2)

    func makeFinder(_ http: HTTPClient, fake: FakeHTTP, limits: SearchLimits = small) -> StreamFinder {
        fake.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        fake.json["https://b.example/manifest.json"] = ["name": "Comet", "resources": ["stream"], "types": ["movie", "series"]]
        let registry = AddonRegistry(http: fake, own: { ["https://a.example", "https://b.example"] })
        return StreamFinder(http: http, registry: registry, limits: limits)
    }

    /// Falla 2: un complemento que no suelta (ni hace caso a la cancelación) ya no deja la búsqueda trabada: pasado el
    /// tiempo de gracia, con lo que dio el otro basta.
    func testAnAddonThatNeverAnswersDoesNotHangTheSearch() async throws {
        let fake = FakeHTTP()
        fake.json["https://b.example/stream/series/tt0096697%3A8%3A3.json"] = ["streams": [["name": "C\n1080p", "title": "Simpsons S08E03 1080p", "url": "https://rd.example/c"]]]
        let http = HangingHTTP(fake, hanging: ["https://a.example/stream/series/tt0096697%3A8%3A3.json"])
        let finder = makeFinder(http, fake: fake, limits: SearchLimits(perAddon: 30, origin: 1, readyLink: 1, total: 30))
        let start = Date()
        let found = try await finder.find(kind: "series", videoID: "tt0096697:8:3", prefs: Preferences())
        XCTAssertEqual(found.count, 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 8, "no se espera al que no suelta (antes: para siempre)")
    }

    /// Falla 2: la búsqueda que empezó la ficha (warm) y nunca termina tampoco la hereda el reproductor para siempre.
    func testJoiningASearchThatNeverEndsHasALimit() async throws {
        let fake = FakeHTTP()
        let http = HangingHTTP(fake, hanging: ["https://a.example/stream/series/tt0096697%3A7%3A2.json", "https://b.example/stream/series/tt0096697%3A7%3A2.json"])
        let finder = makeFinder(http, fake: fake, limits: SearchLimits(perAddon: 30, origin: 1, readyLink: 1, total: 1))
        let warming = Task { await finder.warm(kind: "series", videoID: "tt0096697:7:2") }
        try await Task.sleep(nanoseconds: 50_000_000)
        let start = Date()
        do { _ = try await finder.find(kind: "series", videoID: "tt0096697:7:2", prefs: Preferences()); XCTFail("debe avisar") }
        catch { XCTAssertTrue(error is StreamFinderError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
        _ = await warming.value
    }

    /// Falla 1: Torrentio no contestó y Comet no tenía nada: no es «no hay», es «Torrentio no contestó» (y no se recuerda).
    func testOneQuietAndOneEmptyIsNotNoSources() async throws {
        let fake = FakeHTTP()
        fake.failing = ["https://a.example/stream/series/tt0096697%3A5%3A16.json"]
        fake.json["https://b.example/stream/series/tt0096697%3A5%3A16.json"] = ["streams": []]
        let finder = makeFinder(fake, fake: fake)
        do { _ = try await finder.find(kind: "series", videoID: "tt0096697:5:16", prefs: Preferences()); XCTFail("no se sabe si hay") }
        catch { XCTAssertEqual(error as? StreamFinderError, .incomplete(["Torrentio"])) }
        XCTAssertEqual(fake.calls.filter { $0.hasPrefix("https://a.example/stream/") }.count, 2, "se reintenta solo una vez")
        // Torrentio vuelve: la siguiente búsqueda pregunta de nuevo y encuentra.
        fake.failing = []
        fake.json["https://a.example/stream/series/tt0096697%3A5%3A16.json"] = ["streams": [["name": "T\n1080p [RD+]", "title": "Simpsons S05E16 1080p", "url": "https://rd.example/t"]]]
        let found = try await finder.find(kind: "series", videoID: "tt0096697:5:16", prefs: Preferences())
        XCTAssertEqual(found.count, 1)
    }

    /// Falla 1: un 429 de Torrentio (demasiadas preguntas) es «no contestó», no «no tiene ese video».
    func testTooManyRequestsIsNotAnEmptyAnswer() async throws {
        let fake = FakeHTTP()
        fake.json["https://a.example/stream/series/tt0096697%3A5%3A16.json"] = ["streams": []]
        fake.statuses["https://a.example/stream/series/tt0096697%3A5%3A16.json"] = 429
        let finder = makeFinder(fake, fake: fake)
        do { _ = try await finder.find(kind: "series", videoID: "tt0096697:5:16", prefs: Preferences()); XCTFail("no se sabe si hay") }
        catch { XCTAssertEqual(error as? StreamFinderError, .incomplete(["Torrentio"])) }
    }

    /// Falla 1: si al primer intento no contestó pero al reintento sí, salen sus versiones sin que tengas que hacer nada.
    func testTheAutomaticRetryFindsWhatTheFirstTryMissed() async throws {
        let fake = FakeHTTP()
        let url = "https://a.example/stream/series/tt0096697%3A5%3A16.json"
        fake.json[url] = ["streams": [["name": "T\n1080p [RD+]", "title": "Simpsons S05E16 1080p", "url": "https://rd.example/t"]]]
        let http = HangingHTTP(fake, failFirst: [url])
        let finder = makeFinder(http, fake: fake)
        let found = try await finder.find(kind: "series", videoID: "tt0096697:5:16", prefs: Preferences())
        XCTAssertEqual(found.count, 1)
    }

    /// El tope no espera al trabajo que ignora la cancelación, y lo primero que llega gana.
    func testDeadlineReturnsTheFallbackOnTime() async {
        let start = Date()
        let late = await Deadline.within(0.2, or: -1) { await Task.detached { try? await Task.sleep(nanoseconds: 5_000_000_000); return 1 }.value }
        XCTAssertEqual(late, -1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let quick = await Deadline.within(5, or: -1) { 7 }
        XCTAssertEqual(quick, 7)
    }
}

/// Un servidor que no suelta ciertas direcciones (ni al cancelar), o que falla la primera vez.
final class HangingHTTP: HTTPClient, @unchecked Sendable {
    let base: FakeHTTP
    let hanging: Set<String>
    private let lock = NSLock()
    private var failFirst: Set<String>
    init(_ base: FakeHTTP, hanging: Set<String> = [], failFirst: Set<String> = []) { self.base = base; self.hanging = hanging; self.failFirst = failFirst }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = request.url.absoluteString
        if hanging.contains(key) {
            // Fuera de la tarea que lo pidió: cancelarla no lo suelta (como un servidor que gotea bytes).
            await Task.detached { try? await Task.sleep(nanoseconds: 10_000_000_000) }.value
        }
        if lock.withLock({ failFirst.remove(key) != nil }) { throw NetworkError("sin conexión") }
        return try await base.send(request)
    }
}
