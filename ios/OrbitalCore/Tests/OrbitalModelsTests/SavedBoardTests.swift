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
        let board = SavedBoard.build(watchlist: list, watched: watched, hidden: ["tt8", "tt9"], now: day(40))
        XCTAssertEqual(board.inList.map(\.imdb), ["tt1"], "vista y otra vez en Mi lista: cuenta en Mi lista")
        XCTAssertEqual(board.watching.map(\.imdb), ["tt7", "tt5"], "a medias o al día con lo que sigue saliendo")
        XCTAssertEqual(board.watched.map(\.imdb), ["tt3", "tt2", "tt6"])
        XCTAssertEqual(Set(board.dropped.map(\.imdb)), ["tt8", "tt9"])
        XCTAssertEqual(board.watched.first?.title, "Flow")
    }

    /// «¿La dejaste?» (Fernando, 9 nov 2026: «Completa todos los pendientes»): seis meses sin ver una serie a medias y deja de
    /// contar en Viendo.
    func testSeisMesesSinVerlaYaNoCuentaEnViendo() {
        let day = { (d: Double) in Date(timeIntervalSince1970: d * 86400) }
        let watched = TraktWatchedState(shows: ["tt1": 0.5, "tt2": 0.3, "tt3": 1],
                                        info: ["tt1": .init(kind: "series", title: "Lost", lastWatchedAt: day(10)),
                                               "tt2": .init(kind: "series", title: "Dark", lastWatchedAt: day(300)),
                                               "tt3": .init(kind: "series", title: "Fleabag", lastWatchedAt: day(5))])
        let board = SavedBoard.build(watchlist: [], watched: watched, hidden: [], now: day(310))
        XCTAssertEqual(board.watching.map(\.imdb), ["tt2"])
        XCTAssertEqual(board.stale.map(\.imdb), ["tt1"], "la que no ves hace más de seis meses")
        XCTAssertEqual(board.watched.map(\.imdb), ["tt3"], "una terminada no se pregunta")
    }

    func testMoverAOfreceSoloLoQueTieneSentido() {
        XCTAssertEqual(SavedModel.moves(kind: "movie", from: .inList), [.watched, .dropped])
        XCTAssertEqual(SavedModel.moves(kind: "movie", from: .watched), [.inList])
        XCTAssertEqual(SavedModel.moves(kind: "series", from: .watching), [.inList, .dropped])
        XCTAssertEqual(SavedModel.moves(kind: "series", from: .dropped), [.inList, .watching])
        XCTAssertEqual(SavedModel.moves(kind: "series", from: .inList), [.dropped])
    }

    /// «Si el estado cambia solo, te avisa»: lo que pasó a Vistas o regresó a Viendo; lo que tú mueves y lo nuevo, no.
    func testAvisaLoQueCambioSolo() {
        let watched = TraktWatchedState(movies: ["tt1"], shows: ["tt2": 0.8, "tt3": 1],
                                        info: ["tt1": .init(kind: "movie", title: "Dune"), "tt2": .init(kind: "series", title: "Dark"),
                                               "tt3": .init(kind: "series", title: "Fleabag")])
        let list = [Suggestion(art: "tt4", kind: "movie", title: "Anora", year: nil, reason: .inWatchlist)]
        let board = SavedBoard.build(watchlist: list, watched: watched, hidden: ["tt5"], hiddenNames: ["tt5": "Lost"])
        let changes = board.automaticChanges(since: ["tt1": .inList, "tt2": .watched, "tt3": .watched, "tt5": .watching, "tt4": .none])
        XCTAssertEqual(changes.map(\.title), ["Dune", "Dark"], "Dune a Vistas, Dark otra vez en Viendo")
        XCTAssertEqual(changes.map(\.to), [.watched, .watching])
    }
}
