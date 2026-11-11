import XCTest
@testable import OrbitalCore

/// Lo tuyo en disco (biblioteca, trabajo pendiente, índice de descargas): un archivo con el formato roto se aparta con fecha en
/// vez de pisarse; un tropiezo al leer (el iPhone bloqueado) se reintenta y nunca se aparta ni se pisa; un elemento malo de la
/// cola no tumba a los demás; las descargas sin índice se vuelven a ver (auditoría del 31 oct, C1; revisión del 11 nov 2026).
final class StoredFileTests: XCTestCase {
    private var folder: URL!
    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-stored-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    /// Un lector que falla como «no se pudo leer» las primeras `failures` veces y luego lee de verdad.
    final class Flaky<T: Decodable>: @unchecked Sendable {
        private let lock = NSLock()
        private var failures: Int
        init(failures: Int) { self.failures = failures }
        func setFailures(_ n: Int) { lock.withLock { failures = n } }
        func read(_ url: URL) -> StoredRead<T> {
            if lock.withLock({ () -> Bool in if failures > 0 { failures -= 1; return true }; return false }) { return .unreadable }
            return StoredFile.load(T.self, from: url, what: "prueba")
        }
    }

    func entry(_ id: String, inList: Bool = true) -> LibraryEntry { var e = LibraryEntry(metaID: id, kind: "movie", name: id); e.inList = inList; return e }

    // MARK: formato roto

    func testADamagedLibraryIsSetAsideNotOverwritten() throws {
        let url = folder.appendingPathComponent("library.json")
        try Data("{\"tt1\": {roto".utf8).write(to: url)
        let library = LocalLibrary(url: url)
        XCTAssertTrue(library.isEmpty, "se arranca vacío…")
        let aside = try XCTUnwrap(StoredFile.asideCopies(url).first)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("library.json.corrupt-"), "con fecha en el nombre")
        XCTAssertEqual(try Data(contentsOf: aside), Data("{\"tt1\": {roto".utf8), "…pero el dañado queda apartado para rescatarlo")
        library.update("tt2", make: { LibraryEntry(metaID: "tt2", kind: "movie", name: "Dune") }) { $0.inList = true }
        library.flush()
        XCTAssertEqual(try Data(contentsOf: aside), Data("{\"tt1\": {roto".utf8), "la siguiente escritura no lo pisa")
        XCTAssertEqual(LocalLibrary(url: url).entry("tt2")?.inList, true)
    }

    /// Antes la copia apartada anterior se borraba: un segundo daño perdía el primero. Ahora se guardan varias (con tope).
    func testSeveralDamagedCopiesAreKeptWithACap() throws {
        let url = folder.appendingPathComponent("pending.json")
        for n in 0..<(StoredFile.keptAside + 2) {
            try Data("roto \(n)".utf8).write(to: url)
            XCTAssertEqual(FilePendingStore(url: url).load(), PendingWork())
        }
        let copies = StoredFile.asideCopies(url)
        XCTAssertEqual(copies.count, StoredFile.keptAside, "se guardan las más nuevas")
        XCTAssertEqual(try copies.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }.last, "roto \(StoredFile.keptAside + 1)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAMissingFileIsJustEmpty() {
        let url = folder.appendingPathComponent("nada.json")
        XCTAssertTrue(LocalLibrary(url: url).isEmpty)
        XCTAssertTrue(StoredFile.asideCopies(url).isEmpty, "no existir no es estar dañado")
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

    // MARK: un tropiezo al leer

    /// El iPhone bloqueado con el archivo protegido: no se aparta, no se pisa, y lo que cambies se junta con lo de antes.
    func testATransientReadErrorNeverSetsAsideNorOverwritesTheLibrary() throws {
        let url = folder.appendingPathComponent("library.json")
        XCTAssertTrue(StoredFile.write(["tt1": entry("tt1")], to: url, what: "prueba"))
        let original = try Data(contentsOf: url)
        let flaky = Flaky<[String: LibraryEntry]>(failures: 2)   // al abrir y al primer cambio
        let library = LocalLibrary(url: url, read: { flaky.read($0) })
        library.update("tt2", make: { self.entry("tt2") }) { $0.inList = true }
        library.flush()
        XCTAssertEqual(try Data(contentsOf: url), original, "no se pisó mientras no se podía leer")
        XCTAssertTrue(StoredFile.asideCopies(url).isEmpty, "un tropiezo no es un archivo dañado")
        library.update("tt3", make: { self.entry("tt3") }) { $0.inList = true }   // ya se puede leer
        library.flush()
        XCTAssertEqual(Set(LocalLibrary(url: url).all.map(\.metaID)), ["tt1", "tt2", "tt3"], "lo de antes y lo de ahora, juntos")
    }

    func testATransientReadErrorNeverOverwritesThePendingQueue() throws {
        let url = folder.appendingPathComponent("pending.json")
        var work = PendingWork(); work.traktUnwatched = [TraktTarget(imdb: "tt1")]
        XCTAssertTrue(StoredFile.write(work, to: url, what: "prueba"))
        let original = try Data(contentsOf: url)
        let flaky = Flaky<PendingWork>(failures: 1)
        let store = FilePendingStore(url: url, read: { flaky.read($0) })
        XCTAssertFalse(store.commit { $0.traktUnwatched.append(TraktTarget(imdb: "tt2")) }, "dice que no quedó en disco")
        XCTAssertEqual(try Data(contentsOf: url), original, "el archivo sigue intacto")
        XCTAssertTrue(StoredFile.asideCopies(url).isEmpty)
        store.update { $0.traktUnwatched.append(TraktTarget(imdb: "tt3")) }   // ya se puede leer: se juntan
        XCTAssertEqual(FilePendingStore(url: url).load().traktUnwatched.map(\.imdb), ["tt1", "tt2", "tt3"], "en el orden en que los pediste")
    }

    /// Ya leído una vez: un tropiezo después sigue con lo último conocido (esta app es la única que escribe la cola).
    func testAfterAGoodReadATransientErrorKeepsWorkingWithTheLastKnown() {
        let url = folder.appendingPathComponent("pending.json")
        let flaky = Flaky<PendingWork>(failures: 0)
        let store = FilePendingStore(url: url, read: { flaky.read($0) })
        store.update { $0.traktUnwatched = [TraktTarget(imdb: "tt1")] }
        flaky.setFailures(1)
        XCTAssertTrue(store.commit { $0.traktUnwatched.append(TraktTarget(imdb: "tt2")) })
        XCTAssertEqual(FilePendingStore(url: url).load().traktUnwatched.map(\.imdb), ["tt1", "tt2"])
    }

    // MARK: la cola, elemento por elemento

    func testOneBadQueueItemIsSetAsideAndTheRestStays() throws {
        let url = folder.appendingPathComponent("pending.json")
        let json = #"{"traktWatched":[{"target":{"imdb":"tt1"},"at":10},{"target":"roto"},{"target":{"imdb":"tt2"},"at":20}],"traktUnwatched":[{"imdb":"tt3"}]}"#
        try Data(json.utf8).write(to: url)
        let store = FilePendingStore(url: url)
        XCTAssertEqual(store.load().traktWatched.map(\.target.imdb), ["tt1", "tt2"], "lo bueno sigue")
        XCTAssertEqual(store.load().traktUnwatched.map(\.imdb), ["tt3"])
        XCTAssertTrue(StoredFile.asideCopies(url).isEmpty, "la cola entera no se aparta por un elemento")
        store.update { _ in }
        let rejected = try XCTUnwrap(StoredFile.rejectedCopies(url).first, "el malo quedó apartado")
        XCTAssertTrue(String(decoding: try Data(contentsOf: rejected), as: UTF8.self).contains("roto"))
        XCTAssertEqual(FilePendingStore(url: url).load().traktWatched.count, 2)
        store.update { _ in }
        XCTAssertEqual(StoredFile.rejectedCopies(url).count, 1, "ya no se vuelve a apartar")
    }

    // MARK: escribir dice si pudo

    func testWriteSaysWhenItCouldNot() throws {
        let blocker = folder.appendingPathComponent("soy-un-archivo")
        try Data("x".utf8).write(to: blocker)
        XCTAssertFalse(StoredFile.write([1, 2], to: blocker.appendingPathComponent("dentro.json"), what: "prueba"))
        XCTAssertTrue(StoredFile.write([1, 2], to: folder.appendingPathComponent("bien.json"), what: "prueba"))
    }

    /// La migración de `trakt-outbox` no borra lo de UserDefaults si el archivo no quedó escrito.
    func testTheOutboxMigrationKeepsUserDefaultsIfTheFileWasNotWritten() throws {
        let blocker = folder.appendingPathComponent("soy-un-archivo")
        try Data("x".utf8).write(to: blocker)
        let kv = InMemoryKeyValueStore()
        kv.set(TraktOutbox.legacyKey, data: try JSONEncoder().encode([TraktOutbox.Item(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: true)]))
        let broken = FilePendingStore(url: blocker.appendingPathComponent("pending.json"))
        _ = TraktOutbox(queue: TraktQueue(store: broken), kv: kv)
        XCTAssertNotNil(kv.data(TraktOutbox.legacyKey), "sin archivo escrito, lo de antes se queda")
        let good = FilePendingStore(url: folder.appendingPathComponent("pending.json"))
        let box = TraktOutbox(queue: TraktQueue(store: good), kv: kv)
        XCTAssertNil(kv.data(TraktOutbox.legacyKey), "con el archivo escrito, se borra")
        XCTAssertEqual(box.pending.map(\.imdb), ["tt1"])
    }

    // MARK: el índice de descargas

    func makeDownloads() throws -> URL {
        let root = folder.appendingPathComponent("Downloads")
        let movie = root.appendingPathComponent("tt1160419/tt1160419")
        let episode = root.appendingPathComponent("tt0386676/tt0386676_2_5")
        for dir in [movie, episode.appendingPathComponent("subs")] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data(repeating: 1, count: 1000).write(to: movie.appendingPathComponent("video.mkv"))
        try Data(repeating: 2, count: 500).write(to: episode.appendingPathComponent("video.mp4"))
        try Data("1\n".utf8).write(to: episode.appendingPathComponent("subs/es.srt"))
        return root
    }

    func testWithoutAnIndexTheDownloadsInTheFolderStillShow() throws {
        let root = try makeDownloads()
        let items = DownloadIndexFile(url: folder.appendingPathComponent("downloads.json"), root: root).load()
        XCTAssertEqual(items.map(\.id).sorted(), ["tt0386676|tt0386676:2:5", "tt1160419|tt1160419"])
        let episode = try XCTUnwrap(items.first { $0.kind == "series" })
        XCTAssertEqual(episode.state, .done)
        XCTAssertEqual(episode.writtenBytes, 500)
        XCTAssertEqual(episode.subtitleFiles, ["subs/es.srt"])
        let file = DownloadFiles.contained(root: root, relativePath: episode.relativePath, id: episode.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "apunta al archivo que ya estaba")
    }

    func testADamagedIndexIsSetAsideAndRebuiltFromTheFolder() throws {
        let root = try makeDownloads(), url = folder.appendingPathComponent("downloads.json")
        try Data("[{roto".utf8).write(to: url)
        let index = DownloadIndexFile(url: url, root: root)
        XCTAssertEqual(index.load().count, 2)
        XCTAssertEqual(StoredFile.asideCopies(url).count, 1)
    }

    /// Un índice que solo no se pudo leer: se ven las de la carpeta, pero el índice no se pisa; al poder leerlo, manda el suyo.
    func testAnUnreadableIndexIsNotOverwrittenAndWinsOnceReadable() throws {
        let root = try makeDownloads(), url = folder.appendingPathComponent("downloads.json")
        var full = DownloadIndexFile.scan(root: root).first { $0.kind == "movie" }!
        full.title = "Dune"; full.poster = "https://p.example/dune.jpg"
        XCTAssertTrue(StoredFile.write([full], to: url, what: "prueba"))
        let original = try Data(contentsOf: url)
        let flaky = Flaky<[DownloadItem]>(failures: 2)
        let index = DownloadIndexFile(url: url, root: root, read: { flaky.read($0) })
        let shown = index.load()
        XCTAssertEqual(shown.count, 2, "se ven las de la carpeta")
        XCTAssertFalse(index.save(shown))
        XCTAssertEqual(try Data(contentsOf: url), original, "no se pisó")
        XCTAssertTrue(index.save(shown))
        let saved = DownloadIndexFile(url: url, root: root).load()
        XCTAssertEqual(saved.first { $0.kind == "movie" }?.title, "Dune", "lo del índice gana sobre lo reconstruido")
        XCTAssertEqual(saved.count, 2)
    }
}
