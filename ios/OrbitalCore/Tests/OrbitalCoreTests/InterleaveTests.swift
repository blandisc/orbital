import XCTest
@testable import OrbitalCore

/// Una sola forma de alternar listas (B4): uno de cada una por turno, sin repetir, y lo que sobra de la larga al final.
final class InterleaveTests: XCTestCase {
    func testOneOfEachInTurnAndTheRestAtTheEnd() {
        XCTAssertEqual(Interleave.turns([["s1", "s2", "s3"], ["p1"]], id: { $0 }), ["s1", "p1", "s2", "s3"])
    }

    func testNoRepeatsAndTheLimitIsKept() {
        XCTAssertEqual(Interleave.turns([["a", "b", "c"], ["b", "d"]], limit: 3, id: { $0 }), ["a", "b", "d"], "la «b» de la segunda ya salió")
        XCTAssertEqual(Interleave.turns([[String]](), id: { $0 }), [])
        XCTAssertEqual(Interleave.turns([["a"], []], limit: 0, id: { $0 }), [])
    }
}
