import AVFoundation
import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un motor de video con su superficie (la vista donde se pinta). El motor principal es AetherEngine (MKV, HDR,
/// Dolby Vision, PGS, PiP); el de respaldo, AVPlayer de Apple (MP4/HLS, sin MKV).
protocol VideoPlayerEngine: PlayerEngine {
    @MainActor var surface: AnyView { get }
    var name: String { get }
    /// Lo que se puede llevar a una ventana de PiP ahora (cambia con cada fuente; nil antes de cargar).
    @MainActor var pictureInPicture: PictureInPictureContent? { get }
    /// Pellizcar: el video llena la pantalla (recorta los bordes) o se ve completo con franjas.
    @MainActor func setFillsScreen(_ fill: Bool)
    /// La ventana de PiP se abrió o se cerró (el motor sigue decodificando video en segundo plano mientras tanto).
    @MainActor func setPictureInPictureActive(_ active: Bool)
    /// Los subtítulos encima del video, si el motor no los pinta solo (AVPlayer sí; AetherEngine no).
    @MainActor func subtitleOverlay(lifted: Bool, heightFraction: Double, delay: Double) -> AnyView
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
        let targets: [AsyncStream<EngineSnapshot>.Continuation]? = lock.withLock {
            // Un video que falla avisa varias veces (cada KVO): el modelo cambiaría de fuente por cada aviso repetido.
            if case .failed = snapshot.state, case .failed = last.state { last = snapshot; return nil }
            last = snapshot
            return Array(continuations.values)
        }
        guard let targets else { return }
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

    /// La vista con la capa del video: se arma una vez y la usan la pantalla y PiP.
    @MainActor private lazy var layerView: PlayerLayerView = {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }()

    @MainActor var surface: AnyView { AnyView(AVPlayerSurface(view: layerView).ignoresSafeArea()) }
    @MainActor var pictureInPicture: PictureInPictureContent? { player.currentItem == nil ? nil : .playerLayer(layerView.playerLayer) }
    @MainActor func setFillsScreen(_ fill: Bool) { layerView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect }
    @MainActor func setPictureInPictureActive(_ active: Bool) {}
    @MainActor func subtitleOverlay(lifted: Bool, heightFraction: Double, delay: Double) -> AnyView { AnyView(EmptyView()) }   // AVPlayerLayer pinta los suyos

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in self?.publish() }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.publish() }
    }

    deinit { if let timeObserver { player.removeTimeObserver(timeObserver) } }

    func load(url: URL, startAt: Double) async throws {
        ended = false; chapters = []
        hub.send(EngineSnapshot(state: .loading))   // un video nuevo empieza sin el «falló» del anterior
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
            var found: [Chapter] = []
            for group in metadata {
                guard let title = try? await group.items.first?.load(.stringValue) else { continue }
                found.append(Chapter(title: title, time: group.timeRange.start.seconds))
            }
            chapters = found
        }
        if startAt > 1 { await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        await MainActor.run { player.play() }
        publish()
    }

    func play() async { await MainActor.run { player.play() } }
    func setRate(_ rate: Float) async {
        await MainActor.run {
            player.defaultRate = rate                       // la que usa `play()` desde ahora
            if player.timeControlStatus != .paused { player.rate = rate }
        }
    }
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
    let view: PlayerLayerView
    func makeUIView(context: Context) -> PlayerLayerView { view }
    func updateUIView(_ view: PlayerLayerView, context: Context) {}
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = UIColor(DS.video); playerLayer.videoGravity = .resizeAspect }
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
