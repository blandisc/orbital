import XCTest
@testable import OrbitalCore

/// Lo tuyo en disco (biblioteca, trabajo pendiente): un archivo dañado se aparta en vez de pisarse, y la biblioteca se
/// escribe fuera del candado con el último cambio (auditoría, 31 oct 2026, C1).
final class StoredFileTests: XCTestCase {
    private var folder: URL!
    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-stored-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testADamagedLibraryIsSetAsideNotOverwritten() throws {
        let url = folder.appendingPathComponent("library.json")
        try Data("{\"tt1\": {roto".utf8).write(to: url)
        let library = LocalLibrary(url: url)
        XCTAssertTrue(library.isEmpty, "se arranca vacío…")
        let aside = StoredFile.corruptCopy(url)
        XCTAssertEqual(try Data(contentsOf: aside), Data("{\"tt1\": {roto".utf8), "…pero el dañado queda apartado para rescatarlo")
        library.update("tt2", make: { LibraryEntry(metaID: "tt2", kind: "movie", name: "Dune") }) { $0.inList = true }
        library.flush()
        XCTAssertEqual(try Data(contentsOf: aside), Data("{\"tt1\": {roto".utf8), "la siguiente escritura no lo pisa")
        XCTAssertEqual(LocalLibrary(url: url).entry("tt2")?.inList, true)
    }

    func testManyChangesEndWithTheLastOneOnDisk() {
        let url = folder.appendingPathComponent("library.json")
        let library = LocalLibrary(url: url)
        for n in 1...50 {
            library.update("tt\(n)", make: { LibraryEntry(metaID: "tt\(n)", kind: "movie", name: "\(n)") }) { $0.position = Double(n) }
        }
        library.flush()
        let reopened = LocalLibrary(url: url)
        XCTAssertEqual(reopened.all.count, 50)
        XCTAssertEqual(reopened.entry("tt50")?.position, 50)
    }

    func testADamagedPendingQueueIsSetAside() throws {
        let url = folder.appendingPathComponent("pending.json")
        try Data("no es json".utf8).write(to: url)
        let store = FilePendingStore(url: url)
        XCTAssertEqual(store.load(), PendingWork())
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoredFile.corruptCopy(url).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAMissingFileIsJustEmpty() {
        let url = folder.appendingPathComponent("nada.json")
        XCTAssertTrue(LocalLibrary(url: url).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: StoredFile.corruptCopy(url).path), "no existir no es estar dañado")
    }
}
