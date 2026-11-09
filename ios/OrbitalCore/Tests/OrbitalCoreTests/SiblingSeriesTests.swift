import XCTest
@testable import OrbitalCore

/// Fernando, 8 nov: «Star Wars: Clone Wars» (2003) bajaba los episodios de «Star Wars: The Clone Wars» (2008) que Comet le daba.
final class SiblingSeriesTests: XCTestCase {
    let clone2003 = ["Star Wars: Clone Wars"]

    func testTheSeriesWithAnExtraArticleIsAnother() {
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "📄 Star.Wars.The.Clone.Wars.S01E01.Ambush.1080p.HEVC.x265-MeGusta.mkv"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "Star.Wars.The.Clone.Wars.S01e02.Ita.Eng.1080p.h265.10bit.SubS-Me7alh.mkv"))
    }

    func testTheSameSeriesIsNotFlagged() {
        XCTAssertFalse(Streams.namesAnotherSeries(clone2003, "Star.Wars.Clone.Wars.2003.S01E01.1080p.mkv"), "con su año, es esta")
        XCTAssertFalse(Streams.namesAnotherSeries(clone2003, "Star Wars Clone Wars (2003) 1080p - Episode 1.mkv"), "sin S01E01 no se decide")
        XCTAssertFalse(Streams.namesAnotherSeries(["The Office"], "The.Office.US.S02E05.1080p.mkv"), "una palabra que no es artículo no cuenta")
        XCTAssertFalse(Streams.namesAnotherSeries(["The Office"], "Office.S02E05.720p.mkv"), "sin el artículo, la misma")
        XCTAssertFalse(Streams.namesAnotherSeries(["Star Wars: The Clone Wars"], "Star.Wars.The.Clone.Wars.S01E01.mkv"))
    }
}
