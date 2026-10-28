import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Favoritos de Trakt en la ficha (el corazón: al instante y de vuelta si Trakt no lo acepta) y su fila en Inicio.
@MainActor
final class FavoritesModelTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func linkedRig() throws -> ServicesRig {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json["\(api)/sync/favorites/movies?extended=full"] = [
            ["listed_at": "2026-10-01T00:00:00.000Z", "type": "movie", "movie": ["title": "Interstellar", "ids": ["imdb": "tt0816692"]]]]
        rig.http.json["\(api)/sync/favorites/shows?extended=full"] = []
        return rig
    }

    func testTheHeartReadsTrakt() async throws {
        let rig = try linkedRig()
        let favorite = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        XCTAssertTrue(favorite.canFavorite, "con Trakt conectado se sabe sin esperar a la red")
        await favorite.refreshState()
        XCTAssertTrue(favorite.isFavorite)
        XCTAssertFalse(favorite.isSaved, "un favorito no cuenta como «Guardada»")
        let other = TitleModel(rig.services, kind: "movie", metaID: "tt1160419")
        await other.refreshState()
        XCTAssertFalse(other.isFavorite)
    }

    func testWithoutTraktThereIsNoHeart() throws {
        let rig = try ServicesRig()
        XCTAssertFalse(TitleModel(rig.services, kind: "movie", metaID: "tt0816692").canFavorite)
    }

    func testTogglingSendsToTraktAndAFailureGoesBack() async throws {
        let rig = try linkedRig()
        rig.http.json["\(api)/sync/favorites/remove"] = [:]
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        await title.refreshState()
        let removed = await title.toggleFavorite()
        XCTAssertTrue(removed)
        XCTAssertFalse(title.isFavorite)
        XCTAssertEqual(rig.http.bodies("\(api)/sync/favorites/remove").count, 1)
        // Ya hay 100: Trakt responde 420, el corazón regresa vacío y la ficha dice qué hacer.
        rig.http.json["\(api)/sync/favorites"] = [:]
        rig.http.statuses["\(api)/sync/favorites"] = 420
        let added = await title.toggleFavorite()
        XCTAssertFalse(added)
        XCTAssertFalse(title.isFavorite)
        XCTAssertEqual(title.message, Trakt.favoritesFullMessage)
        // Trakt caído o sin red: no se pierde. Se queda guardado en el iPhone (el corazón lleno) y sale en cuanto se pueda.
        rig.http.statuses["\(api)/sync/favorites"] = 500
        let queued = await title.toggleFavorite()
        XCTAssertTrue(queued)
        XCTAssertTrue(title.isFavorite)
        XCTAssertEqual(rig.services.traktOutbox.pending(target: TraktOutbox.favorites, imdb: "tt0816692"), true)
        XCTAssertTrue(title.message?.hasPrefix("Guardado en el iPhone") == true)
        // Al volver Trakt, la cola lo manda.
        rig.http.statuses["\(api)/sync/favorites"] = nil
        _ = await rig.services.traktOutbox.flush(rig.services.trakt)
        XCTAssertNil(rig.services.traktOutbox.pending(target: TraktOutbox.favorites, imdb: "tt0816692"))
    }

    func testHomeRowChangesAtOnce() async throws {
        let rig = try linkedRig()
        let home = HomeModel(rig.services)
        await home.refresh()
        let dune = Suggestion(kind: "movie", imdb: "tt1160419", title: "Dune", poster: "p", wide: "", reason: .inList(ForYou.favoritesName))
        FavoriteChange.post(dune, add: true)   // el corazón de la ficha
        XCTAssertEqual(home.favorites.map(\.imdb), ["tt1160419", "tt0816692"], "entra al principio sin esperar la recarga")
        FavoriteChange.post(home.favorites[1], add: false)   // «Quitar de favoritos» en Inicio
        XCTAssertEqual(home.favorites.map(\.imdb), ["tt1160419"])
        FavoriteChange.post(Suggestion(kind: "movie", imdb: "tt0816692", title: "", poster: "", wide: "", reason: .inList("")), add: true)   // «Deshacer»
        XCTAssertEqual(home.favorites.map(\.imdb), ["tt1160419", "tt0816692"], "vuelve a su lugar")
        XCTAssertEqual(home.favorites[1].title, "Interstellar", "con lo que ya tenía")
    }

    func testHomeShowsFavoritesOnlyWithTrakt() async throws {
        let rig = try linkedRig()
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(home.favorites.map(\.imdb), ["tt0816692"])
        XCTAssertEqual(HomeModel(rig.services).favorites.map(\.imdb), ["tt0816692"], "la copia guardada se ve al abrir")
        let without = try ServicesRig()
        without.http.json[stremioGet] = ["result": []]
        let empty = HomeModel(without.services)
        await empty.refresh()
        XCTAssertTrue(empty.favorites.isEmpty, "sin Trakt la fila no se pinta")
    }
}
