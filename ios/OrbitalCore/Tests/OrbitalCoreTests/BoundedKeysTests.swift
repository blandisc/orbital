import XCTest
@testable import OrbitalCore

/// F10: lo que se guarda una clave por video (IntroDB, sustos) ya no crece sin límite en UserDefaults.
final class BoundedKeysTests: XCTestCase {
    func testKeepsOnlyTheNewestKeys() {
        let store = InMemoryKeyValueStore()
        let keys = BoundedKeys(store: store, prefix: "introdb", limit: 3)
        for i in 1...5 { keys.set("introdb.tt\(i)", data: Data([UInt8(i)])) }
        XCTAssertNil(store.data("introdb.tt1"))
        XCTAssertNil(store.data("introdb.tt2"))
        XCTAssertEqual(store.data("introdb.tt5"), Data([5]))
        keys.set("introdb.tt3", data: Data([9]))   // volver a guardar una la hace la más nueva
        keys.set("introdb.tt6", data: Data([6]))
        XCTAssertEqual(store.data("introdb.tt3"), Data([9]))
        XCTAssertNil(store.data("introdb.tt4"))
    }

    func testIntroDBMarksAreCapped() async {
        let store = InMemoryKeyValueStore()
        XCTAssertEqual(IntroDB.savedLimit, 1000)
        let saved = BoundedKeys(store: store, prefix: "introdb", limit: IntroDB.savedLimit)
        for i in 0..<1005 { saved.set("introdb.tt\(i)", data: Data()) }
        let index = store.data("introdb.index").flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        XCTAssertEqual(index?.count, 1000)
        XCTAssertNil(store.data("introdb.tt0"))
    }

    /// Lo guardado antes de que hubiera índice también entra al tope (antes se quedaba para siempre).
    func testWhatWasSavedBeforeTheIndexIsAlsoCapped() {
        let store = InMemoryKeyValueStore()
        for i in 1...4 { store.set("introdb.old\(i)", data: Data([UInt8(i)])) }
        store.set("jumpscares.tt9", data: Data([9]))   // de otro tipo: no se toca
        let keys = BoundedKeys(store: store, prefix: "introdb", limit: 3)
        keys.set("introdb.new", data: Data([7]))
        XCTAssertEqual(store.keys(prefix: "introdb.")?.filter { $0 != "introdb.index" }.sorted(), ["introdb.new", "introdb.old3", "introdb.old4"])
        XCTAssertEqual(store.data("jumpscares.tt9"), Data([9]))
    }

    func testUserDefaultsListsItsKeysWithoutItsOwnPrefix() throws {
        let suite = "orbital-bounded-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsKeyValueStore(defaults: defaults, prefix: "orbital.")
        store.set("introdb.a", data: Data([1])); store.set("introdb.b", data: Data([2])); store.set("otra", data: Data([3]))
        XCTAssertEqual(store.keys(prefix: "introdb.")?.sorted(), ["introdb.a", "introdb.b"])
        BoundedKeys(store: store, prefix: "introdb", limit: 2).set("introdb.c", data: Data([4]))
        XCTAssertNil(store.data("introdb.a"), "la más vieja de antes del índice se borra")
        XCTAssertNotNil(store.data("introdb.c"))
    }

    /// PosterSource: con más de 4000 títulos en 30 días ya no crece sin fin (antes solo se quitaba lo vencido).
    func testPosterMemoryHasARealCap() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var map: [String: Date] = [:]
        for i in 0..<10 { map["tt\(i)"] = now.addingTimeInterval(-Double(i)) }   // todos frescos
        map["viejo"] = now.addingTimeInterval(-PosterSource.ttl - 1)
        let capped = PosterSource.capped(map, at: { $0 }, now: now, max: 4)
        XCTAssertEqual(capped.keys.sorted(), ["tt0", "tt1", "tt2", "tt3"], "los más nuevos, sin lo vencido")
        XCTAssertEqual(PosterSource.capped(["a": now], at: { $0 }, now: now, max: 4).count, 1)
    }
}
