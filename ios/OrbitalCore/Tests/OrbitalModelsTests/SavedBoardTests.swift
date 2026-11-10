import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// G2-A: Guardado por estado, con las mismas reglas que el botón de la ficha.
final class SavedBoardTests: XCTestCase {
    func testCadaTituloCaeEnUnSoloMontonConLoMasRecientePrimero() {
        let day = { (d: Double) in Date(timeIntervalSince1970: d * 86400) }
        let list = [Suggestion(art: "tt1", kind: "movie", title: "Dune", year: 2024, reason: .inWatchlist),
                    Suggestion(art: "tt9", kind: "series", title: "Dejada y en la lista", year: nil, reason: .inWatchlist)]
        let watched = TraktWatchedState(
            movies: ["tt2", "tt3", "tt1"],
            shows: ["tt5": 0.4, "tt6": 1, "tt7": 1, "tt8": 0.2],
            info: ["tt2": .init(kind: "movie", title: "Anora", lastWatchedAt: day(10)), "tt3": .init(kind: "movie", title: "Flow", lastWatchedAt: day(20)),
                   "tt5": .init(kind: "series", title: "The Office", lastWatchedAt: day(5)), "tt6": .init(kind: "series", title: "Dark", lastWatchedAt: day(1)),
                   "tt7": .init(kind: "series", title: "Severance", lastWatchedAt: day(30)), "tt8": .init(kind: "series", title: "Lost", lastWatchedAt: day(2))],
            airing: ["tt7"])
        let board = SavedBoard.build(watchlist: list, watched: watched, hidden: ["tt8", "tt9"])
        XCTAssertEqual(board.inList.map(\.imdb), ["tt1"], "vista y otra vez en Mi lista: cuenta en Mi lista")
        XCTAssertEqual(board.watching.map(\.imdb), ["tt7", "tt5"], "a medias o al día con lo que sigue saliendo")
        XCTAssertEqual(board.watched.map(\.imdb), ["tt3", "tt2", "tt6"])
        XCTAssertEqual(Set(board.dropped.map(\.imdb)), ["tt8", "tt9"])
        XCTAssertEqual(board.watched.first?.title, "Flow")
    }
}
