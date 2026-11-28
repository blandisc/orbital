import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Fallas de la ficha que encontró la revisión del 27 nov 2026.
@MainActor
final class TitleReviewTests: XCTestCase {
    /// Los especiales vistos no completan la serie: con 3 episodios sin ver sigue «Viendo», no «Vista».
    func testSpecialsDoNotMakeASeriesWatched() async throws {
        let rig = try ScreenModelsTests().titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let released = title.videos(in: .series)
        XCTAssertGreaterThan(released.count, 3)
        let seen = Array(released.dropLast(3)) + ["tt0386676:0:1", "tt0386676:0:2", "tt0386676:0:3"]
        rig.services.library.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) { $0.seen = Set(seen) }
        await title.refreshState()
        XCTAssertNotEqual(title.status(dropped: false), .watched, "le faltan 3 episodios")
        let first = try XCTUnwrap(title.seasons.first { !$0.isSpecials }?.season)
        let count = title.watchedCount(.season(first))
        XCTAssertLessThanOrEqual(count.watched, count.total)
        XCTAssertTrue(title.watchedAnyEpisode)
    }
}
