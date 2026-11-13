import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Del cartel a la carta (13 nov 2026): al pasar a «Una por una» el mazo empieza por el cartel elegido en «Tres que caben»
/// y lo demás conserva su orden del día (no se vuelve a barajar).
@MainActor
final class MatchDeckLeadTests: XCTestCase {
    private func item(_ id: String) -> Suggestion {
        Suggestion(kind: "movie", imdb: id, title: id, year: 2015, runtime: 100, poster: "", wide: "", reason: .recommended)
    }

    func testElElegidoVaArribaSinRebarajar() async throws {
        let rig = try ServicesRig()
        let deck = MatchDeckModel(rig.services, pool: (1...6).map { item("tt\($0)") }, watched: { [] })
        await deck.load()
        let day = deck.cards.map(\.imdb)
        let chosen = day[3]
        deck.lead = chosen
        XCTAssertEqual(deck.cards.first?.imdb, chosen, "el cartel elegido es la carta de arriba")
        XCTAssertEqual(deck.cards.dropFirst().map(\.imdb), day.filter { $0 != chosen }, "lo demás, en su orden del día")
        deck.lead = "tt-no-esta"
        XCTAssertEqual(deck.cards.map(\.imdb), day, "si no está en el mazo, el orden del día")
        XCTAssertEqual(MatchDeckModel.leading(deck.cards, nil).map(\.imdb), day)
    }
}
