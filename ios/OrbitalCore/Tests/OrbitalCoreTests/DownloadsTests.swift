import XCTest
@testable import OrbitalCore

final class FakeTransport: DownloadTransport, @unchecked Sendable {
    struct Start: Equatable { var id: String; var url: URL; var resumeFrom: Int64; var file: URL }
    private let lock = NSLock()
    private var _starts: [Start] = [], _cancels: [String] = []
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream() }
    var starts: [Start] { lock.withLock { _starts } }
    var cancels: [String] { lock.withLock { _cancels } }
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async { lock.withLock { _starts.append(.init(id: id, url: url, resumeFrom: resumeFrom, file: file)) } }
    func cancel(id: String) async { lock.withLock { _cancels.append(id) } }
    func emit(_ event: DownloadEvent) { continuation.yield(event) }
}

final class DownloadsTests: XCTestCase {
    var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-dl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func item(_ video: String, size: Int64? = 1_000_000_000, meta: String = "tt1") -> DownloadItem {
        DownloadItem(id: DownloadItem.makeID(metaID: meta, videoID: video), kind: "series", metaID: meta, videoID: video, title: "Serie", originalTitle: "Series",
                     subtitle: "T1 · E1", poster: nil, addonURL: "https://a.example/manifest.json", sourceIndex: 7, expectedBytes: size,
                     relativePath: DownloadFiles.relativePath(metaID: meta, videoID: video, ext: "mkv"), createdAt: 1)
    }

    func makeDownloads(_ transport: FakeTransport, secrets: SecretsStore = InMemorySecrets(), free: Int64 = 50_000_000_000, saved: [DownloadItem] = [],
                       refresh: @escaping @Sendable (DownloadItem) async -> URL? = { _ in nil },
                       subs: @escaping @Sendable (DownloadItem) async -> [(name: String, data: Data)] = { _ in [] }) -> Downloads {
        let d = Downloads(transport: transport, secrets: secrets, root: root, saved: saved, freeSpace: { free }, refresh: refresh, subtitles: subs, backoff: { _ in })
        Task { await d.start() }
        return d
    }

    func settle(_ message: String = "", timeout: TimeInterval = 2, _ condition: @escaping () async -> Bool) async {
        let limit = Date().addingTimeInterval(timeout)
        while Date() < limit { if await condition() { return }; try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("tiempo agotado: \(message)")
    }

    func testEnqueueKeepsTheLinkInSecretsNotInTheItem() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let d = makeDownloads(transport, secrets: secrets)
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/SECRETKEY/a.mkv")!)
        await settle("empieza") { transport.starts.count == 1 }
        XCTAssertEqual(secrets.get(SecretKey.download("tt1|tt1:1:1")), "https://rd.example/SECRETKEY/a.mkv")
        let saved = await d.all
        let json = String(data: try JSONEncoder().encode(saved), encoding: .utf8)!
        XCTAssertFalse(json.contains("SECRETKEY"), "la clave de Real-Debrid no se guarda en la cola")
    }

    func testOnlyTwoAtATimeAndTheNextStartsWhenOneFinishes() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        for n in 1...3 { try await d.enqueue(item("tt1:1:\(n)"), url: URL(string: "https://rd.example/\(n).mkv")!) }
        await settle("dos") { transport.starts.count == 2 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(transport.starts.count, 2)
        let first = transport.starts[0]
        try Data(count: 10).write(to: first.file)
        transport.emit(.finished(id: first.id))
        await settle("la tercera") { transport.starts.count == 3 }
        let done = await d.item(first.id)
        XCTAssertEqual(done?.state, .done)
        XCTAssertNil(InMemorySecrets().get("x"))
    }

    func testFinishedDownloadDropsItsLinkAndSavesSubtitles() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let d = makeDownloads(transport, secrets: secrets, subs: { _ in [(name: "es.srt", data: Data("1\n".utf8))] })
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 5).write(to: transport.starts[0].file)
        transport.emit(.finished(id: "tt1|tt1:1:1"))
        await settle("hecha") { await d.item("tt1|tt1:1:1")?.state == .done }
        XCTAssertNil(secrets.get(SecretKey.download("tt1|tt1:1:1")))
        let done = await d.item("tt1|tt1:1:1")
        XCTAssertEqual(done?.subtitleFiles, ["subs/es.srt"])
        let sub = await d.fileURL(done!).deletingLastPathComponent().appendingPathComponent("subs/es.srt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sub.path))
    }

    func testExpiredLinkGetsAFreshOneAndResumesFromWhatIsOnDisk() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let d = makeDownloads(transport, secrets: secrets, refresh: { _ in URL(string: "https://rd.example/FRESH.mkv")! })
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/OLD.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 4096).write(to: transport.starts[0].file)   // ya hay 4096 bytes bajados
        transport.emit(.failed(id: "tt1|tt1:1:1", status: 403, message: "HTTP 403"))
        await settle("reintento") { transport.starts.count == 2 }
        XCTAssertEqual(transport.starts[1].url.absoluteString, "https://rd.example/FRESH.mkv")
        XCTAssertEqual(transport.starts[1].resumeFrom, 4096, "continúa con Range desde lo que ya hay")
    }

    func testNetworkFailuresRetryThenGiveUp() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        for attempt in 1...Downloads.maxAttempts {
            await settle("intento \(attempt)") { transport.starts.count == attempt }
            transport.emit(.failed(id: "tt1|tt1:1:1", status: nil, message: "sin conexión"))
        }
        await settle("falló") { await d.item("tt1|tt1:1:1")?.state == .failed }
        XCTAssertEqual(transport.starts.count, Downloads.maxAttempts)
        await d.resume("tt1|tt1:1:1")
        await settle("otra vez") { transport.starts.count == Downloads.maxAttempts + 1 }
    }

    func testNotEnoughSpaceIsRefusedBeforeStarting() async {
        let transport = FakeTransport()
        let d = makeDownloads(transport, free: 1_200_000_000)
        do { try await d.enqueue(item("tt1:1:1", size: 2_000_000_000), url: URL(string: "https://rd.example/a.mkv")!); XCTFail() }
        catch let error as DownloadError { if case .notEnoughSpace = error {} else { XCTFail("\(error)") } } catch { XCTFail("\(error)") }
        XCTAssertTrue(transport.starts.isEmpty)
    }

    func testPauseCancelsAndFreesTheSlot() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        for n in 1...3 { try await d.enqueue(item("tt1:1:\(n)"), url: URL(string: "https://rd.example/\(n).mkv")!) }
        await settle("dos") { transport.starts.count == 2 }
        await d.pause("tt1|tt1:1:1")
        XCTAssertEqual(transport.cancels, ["tt1|tt1:1:1"])
        await settle("la tercera ocupa el lugar") { transport.starts.count == 3 }
    }

    func testRemoveDeletesFileAndLink() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let d = makeDownloads(transport, secrets: secrets)
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 5).write(to: transport.starts[0].file)
        await d.remove("tt1|tt1:1:1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.starts[0].file.path))
        XCTAssertNil(secrets.get(SecretKey.download("tt1|tt1:1:1")))
        let remaining = await d.all
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInterruptedDownloadsResumeOnLaunch() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        secrets.set(SecretKey.download("tt1|tt1:1:1"), "https://rd.example/a.mkv")
        var saved = item("tt1:1:1"); saved.state = .downloading; saved.writtenBytes = 100
        let file = root.appendingPathComponent(saved.relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 100).write(to: file)
        _ = makeDownloads(transport, secrets: secrets, saved: [saved])
        await settle("se retoma") { transport.starts.count == 1 }
        XCTAssertEqual(transport.starts[0].resumeFrom, 100)
    }

    func testNextEpisodesToDownload() async throws {
        let series = try Fixtures.json("cinemeta/meta_series_tt0386676.json")
        let transport = FakeTransport()
        let d = makeDownloads(transport, saved: [item("tt0386676:1:1", meta: "tt0386676")])
        let next = await d.nextToDownload(metaID: "tt0386676", meta: series, ahead: 2)
        XCTAssertEqual(next, ["tt0386676:1:2", "tt0386676:1:3"])
        let none = await d.nextToDownload(metaID: "otra", meta: series)
        XCTAssertTrue(none.isEmpty)
    }

    func testFilePaths() {
        XCTAssertEqual(DownloadFiles.fileExtension(for: URL(string: "https://x/a/b.MP4?x=1")!), "mp4")
        XCTAssertEqual(DownloadFiles.fileExtension(for: URL(string: "https://x/resolve/abc")!), "mkv")
        XCTAssertEqual(DownloadFiles.relativePath(metaID: "tt1", videoID: "tt1:1:2", ext: "mkv"), "tt1/tt1_1_2/video.mkv")
        XCTAssertFalse(DownloadFiles.relativePath(metaID: "../x", videoID: "a/b", ext: "mkv").contains("/../"))
    }
}
