import XCTest
@testable import OrbitalModels
@testable import OrbitalCore

/// R15: «Avisarme cuando aparezca» revisa una vez al día durante 14 días y avisa en cuanto aparece.
@MainActor
final class AppearWatchTests: XCTestCase {
    final class Box: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_762_000_000) }

    func testOnceADayForFourteenDaysAndItNotifiesWhenItShowsUp() async {
        let clock = Box()
        var exists: Bool? = false
        var asked = 0
        let kv = InMemoryKeyValueStore()
        let watch = AppearWatch(kv: kv, clock: { clock.now }) { _ in asked += 1; return exists }
        var told: [String] = []
        watch.onAppeared = { told.append($0.title) }
        watch.watch(kind: "movie", metaID: "tt1", videoID: "tt1", title: "Nocturne")
        await watch.check()
        XCTAssertEqual(asked, 0, "acabas de ver que nadie lo tiene: hoy no se vuelve a preguntar")
        clock.now += 21 * 3_600
        await watch.check()
        XCTAssertEqual(asked, 1, "al día siguiente, sí")
        clock.now += 3_600
        await watch.check()
        XCTAssertEqual(asked, 1, "una vez al día")
        exists = nil
        clock.now += 21 * 3_600
        await watch.check()
        XCTAssertEqual(watch.entries.count, 1, "sin red, se intenta otra vez")
        exists = true
        await watch.check()
        XCTAssertEqual(told, ["Nocturne"])
        XCTAssertTrue(watch.entries.isEmpty, "ya apareció: deja de revisar")

        watch.watch(kind: "series", metaID: "tt2", videoID: "tt2:1:1", title: "The Office")
        let reopened = AppearWatch(kv: kv, clock: { clock.now }) { _ in false }
        XCTAssertEqual(reopened.entries.map(\.title), ["The Office"], "se recuerda al cerrar la app")
        clock.now += 15 * 86_400
        XCTAssertTrue(reopened.due().isEmpty)
        XCTAssertTrue(reopened.entries.isEmpty, "a los 14 días se olvida")
    }
}
