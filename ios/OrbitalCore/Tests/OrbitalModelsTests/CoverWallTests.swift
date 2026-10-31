import XCTest
@testable import OrbitalModels

/// El muro de la portada de Para ti: el mismo al volver, otro si llegan pósters distintos, sin franjas de los mismos.
final class CoverWallTests: XCTestCase {
    private func posters(_ n: Int, from: Int = 0) -> [String] { (from..<from + n).map { "/p\($0).jpg" } }

    func testTheSamePostersGiveTheSameWall() {
        let first = CoverWall().next(for: posters(50), size: 20)
        XCTAssertEqual(first.order.count, 20)
        XCTAssertEqual(Set(first.order).count, 20, "con suficientes, ninguno repetido")
        XCTAssertEqual(first.next(for: posters(50), size: 20), first, "al volver del mosaico, el mismo muro")
        XCTAssertEqual(first.next(for: Array(posters(50).prefix(10)), size: 20), first, "menos de los mismos: igual")
    }

    func testNewDistinctPostersMakeAnotherWallWithAll() {
        let few = CoverWall().next(for: posters(3), size: 12, shuffle: { $0 })
        let more = few.next(for: posters(30), size: 12, shuffle: { $0 })
        XCTAssertNotEqual(more.order, few.order)
        XCTAssertEqual(Set(more.order).count, 12, "con todos los distintos, no solo los tres de antes")
    }

    func testFewPostersRepeatInBatchesWithoutTwoTogether() {
        let wall = CoverWall().next(for: ["a", "b", "c", "a"], size: 10, shuffle: { $0.reversed() })
        XCTAssertEqual(wall.order.count, 10)
        XCTAssertEqual(Set(wall.order), ["a", "b", "c"])
        for (x, y) in zip(wall.order, wall.order.dropFirst()) { XCTAssertNotEqual(x, y, "dos iguales juntos: \(wall.order)") }
    }

    func testNothingGivesNothing() {
        XCTAssertEqual(CoverWall().next(for: [], size: 10).order, [])
    }

    @MainActor func testTheMemoryKeepsTheLastWall() {
        let memory = CoverWallMemory()
        let a = memory.order(for: posters(40), size: 15)
        XCTAssertEqual(memory.order(for: posters(40), size: 15), a)
        XCTAssertEqual(memory.last.source, posters(40))
    }
}
