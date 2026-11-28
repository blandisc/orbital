import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Fallas de Inicio que encontró la revisión del 27 nov 2026.
@MainActor
final class HomeReviewTests: XCTestCase {
    /// Quitada de «Seguir viendo» y luego la vuelves a ver: regresa a la fila (antes, hasta cerrar la app).
    func testDismissedContinueComesBackWhenWatchedAgain() async throws {
        let rig = try ServicesRig(signedIn: false)
        let lib = rig.services.library
        for (i, id) in ["tt1", "tt2"].enumerated() {
            lib.update(id, make: { LibraryEntry(metaID: id, kind: "movie", name: id) }) {
                $0.videoID = id; $0.position = 600; $0.duration = 6000; $0.updatedAt = Double(100 - i)
            }
        }
        let home = HomeModel(rig.services)
        await home.refresh()
        let second = try XCTUnwrap(home.continueWatching.first { $0.metaID == "tt2" })
        await home.dismiss(second)
        await home.refresh()
        XCTAssertEqual(home.continueWatching.map(\.metaID), ["tt1"])
        lib.update("tt2", make: { LibraryEntry(metaID: "tt2", kind: "movie", name: "tt2") }) {
            $0.hiddenAt = nil; $0.position = 900; $0.updatedAt = 200
        }
        await home.refresh()
        XCTAssertEqual(home.continueWatching.map(\.metaID), ["tt2", "tt1"], "la volviste a ver: regresa")
    }

    /// Quitada de «Mi lista» en Inicio y luego guardada otra vez desde su ficha: regresa a la fila.
    func testRemovedFromMyListComesBackWhenSavedAgain() async throws {
        let rig = try ServicesRig(signedIn: false)
        let lib = rig.services.library
        for (i, id) in ["tt1", "tt2"].enumerated() {
            lib.update(id, make: { LibraryEntry(metaID: id, kind: "movie", name: id) }) { $0.inList = true; $0.listedAt = Double(10 - i) }
        }
        let home = HomeModel(rig.services)
        await home.refresh()
        home.setShown("tt2", shown: false)
        lib.update("tt2", make: { LibraryEntry(metaID: "tt2", kind: "movie", name: "tt2") }) { $0.inList = false }
        await home.refresh()
        XCTAssertEqual(home.traktPending.map(\.imdb), ["tt1"])
        lib.update("tt2", make: { LibraryEntry(metaID: "tt2", kind: "movie", name: "tt2") }) { $0.inList = true; $0.listedAt = 20 }
        await home.refresh()
        XCTAssertEqual(Set(home.traktPending.map(\.imdb)), ["tt1", "tt2"], "la guardaste otra vez: regresa")
    }

    /// Desconectar tu Orbital con un juego abierto: la barra del juego se va (antes se quedaba para siempre).
    func testTurningOffOrbitalClearsTheGameBar() async throws {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example"; $0.orbitalEnabled = true }
        rig.secrets.set(SecretKey.orbitalToken, "secreto")
        rig.http.json["https://tv.example/api/companion/now"] = .object(["playing": .null,
            "game": .object(["id": .string("g1"), "title": .string("Hades"), "system": .string("steam")])])
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.setActive(true)
        for _ in 0..<200 where model.game == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.game?.title, "Hades")
        rig.services.turnOffOrbital()
        for _ in 0..<200 where model.game != nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNil(model.game, "sin tu Orbital no queda la barra del juego")
        model.setActive(false)
    }
}
