import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Favoritos vive en Para ti › Tuyo (ya no en Inicio): quitar uno lo saca de su lista al momento y «Deshacer» lo regresa a
/// su lugar, como hacía la fila de Inicio.
@MainActor
final class ParaTiFavoritesTests: XCTestCase {
    func suggestion(_ id: String) -> Suggestion { Suggestion(kind: "movie", imdb: id, title: id, poster: "", wide: "", reason: .inList(ForYou.favoritesName)) }

    func testQuitarDeFavoritosLoSacaYDeshacerLoRegresaASuLugar() throws {
        let rig = try ServicesRig()
        let model = ParaTiModel(rig.services)
        let (a, b, c) = (suggestion("tt1"), suggestion("tt2"), suggestion("tt3"))
        model.seedRailForTesting(listID: ForYou.favoritesList, splits: false, [a, b, c])
        let key = model.key(listID: ForYou.favoritesList, splits: false)

        FavoriteChange.post(b, add: false)
        XCTAssertEqual(model.railItems[key]?.map(\.imdb), ["tt1", "tt3"], "sale al momento")

        FavoriteChange.post(b, add: true)
        XCTAssertEqual(model.railItems[key]?.map(\.imdb), ["tt1", "tt2", "tt3"], "«Deshacer» la regresa a su lugar")

        let d = suggestion("tt4")
        FavoriteChange.post(d, add: true)
        XCTAssertEqual(model.railItems[key]?.first?.imdb, "tt4", "un corazón nuevo entra al principio")
    }
}
