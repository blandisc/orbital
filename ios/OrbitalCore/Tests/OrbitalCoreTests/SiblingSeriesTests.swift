import XCTest
@testable import OrbitalCore

/// Fernando, 8 nov: «Star Wars: Clone Wars» (2003) bajaba los episodios de «Star Wars: The Clone Wars» (2008) que Comet le daba.
final class SiblingSeriesTests: XCTestCase {
    let clone2003 = ["Star Wars: Clone Wars"]

    func testTheSeriesWithAnExtraArticleIsAnother() {
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "📄 Star.Wars.The.Clone.Wars.S01E01.Ambush.1080p.HEVC.x265-MeGusta.mkv"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "Star.Wars.The.Clone.Wars.S01-S07.1080p.BluRay"), "un paquete sin S01E01")
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "Star Wars The Clone Wars Complete Series 1080p"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "Star Wars The Clone Wars (2008) Season 1"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "Star.Wars.The.Clone.Wars.S01e02.Ita.Eng.1080p.h265.10bit.SubS-Me7alh.mkv"))
    }

    func testTheSameSeriesIsNotFlagged() {
        XCTAssertFalse(Streams.namesAnotherSeries(clone2003, "Star.Wars.Clone.Wars.2003.S01E01.1080p.mkv"), "con su año, es esta")
        XCTAssertFalse(Streams.namesAnotherSeries(clone2003, "Star Wars Clone Wars (2003) 1080p - Episode 1.mkv"), "sin S01E01 no se decide")
        XCTAssertFalse(Streams.namesAnotherSeries(["The Office"], "The.Office.US.S02E05.1080p.mkv"), "una palabra que no es artículo no cuenta")
        XCTAssertFalse(Streams.namesAnotherSeries(["The Office"], "Office.S02E05.720p.mkv"), "sin el artículo, la misma")
        XCTAssertFalse(Streams.namesAnotherSeries(["Star Wars: The Clone Wars"], "Star.Wars.The.Clone.Wars.S01E01.mkv"))
    }

    func testTheSeriesNamedByTheEndOfTheTitleIsAnother() {
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "The.Clone.Wars.S01E04.1080p.WEB.mkv"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "The Clone Wars Season 1 1080p"))
        XCTAssertTrue(Streams.namesAnotherSeries(clone2003, "📄 StarWars.The.Clone.Wars.S01e01.Ita.Eng.720p.h264.byMetalh.mkv"), "lo que abrió el 9 nov")
        XCTAssertFalse(Streams.namesAnotherSeries(clone2003, "Clone.Wars.S01E04.mkv"), "sin artículo, no se decide")
        XCTAssertFalse(Streams.namesAnotherSeries(["Star Wars: The Mandalorian"], "The.Mandalorian.S01E01.mkv"))
    }

    func testAnotherYearIsAnotherSeries() {
        let years = Streams.seriesYears("2003–2005")
        XCTAssertEqual(years, 2003...2005)
        XCTAssertTrue(Streams.otherYears("Star Wars Clone Wars (2008) S01E04 1080p", years: years))
        XCTAssertFalse(Streams.otherYears("Star Wars Clone Wars (2003) 1080p - Episode 4.mkv", years: years))
        XCTAssertTrue(Streams.otherYears("📄 Star.Wars-Clone.Wars.S1E01.2008-2009.1080p.NF.WebDL.AVC.DD.5.1-DTOne.mkv", years: years), "lo que abrió el 9 nov")
        XCTAssertFalse(Streams.otherYears("Star Wars Saga (1977-2005)", years: years), "dos años: colección, no se decide")
        XCTAssertFalse(Streams.otherYears("Clone.Wars.S01E04.mkv", years: years))
        XCTAssertEqual(Streams.seriesYears("2019–")?.lowerBound, 2019)
        XCTAssertNil(Streams.seriesYears(nil))
    }
}
