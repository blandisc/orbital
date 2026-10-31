import XCTest
@testable import OrbitalModels

/// La regla de años de Época: lo que queda elegido al tocar, arrastrar, tocar una década o moverla con VoiceOver.
final class YearRulerLogicTests: XCTestCase {
    let ruler = YearRulerLogic(first: 1920, last: 2026)

    func testTheFirstTouchPutsADecadeAroundTheFinger() {
        let (years, drag) = ruler.change(nil, drag: nil, at: 1985, nearLower: false, nearUpper: false)
        XCTAssertEqual(years, 1981...1990)
        XCTAssertEqual(drag, .move(offset: 4, length: 9))
        // y desde ahí se mueve entera
        XCTAssertEqual(ruler.change(years, drag: drag, at: 1995, nearLower: false, nearUpper: false).years, 1991...2000)
    }

    func testAtTheEdgesTheDecadeStaysInsideTheRuler() {
        XCTAssertEqual(ruler.change(nil, drag: nil, at: 2026, nearLower: false, nearUpper: false).years, 2017...2026, "años muy recientes")
        XCTAssertEqual(ruler.change(nil, drag: nil, at: 1920, nearLower: false, nearUpper: false).years, 1920...1929)
        let moved = ruler.change(2000...2009, drag: .move(offset: 5, length: 9), at: 2026, nearLower: false, nearUpper: false).years
        XCTAssertEqual(moved, 2017...2026, "arrastrar la ventana no la saca por la derecha")
    }

    func testAnEdgeIsDraggedAndNeverCrossesTheOther() {
        var (years, drag) = ruler.change(1990...1999, drag: nil, at: 1990, nearLower: true, nearUpper: false)
        XCTAssertEqual(drag, .lower)
        (years, drag) = ruler.change(years, drag: drag, at: 1975, nearLower: false, nearUpper: false)
        XCTAssertEqual(years, 1975...1999)
        XCTAssertEqual(ruler.change(years, drag: drag, at: 2010, nearLower: false, nearUpper: false).years, 1999...1999, "no cruza la otra orilla")
        XCTAssertEqual(ruler.change(1990...1999, drag: nil, at: 1999, nearLower: false, nearUpper: true).drag, .upper)
    }

    func testTouchingOutsidePullsTheNearestEdge() {
        let left = ruler.change(1990...1999, drag: nil, at: 1960, nearLower: false, nearUpper: false)
        XCTAssertEqual(left.drag, .lower); XCTAssertEqual(left.years, 1960...1999)
        let right = ruler.change(1990...1999, drag: nil, at: 2015, nearLower: false, nearUpper: false)
        XCTAssertEqual(right.drag, .upper); XCTAssertEqual(right.years, 1990...2015)
        let inside = ruler.change(1990...1999, drag: nil, at: 1994, nearLower: false, nearUpper: false)
        XCTAssertEqual(inside.drag, .move(offset: 4, length: 9)); XCTAssertEqual(inside.years, 1990...1999)
    }

    func testDecadesAndTheirToggle() {
        XCTAssertEqual(ruler.decades.first, 1920...1929)
        XCTAssertEqual(ruler.decades.last, 2020...2026, "la última, hasta donde llega la regla")
        XCTAssertEqual(ruler.toggle(1980...1989, in: nil), 1980...1989)
        XCTAssertNil(ruler.toggle(1980...1989, in: 1980...1989), "otra vez, la quita")
    }

    func testVoiceOverMovesOneYearAndStopsAtTheEdge() {
        XCTAssertEqual(ruler.step(nil, by: -1), 2016...2025, "sin nada elegido, desde los últimos diez")
        XCTAssertEqual(ruler.step(1990...1999, by: 1), 1991...2000)
        XCTAssertEqual(ruler.step(2017...2026, by: 1), 2017...2026, "en la orilla no se mueve")
    }

    func testPositionsAndYearsMatch() {
        XCTAssertEqual(ruler.fraction(of: 1920), 0)
        XCTAssertEqual(ruler.fraction(of: 2026), 1)
        XCTAssertEqual(ruler.year(atFraction: 0.5), 1973)
        XCTAssertEqual(ruler.year(atFraction: -3), 1920)
        XCTAssertEqual(ruler.year(atFraction: 9), 2026)
        XCTAssertEqual(YearRulerLogic(first: 2026, last: 2026).fraction(of: 2026), 0, "un solo año no divide entre cero")
    }
}
