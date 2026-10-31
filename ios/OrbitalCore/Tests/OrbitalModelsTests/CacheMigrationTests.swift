import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Abrir la versión nueva con el historial de Trakt guardado por la anterior (en UserDefaults): se ve igual al abrir, pasa a
/// un archivo de Caches y deja de ocupar UserDefaults (auditoría, 31 oct 2026, B3).
@MainActor
final class CacheMigrationTests: XCTestCase {
    func testElHistorialDeLaVersionAnteriorNoSePierde() async throws {
        // La versión anterior: sin carpeta de cachés, el historial queda en `kv` (UserDefaults).
        let old = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let clock = old.clock
        old.http.prefix["https://api.trakt.tv/sync/history"] = [["type": "movie", "watched_at": "2025-10-08T20:00:00.000Z",
                                                                 "movie": ["title": "Dune", "runtime": 155, "genres": ["science-fiction"], "ids": ["imdb": "tt1160419"]]]]
        await WatchingModel(old.services, clock: { clock.now }).load()
        XCTAssertNotNil(old.kv.data(WatchingModel.cacheKey), "la versión anterior lo dejaba en UserDefaults")

        // La versión nueva, con la misma UserDefaults y una carpeta en Caches.
        let caches = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-mig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        func services(_ kv: KeyValueStore) -> Services {
            Services(http: old.http, secrets: old.secrets, kv: kv, pending: old.pending, downloadTransport: old.transport, downloadsRoot: old.root,
                     freeSpace: { 50_000_000_000 }, cacheRoot: caches, clock: { clock.now })
        }
        let updated = services(old.kv)
        let model = WatchingModel(updated, clock: { clock.now })
        XCTAssertEqual(model.plays.map(\.imdb), ["tt1160419"], "al abrir se ve lo de antes, sin esperar a Trakt")
        XCTAssertTrue(model.loaded)
        await updated.caches.flush()
        XCTAssertNil(old.kv.data(WatchingModel.cacheKey), "ya no ocupa UserDefaults")

        // Otra apertura (aunque UserDefaults ya no lo tenga): sale del archivo.
        let reopened = WatchingModel(services(InMemoryKeyValueStore()), clock: { clock.now })
        XCTAssertEqual(reopened.plays.map(\.imdb), ["tt1160419"])
    }
}
