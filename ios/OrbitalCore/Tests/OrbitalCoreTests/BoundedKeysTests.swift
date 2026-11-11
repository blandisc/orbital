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
}
