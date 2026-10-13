import AVFoundation
import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un motor de video con su superficie (la vista donde se pinta). El motor principal es AetherEngine (MKV, HDR,
/// Dolby Vision, PGS, PiP); el de respaldo, AVPlayer de Apple (MP4/HLS, sin MKV).
protocol VideoPlayerEngine: PlayerEngine {
    @MainActor var surface: AnyView { get }
    /// Para PiP y AirPlay si el motor los da.
    var name: String { get }
}

/// Reparte cada «foto» del motor a quien la pida (`snapshots` entrega un flujo nuevo en cada acceso).
final class SnapshotHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<EngineSnapshot>.Continuation] = [:]
    private(set) var last = EngineSnapshot()

    func makeStream() -> AsyncStream<EngineSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.continuations[id] = nil } }
        }
    }

    func send(_ snapshot: EngineSnapshot) {
        let targets = lock.withLock { last = snapshot; return Array(continuations.values) }
        for continuation in targets { continuation.yield(snapshot) }
    }
}

// MARK: - AVPlayer (respaldo)

/// AVPlayer de Apple: abre MP4, MOV y HLS (no MKV). Es la vía de respaldo, y la única con AirPlay de video «de verdad».
final class AVPlayerEngine: VideoPlayerEngine, @unchecked Sendable {
    let name = "AVPlayer"
    let player = AVPlayer()
    private let hub = SnapshotHub()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var chapters: [Chapter] = []
    private var ended = false

    var snapshots: AsyncStream<EngineSnapshot> { hub.makeStream() }

    @MainActor var surface: AnyView { AnyView(AVPlayerSurface(player: player).ignoresSafeArea()) }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in self?.publish() }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.publish() }
    }

    deinit { if let timeObserver { player.removeTimeObserver(timeObserver) } }

    func load(url: URL, startAt: Double) async throws {
        ended = false; chapters = []
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        await MainActor.run {
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.ended = true; self?.publish() }
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in self?.publish() }
            player.replaceCurrentItem(with: item)
        }
        audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        if let groups = try? await asset.load(.availableChapterLocales), let locale = groups.first,
           let metadata = try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: []) {
            chapters = metadata.compactMap { group in
                guard let title = group.items.first?.stringValue else { return nil }
                return Chapter(title: title, time: group.timeRange.start.seconds)
            }
        }
        if startAt > 1 { await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        await MainActor.run { player.play() }
        publish()
    }

    func play() async { await MainActor.run { player.play() } }
    func pause() async { await MainActor.run { player.pause() } }
    func seek(to seconds: Double) async {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publish()
    }
    func stop() async {
        await MainActor.run { player.pause(); player.replaceCurrentItem(with: nil) }
        hub.send(EngineSnapshot(state: .idle))
    }

    func selectAudio(_ id: Int?) async { select(audioGroup, index: id) }
    func selectSubtitle(_ id: Int?) async { select(legibleGroup, index: id) }
    /// AVPlayer no suma un archivo .srt suelto sin reconstruir el video; las pistas externas son cosa de AetherEngine.
    func addSubtitle(url: URL, language: String?) async {}

    private func select(_ group: AVMediaSelectionGroup?, index: Int?) {
        guard let group, let item = player.currentItem else { return }
        if let index, group.options.indices.contains(index) { item.select(group.options[index], in: group) } else { item.select(nil, in: group) }
        publish()
    }

    private func tracks(_ group: AVMediaSelectionGroup?, kind: MediaTrack.Kind) -> [MediaTrack] {
        (group?.options ?? []).enumerated().map { index, option in
            MediaTrack(id: index, kind: kind, language: option.locale?.identifier ?? option.extendedLanguageTag, title: option.displayName,
                       isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles))
        }
    }

    private func selectedIndex(_ group: AVMediaSelectionGroup?) -> Int? {
        guard let group, let item = player.currentItem, let option = item.currentMediaSelection.selectedMediaOption(in: group) else { return nil }
        return group.options.firstIndex(of: option)
    }

    private func publish() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
        let state: EngineState
        if item.status == .failed { state = .failed(item.error?.localizedDescription ?? "No se pudo reproducir") }
        else if ended { state = .ended }
        else if item.status != .readyToPlay { state = .loading }
        else {
            switch player.timeControlStatus {
            case .playing: state = .playing
            case .paused: state = .paused
            case .waitingToPlayAtSpecifiedRate: state = .buffering
            @unknown default: state = .paused
            }
        }
        hub.send(EngineSnapshot(state: state, position: max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0), duration: duration,
                                audioTracks: tracks(audioGroup, kind: .audio), subtitleTracks: tracks(legibleGroup, kind: .subtitle),
                                selectedAudio: selectedIndex(audioGroup), selectedSubtitle: selectedIndex(legibleGroup), chapters: chapters))
    }
}

struct AVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.playerLayer.player = player; return view }
    func updateUIView(_ view: PlayerLayerView, context: Context) { view.playerLayer.player = player }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black; playerLayer.videoGravity = .resizeAspect }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
}

// MARK: - Fábrica

enum PlayerEngines {
    /// El motor para una reproducción. AetherEngine si está compilado (bandera AETHER_ENGINE) y no se pidió otro; si no, AVPlayer.
    @MainActor static func make(preferred: String = "aether") -> VideoPlayerEngine {
        #if AETHER_ENGINE
        if preferred == "aether" { return AetherEnginePlayer() }
        #endif
        return AVPlayerEngine()
    }

    static var aetherAvailable: Bool {
        #if AETHER_ENGINE
        return true
        #else
        return false
        #endif
    }
}
