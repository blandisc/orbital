import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «La dejé» (G1-A, Fernando, 9 nov 2026: «Completa todos los pendientes»): la serie también cuenta como dejada en trakt.tv
/// (`/users/hidden/dropped`), lo que dejaste allá cuenta aquí, y sin internet se queda hecho y espera a Trakt.
@MainActor
final class DroppedTraktTests: XCTestCase {
    let api = "https://api.trakt.tv"
    var watchedURL: String { "\(api)/sync/watched/shows?extended=noseasons" }
    var hiddenURL: String { "\(api)/users/hidden/progress_watched?type=show&limit=1000" }
    var droppedURL: String { "\(api)/users/hidden/dropped?type=show&limit=1000" }

    func row(_ imdb: String, _ title: String) -> JSON { ["type": "show", "show": ["title": .string(title), "ids": ["imdb": .string(imdb), "trakt": 2]]] }
    func sentIDs(_ rig: ServicesRig, _ path: String) -> [String] {
        rig.http.bodies("\(api)\(path)").compactMap { JSON.parse($0)?["shows"]?.array?.first?["ids"]?["imdb"]?.string }
    }

    func linkedRig() throws -> ServicesRig {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        for path in ["calendar", "progress_watched", "dropped"] {
            rig.http.json["\(api)/users/hidden/\(path)"] = ["added": ["shows": 1]]
            rig.http.json["\(api)/users/hidden/\(path)/remove"] = ["deleted": ["shows": 1]]
        }
        rig.http.json[watchedURL] = [["last_watched_at": "2026-11-01T00:00:00.000Z", "show": ["title": "Lost", "ids": ["imdb": "tt0000001", "trakt": 1]]]]
        rig.http.json[hiddenURL] = []
        rig.http.json[droppedURL] = []
        return rig
    }

    func testLaDejeTambienLaMarcaComoDejadaEnTrakt() async throws {
        let rig = try linkedRig()
        let model = FollowModel(rig.services)
        await model.loadSeries()
        let problem = await model.hide("tt0000001")
        XCTAssertNil(problem)
        XCTAssertEqual(sentIDs(rig, "/users/hidden/dropped"), ["tt0000001"], "trakt.tv la ve como dejada")
        XCTAssertEqual(sentIDs(rig, "/users/hidden/progress_watched"), ["tt0000001"])
        _ = await model.unhide("tt0000001", following: false)
        XCTAssertEqual(sentIDs(rig, "/users/hidden/dropped/remove"), ["tt0000001"], "«Viendo» otra vez: deja de contar como dejada")
        XCTAssertTrue(sentIDs(rig, "/users/hidden/calendar/remove").isEmpty, "sin la campana, como estaba")
    }

    func testLasQueDejasteEnTraktTvCuentanAqui() async throws {
        let rig = try linkedRig()
        rig.http.json[droppedURL] = [row("tt0000009", "Dexter"), row("tt0000001", "Lost")]
        rig.http.json[hiddenURL] = [row("tt0000001", "Lost")]
        let shows = try await rig.services.trakt!.hiddenShows()
        XCTAssertEqual(shows.map(\.imdb), ["tt0000001", "tt0000009"], "escondidas y dejadas, sin repetir")
    }

    func testSinInternetSeQuedaDejadaYLlegaDespues() async throws {
        let rig = try linkedRig()
        let model = FollowModel(rig.services)
        await model.loadSeries()
        rig.http.offline = true
        let problem = await model.hide("tt0000001")
        XCTAssertNil(problem, "no regresa ni da error")
        XCTAssertEqual(model.hidden, ["tt0000001"], "se queda dejada")
        XCTAssertEqual(rig.services.traktOutbox.pendingHidden, ["tt0000001": true], "espera a Trakt")

        rig.http.offline = false
        await model.loadSeries()
        XCTAssertEqual(model.hidden, ["tt0000001"], "Trakt aún no sabe, pero no la regresa")

        let sent = await rig.services.traktOutbox.flush(rig.services.trakt)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(sentIDs(rig, "/users/hidden/dropped"), ["tt0000001"], "al volver la conexión, llega")
        XCTAssertTrue(rig.services.traktOutbox.pendingHidden.isEmpty)
    }

    func testSinInternetMostrarOtraVezTambienEspera() async throws {
        let rig = try linkedRig()
        rig.http.json[hiddenURL] = [row("tt0000001", "Lost")]
        let model = FollowModel(rig.services)
        await model.loadSeries()
        XCTAssertEqual(model.hidden, ["tt0000001"])
        rig.http.offline = true
        let problem = await model.unhide("tt0000001", following: false)
        XCTAssertNil(problem)
        XCTAssertTrue(model.hidden.isEmpty)
        rig.http.offline = false
        await model.loadSeries()
        XCTAssertTrue(model.hidden.isEmpty, "Trakt aún la tiene escondida, pero lo tuyo manda")
    }
}
