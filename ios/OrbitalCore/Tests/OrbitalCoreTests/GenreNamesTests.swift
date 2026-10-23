import XCTest
@testable import OrbitalCore

/// Los géneros en español vengan de Cinemeta («Science Fiction») o de Trakt («science-fiction»): en Para ti salían en inglés.
final class GenreNamesTests: XCTestCase {
    func testTraktKeysAreTranslated() {
        XCTAssertEqual(Vocabulary.genres(["science-fiction", "comedy", "superhero", "mini-series"], language: "es"),
                       ["Ciencia ficción", "Comedia", "Superhéroes", "Miniserie"])
    }
    func testCinemetaNamesStillWork() {
        XCTAssertEqual(Vocabulary.genres(["Science Fiction", "Sci-Fi", "Action"], language: "es"), ["Ciencia ficción", "Ciencia ficción", "Acción"])
    }
    func testEnglishShowsNamesNotKeys() {
        XCTAssertEqual(Vocabulary.genres(["science-fiction", "Action"], language: "en"), ["Science Fiction", "Action"])
    }
}
