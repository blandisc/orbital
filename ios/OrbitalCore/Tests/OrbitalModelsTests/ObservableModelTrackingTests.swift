import Observation
import XCTest
@testable import OrbitalModels

@MainActor
final class ObservableModelTrackingTests: XCTestCase {
    final class Counter: @unchecked Sendable { var value = 0 }

    func testChangedInvalidatesWhoTracked() {
        let model = ObservableModel()
        let fired = Counter()
        withObservationTracking { model.track() } onChange: { fired.value += 1 }
        model.changed()
        model.changed()   // el seguimiento es de una sola vez, como en SwiftUI
        XCTAssertEqual(fired.value, 1)
    }

    func testOnChangeStillFires() {
        let model = ObservableModel()
        var count = 0
        let subscription = model.onChange { count += 1 }
        model.changed()
        XCTAssertEqual(count, 1)
        subscription.cancel()
    }
}
