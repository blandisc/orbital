import XCTest
@testable import OrbitalModels

/// Un solo nombre por título (revisión 2 del 11 nov 2026): «Dune / Duna», «The Office / La Oficina» e «Interstellar /
/// Interestelar» convivían en la misma pantalla. La regla es la de la TV (`tests/test_title_names.py`).
@MainActor
final class TitleNamesTests: XCTestCase {
    private let spanish: [String: String] = ["tt1160419": "Duna", "tt0386676": "La Oficina", "tt0816692": "Interestelar"]

    private func book(language: String? = "es-MX", known: [String: String] = [:], spanish: [String: String]? = nil) -> TitleNames {
        let table = spanish ?? self.spanish
        return TitleNames(language: { language }, lookup: { _, imdb in table[imdb] }, known: { known }, settle: .milliseconds(1))
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(30)) }

    func testRuleIsKnownNameOrWhatCame() {
        XCTAssertEqual(DisplayTitle.resolve(raw: "Dune", known: "Duna"), "Duna")
        XCTAssertEqual(DisplayTitle.resolve(raw: " The Office ", known: nil), "The Office")
        XCTAssertEqual(DisplayTitle.resolve(raw: "Interstellar", known: "  "), "Interstellar", "lo vacío no cuenta: queda el que llegó")
    }

    func testEpisodeIDsAndKindsMapToTheTitle() {
        XCTAssertEqual(DisplayTitle.titleID("tt0386676:2:5"), "tt0386676")
        XCTAssertNil(DisplayTitle.titleID("kitsu:1"))
        XCTAssertNil(DisplayTitle.titleID(nil))
        XCTAssertEqual(DisplayTitle.kind("show"), "series")
        XCTAssertEqual(DisplayTitle.kind("episode"), "series")
        XCTAssertEqual(DisplayTitle.kind("movie"), "movie")
        XCTAssertNil(DisplayTitle.kind("game"))
    }

    func testTheSameTitleReadsTheSameEverywhere() async {
        let names = book()
        // Primer pintado: lo que llegó (nunca hace esperar a una lista); en el siguiente, el nombre en tu idioma.
        XCTAssertEqual(names.name("Dune", id: "tt1160419", kind: "movie"), "Dune")
        XCTAssertEqual(names.name("The Office", id: "tt0386676:2:5", kind: "show"), "The Office")
        XCTAssertEqual(names.name("Interstellar", id: "tt0816692", kind: "movie"), "Interstellar")
        await settle()
        XCTAssertEqual(names.name("Dune", id: "tt1160419", kind: "movie"), "Duna")
        XCTAssertEqual(names.name("Duna", id: "tt1160419"), "Duna", "venga como venga (la ficha o una fila), un solo nombre")
        XCTAssertEqual(names.name("The Office", id: "tt0386676", kind: "series"), "La Oficina")
        XCTAssertEqual(names.name("The Office", id: "tt0386676:1:1"), "La Oficina", "el control y el reproductor mandan el episodio")
        XCTAssertEqual(names.name("Interstellar", id: "tt0816692"), "Interestelar")
    }

    func testWhatIsKnownComesTranslatedFromTheFirstPaint() async {
        let names = book(known: ["tt0386676": "La Oficina"])
        await settle()
        XCTAssertEqual(names.name("The Office", id: "tt0386676"), "La Oficina")
    }

    func testEnglishOrNoKeyLeavesItAsItCame() async {
        let names = book(language: nil, known: ["tt1160419": "Duna"])
        _ = names.name("Dune", id: "tt1160419", kind: "movie")
        await settle()
        XCTAssertEqual(names.name("Dune", id: "tt1160419", kind: "movie"), "Dune")
        names.remember(id: "tt1160419", name: "Duna")
        XCTAssertEqual(names.name("Dune", id: "tt1160419"), "Dune")
    }

    func testWithoutAnIMDbIDOrATranslationItStaysAsItCame() async {
        let names = book(spanish: [:])
        XCTAssertEqual(names.name("Bluey", id: "kitsu:9", kind: "series"), "Bluey")
        _ = names.name("Severance", id: "tt11280740", kind: "series")
        await settle()
        XCTAssertEqual(names.name("Severance", id: "tt11280740", kind: "series"), "Severance")
    }

    func testTheFichaTeachesTheRest() {
        let names = book(spanish: [:])
        names.remember(id: "tt1160419", name: "Duna")
        XCTAssertEqual(names.name("Dune", id: "tt1160419:0:0"), "Duna")
        XCTAssertEqual(names.known("tt1160419"), "Duna")
    }

    func testChangingLanguageForgetsTheOldNames() {
        var language: String? = "es-MX"
        let names = TitleNames(language: { language }, lookup: { _, _ in nil })
        names.remember(id: "tt1160419", name: "Duna")
        XCTAssertEqual(names.name("Dune", id: "tt1160419"), "Duna")
        language = "pt-BR"
        XCTAssertEqual(names.name("Dune", id: "tt1160419"), "Dune")
    }
}
