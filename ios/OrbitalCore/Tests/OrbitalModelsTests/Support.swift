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
    var calls: [String] { lock.withLock { _calls } }
    func bodies(_ url: String) -> [Data] { lock.withLock { _bodies[url] ?? [] } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = request.url.absoluteString
        lock.withLock { _calls.append(key); if let b = request.body { _bodies[key, default: []].append(b) } }
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
    }
    private func note(_ s: String) { lock.withLock { _calls.append(s) } }
    func play() async { note("play") }
    func pause() async { note("pause") }
    func seek(to seconds: Double) async { note("seek \(Int(seconds))") }
    func stop() async { note("stop") }
    func selectAudio(_ id: Int?) async { note("audio \(id.map(String.init) ?? "none")") }
    func selectSubtitle(_ id: Int?) async { note("sub \(id.map(String.init) ?? "none")") }
    func addSubtitle(url: URL, language: String?) async { lock.withLock { _subs.append(url) }; note("addsub \(language ?? "")") }
}

let stremioGet = "https://api.strem.io/api/datastoreGet", stremioPut = "https://api.strem.io/api/datastorePut"

/// Un entorno completo con red falsa: complementos con fuentes, una ficha de serie, y la cuenta de Stremio.
@MainActor
final class Rig {
    let http = FakeHTTP(), clock = Clock(), engine = FakeEngine(), kv = InMemoryKeyValueStore(), pending = InMemoryPendingStore()
    let settings: SettingsStore, titlePrefs: TitlePreferences, finder: StreamFinder, watch: WatchService, model: PlayerModel
    let series: JSON

    init(streams: [String: [JSON]] = [:], remote: JSON? = nil, trakt: Trakt? = nil) throws {
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
        watch = WatchService(stremio: StremioAPI(http: http), authKey: { "KEY" }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: { clock.now })
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
