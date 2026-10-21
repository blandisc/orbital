import AVFoundation
import MediaAccessibility
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
    /// El zoom del video (botón y pellizco, como Infuse). «Ajuste de aspecto» es ajustar: el recuadro más chico lo pone `PlayerScreen`.
    @MainActor func setZoom(_ zoom: VideoZoom)
    /// La ventana de PiP se abrió o se cerró (el motor sigue decodificando video en segundo plano mientras tanto).
    @MainActor func setPictureInPictureActive(_ active: Bool)
    /// Los subtítulos encima del video, si el motor no los pinta solo (AVPlayer sí; AetherEngine no).
    @MainActor func subtitleOverlay(lifted: Bool, look: SubtitleLook, delay: Double) -> AnyView
    /// Si los subtítulos los dibuja la app (y por eso se pueden adelantar o atrasar, y cambiar de estilo).
    var drawsSubtitles: Bool { get }
    /// «Sincronizar con una línea»: las frases de texto del subtítulo puesto desde ese segundo del archivo (vacío si no hay
    /// texto, p. ej. un PGS de imagen) y el segundo del cuadro que se ve ahora.
    @MainActor func subtitleLines(from seconds: Double, count: Int) -> [SubtitleLine]
    @MainActor var shownTime: Double { get }
}

/// Una frase del subtítulo puesto, con el segundo en que el archivo la pone.
struct SubtitleLine: Identifiable, Equatable {
    let start: Double
    let text: String
    var id: Double { start }
}

extension View {
    /// Una línea de subtítulo con su estilo: contorno oscuro (cuatro copias desplazadas, sin desenfoque, más una sombra
    /// suave: se lee sobre nieve y sobre negro) o, con «Caja oscura» / «Translúcido» / el estilo del iPhone, una caja detrás.
    @ViewBuilder func subtitleLook(_ look: SubtitleLook, size: CGFloat) -> some View {
        if let box = look.box {
            padding(.horizontal, size * DS.Subtitle.boxPaddingH).padding(.vertical, size * DS.Subtitle.boxPaddingV)
                .background(box, in: RoundedRectangle(cornerRadius: size * DS.Subtitle.boxRadius, style: .continuous))
        } else {
            let outline = size * DS.Subtitle.outlineWidth
            shadow(color: DS.subtitleShadow, radius: 0, x: -outline, y: 0)
                .shadow(color: DS.subtitleShadow, radius: 0, x: outline, y: 0)
                .shadow(color: DS.subtitleShadow, radius: 0, x: 0, y: -outline)
                .shadow(color: DS.subtitleShadow, radius: 0, x: 0, y: outline)
                .shadow(color: DS.subtitleShadow, radius: size * DS.Subtitle.shadowRadius)
        }
    }
}

/// Cómo se ven los subtítulos que dibuja la app (Ajustes › Subtítulos): tamaño, fondo, posición y, si lo pides, el estilo
/// de Accesibilidad del iPhone (su color de letra, de fondo y su tamaño).
struct SubtitleLook: Equatable {
    enum Background: String { case outline, box, translucent }
    var heightFraction: Double
    var background: Background = .outline
    var raised = false
    var text: Color = DS.subtitleText
    /// El fondo del estilo del iPhone (reemplaza la caja oscura).
    var systemBox: Color?

    init(heightFraction: Double, background: Background = .outline, raised: Bool = false) {
        self.heightFraction = heightFraction; self.background = background; self.raised = raised
    }

    init(settings: AppSettings) {
        self.init(heightFraction: settings.subtitleHeightFraction, background: Background(rawValue: settings.subtitleBackground) ?? .outline,
                  raised: settings.subtitlePosition == "raised")
        guard settings.subtitleSystemStyle else { return }
        text = Color(cgColor: MACaptionAppearanceCopyForegroundColor(.user, nil).takeRetainedValue())   // ds-exception: el color lo eliges en Accesibilidad
        let opacity = MACaptionAppearanceGetBackgroundOpacity(.user, nil)
        if opacity > 0 {
            systemBox = Color(cgColor: MACaptionAppearanceCopyBackgroundColor(.user, nil).takeRetainedValue()).opacity(opacity)   // ds-exception: ídem
            background = .box
        } else { background = .outline }
        heightFraction *= max(0.5, min(2, MACaptionAppearanceGetRelativeCharacterSize(.user, nil)))
    }

    /// El fondo detrás de cada línea (nil: contorno, sin caja).
    var box: Color? {
        switch background {
        case .outline: nil
        case .box: systemBox ?? DS.subtitleBox
        case .translucent: DS.subtitleTranslucent
        }
    }
}

extension VideoZoom {
    /// Cómo pinta la capa del video cada modo.
    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit, .fitSafeArea: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch: .resize
        }
    }

    /// El ícono del botón de zoom (muestra el modo actual).
    var symbol: String {
        switch self {
        case .fit: "arrow.left.and.right"
        case .fitSafeArea: "rectangle.inset.filled"
        case .fill: "arrow.up.left.and.arrow.down.right"
        case .stretch: "arrow.left.and.right.square"
        }
    }
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
    @MainActor func setZoom(_ zoom: VideoZoom) { layerView.playerLayer.videoGravity = zoom.gravity }
    @MainActor func setPictureInPictureActive(_ active: Bool) {}
    @MainActor func subtitleOverlay(lifted: Bool, look: SubtitleLook, delay: Double) -> AnyView { AnyView(EmptyView()) }   // AVPlayerLayer pinta los suyos
    var drawsSubtitles: Bool { false }
    @MainActor func subtitleLines(from seconds: Double, count: Int) -> [SubtitleLine] { [] }
    @MainActor var shownTime: Double { player.currentTime().seconds }

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
    /// AVPlayer se rearma solo; lo que no recupera es un elemento que falló (la conexión se cortó estando suspendida).
    func restoreAfterBackground(resume: Bool) async -> Bool {
        await MainActor.run {
            guard let item = player.currentItem, item.status != .failed, player.error == nil else { return false }
            if resume { player.play() }
            return true
        }
    }
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
