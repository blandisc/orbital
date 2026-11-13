import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// DE2 (Fernando, 13 nov 2026: «Construye DE1 y DE2 para ver cómo se ven»): «Decide por mí» con una sola puerta y dos
/// pestañas, «Tres que caben» y «Una por una»; las dos usan los filtros de «Afinar».
@MainActor
final class DecideDeckTests: XCTestCase {
    private func title(_ id: String, minutes: Int = 90, genres: [String] = ["Drama"], kind: String = "movie", year: Int = 2015) -> Suggestion {
        var s = Suggestion(kind: kind, imdb: id, title: id, year: year, runtime: minutes, poster: "", wide: "", reason: .recommended)
        s.genres = genres
        return s
    }

    /// Las dos pestañas, con los nombres de la TV.
    func testLasDosManerasSonLasDeLaTV() {
        XCTAssertEqual(DecideModel.Mode.allCases, [.trio, .deck])
    }

    /// Lo que pones en «Afinar» (género, época, tipo) filtra el mazo igual que los tres carteles.
    func testElMazoUsaLosFiltrosDeAfinar() async throws {
        let rig = try ServicesRig()
        let pool = [title("tt1", genres: ["Horror"]), title("tt2", genres: ["Comedy"]), title("tt3", genres: ["Horror"], kind: "series"),
                    title("tt4", genres: ["Horror"], year: 1995)]
        let model = DecideModel(rig.services, pool: pool)
        XCTAssertEqual(Set(model.deckPool().map(\.imdb)), ["tt1", "tt2", "tt3", "tt4"], "sin filtros, todo")
        model.genres = ["horror"]
        XCTAssertEqual(Set(model.deckPool().map(\.imdb)), ["tt1", "tt3", "tt4"], "el género de «Afinar»")
        XCTAssertEqual(model.deckPool().count, model.count(), "lo mismo que cuentan los tres carteles")
        model.kind = "movie"
        XCTAssertEqual(Set(model.deckPool().map(\.imdb)), ["tt1", "tt4"], "y el tipo")
        model.decades = [2010]
        XCTAssertEqual(model.deckPool().map(\.imdb), ["tt1"], "y la época")
        model.stop()
    }

    /// El tiempo y el ánimo son de «Tres que caben»: no le quitan cartas al mazo, y no lo vuelven a barajar.
    func testElTiempoYElAnimoNoTocanElMazo() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: [title("tt1", minutes: 25), title("tt2", minutes: 175, genres: ["Comedy"])])
        let key = model.deckKey
        await model.chooseTime(.short)
        model.mood = .intense
        XCTAssertEqual(model.deckPool().count, 2)
        XCTAssertEqual(model.deckKey, key, "cambiar el tiempo o el ánimo no rebaraja el mazo")
        model.genres = ["comedy"]
        XCTAssertNotEqual(model.deckKey, key, "cambiar «Afinar» sí")
        model.stop()
    }

    /// Lo que apartaste hoy («Hoy no») tampoco sale en el mazo.
    func testLoApartadoHoyNoSaleEnElMazo() async throws {
        let rig = try ServicesRig()
        let model = DecideModel(rig.services, pool: (1...4).map { title("tt\($0)") })
        await model.quick()
        let skipped = try XCTUnwrap(model.pick)
        await model.skipToday()
        XCTAssertFalse(model.deckPool().contains { $0.imdb == skipped.imdb })
        model.stop()
    }
}
