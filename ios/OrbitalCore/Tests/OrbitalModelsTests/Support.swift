import Foundation
import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

enum Fixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("tests/fixtures")
    }()
    static func json(_ path: String) throws -> JSON { try XCTUnwrap(JSON.parse(try Data(contentsOf: root.appendingPathComponent(path)))) }
}

final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _json: [String: JSON] = [:], _calls: [String] = [], _bodies: [String: [Data]] = [:], _statuses: [String: Int] = [:]
    var json: [String: JSON] { get { lock.withLock { _json } } set { lock.withLock { _json = newValue } } }
    var statuses: [String: Int] { get { lock.withLock { _statuses } } set { lock.withLock { _statuses = newValue } } }
    private var _delays: [String: Int] = [:]
    /// Milisegundos de demora por URL (para que dos peticiones se crucen).
    var delays: [String: Int] { get { lock.withLock { _delays } } set { lock.withLock { _delays = newValue } } }
    var calls: [String] { lock.withLock { _calls } }
    func bodies(_ url: String) -> [Data] { lock.withLock { _bodies[url] ?? [] } }
    /// Modo avión: toda petición falla sin respuesta.
    var offline: Bool { get { lock.withLock { _offline } } set { lock.withLock { _offline = newValue } } }
    private var _offline = false
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = request.url.absoluteString
        if offline { throw URLError(.notConnectedToInternet) }
        lock.withLock { _calls.append(key); if let b = request.body { _bodies[key, default: []].append(b) } }
        if let ms = lock.withLock({ _delays[key] }) { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
        let forced = lock.withLock { _statuses[key] }
        guard let body = lock.withLock({ _json[key] }) else { return HTTPResponse(status: forced ?? 404, data: Data()) }
        return HTTPResponse(status: forced ?? 200, data: body.serialized())
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_760_000_000)
    var now: Date { get { lock.withLock { _now } } set { lock.withLock { _now = newValue } } }
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

final class FakeEngine: PlayerEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var _loads: [(url: URL, start: Double)] = [], _calls: [String] = [], _subs: [URL] = []
    var failing: Set<String> = []
    var loads: [(url: URL, start: Double)] { lock.withLock { _loads } }
    var calls: [String] { lock.withLock { _calls } }
    var subs: [URL] { lock.withLock { _subs } }
    var snapshots: AsyncStream<EngineSnapshot> { AsyncStream { _ in } }
    func load(url: URL, startAt: Double) async throws {
        lock.withLock { _loads.append((url, startAt)) }
        if failing.contains(url.absoluteString) { throw NetworkError("no abre") }
        // Como el motor del iPhone el 29 oct: se queda abriendo el archivo y no vuelve hasta que lo detienen.
        if hangLoads { try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in lock.withLock { hung.append(c) } } }
    }
    var hangLoads = false
    private var hung: [CheckedContinuation<Void, Error>] = []
    var hungLoads: Int { lock.withLock { hung.count } }
    private func note(_ s: String) { lock.withLock { _calls.append(s) } }
    func play() async { note("play") }
    func pause() async { note("pause") }
    /// Lo que contesta al volver de segundo plano (false: no pudo rearmar el video).
    var restores = true
    var hangRestore = false
    func restoreAfterBackground(resume: Bool) async -> Bool {
        note("restore \(resume)")
        if hangRestore { _ = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in lock.withLock { hung.append(c) } } }
        return restores
    }
    func seek(to seconds: Double) async { note("seek \(Int(seconds))") }
    func stop() async {
        note("stop")
        let pending = lock.withLock { let all = hung; hung = []; return all }
        for c in pending { c.resume(throwing: CancellationError()) }
    }
    func selectAudio(_ id: Int?) async { note("audio \(id.map(String.init) ?? "none")") }
    func selectSubtitle(_ id: Int?) async { note("sub \(id.map(String.init) ?? "none")") }
    func addSubtitle(url: URL, language: String?) async { lock.withLock { _subs.append(url) }; note("addsub \(language ?? "")") }
    func setRate(_ rate: Float) async { note("rate \(rate)") }
}

let stremioGet = "https://api.strem.io/api/datastoreGet", stremioPut = "https://api.strem.io/api/datastorePut"

/// Un entorno completo con red falsa: complementos con fuentes, una ficha de serie, y la cuenta de Stremio.
@MainActor
final class Rig {
    let http = FakeHTTP(), clock = Clock(), engine = FakeEngine(), kv = InMemoryKeyValueStore(), pending = InMemoryPendingStore()
    let settings: SettingsStore, titlePrefs: TitlePreferences, finder: StreamFinder, watch: WatchService, model: PlayerModel
    let series: JSON
    let library: LocalLibrary

    init(streams: [String: [JSON]] = [:], remote: JSON? = nil, trakt: Trakt? = nil, scrobbleLog: ScrobbleLog? = nil) throws {
        series = try Fixtures.json("cinemeta/meta_series_tt0386676.json")
        let http = self.http, clock = self.clock
        http.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream", "subtitles"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        for (video, list) in streams {
            let kind = video.contains(":") ? "series" : "movie"
            http.json["https://a.example/stream/\(kind)/\(video.replacingOccurrences(of: ":", with: "%3A")).json"] = ["streams": .array(list)]
        }
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json[stremioGet] = ["result": remote.map { [$0] } ?? []]
        http.json[stremioPut] = ["result": ["success": true]]
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.stremioAuth, "KEY")
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://a.example"] }, clock: { clock.now })
        settings = SettingsStore(kv)
        settings.update { $0.audio = "es"; $0.subtitles = "es"; $0.quality = "1080p" }
        titlePrefs = TitlePreferences(kv)
        finder = StreamFinder(http: http, registry: registry, clock: { clock.now })
        let cinemeta = Cinemeta(http: http, clock: { clock.now })
        // Lo de `remote` como si ya se hubiera traído de Stremio al teléfono (la app ya no le pregunta a Stremio dónde ibas).
        let library = LocalLibrary()
        if let remote, let id = remote["_id"]?.string {
            let state = StremioLibrary.state(of: remote)
            var entry = LibraryEntry(metaID: id, kind: "series", name: remote["name"]?.string ?? "The Office")
            entry.videoID = state["video_id"]?.string
            entry.position = Double(state["timeOffset"]?.intValue ?? 0) / 1000; entry.duration = Double(state["duration"]?.intValue ?? 0) / 1000
            entry.updatedAt = StremioLibrary.epoch(state["lastWatched"]) ?? 0
            library.update(id, make: { entry }) { _ in }
        }
        self.library = library
        watch = WatchService(library: library, stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: cinemeta, trakt: trakt, pending: pending,
                             clock: { clock.now }, scrobbleLog: scrobbleLog, sleep: { _ in })
        model = PlayerModel(engine: engine, finder: finder, watch: watch, titlePrefs: titlePrefs, settings: settings, clock: { clock.now })
    }

    func stream(_ id: String, title: String = "Show 1080p", size: String = "💾 2 GB", url: String? = nil, name: String = "T\n1080p [RD+]", binge: String? = nil) -> JSON {
        var s: [String: JSON] = ["name": .string(name), "title": .string("\(title)\n\(size) 🇲🇽"), "url": .string(url ?? "https://rd.example/\(id).mkv")]
        if let binge { s["behaviorHints"] = ["bingeGroup": .string(binge)] }
        return .object(s)
    }

    func request(video: String = "tt0386676:1:1", fromStart: Bool = false) -> PlayRequest {
        PlayRequest(kind: "series", metaID: "tt0386676", videoID: video, originalTitle: "The Office", displayTitle: "La Oficina", episodeLabel: "T1 · E1", meta: series, fromStart: fromStart)
    }

    func saved() throws -> [JSON] { try http.bodies(stremioPut).map { try XCTUnwrap(JSON.parse($0))["changes"]?.array?.first ?? .null } }

    func playing(_ position: Double, duration: Double = 1320, audio: [MediaTrack] = [], subs: [MediaTrack] = [], chapters: [Chapter] = [], state: EngineState = .playing,
                 selectedAudio: Int? = nil, selectedSubtitle: Int? = nil) -> EngineSnapshot {
        EngineSnapshot(state: state, position: position, duration: duration, audioTracks: audio, subtitleTracks: subs, selectedAudio: selectedAudio, selectedSubtitle: selectedSubtitle, chapters: chapters)
    }
}

/// Los servicios completos con red falsa (para probar los modelos de pantalla).
@MainActor
final class ServicesRig {
    let http = FakeHTTP(), clock = Clock(), kv = InMemoryKeyValueStore(), secrets = InMemorySecrets(), pending = InMemoryPendingStore()
    let transport = FakeDownloadTransport()
    let services: Services
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-svc-\(UUID().uuidString)")

    init(signedIn: Bool = true, traktLinked: Bool = false, traktClientID: String = "", tmdbKey: String = "", builtInTraktClientID: String = "") throws {
        if signedIn { secrets.set(SecretKey.stremioAuth, "KEY") }
        if !tmdbKey.isEmpty { secrets.set(SecretKey.tmdbKey, tmdbKey) }
        if !traktClientID.isEmpty {
            let s = SettingsStore(kv); s.update { $0.traktClientID = traktClientID }
        }
        if traktLinked { secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(1_760_000_000 + 86400)}"#) }
        let clock = self.clock
        services = Services(http: http, secrets: secrets, kv: kv, pending: pending, downloadTransport: transport, downloadsRoot: root,
                            freeSpace: { 50_000_000_000 }, clock: { clock.now }, builtInTraktClientID: builtInTraktClientID)
        let series = try Fixtures.json("cinemeta/meta_series_tt0386676.json")
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        http.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream", "subtitles"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        secrets.set(SecretKey.ownAddons, "https://a.example/manifest.json")
    }
}

final class FakeDownloadTransport: DownloadTransport, @unchecked Sendable {
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    private let lock = NSLock()
    private var _starts: [String] = []
    init() { (events, continuation) = AsyncStream.makeStream() }
    var starts: [String] { lock.withLock { _starts } }
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async { lock.withLock { _starts.append(url.absoluteString) } }
    func cancel(id: String) async {}
    func emit(_ e: DownloadEvent) { continuation.yield(e) }
}
