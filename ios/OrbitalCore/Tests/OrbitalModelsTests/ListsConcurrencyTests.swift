import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Para ti › Listas: tus listas de Trakt, los catálogos de tus complementos y las plataformas de TMDB se piden a la vez,
/// no en fila (el destacado de Para ti esperaba la suma de las tres).
@MainActor
final class ListsConcurrencyTests: XCTestCase {
    func testListsAskTraktAddonsAndTMDBAtTheSameTime() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "id", tmdbKey: "key")
        // Primera vuelta: qué URLs pide (sin demora).
        _ = await rig.services.forYou.lists()
        let asked = Set(rig.http.calls.filter { $0.contains("api.trakt.tv/users/me/lists") || $0.contains("manifest.json") || $0.contains("watch/providers") })
        XCTAssertFalse(asked.isEmpty)
        // Segunda, sin caché y con 400 ms de demora en cada una: en fila serían ≥ 1.2 s; a la vez, poco más de 0.4 s.
        let fresh = try ServicesRig(traktLinked: true, traktClientID: "id", tmdbKey: "key")
        fresh.http.delays = Dictionary(uniqueKeysWithValues: asked.map { ($0, 400) })
        let start = Date()
        _ = await fresh.services.forYou.lists()
        let elapsed = Date().timeIntervalSince(start)
        print("LISTS-ELAPSED \(elapsed) s para \(asked.count) consultas de 0.4 s")
        XCTAssertLessThan(elapsed, 0.75, "se piden a la vez (en fila eran ≥ 1.2 s)")
    }
}
