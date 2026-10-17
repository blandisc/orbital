import XCTest
@testable import OrbitalCore

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSONAndKeepsOnlyThreeItems() throws {
        let items = (1...5).map { WidgetSnapshot.Item(kind: "series", metaID: "tt\($0)", videoID: "tt\($0):2:6", title: "Serie \($0)", episodeLabel: "T2 · E6", status: "quedan 20 min", progress: 0.4) }
        let upcoming = [WidgetSnapshot.UpcomingEpisode(title: "Severance", episodeLabel: "T3 E4", date: Date(timeIntervalSince1970: 1_760_000_000))]
        let snapshot = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_760_000_000), language: "en", items: items, upcoming: upcoming)
        XCTAssertEqual(snapshot.items.count, 3)
        XCTAssertEqual(WidgetSnapshot.decode(try snapshot.encoded()), snapshot)
    }

    func testUpcomingIsOptionalAndOldFilesWithoutItStillDecode() throws {
        let json = #"{"generatedAt":"2025-10-09T08:53:20Z","language":"es","items":[]}"#
        let snapshot = try XCTUnwrap(WidgetSnapshot.decode(Data(json.utf8)))
        XCTAssertNil(snapshot.upcoming)
        XCTAssertNil(WidgetSnapshot.decode(Data("no es json".utf8)))
    }

    func testDetailJoinsWhatThereIsWithoutDanglingDots() {
        XCTAssertEqual(WidgetSnapshot.Item(kind: "series", metaID: "a", title: "A", episodeLabel: "T2 · E6", status: "quedan 20 min").detail, "T2 · E6 · quedan 20 min")
        XCTAssertEqual(WidgetSnapshot.Item(kind: "series", metaID: "a", title: "A", status: "Sigue: T3 · E1").detail, "Sigue: T3 · E1")
        XCTAssertEqual(WidgetSnapshot.Item(kind: "movie", metaID: "a", title: "A").detail, "")
    }

    func testLinksRoundTripAndRejectForeignURLs() throws {
        let play = try XCTUnwrap(WidgetLink.play(kind: "series", id: "tt0386676", video: "tt0386676:2:6"))
        XCTAssertEqual(WidgetLink.parse(play), .play(kind: "series", id: "tt0386676", video: "tt0386676:2:6"))
        XCTAssertEqual(WidgetLink.parse(WidgetLink.remoteURL), .remote, "el botón del Centro de control")
        let title = try XCTUnwrap(WidgetLink.title(kind: "movie", id: "tt1160419"))
        XCTAssertEqual(WidgetLink.parse(title), .title(kind: "movie", id: "tt1160419"))
        XCTAssertNil(WidgetLink.parse(try XCTUnwrap(URL(string: "orbital-ios://pair?u=https%3A%2F%2Ftv&t=x"))))
        XCTAssertNil(WidgetLink.parse(try XCTUnwrap(URL(string: "orbital-ios://play?kind=movie"))), "sin id no se abre nada")
        XCTAssertNil(WidgetLink.parse(try XCTUnwrap(URL(string: "https://example.com/play?kind=movie&id=x"))))
    }

    func testItemLinkPlaysWhenItHasAnEpisodeAndOpensTheTitleOtherwise() {
        XCTAssertEqual(WidgetSnapshot.Item(kind: "series", metaID: "tt1", videoID: "tt1:1:1", title: "A").link.flatMap(WidgetLink.parse), .play(kind: "series", id: "tt1", video: "tt1:1:1"))
        XCTAssertEqual(WidgetSnapshot.Item(kind: "series", metaID: "tt1", title: "A").link.flatMap(WidgetLink.parse), .title(kind: "series", id: "tt1"))
    }

    func testImageFileNamesAreSafeForTheFileSystem() {
        XCTAssertEqual(WidgetSnapshot.imageFileName(for: "tt0386676"), "tt0386676.jpg")
        XCTAssertEqual(WidgetSnapshot.imageFileName(for: "kitsu:123/4"), "kitsu_123_4.jpg")
    }

    func testTintMatchesTheScreensBackdropRecipe() {
        // 45 % del color del arte + 55 % de ink-1000 (#070708), como `ArtTint`.
        XCTAssertEqual(WidgetSnapshot.tintHex(r: 1, g: 1, b: 1), "#777777")
        XCTAssertEqual(WidgetSnapshot.tintHex(r: 0, g: 0, b: 0), "#040404")
    }

    func testSpanishLabels() {
        XCTAssertEqual(WidgetLabels.spanish.episode(2, 6), "T2 · E6")
        XCTAssertEqual(WidgetLabels.spanish.episode(nil, 6), "E6")
        XCTAssertEqual(WidgetLabels.spanish.timeLeft(100), "quedan 1 h 40 min")
        XCTAssertEqual(WidgetLabels.spanish.timeLeft(20), "quedan 20 min")
    }

    func testWidgetImagesStaySmall() {
        XCTAssertLessThanOrEqual(DesignTokens.Widget.maxImagePixels, 300)
        XCTAssertGreaterThan(DesignTokens.Widget.fallbackRefreshHours, 0)
    }
}
