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
}
