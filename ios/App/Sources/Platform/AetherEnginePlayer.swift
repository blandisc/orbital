// AetherEngine: el motor principal (FFmpeg + VideoToolbox: MKV, HDR10, Dolby Vision, Atmos, PGS/ASS, PiP).
// https://github.com/superuser404notfound/AetherEngine (LGPL-3.0 con excepción de App Store). Fijar la versión exacta.
//
// Revisado contra el código fuente de la versión 7.35.1 (nombres de miembros y tipos), pero NO compilado ni probado en un iPhone.
// Si el nombre de algún miembro cambió, el compilador lo marcará aquí y solo aquí. Se activa con la bandera de compilación
// AETHER_ENGINE (en project.yml); sin ella la app usa AVPlayer y compila igual.
#if AETHER_ENGINE
import AetherEngine
import AVKit
import Combine
import SwiftUI
import OrbitalCore
import OrbitalModels

@MainActor
final class AetherEnginePlayer: VideoPlayerEngine, @unchecked Sendable {
    nonisolated let name = "AetherEngine"
    private let engine: AetherEngine
    private let hub = SnapshotHub()
    private var cancellables = Set<AnyCancellable>()
    private var external: [(url: URL, language: String?)] = []

    nonisolated var snapshots: AsyncStream<EngineSnapshot> { hub.makeStream() }
    var surface: AnyView { AnyView(AetherPlayerSurface(engine: engine).ignoresSafeArea()) }

    init() {
        engine = try! AetherEngine()
        // Cada cambio relevante vuelve a armar la «foto» completa.
        let changes: [AnyPublisher<Void, Never>] = [
            engine.$state.map { _ in () }.eraseToAnyPublisher(),
            engine.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
            engine.clock.$currentTime.map { _ in () }.eraseToAnyPublisher(),
            engine.$duration.map { _ in () }.eraseToAnyPublisher(),
            engine.$audioTracks.map { _ in () }.eraseToAnyPublisher(),
            engine.$subtitleTracks.map { _ in () }.eraseToAnyPublisher(),
            engine.$activeAudioTrackIndex.map { _ in () }.eraseToAnyPublisher(),
            engine.$activeSubtitleTrackIndex.map { _ in () }.eraseToAnyPublisher(),
            engine.$mediaChapters.map { _ in () }.eraseToAnyPublisher(),
        ]
        // `@Published` avisa ANTES de cambiar el valor: leer `engine.state` en el mismo instante daba el estado viejo
        // (al pausar, la foto seguía diciendo «reproduciendo» y, con el reloj ya quieto, el botón se quedaba en pausa).
        // Se lee en la siguiente vuelta del hilo principal, cuando el valor ya cambió.
        Publishers.MergeMany(changes).receive(on: DispatchQueue.main).sink { [weak self] in self?.publish() }.store(in: &cancellables)
    }

    func load(url: URL, startAt: Double) async throws {
        hub.send(EngineSnapshot(state: .loading))
        var options = LoadOptions()
        // Los subtítulos de texto también como pista nativa: así salen en la ventana de PiP y en AirPlay (sin esto, en PiP no
        // había subtítulos).
        options.prepareNativeSubtitles = true
        options.preferredAudioLanguages = preferredAudio
        options.preferredSubtitleLanguages = preferredSubtitles
        options.externalSubtitles = declaredExternal.map { ExternalSubtitleTrack(url: $0, name: $0.deletingPathExtension().lastPathComponent, language: Self.language(of: $0)) }
        try await engine.load(url: url, startPosition: startAt, options: options)
        engine.play()
    }

    private var preferredAudio: [String] = [], preferredSubtitles: [String] = [], declaredExternal: [URL] = []

    func prepare(audioLanguages: [String], subtitleLanguages: [String], externalSubtitles: [URL]) async {
        preferredAudio = audioLanguages; preferredSubtitles = subtitleLanguages; declaredExternal = externalSubtitles
    }

    /// «es-1.srt» → «es» (los subtítulos de una descarga empiezan con su idioma).
    private static func language(of url: URL) -> String? {
        let head = url.deletingPathExtension().lastPathComponent.split(separator: "-").first.map(String.init) ?? ""
        return head.count == 2 || head.count == 3 ? head : nil
    }

    var pictureInPicture: PictureInPictureContent? {
        // Vía nativa (MP4, HLS, MKV que AVPlayer abre): su capa. Vía por software (lo demás): la capa de muestras.
        if let layer = engine.nativePlayerLayer { return .playerLayer(layer) }
        if let source = engine.softwarePiPSource { return .sampleBuffer(source.layer, AetherSampleBufferPiP(source: source)) }
        return nil
    }
    func setFillsScreen(_ fill: Bool) { engine.videoGravity = fill ? .resizeAspectFill : .resizeAspect; fills = fill }
    private var fills = false

    /// AetherEngine no pinta subtítulos: entrega las líneas y la app las dibuja encima del video (su README: «your UI paints them»).
    var drawsSubtitles: Bool { true }
    func subtitleOverlay(lifted: Bool, heightFraction: Double, delay: Double) -> AnyView {
        AnyView(AetherSubtitleOverlay(engine: engine, clock: engine.clock, lifted: lifted, heightFraction: heightFraction, fills: fills, delay: delay))
    }
    func setPictureInPictureActive(_ active: Bool) {
        engine.pictureInPictureActive = active
        // En la ventana de PiP el subtítulo que dibujamos encima del video no existe: AVKit dibuja el suyo (la pista de
        // texto nativa del motor) mientras la ventana está fuera, y al volver a la app se quita (vuelve el nuestro).
        // No hay equivalente para subtítulos de imagen (PGS); los que se agregan después de cargar entran al rearmar (`addSubtitle`).
        engine.setNativeSubtitleRendering(active)
    }

    func setRate(_ rate: Float) async { engine.setRate(rate); currentRate = rate }
    private var currentRate: Float = 1

    func play() async { engine.play() }
    func pause() async { engine.pause() }
    func seek(to seconds: Double) async { await engine.seek(to: seconds) }
    func stop() async { engine.stop(); hub.send(EngineSnapshot(state: .idle)) }
    // Los ids de pista son los de AetherEngine (`TrackInfo.id`), no la posición en la lista.
    func selectAudio(_ id: Int?) async { if let id { engine.selectAudioTrack(index: id) } }
    func selectSubtitle(_ id: Int?) async { if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() } }
    /// Un subtítulo sumado a media reproducción el motor solo lo entrega para dibujarlo encima: no llega a la ventana de
    /// PiP. Se rearma la sesión en el mismo punto (conserva las pistas, la elegida y si iba en pausa) y así entra como pista
    /// nativa, igual que los que se declaran al cargar. Cuesta un instante de carga, una sola vez por subtítulo.
    func addSubtitle(url: URL, language: String?) async {
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: url, name: language ?? "Externo", language: language))
        guard engine.sessionReloadRefusal == nil else { return }
        engine.selectSubtitleTrack(index: track.id)
        try? await engine.reloadAtCurrentPosition()
        if currentRate != 1 { engine.setRate(currentRate) }
    }

    /// En segundo plano y en pausa (o tras la ventana de gracia de 15 s), AetherEngine suelta el decodificador y la conexión
    /// (`releaseVideoPipelineForBackground`) y deja al anfitrión el rearmado: `needsForegroundVideoRestore` lo avisa y
    /// `reloadAtCurrentPosition` lo hace. Sin esto, al volver la capa quedaba sin video (negro) para siempre.
    func restoreAfterBackground(resume: Bool) async -> Bool {
        var broken = false
        if case .error = engine.state { broken = true }
        guard engine.needsForegroundVideoRestore || broken else {
            if resume, engine.state == .paused { engine.play() }
            return true
        }
        guard engine.sessionReloadRefusal == nil else { return false }
        do { try await engine.reloadAtCurrentPosition() } catch { return false }
        if case .error = engine.state { return false }
        if resume { engine.play() } else { engine.pause() }
        if currentRate != 1 { engine.setRate(currentRate) }
        return true
    }

    private func publish() {
        let state: EngineState
        switch engine.state {
        case .idle: state = .idle
        case .loading: state = .loading
        case .playing: state = engine.isBuffering ? .buffering : .playing
        case .paused: state = .paused
        case .seeking: state = .buffering
        case .ended: state = .ended
        case .error(let message): state = .failed("\(message)")
        @unknown default: state = .paused
        }
        hub.send(EngineSnapshot(
            state: state, position: engine.clock.currentTime, duration: engine.duration,
            audioTracks: engine.audioTracks.map { MediaTrack(id: $0.id, kind: .audio, language: $0.language, title: $0.name, codec: $0.codec, isDefault: $0.isDefault) },
            subtitleTracks: engine.subtitleTracks.map { MediaTrack(id: $0.id, kind: .subtitle, language: $0.language, title: $0.name, isDefault: $0.isDefault, isForced: $0.isForced) },
            selectedAudio: engine.activeAudioTrackIndex, selectedSubtitle: engine.activeSubtitleTrackIndex,
            chapters: engine.mediaChapters.map { Chapter(title: $0.name, time: $0.startSeconds) }))
    }
}
/// Los subtítulos de AetherEngine dibujados sobre el video: las líneas que tocan según el reloj del cuadro que se ve
/// (`clock.sourceTime`), en texto (con color, negrita y cursiva del archivo) o como imagen (PGS de Blu-ray), colocados
/// sobre el rectángulo real del video (no sobre las franjas negras). Suben cuando están los controles para no taparse.
struct AetherSubtitleOverlay: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var clock: PlaybackClock
    let lifted: Bool
    let heightFraction: Double
    let fills: Bool
    /// La sincronía elegida (s): con +1 cada línea sale un segundo después.
    var delay: Double = 0

    var body: some View {
        GeometryReader { geo in
            let video = videoRect(in: geo.size)
            let now = clock.sourceTime - delay
            let active = engine.subtitleCues.filter { $0.startTime <= now && now < $0.endTime }
            ZStack(alignment: .topLeading) {
                ForEach(active.filter { if case .image = $0.body { true } else { false } }) { cue in
                    if case .image(let image) = cue.body { bitmap(image, in: video) }
                }
                let texts = active.filter { if case .image = $0.body { false } else { true } }
                if !texts.isEmpty { textBlock(texts, video: video, screen: geo.size) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(nil, value: now)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Dónde está el video en pantalla: lo mide la capa de AVPlayer (vía nativa) o se calcula con el tamaño del cuadro (software).
    private func videoRect(in size: CGSize) -> CGRect {
        if let layer = engine.nativePlayerLayer, !layer.videoRect.isEmpty { return layer.videoRect }
        guard let picture = engine.softwareDisplaySize, picture.width > 0, picture.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = fills ? max(size.width / picture.width, size.height / picture.height) : min(size.width / picture.width, size.height / picture.height)
        let w = picture.width * scale, h = picture.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func textBlock(_ cues: [SubtitleCue], video: CGRect, screen: CGSize) -> some View {
        // La parte del video que se ve (con «llenar pantalla» el video se sale por los lados).
        let visible = video.intersection(CGRect(origin: .zero, size: screen))
        let fontSize = max(DS.Subtitle.minFont, visible.height * heightFraction)
        let lift = lifted ? DS.Subtitle.liftWithControls : 0
        let placement = cues.compactMap(\.placement).first
        let top = placement?.alignment.map { (7...9).contains($0) } ?? false
        return VStack(spacing: fontSize * DS.Subtitle.lineGap) {
            ForEach(cues) { cue in line(cue, size: fontSize) }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, fontSize)
        // El margen va por dentro del rectángulo del video (si no, en un video que llena el alto la línea se sale por abajo).
        .padding(top ? .top : .bottom, visible.height * DS.Subtitle.edgeMargin + lift)
        .frame(width: visible.width, height: visible.height, alignment: top ? .top : .bottom)
        .offset(x: visible.minX, y: visible.minY)
    }

    /// Contorno oscuro (cuatro copias desplazadas, sin desenfoque) más una sombra suave detrás: se lee tanto sobre
    /// nieve como sobre un fondo negro, que es donde fallaba un solo `shadow` difuminado.
    private func line(_ cue: SubtitleCue, size: CGFloat) -> some View {
        let outline = size * DS.Subtitle.outlineWidth
        return styled(cue.body, size: size)
            .shadow(color: DS.subtitleShadow, radius: 0, x: -outline, y: 0)
            .shadow(color: DS.subtitleShadow, radius: 0, x: outline, y: 0)
            .shadow(color: DS.subtitleShadow, radius: 0, x: 0, y: -outline)
            .shadow(color: DS.subtitleShadow, radius: 0, x: 0, y: outline)
            .shadow(color: DS.subtitleShadow, radius: size * DS.Subtitle.shadowRadius)
    }

    private func styled(_ body: SubtitleCue.Body, size: CGFloat) -> Text {
        let base = Font.system(size: size, weight: .semibold)   // ds-exception: la letra se mide con el video, no con Dynamic Type
        switch body {
        case .text(let text):
            return Text(clean(text)).font(base).foregroundStyle(DS.subtitleText)
        case .richText(let runs):
            var text = AttributedString()
            for run in runs {
                var piece = AttributedString(clean(run.text))
                var font = base
                if run.isBold { font = font.bold() }
                if run.isItalic { font = font.italic() }
                piece.font = font
                if run.isUnderlined { piece.underlineStyle = .single }
                if run.isStruckThrough { piece.strikethroughStyle = .single }
                piece.foregroundColor = run.color.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) } ?? DS.subtitleText   // ds-exception: el color lo trae el archivo de subtítulos
                text += piece
            }
            return Text(text)
        case .image:
            return Text("")
        }
    }

    /// Saltos de línea de ASS (`\N`, `\n`) y espacios sobrantes.
    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Una imagen PGS/DVB: su lienzo se acomoda a lo ancho del video, centrado (como lo pide AetherEngine).
    private func bitmap(_ image: SubtitleImage, in video: CGRect) -> some View {
        var canvas = video
        if image.canvasSize.width > 0, image.canvasSize.height > 0 {
            let h = video.width * image.canvasSize.height / image.canvasSize.width
            canvas = CGRect(x: video.minX, y: video.midY - h / 2, width: video.width, height: h)
        }
        let frame = CGRect(x: canvas.minX + image.position.minX * canvas.width, y: canvas.minY + image.position.minY * canvas.height,
                           width: image.position.width * canvas.width, height: image.position.height * canvas.height)
        return Image(decorative: image.cgImage, scale: 1).resizable()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY - (lifted ? DS.Subtitle.liftWithControls : 0))
    }
}

/// Los botones de la ventana de PiP en la vía por software (pausa, ±10 s y la barra), contestados por AetherEngine.
final class AetherSampleBufferPiP: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private let source: SoftwarePiPSource
    init(source: SoftwarePiPSource) { self.source = source }

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { source.setPlaying(playing) }
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated { source.timeRange() }
    }
    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { source.isPaused }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated { source.skip(by: skipInterval.seconds) }
        completionHandler()
    }
}
#endif
