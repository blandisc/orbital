import XCTest
@testable import OrbitalModels

/// Avisos que esperan mientras el candado ocupa su sitio: orden de llegada, uno por clase, y que un
/// candado nuevo no tire lo que todavía no se mostró.
final class HeldNoticesTests: XCTestCase {

    func testHoldQueuesInArrivalOrderAndNextStaysQuiet() {
        var queue = HeldNotices<String>()
        queue.hold()
        queue.hold("descarga")
        queue.hold("subtítulos")
        XCTAssertNil(queue.next())
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.release(), ["descarga", "subtítulos"])
        XCTAssertFalse(queue.isHolding)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.next())
    }

    func testNextDeliversOneAtATimeAndANewHoldKeepsTheRest() {
        var queue = HeldNotices<String>()
        queue.hold()
        queue.hold("primero")
        queue.hold("segundo")
        queue.hold("tercero")
        queue.resume()
        XCTAssertEqual(queue.next(), "primero")
        queue.hold()
        XCTAssertNil(queue.next())
        queue.hold("cuarto")
        queue.resume()
        XCTAssertEqual(queue.next(), "segundo")
        XCTAssertEqual(queue.next(), "tercero")
        XCTAssertEqual(queue.next(), "cuarto")
        XCTAssertNil(queue.next())
        XCTAssertTrue(queue.isEmpty)
    }

    func testReleaseReturnsWhatNextHasNotTaken() {
        var queue = HeldNotices<String>()
        queue.hold("uno")
        queue.hold("dos")
        queue.hold("tres")
        XCTAssertEqual(queue.next(), "uno")
        XCTAssertEqual(queue.release(), ["dos", "tres"])
    }

    func testSameKeyKeepsOnlyTheLatestInItsPlace() {
        var queue = HeldNotices<String>()
        queue.hold("encajar", key: "zoom")
        queue.hold("bajando")
        queue.hold("español", key: "subtítulos")
        queue.hold("llenar", key: "zoom")
        queue.hold("inglés", key: "subtítulos")
        XCTAssertEqual(queue.release(), ["llenar", "bajando", "inglés"])
    }

    func testDifferentKeysAndPlainItemsAllStay() {
        var queue = HeldNotices<String>()
        queue.hold("aviso")
        queue.hold("otro aviso")
        queue.hold("zoom", key: "zoom")
        XCTAssertEqual(queue.next(), "aviso")
        XCTAssertEqual(queue.next(), "otro aviso")
        XCTAssertEqual(queue.next(), "zoom")
        XCTAssertNil(queue.next())
    }

    func testHoldAgainDoesNotDropWhatWasAlreadyWaiting() {
        var queue = HeldNotices<String>()
        queue.hold("antes")
        queue.hold()
        queue.hold("durante", key: "zoom")
        queue.hold("durante-nuevo", key: "zoom")
        XCTAssertNil(queue.next())
        queue.resume()
        XCTAssertEqual(queue.release(), ["antes", "durante-nuevo"])
    }

    func testEmptyQueueReleasesNothing() {
        var queue = HeldNotices<String>()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.next())
        XCTAssertEqual(queue.release(), [])
    }
}
