import XCTest
@testable import OrbitalCore

/// La fila de los detalles de TMDB: nunca más de `limit` a la vez y un título se pide una sola vez aunque lo pidan varios.
final class TmdbDetailsGateTests: XCTestCase {
    private actor Counter {
        var now = 0, most = 0, calls = 0
        func enter() { now += 1; calls += 1; most = max(most, now) }
        func leave() { now -= 1 }
    }

    private static func details(_ id: Int) -> TmdbDetails {
        TmdbDetails(kind: "movie", tmdbID: id, imdb: "tt\(id)", title: "\(id)", year: nil, overview: "", runtime: nil, seasons: nil, episodes: nil, poster: nil, backdrop: nil)
    }

    func testNeverMoreThanTheLimitAtOnce() async throws {
        let gate = TmdbDetailsGate(limit: 2), counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 1...8 {
                group.addTask {
                    _ = try await gate.details("k\(id)") {
                        await counter.enter(); try await Task.sleep(nanoseconds: 30_000_000); await counter.leave()
                        return Self.details(id)
                    }
                }
            }
            try await group.waitForAll()
        }
        let most = await counter.most
        XCTAssertLessThanOrEqual(most, 2)
    }

    func testTheSameTitleIsFetchedOnce() async throws {
        let gate = TmdbDetailsGate(limit: 2), counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...3 {
                group.addTask {
                    _ = try await gate.details("igual") {
                        await counter.enter(); try await Task.sleep(nanoseconds: 50_000_000); await counter.leave()
                        return Self.details(1)
                    }
                }
            }
            try await group.waitForAll()
        }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }

    /// Lo que sale a la red y espera a que la cancelen (hasta 10 s): dice si la cancelaron.
    private actor Probe {
        var started = 0, cancelled = 0, finished = 0
        func start() { started += 1 }
        func cancel() { cancelled += 1 }
        func finish() { finished += 1 }
    }

    private static func slow(_ probe: Probe) -> @Sendable () async throws -> TmdbDetails {
        {
            await probe.start()
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { await probe.cancel(); throw error }
            await probe.finish()
            return details(7)
        }
    }

    private static func waitFor(_ condition: @escaping @Sendable () async -> Bool) async {
        for _ in 0..<200 where !(await condition()) { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    /// B9: dos secciones esperan el mismo título y las dos se van → la petición se cancela (antes seguía 10 s).
    func testWhenEveryoneLeavesTheRequestIsCancelled() async {
        let gate = TmdbDetailsGate(limit: 2), probe = Probe()
        let a = Task { try await gate.details("igual", Self.slow(probe)) }
        let b = Task { try await gate.details("igual", Self.slow(probe)) }
        await Self.waitFor { await probe.started == 1 }
        a.cancel(); b.cancel()
        await Self.waitFor { await probe.cancelled == 1 }
        let cancelled = await probe.cancelled, started = await probe.started, left = await gate.inflightCount
        XCTAssertEqual(started, 1, "un solo viaje a la red")
        XCTAssertEqual(cancelled, 1, "nadie lo quería: se canceló")
        XCTAssertEqual(left, 0, "y no queda en vuelo")
        _ = await (a.result, b.result)
    }

    /// Si solo una se va, la otra sigue esperando lo suyo: no se cancela.
    func testIfSomeoneStillWaitsItIsNotCancelled() async throws {
        let gate = TmdbDetailsGate(limit: 2), probe = Probe()
        let quick: @Sendable () async throws -> TmdbDetails = {
            await probe.start(); try await Task.sleep(nanoseconds: 150_000_000); await probe.finish(); return Self.details(7)
        }
        let a = Task { try await gate.details("igual", quick) }
        let b = Task { try await gate.details("igual", quick) }
        await Self.waitFor { await probe.started == 1 }
        a.cancel()
        let value = try await b.value
        XCTAssertEqual(value.tmdbID, 7)
        let finished = await probe.finished
        XCTAssertEqual(finished, 1)
        _ = await a.result
    }
}
