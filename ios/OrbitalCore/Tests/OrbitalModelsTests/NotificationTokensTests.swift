import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// C4: los modelos dejan de escuchar NotificationCenter al irse (antes sus observadores se quedaban para siempre).
@MainActor
final class NotificationTokensTests: XCTestCase {
    private final class Hits: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func add() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    func testWhenTheBagGoesTheObserverGoesToo() {
        let center = NotificationCenter(), name = Notification.Name("prueba"), hits = Hits()
        var bag: NotificationTokens? = NotificationTokens(center: center)
        bag?.observe(name) { _ in hits.add() }
        center.post(name: name, object: nil)
        XCTAssertEqual(hits.count, 1)
        bag = nil
        center.post(name: name, object: nil)
        XCTAssertEqual(hits.count, 1, "ya nadie escucha")
    }

    func testInicioAndParaTiAreReleasedAndListenWhileTheyLive() throws {
        let rig = try ServicesRig()
        weak var home: HomeModel?, paraTi: ParaTiModel?
        do {
            let h = HomeModel(rig.services), p = ParaTiModel(rig.services)
            home = h; paraTi = p
            XCTAssertEqual(h.notifications.count, 2, "favoritos y biblioteca")
            XCTAssertEqual(p.notifications.count, 1, "favoritos")
        }
        XCTAssertNil(home, "Inicio se suelta (sus observadores con él)")
        XCTAssertNil(paraTi, "Para ti también")
    }
}
