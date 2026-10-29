import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Lo que se hace con un título desde un póster (antes vivía en `AppEnvironment`, sin pruebas).
@MainActor
final class TitleActionsTests: XCTestCase {
    private func suggestion(kind: String = "series", imdb: String = "tt0386676", next: (season: Int, episode: Int)? = nil) -> Suggestion {
        var s = Suggestion(kind: kind, imdb: imdb, title: "The Office", poster: "", wide: "", reason: .popular)
        if let next { s.next = .init((season: next.season, episode: next.episode)) }
        return s
    }

    func testVideoIDIsTheNextEpisodeTheMovieOrTheFirstEpisode() throws {
        let actions = TitleActions(try ServicesRig().services)
        XCTAssertEqual(actions.videoID(for: suggestion(next: (2, 5))), "tt0386676:2:5")
        XCTAssertEqual(actions.videoID(for: suggestion(kind: "movie", imdb: "tt0111161")), "tt0111161")
        XCTAssertEqual(actions.videoID(for: suggestion()), "tt0386676:1:1")
    }

    func testSeriesStartUsesTheSuggestedEpisodeWhenNothingWasWatched() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": []]
        let start = await TitleActions(rig.services).seriesStart(suggestion(next: (3, 2)))
        XCTAssertEqual(start?.videoID, "tt0386676:3:2")
        XCTAssertEqual(start?.season, 3); XCTAssertEqual(start?.episode, 2)
        XCTAssertEqual(start?.isResume, false)
        XCTAssertEqual(start?.meta["name"]?.string, "The Office")
    }

    func testSeriesStartIsNilWhenCinemetaDoesNotAnswer() async throws {
        let rig = try ServicesRig()
        rig.http.offline = true
        let start = await TitleActions(rig.services).seriesStart(suggestion())
        XCTAssertNil(start)
    }

    func testPreferredDestinationIsStremioWithoutTrakt() throws {
        XCTAssertEqual(TitleActions(try ServicesRig().services).preferredDestination(for: suggestion()), .stremioLibrary)
        XCTAssertEqual(TitleActions(try ServicesRig(traktLinked: true, traktClientID: "demo").services).preferredDestination(for: suggestion()), .traktWatchlist)
    }

    func testSavingToStremioWritesTheLibrary() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json[stremioPut] = ["result": ["success": true]]
        try await TitleActions(rig.services).setSaved(suggestion(), in: .stremioLibrary, add: true)
        XCTAssertEqual(rig.http.bodies(stremioPut).count, 1, "una escritura a la biblioteca de Stremio")
    }

    func testFavoritesNeedTrakt() async throws {
        let actions = TitleActions(try ServicesRig().services)
        do { try await actions.setFavorite(suggestion(), add: true); XCTFail("sin Trakt no hay favoritos") }
        catch { XCTAssertTrue(error is TraktError) }
    }
}
