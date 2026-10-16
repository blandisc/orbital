import XCTest
@testable import OrbitalCore

/// El vocabulario que la TV y el iPhone comparten: `runtime_text` y `time_left` de Python (valores de `scripts/ios_golden.py`)
/// y las reglas de la línea de datos, el saludo y las cuatro cifras de la ficha.
final class VocabularyTests: XCTestCase {
    private func number(_ json: JSON?) -> Double {
        switch json { case .int(let i)?: return Double(i); case .double(let d)?: return d; default: return 0 }
    }

    func testRuntimeTextMatchesPython() throws {
        let golden = try Fixtures.json("ios/vocabulary.json")
        for c in try XCTUnwrap(golden["runtime"]?.array) {
            let minutes = c["minutes"]?.intValue
            let want = c["text"]?.string
            XCTAssertEqual(Vocabulary.runtimeText(minutes: minutes), want, "minutos \(String(describing: minutes))")
        }
    }

    func testTimeLeftMatchesPython() throws {
        let golden = try Fixtures.json("ios/vocabulary.json")
        for c in try XCTUnwrap(golden["time_left"]?.array) {
            let seconds = number(c["seconds"])
            XCTAssertEqual(Vocabulary.timeLeft(seconds: seconds), c["text"]?.string, "segundos \(seconds)")
        }
    }

    func testFactVariantsDropYearThenRuntime() {
        XCTAssertEqual(Vocabulary.factVariants(kind: "Película", year: 2026, runtime: 105, next: nil),
                       ["Película · 2026 · 1 h 45 min", "Película · 1 h 45 min", "Película"])
        XCTAssertEqual(Vocabulary.factVariants(kind: "Película", year: 2026, runtime: nil, next: nil), ["Película · 2026", "Película"])
        XCTAssertEqual(Vocabulary.factVariants(kind: "Serie", year: nil, runtime: nil, next: nil), ["Serie"])
        XCTAssertEqual(Vocabulary.factVariants(kind: "Serie", year: 2020, runtime: 50, next: "T2 · E5"), ["Serie · T2 · E5", "Serie"])
    }

    func testFactLineSkipsEmptyParts() {
        XCTAssertEqual(Vocabulary.factLine(["T2 · E5", nil, "", "quedan 20 min"]), "T2 · E5 · quedan 20 min")
        XCTAssertEqual(Vocabulary.factLine([nil, ""]), "")
    }

    func testTitleFactsOrderAndLimit() {
        XCTAssertEqual(Vocabulary.titleFacts(year: "2021", genres: ["Ciencia ficción", "Aventura", "Drama"], runtime: "155 min", rating: "8.0"),
                       ["2021", "Ciencia ficción, Aventura", "155 min", "★ 8.0"])
        XCTAssertEqual(Vocabulary.titleFacts(year: "", genres: [], runtime: "", rating: ""), [])
        XCTAssertEqual(Vocabulary.titleFacts(year: "2005–2013", genres: [], runtime: "", rating: "8.9"), ["2005–2013", "★ 8.9"])
    }

    func testGreetingBoundariesMatchTheConsole() {
        XCTAssertEqual(Vocabulary.greeting(hour: 4), .evening)
        XCTAssertEqual(Vocabulary.greeting(hour: 5), .morning)
        XCTAssertEqual(Vocabulary.greeting(hour: 11), .morning)
        XCTAssertEqual(Vocabulary.greeting(hour: 12), .afternoon)
        XCTAssertEqual(Vocabulary.greeting(hour: 19), .afternoon)
        XCTAssertEqual(Vocabulary.greeting(hour: 20), .evening)
        XCTAssertEqual(Vocabulary.greeting(hour: 0), .evening)
    }

    func testLogoURLOnlyForIMDb() {
        XCTAssertEqual(Artwork.logoURL(metaID: "tt0386676"), "https://images.metahub.space/logo/medium/tt0386676/img")
        XCTAssertNil(Artwork.logoURL(metaID: "kitsu:1"))
    }
}
