import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La persona (B2): la trae el modelo, no la vista; si TMDB no contesta, se dice.
@MainActor
final class PersonModelTests: XCTestCase {
    let tmdb = "https://api.themoviedb.org/3"

    func testTraeALaPersonaUnaSolaVez() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        rig.http.prefix["\(tmdb)/person/31?"] = ["id": 31, "name": "Tom Hanks", "biography": "Actor.", "place_of_birth": "Concord",
                                                   "combined_credits": ["cast": [["id": 13, "media_type": "movie", "title": "Forrest Gump",
                                                                                  "release_date": "1994-07-06", "popularity": 50]]]]
        let model = PersonModel(rig.services, id: 31)
        XCTAssertTrue(model.isLoading)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.person?.name, "Tom Hanks")
        let asked = rig.http.calls.count
        await model.load()
        XCTAssertEqual(rig.http.calls.count, asked, "ya la tiene: no vuelve a pedir")
    }

    func testSinRespuestaDeTMDBSeDice() async throws {
        let rig = try ServicesRig(tmdbKey: "K")   // nada para /person: la petición falla
        let model = PersonModel(rig.services, id: 31)
        await model.load()
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.person)
    }
}
