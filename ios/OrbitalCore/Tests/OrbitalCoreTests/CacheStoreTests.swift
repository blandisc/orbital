import XCTest
@testable import OrbitalCore

/// Las cachés en archivos de Caches (antes en UserDefaults): se leen al instante, se escriben fuera del hilo principal y lo
/// de la versión anterior se pasa al archivo sin perderse.
final class CacheStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-cache-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testWhatIsSavedIsReadAtOnceAndThenFromTheFile() async throws {
        let legacy = InMemoryKeyValueStore()
        let store = CacheStore(directory: folder, legacy: legacy)
        store.set("watching-history") { Data("uno".utf8) }
        XCTAssertEqual(store.data("watching-history"), Data("uno".utf8), "lo recién guardado se lee sin esperar al disco")
        await store.flush()
        XCTAssertNil(legacy.data("watching-history"), "no va a UserDefaults")
        let reopened = CacheStore(directory: folder, legacy: legacy)   // otra apertura de la app
        XCTAssertEqual(reopened.data("watching-history"), Data("uno".utf8))
    }

    func testTheLastOfSeveralSavesWins() async {
        let store = CacheStore(directory: folder, legacy: InMemoryKeyValueStore())
        for n in 1...20 { store.set("home-lists") { Data("\(n)".utf8) } }
        await store.flush()
        XCTAssertEqual(CacheStore(directory: folder, legacy: InMemoryKeyValueStore()).data("home-lists"), Data("20".utf8))
    }

    /// Abrir la versión nueva con el historial guardado en UserDefaults: se usa, se pasa al archivo y solo entonces se borra.
    func testTheOldUserDefaultsCopyIsMovedToTheFile() async {
        let legacy = InMemoryKeyValueStore()
        legacy.set("watching-history", data: Data("historial".utf8))
        let store = CacheStore(directory: folder, legacy: legacy)
        XCTAssertEqual(store.data("watching-history"), Data("historial".utf8), "no se pierde al actualizar la app")
        await store.flush()
        XCTAssertNil(legacy.data("watching-history"), "ya no ocupa UserDefaults")
        XCTAssertEqual(CacheStore(directory: folder, legacy: legacy).data("watching-history"), Data("historial".utf8))
    }

    func testKeysWithSymbolsAreSafeFileNames() async throws {
        let store = CacheStore(directory: folder, legacy: InMemoryKeyValueStore())
        store.set("charts:netflix:series/MX", data: Data("top".utf8))
        await store.flush()
        let file = try XCTUnwrap(store.file("charts:netflix:series/MX"))
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL, "sin subcarpetas por la /")
        XCTAssertEqual(try Data(contentsOf: file), Data("top".utf8))
    }

    func testRemovingDeletesTheFile() async {
        let store = CacheStore(directory: folder, legacy: InMemoryKeyValueStore())
        store.set("catalog-popular", data: Data("x".utf8))
        await store.flush()
        store.set("catalog-popular", data: nil)
        await store.flush()
        XCTAssertNil(CacheStore(directory: folder, legacy: InMemoryKeyValueStore()).data("catalog-popular"))
    }

    func testWithoutAFolderItUsesTheOldStore() {
        let legacy = InMemoryKeyValueStore()
        let store = CacheStore(directory: nil, legacy: legacy)
        store.set("paraTi-snapshot") { Data("foto".utf8) }
        XCTAssertEqual(legacy.data("paraTi-snapshot"), Data("foto".utf8))
    }
}
