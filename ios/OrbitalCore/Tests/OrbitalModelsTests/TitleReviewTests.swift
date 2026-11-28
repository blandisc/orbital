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

    /// «La viste N veces» vuelve a preguntar cuando cambia lo tuyo: marcar, ver o deshacer fuera de su hoja.
    func testWatchChangesBumpTheStateVersion() async throws {
        let rig = try ScreenModelsTests().titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let before = title.stateVersion
        let episode = try XCTUnwrap(title.videos(in: .series).first)
        await title.markWatchedAgain(.episode(episode))
        XCTAssertGreaterThan(title.stateVersion, before)
        let after = title.stateVersion
        await title.unmarkWatched(.episode(episode))
        XCTAssertGreaterThan(title.stateVersion, after)
    }

    /// Revisión del 28 nov 2026: «El día que salió» es ese día en tu calendario (en México salía el anterior) y un episodio que
    /// sale hoy más tarde todavía no cuenta como estrenado.
    func testReleaseDaysAreLocalAndLaterTodayIsNotOutYet() {
        var mx = Calendar(identifier: .gregorian); mx.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let day = try? XCTUnwrap(TitleModel.day("2005-10-18T00:00:00.000Z", calendar: mx))
        XCTAssertEqual(day.map { mx.component(.day, from: $0) }, 18)
        let later = Date().addingTimeInterval(3 * 3600)
        let text = ISO8601DateFormatter().string(from: later)
        XCTAssertGreaterThan(TitleModel.releasedAt(text) ?? .distantPast, Date(), "sale más tarde: aún no")
        XCTAssertNotNil(TitleModel.releasedAt("2005-10-18"))
    }
}
