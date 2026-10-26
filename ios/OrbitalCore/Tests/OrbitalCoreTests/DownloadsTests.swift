import XCTest
@testable import OrbitalCore

final class FakeTransport: DownloadTransport, @unchecked Sendable {
    struct Start: Equatable { var id: String; var url: URL; var resumeFrom: Int64; var file: URL }
    private let lock = NSLock()
    private var _starts: [Start] = [], _cancels: [String] = [], _discards: [String] = []
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation

    init() { (events, continuation) = AsyncStream.makeStream() }
    var starts: [Start] { lock.withLock { _starts } }
    var cancels: [String] { lock.withLock { _cancels } }
    var discards: [String] { lock.withLock { _discards } }
    func discard(id: String) async { lock.withLock { _discards.append(id) } }
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

    func item(_ video: String, size: Int64? = 10, meta: String = "tt1") -> DownloadItem {
        DownloadItem(id: DownloadItem.makeID(metaID: meta, videoID: video), kind: "series", metaID: meta, videoID: video, title: "Serie", originalTitle: "Series",
                     subtitle: "T1 · E1", poster: nil, addon: "Torrentio", sourceIndex: 7, expectedBytes: size,
                     relativePath: DownloadFiles.relativePath(metaID: meta, videoID: video, ext: "mkv"), createdAt: 1)
    }

    func makeDownloads(_ transport: FakeTransport, secrets: SecretsStore = InMemorySecrets(), free: Int64 = 50_000_000_000, saved: [DownloadItem] = [],
                       refresh: @escaping @Sendable (DownloadItem) async -> URL? = { _ in nil },
                       otherSource: @escaping @Sendable (DownloadItem) async -> DownloadSource? = { _ in nil },
                       subs: @escaping @Sendable (DownloadItem) async -> SubtitleFetch? = { _ in SubtitleFetch(files: []) }) -> Downloads {
        let d = Downloads(transport: transport, secrets: secrets, root: root, saved: saved, freeSpace: { free }, refresh: refresh,
                          otherSource: otherSource, subtitles: subs, backoff: { _ in })
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
        let d = makeDownloads(transport, secrets: secrets, subs: { _ in SubtitleFetch(files: [DownloadsTests.sub("es", "1\n")]) })
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 10).write(to: transport.starts[0].file)
        transport.emit(.finished(id: "tt1|tt1:1:1"))
        await settle("hecha") { await d.item("tt1|tt1:1:1")?.state == .done }
        XCTAssertNil(secrets.get(SecretKey.download("tt1|tt1:1:1")))
        // Los subtítulos se bajan aparte, después de anotarla como hecha (la cola no los espera).
        await settle("subtítulos") { await d.item("tt1|tt1:1:1")?.subtitleFiles.isEmpty == false }
        let done = await d.item("tt1|tt1:1:1")
        XCTAssertEqual(done?.subtitleFiles, ["subs/es-1.srt"])
        let file = await d.fileURL(done!).deletingLastPathComponent().appendingPathComponent("subs/es-1.srt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
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

    func testAFileThatFinishedWhileTheAppWasClosedIsNotDownloadedAgain() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        var saved = item("tt1:1:2", size: 60_000_000)
        saved.state = .downloading
        let file = root.appendingPathComponent(saved.relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file); try handle.truncate(atOffset: 60_000_000); try handle.close()   // completo en disco
        secrets.set(SecretKey.download(saved.id), "https://rd.example/a.mkv")
        let d = makeDownloads(transport, secrets: secrets, saved: [saved])
        await settle("listo") { await d.item(saved.id)?.state == .done }
        XCTAssertTrue(transport.starts.isEmpty, "no se vuelve a pedir")
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

    func testEachScreenGetsItsOwnUpdatesAndOneClosingDoesNotKillTheOthers() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        let first = Task { () -> Int in var n = 0; for await _ in d.makeUpdates() { n += 1; if n == 2 { break } }; return n }
        let second = d.makeUpdates()
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        _ = await first.value                                  // la primera pantalla se cierra
        try await d.enqueue(item("tt1:1:2"), url: URL(string: "https://rd.example/b.mkv")!)
        var seen = 0
        for await items in second { seen = items.count; if seen == 2 { break } }
        XCTAssertEqual(seen, 2, "la segunda pantalla sigue viendo los cambios")
        let late = d.makeUpdates()                             // una pantalla que entra después ve lo último al instante
        for await items in late { XCTAssertEqual(items.count, 2); break }
    }

    func testRemoveDeletesFileAndLink() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let d = makeDownloads(transport, secrets: secrets)
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 5).write(to: transport.starts[0].file)
        await d.remove("tt1|tt1:1:1")
        XCTAssertEqual(transport.discards, ["tt1|tt1:1:1"], "borrar olvida también lo bajado, no solo pausa")
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

    // MARK: revisión de seguridad y robustez

    func testQueueFileNeverContainsTheAddonOrSourceURLKeys() async throws {
        let transport = FakeTransport()
        var collected = Data()
        let sink = Sink()
        let d = Downloads(transport: transport, secrets: InMemorySecrets(), root: root, freeSpace: { 50_000_000_000 }, refresh: { _ in nil },
                          backoff: { _ in }, onChange: { items in sink.set((try? JSONEncoder().encode(items)) ?? Data()) })
        Task { await d.start() }
        var it = item("tt1:1:1"); it.addon = "Torrentio"; it.release = "Peli.2024.1080p"
        try await d.enqueue(it, url: URL(string: "https://rd.example/realdebrid=SECRETKEY/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        collected = sink.get()
        XCTAssertFalse(String(data: collected, encoding: .utf8)!.contains("SECRETKEY"))
        // Un índice viejo con `addonURL` (y la clave dentro) se lee sin perder la lista y la clave no vuelve a escribirse.
        let legacy = #"[{"id":"tt1|v","kind":"movie","metaID":"tt1","videoID":"v","title":"x","originalTitle":"x","subtitle":"","addonURL":"https://t.example/realdebrid=SECRETKEY/manifest.json","sourceIndex":3,"relativePath":"tt1/v/video.mkv","createdAt":1}]"#
        let decoded = try JSONDecoder().decode([DownloadItem].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertFalse(String(data: try JSONEncoder().encode(decoded), encoding: .utf8)!.contains("SECRETKEY"))
    }

    func testDotDotIdsCannotEscapeTheDownloadsFolder() async throws {
        XCTAssertEqual(DownloadFiles.relativePath(metaID: "..", videoID: "..", ext: "mkv"), "_/_/video.mkv")
        XCTAssertEqual(DownloadFiles.relativePath(metaID: ".", videoID: "", ext: "mkv"), "_/_/video.mkv")
        XCTAssertEqual(DownloadFiles.relativePath(metaID: "../x", videoID: "a/b", ext: "mkv"), ".._x/a_b/video.mkv")
        // Un índice dañado o malicioso con una ruta que se sale de la carpeta: se usa una segura.
        let transport = FakeTransport()
        var evil = item("v"); evil.relativePath = "../../escape/video.mkv"
        let d = makeDownloads(transport, saved: [evil])
        let url = await d.fileURL(evil)
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"))
        // Y borrar nunca toca la carpeta de descargas completa.
        let keep = root.appendingPathComponent("otra/video.mkv")
        try FileManager.default.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 3).write(to: keep)
        var dots = item("..", meta: ".."); dots.relativePath = DownloadFiles.relativePath(metaID: "..", videoID: "..", ext: "mkv")
        let d2 = makeDownloads(FakeTransport(), saved: [dots])
        await d2.remove(dots.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path), "borrar un id raro no se lleva el resto")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testAnExpiredLinkThatNeverGetsFixedStopsInsteadOfLoopingForever() async throws {
        let transport = FakeTransport()
        let counter = Counter()
        let d = makeDownloads(transport, refresh: { _ in counter.bump(); return URL(string: "https://rd.example/FRESH\(counter.value).mkv")! })
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        for round in 1...12 {
            let before = transport.starts.count
            await settle("arranque \(round)", timeout: 1) {
                if transport.starts.count > before { return true }
                return await d.item("tt1|tt1:1:1")?.state == .failed
            }
            if await d.item("tt1|tt1:1:1")?.state == .failed { break }
            transport.emit(.failed(id: "tt1|tt1:1:1", status: 403, message: "HTTP 403"))
        }
        await settle("falló", timeout: 1) { await d.item("tt1|tt1:1:1")?.state == .failed }
        XCTAssertLessThanOrEqual(counter.value, Downloads.maxRefreshes, "como mucho dos enlaces nuevos")
        XCTAssertLessThanOrEqual(transport.starts.count, Downloads.maxAttempts + 1)
    }

    func testTheSameDeadLinkIsNotTreatedAsFresh() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport, refresh: { _ in URL(string: "https://rd.example/a.mkv") })   // devuelve el mismo enlace muerto
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        transport.emit(.failed(id: "tt1|tt1:1:1", status: 410, message: "HTTP 410"))
        await settle("cuenta como fallo normal") { await d.item("tt1|tt1:1:1")?.attempts == 1 }
    }

    func testRemovingWhileTheLinkIsBeingRefreshedDoesNotResurrectTheItem() async throws {
        let transport = FakeTransport()
        let gate = Gate()
        let d = makeDownloads(transport, refresh: { _ in await gate.wait(); return URL(string: "https://rd.example/new.mkv") })
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        transport.emit(.failed(id: "tt1|tt1:1:1", status: 403, message: "HTTP 403"))
        try await Task.sleep(nanoseconds: 30_000_000)
        await d.remove("tt1|tt1:1:1")
        await gate.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        let all = await d.all
        XCTAssertTrue(all.isEmpty, "una descarga borrada no vuelve")
        XCTAssertEqual(transport.starts.count, 1)
    }

    func testARetryWaitDoesNotFreezeOtherDownloadsEvents() async throws {
        let transport = FakeTransport()
        let gate = Gate()
        let d = Downloads(transport: transport, secrets: InMemorySecrets(), root: root, freeSpace: { 50_000_000_000 }, refresh: { _ in nil }, backoff: { _ in await gate.wait() })
        Task { await d.start() }
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/1.mkv")!)
        try await d.enqueue(item("tt1:1:2"), url: URL(string: "https://rd.example/2.mkv")!)
        await settle("dos") { transport.starts.count == 2 }
        transport.emit(.failed(id: "tt1|tt1:1:1", status: nil, message: "sin red"))      // la primera espera su reintento…
        try Data(count: 10).write(to: transport.starts[1].file)
        transport.emit(.finished(id: "tt1|tt1:1:2"))                                      // …y la segunda termina sin esperarla
        await settle("la segunda terminó") { await d.item("tt1|tt1:1:2")?.state == .done }
        await gate.open()
    }

    func testSpaceCheckCountsWhatOtherDownloadsStillNeed() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport, free: 25_000_000_000)
        try await d.enqueue(item("tt1:1:1", size: 20_000_000_000), url: URL(string: "https://rd.example/1.mkv")!)
        do { try await d.enqueue(item("tt1:1:2", size: 20_000_000_000), url: URL(string: "https://rd.example/2.mkv")!); XCTFail("no cabe") }
        catch let error as DownloadError { if case .notEnoughSpace = error {} else { XCTFail("\(error)") } }
    }

    func testATinyFileIsNotAcceptedAsTheFinishedVideo() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        try await d.enqueue(item("tt1:1:1", size: 2_000_000_000), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try Data(count: 2_000).write(to: transport.starts[0].file)    // «failed access»: un video de aviso diminuto
        transport.emit(.finished(id: "tt1|tt1:1:1"))
        await settle("se reintenta") { transport.starts.count == 2 }
        let state = await d.item("tt1|tt1:1:1")?.state
        XCTAssertNotEqual(state, .done)
    }

    func testAServerThatSendsSomethingFarSmallerThanTheSourceSaidIsNotTheVideo() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        try await d.enqueue(item("tt1:1:1", size: 2_000_000_000), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        transport.emit(.progress(id: "tt1|tt1:1:1", written: 6_000, total: 6_000))     // una lista HLS de 6 kB
        try Data(count: 6_000).write(to: transport.starts[0].file)
        transport.emit(.finished(id: "tt1|tt1:1:1"))
        await settle("se reintenta") { transport.starts.count == 2 }
        let state = await d.item("tt1|tt1:1:1")?.state
        XCTAssertNotEqual(state, .done)
    }

    /// La fuente manda 5 kB (el aviso de Torrentio) en vez de la película: se prueba la siguiente fuente al instante, desde cero, y la
    /// mala no se vuelve a elegir; no se gastan los cinco intentos en la misma.
    func testASourceThatDoesNotSendTheVideoIsSwappedForTheNextOne() async throws {
        let transport = FakeTransport(), secrets = InMemorySecrets()
        let asked = Locked<[[String]]>([])
        let d = makeDownloads(transport, secrets: secrets, otherSource: { item in
            asked.mutate { $0.append(item.skippedReleases) }
            return DownloadSource(url: URL(string: "https://rd.example/good.mkv")!, addon: "Torrentio", release: "Peli.1080p.WEB", sourceIndex: 3, size: 3_000_000_000)
        })
        var bad = item("tt1:1:1", size: 3_870_000_000); bad.release = "Peli.AV1"
        try await d.enqueue(bad, url: URL(string: "https://rd.example/bad.mkv")!)
        await settle("empieza") { transport.starts.count == 1 }
        try Data(count: 5_376).write(to: transport.starts[0].file)
        transport.emit(.finished(id: "tt1|tt1:1:1"))
        await settle("arranca con la otra fuente") { transport.starts.count == 2 }
        XCTAssertEqual(transport.starts[1].url.absoluteString, "https://rd.example/good.mkv")
        XCTAssertEqual(transport.starts[1].resumeFrom, 0, "desde cero")
        XCTAssertEqual(asked.value, [["Peli.AV1"]], "la mala queda apartada")
        XCTAssertTrue(transport.discards.contains("tt1|tt1:1:1"), "lo de la fuente mala se tira")
        let now = await d.item("tt1|tt1:1:1")
        XCTAssertEqual(now?.release, "Peli.1080p.WEB")
        XCTAssertEqual(now?.expectedBytes, 3_000_000_000)
        XCTAssertEqual(now?.attempts, 0)
        XCTAssertEqual(secrets.get(SecretKey.download("tt1|tt1:1:1")), "https://rd.example/good.mkv")
    }

    func testASeasonPackSizeDoesNotRejectTheEpisodeFile() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        try await d.enqueue(item("tt1:1:2", size: 45_000_000_000), url: URL(string: "https://rd.example/e2.mkv")!)   // «💾 45 GB»: todo el paquete
        await settle("start") { transport.starts.count == 1 }
        transport.emit(.progress(id: "tt1|tt1:1:2", written: 1_000, total: 15_000_000))
        try Data(count: 15_000_000).write(to: transport.starts[0].file)
        transport.emit(.finished(id: "tt1|tt1:1:2"))
        await settle("terminó") { await d.item("tt1|tt1:1:2")?.state == .done }
    }

    func testServerErrorsAreExplainedInWords() {
        XCTAssertTrue(DownloadMessages.forStatus(403).contains("caducó"))
        XCTAssertTrue(DownloadMessages.forStatus(503).contains("servidor"))
        XCTAssertFalse(DownloadMessages.forStatus(403).contains("HTTP"))
        XCTAssertTrue(DownloadMessages.forStatus(418).contains("418"))
    }

    func testEnqueueingAnActiveDownloadAgainDoesNothing() async throws {
        let transport = FakeTransport()
        let d = makeDownloads(transport)
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        await settle("start") { transport.starts.count == 1 }
        try await d.enqueue(item("tt1:1:1"), url: URL(string: "https://rd.example/a.mkv")!)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(transport.starts.count, 1)
    }
}

final class Sink: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data()
    func set(_ d: Data) { lock.withLock { data = d } }
    func get() -> Data { lock.withLock { data } }
}
final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
actor Gate {
    private var opened = false; private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if opened { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { opened = true; waiters.forEach { $0.resume() }; waiters = [] }
}

/// Un valor que cambian varias tareas a la vez (para anotar lo que pide la cola).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value { lock.withLock { _value } }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&_value) } }

}

extension DownloadsTests {
    func testSubtitlesMissedForLackOfNetworkAreFetchedAgainLater() async throws {
        var done = item("tt1:1:1"); done.state = .done
        let online = Flag()
        let d = makeDownloads(FakeTransport(), saved: [done], subs: { _ in online.value ? SubtitleFetch(files: [DownloadsTests.sub("es", "a"), DownloadsTests.sub("en", "b")]) : nil })
        try? await Task.sleep(nanoseconds: 30_000_000)
        var now = await d.item(done.id)
        XCTAssertEqual(now?.subtitleFiles, [], "sin red no se guarda nada…")
        XCTAssertEqual(now?.subtitleTries, 0, "…y no cuenta como intento")
        online.value = true
        await d.setBackgrounded(false)   // vuelves a la app, ya con red
        now = await d.item(done.id)
        XCTAssertEqual(now?.subtitleFiles, ["subs/es-1.srt", "subs/en-1.srt"])
        XCTAssertEqual(now?.subtitleTries, 1)
        XCTAssertEqual(now?.subtitlesComplete, true)
    }

    func testSubtitleTriesSurviveTheIndex() throws {
        var it = item("tt1:1:1"); it.subtitleTries = 2
        let back = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(it))
        XCTAssertEqual(back.subtitleTries, 2)
    }

    func testDownloadSubtitleLanguagesAlwaysIncludeSpanishAndEnglish() {
        XCTAssertEqual(DownloadSubtitles.languages(["es", "es", "es", "es"]), ["es", "en"])
        XCTAssertEqual(DownloadSubtitles.languages(["", "fre", "en", "es"]), ["fr", "en", "es"])
    }

    // MARK: parte 2: todos los subtítulos de español e inglés

    static func sub(_ language: String, _ text: String, id: String? = nil, release: String? = nil, hi: Bool = false) -> DownloadedSubtitle {
        DownloadedSubtitle(info: SavedSubtitle(file: "", language: language, source: "OpenSubtitles", release: release, hearingImpaired: hi, fileID: id),
                           data: Data(text.utf8))
    }

    func option(_ n: Int, _ lang: String, release: String? = nil, downloads: Int? = nil, hi: Bool = false, id: String? = nil) -> SubtitleOption {
        SubtitleOption(url: URL(string: "https://s.example/\(lang)/\(n)")!, language: lang, release: release, downloads: downloads,
                       hearingImpaired: hi, source: "OpenSubtitles", fileID: id ?? "\(lang)\(n)")
    }

    func testPicksEveryAvailableSubtitleInOrderWithHearingImpairedLast() {
        let found = [option(1, "spa", downloads: 10), option(2, "spa", hi: true), option(3, "spa", release: "Dune.2021.1080p.WEB-DL-FLUX", downloads: 1),
                     option(4, "spa", downloads: 500), option(5, "eng"), option(6, "eng", downloads: 3), option(7, "fre")]
        let picked = DownloadSubtitles.pick(found, languages: ["es", "en"], release: "Dune.2021.1080p.WEB-DL-FLUX")
        XCTAssertEqual(picked.map(\.option.fileID), ["spa3", "spa4", "spa1", "spa2", "eng6", "eng5"],
                       "todos: primero el de tu copia, luego los más bajados, los de sordos al final; nada de francés")
    }

    func testFewerThanTheCapAreAllTakenAndTheCapIsFiftyPerLanguage() {
        let many = (1...80).map { option($0, "spa") } + (1...3).map { option($0, "eng") }
        let picked = DownloadSubtitles.pick(many, languages: ["es", "en"], release: nil)
        XCTAssertEqual(picked.filter { $0.language == "es" }.count, 50, "tope de seguridad")
        XCTAssertEqual(picked.filter { $0.language == "en" }.count, 3, "si hay menos, todos")
        let saved = (1...48).map { SavedSubtitle(file: "subs/es-\($0).srt", language: "es", fileID: "spa\($0)") }
        XCTAssertEqual(DownloadSubtitles.pick(many, languages: ["es"], release: nil, saved: saved).count, 2, "el tope cuenta los ya guardados")
    }

    func testPickSkipsWhatIsAlreadySavedAndRepeatedIDs() {
        let found = [option(1, "spa"), option(2, "spa", id: "x"), option(3, "spa", id: "x"), option(4, "spa")]
        let saved = [SavedSubtitle(file: "subs/es-1.srt", language: "es", fileID: "spa1"),
                     SavedSubtitle(file: "subs/es-2.srt", language: "es", url: "https://s.example/spa/4")]
        let picked = DownloadSubtitles.pick(found, languages: ["es"], release: nil, saved: saved)
        XCTAssertEqual(picked.map(\.option.url.absoluteString), ["https://s.example/spa/2"], "ni por id ni por enlace, ni dos con el mismo id")
    }

    func testFetchAllKeepsGoingWhenOneFailsAndUsesFewAtATime() async {
        let picks = (1...7).map { (language: "es", option: option($0, "spa")) }
        let running = Counter(), peak = Counter()
        let fetch = await DownloadSubtitles.fetchAll(picks, concurrency: 3) { url in
            let now = running.add(1); peak.max(now)
            try? await Task.sleep(nanoseconds: 5_000_000)
            running.add(-1)
            return url.lastPathComponent == "3" ? nil : Data(url.lastPathComponent.utf8)
        }
        XCTAssertEqual(fetch.files.count, 6, "una falla no tumba a los demás")
        XCTAssertFalse(fetch.complete, "y queda para el reintento")
        XCTAssertLessThanOrEqual(peak.value, 3)
        XCTAssertEqual(fetch.files.first?.info.source, "OpenSubtitles")
        XCTAssertEqual(fetch.files.first?.info.url, "https://s.example/spa/1")
    }

    func testIdenticalContentIsSavedOnceWithItsInfo() async throws {
        var done = item("tt1:1:1"); done.state = .done
        let d = makeDownloads(FakeTransport(), saved: [done], subs: { _ in
            SubtitleFetch(files: [DownloadsTests.sub("es", "mismo", id: "1", release: "Dune.WEB-DL"), DownloadsTests.sub("es", "mismo", id: "2"),
                                  DownloadsTests.sub("es", "otro", id: "3", hi: true), DownloadsTests.sub("en", "english", id: "4")])
        })
        await settle("subtítulos") { await d.item(done.id)?.subtitlesComplete == true }
        let now = await d.item(done.id)
        XCTAssertEqual(now?.subtitleFiles, ["subs/es-1.srt", "subs/es-2.srt", "subs/en-1.srt"], "el mismo contenido una sola vez")
        XCTAssertEqual(now?.savedSubtitles.map(\.release), ["Dune.WEB-DL", nil, nil])
        XCTAssertEqual(now?.savedSubtitles.map(\.hearingImpaired), [false, true, false])
        XCTAssertEqual(now?.savedSubtitles.first?.source, "OpenSubtitles")
        let back = try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(now!))
        XCTAssertEqual(back.savedSubtitles, now?.savedSubtitles, "el índice se guarda con la descarga")
    }

    func testRetryCompletesWhatWasMissingWithoutRepeating() async throws {
        var done = item("tt1:1:1"); done.state = .done
        let calls = Counter()
        let d = makeDownloads(FakeTransport(), saved: [done], subs: { item in
            let n = calls.add(1)
            // La primera vez una falla (queda incompleta); la segunda trae lo que ya había y uno nuevo.
            if n == 1 { return SubtitleFetch(files: [DownloadsTests.sub("es", "a", id: "1")], complete: false) }
            XCTAssertEqual(item.savedSubtitles.map(\.fileID), ["1"], "el buscador sabe lo que ya está")
            return SubtitleFetch(files: [DownloadsTests.sub("es", "a", id: "1"), DownloadsTests.sub("es", "b", id: "2")])
        })
        await settle("primera") { await d.item(done.id)?.subtitleTries == 1 }
        await d.setBackgrounded(false)
        let now = await d.item(done.id)
        XCTAssertEqual(now?.subtitleFiles, ["subs/es-1.srt", "subs/es-2.srt"])
        XCTAssertEqual(now?.subtitlesComplete, true)
        await d.setBackgrounded(false)
        XCTAssertEqual(calls.value, 2, "completa: no se vuelve a pedir")
    }

    func testOldDownloadsKeepTheirSubtitlesAndGetTheRest() async throws {
        var old = item("tt1:1:1"); old.state = .done
        old.subtitleFiles = ["subs/es.srt"]; old.subtitleTries = 1   // de la versión anterior: uno por idioma, sin índice
        let d0 = makeDownloads(FakeTransport(), saved: [], subs: { _ in nil })
        let folder = await d0.fileURL(old).deletingLastPathComponent().appendingPathComponent("subs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("viejo".utf8).write(to: folder.appendingPathComponent("es.srt"))
        XCTAssertEqual(old.allSavedSubtitles.map(\.language), ["es"], "el idioma sale del nombre")
        let d = makeDownloads(FakeTransport(), saved: [old], subs: { _ in
            SubtitleFetch(files: [DownloadsTests.sub("es", "viejo", id: "1"), DownloadsTests.sub("es", "nuevo", id: "2"), DownloadsTests.sub("en", "new", id: "3")])
        })
        await settle("completa") { await d.item(old.id)?.subtitlesComplete == true }
        let now = await d.item(old.id)
        XCTAssertEqual(now?.subtitleFiles, ["subs/es.srt", "subs/es-1.srt", "subs/en-1.srt"], "es.srt se queda; el mismo contenido no se repite")
    }

    func testSavedSubtitlesAreNamedAndRankedNotAsFromTheVideo() {
        let tracks = [MediaTrack(id: 1, kind: .subtitle, language: "spa", title: "Spanish"),
                      MediaTrack(id: 10, kind: .subtitle, language: "es", title: "es-1"),
                      MediaTrack(id: 11, kind: .subtitle, language: "es", title: "es-2"),
                      MediaTrack(id: 12, kind: .subtitle, language: "es", title: "es")]
        let saved = ["es-1": SavedSubtitle(file: "subs/es-1.srt", language: "es", source: "OpenSubtitles", release: "Dune.HDRip", hearingImpaired: true),
                     "es-2": SavedSubtitle(file: "subs/es-2.srt", language: "es", source: "OpenSubtitles", release: "Dune.2021.1080p.WEB-DL-FLUX"),
                     "es": SavedSubtitle.legacy(file: "subs/es.srt")!]
        let v = SubtitleVersions.ranked(language: "es", tracks: tracks, found: [], release: "Dune.2021.1080p.WEB-DL-FLUX", saved: saved)
        XCTAssertEqual(v.map(\.id), ["track-1", "track-11", "track-12", "track-10"], "el del video, el de tu copia, el de antes, el de sordos al final")
        XCTAssertEqual(v.map(\.fromVideo), [true, false, false, false], "un .srt guardado no es «Del video»")
        XCTAssertEqual(v.map(\.savedNumber), [nil, 1, 2, 3])
        XCTAssertEqual(v[1].name, "Dune.2021.1080p.WEB-DL-FLUX")
        XCTAssertEqual(v[1].saved?.source, "OpenSubtitles")
    }
}

extension Counter {
    @discardableResult func add(_ d: Int) -> Int { lock.withLock { n += d; return n } }
    func max(_ v: Int) { lock.withLock { n = Swift.max(n, v) } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var _value = false
    var value: Bool { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
