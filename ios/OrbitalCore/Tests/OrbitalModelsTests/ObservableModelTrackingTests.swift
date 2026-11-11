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

/// V9 (repintado fino): con `@Tracked`, quien lee una propiedad se entera solo de esa; quien escucha todo, de todo.
@MainActor
final class TrackedPropertyTests: XCTestCase {
    final class Counter: @unchecked Sendable { var value = 0 }

    final class Sample: ObservableModel {
        override var observesByProperty: Bool { true }
        @Tracked var name = ""
        @Tracked var count = 0
        @Tracked(always: true) var kick = 0
        var shout: String { name.uppercased() }   // derivada: sigue a `name`
    }

    func testReadingOnePropertyIgnoresTheOthers() {
        let model = Sample()
        let fired = Counter()
        withObservationTracking { _ = model.name } onChange: { fired.value += 1 }
        model.count = 3
        XCTAssertEqual(fired.value, 0, "cambiar otra propiedad no vuelve a pintar a quien solo lee `name`")
        model.name = "Dune"
        XCTAssertEqual(fired.value, 1)
    }

    func testTheSameValueDoesNotNotifyUnlessAlways() {
        let model = Sample()
        model.name = "Dune"
        let fired = Counter(), kicked = Counter()
        withObservationTracking { _ = model.name } onChange: { fired.value += 1 }
        withObservationTracking { _ = model.kick } onChange: { kicked.value += 1 }
        var heard = 0
        let subscription = model.onChange { heard += 1 }
        model.name = "Dune"
        model.kick = 0
        XCTAssertEqual(fired.value, 0, "el mismo valor no avisa")
        XCTAssertEqual(kicked.value, 1, "`always` avisa aunque sea el mismo")
        XCTAssertEqual(heard, 1)
        subscription.cancel()
    }

    func testDerivedPropertiesFollowWhatTheyRead() {
        let model = Sample()
        let fired = Counter()
        withObservationTracking { _ = model.shout } onChange: { fired.value += 1 }
        model.name = "x"
        XCTAssertEqual(fired.value, 1)
    }

    func testListenersAndWholeModelTrackersStillHearEverything() {
        let model = Sample()
        let fired = Counter()
        withObservationTracking { model.trackAll() } onChange: { fired.value += 1 }
        var heard = 0
        let subscription = model.onChange { heard += 1 }
        model.count = 1
        XCTAssertEqual(fired.value, 1)
        XCTAssertEqual(heard, 1)
        subscription.cancel()
    }

    func testTrackDoesNothingOnAPerPropertyModel() {
        let model = Sample()
        let fired = Counter()
        withObservationTracking { model.track() } onChange: { fired.value += 1 }
        model.count = 1
        XCTAssertEqual(fired.value, 0, "`track()` ya no suscribe a todo: la vista sigue lo que lee")
    }

    final class Hub: ObservableModel {
        @Tracked(alone: true) var link = 0
        @Tracked var setting = ""
    }

    func testAnAlonePropertyDoesNotRepaintWholeModelReaders() {
        let hub = Hub()
        let whole = Counter(), reader = Counter()
        withObservationTracking { hub.track() } onChange: { whole.value += 1 }
        withObservationTracking { _ = hub.link } onChange: { reader.value += 1 }
        var heard = 0
        let subscription = hub.onChange { heard += 1 }
        hub.link = 1
        XCTAssertEqual(whole.value, 0, "lo que cambia seguido (la TV) ya no repinta a quien lee todo el contenedor")
        XCTAssertEqual(reader.value, 1, "quien la lee sí se entera")
        XCTAssertEqual(heard, 1, "quien escucha desde código, también")
        hub.setting = "es"
        XCTAssertEqual(whole.value, 1, "lo general sigue avisando a todos")
        subscription.cancel()
    }

    func testCoalescingStillSendsOneListenerCall() {
        let model = Sample()
        var heard = 0
        let subscription = model.onChange { heard += 1 }
        model.coalescing { model.name = "a"; model.count = 2 }
        XCTAssertEqual(heard, 1)
        subscription.cancel()
    }
}
