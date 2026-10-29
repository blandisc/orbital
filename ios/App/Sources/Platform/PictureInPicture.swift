import AVKit
import MediaPlayer
import SwiftUI
import OrbitalCore
import OrbitalModels

/// Lo que un motor ofrece para PiP: la capa del video (AVPlayer) o una capa de muestras con quien la controle
/// (la vía por software de AetherEngine: MKV, PGS…).
enum PictureInPictureContent {
    case playerLayer(AVPlayerLayer)
    case sampleBuffer(AVSampleBufferDisplayLayer, AVPictureInPictureSampleBufferPlaybackDelegate)

    var layer: CALayer {
        switch self { case .playerLayer(let l): l; case .sampleBuffer(let l, _): l }
    }
}

/// Imagen dentro de imagen: el botón del reproductor y, al salir de la app con el video sonando, la ventana sola.
@MainActor
@Observable
final class PictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    private(set) var isPossible = false
    private(set) var isActive = false
    /// El motor necesita saberlo (AetherEngine mantiene el video vivo en segundo plano y cambia de episodio sin cerrar la ventana).
    @ObservationIgnored var onActiveChange: (Bool) -> Void = { _ in }
    /// Al volver de la ventana a la app: el reproductor vuelve a pantalla completa.
    @ObservationIgnored var onRestore: () -> Void = {}

    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var sampleDelegate: AVPictureInPictureSampleBufferPlaybackDelegate?
    @ObservationIgnored private weak var layer: CALayer?
    @ObservationIgnored private var possible: NSKeyValueObservation?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// Arma (o rearma, si el motor cambió de capa al cambiar de fuente) el controlador para este contenido.
    func update(_ content: PictureInPictureContent?) {
        guard Self.isSupported, !isActive else { return }
        guard let content else { controller = nil; layer = nil; isPossible = false; return }
        if content.layer === layer { return }
        let source: AVPictureInPictureController.ContentSource
        switch content {
        case .playerLayer(let l): source = .init(playerLayer: l); sampleDelegate = nil
        case .sampleBuffer(let l, let delegate): source = .init(sampleBufferDisplayLayer: l, playbackDelegate: delegate); sampleDelegate = delegate
        }
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true   // sales de la app con el video sonando: sigue en una ventana
        possible = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            let value = pip.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = value }
        }
        controller = pip
        layer = content.layer
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() } else { controller.startPictureInPicture() }
    }

    func stop() { controller?.stopPictureInPicture() }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isActive = true; onActiveChange(true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isActive = false; onActiveChange(false) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in onRestore(); completionHandler(true) }
    }
}

/// El botón de AirPlay del sistema (elige el televisor o las bocinas).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor(DS.text)
        view.activeTintColor = UIColor(DS.good)
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Lo que se ve en la pantalla bloqueada y en el Centro de control, y sus botones (pausa, ±10 s, mover la barra).
@MainActor
final class NowPlaying {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkURL: String?
    private var artwork: MPMediaItemArtwork?

    func start(model: PlayerModel) {
        let center = MPRemoteCommandCenter.shared()
        let skip = NSNumber(value: PlaybackRules.skipSeconds)
        center.skipForwardCommand.preferredIntervals = [skip]
        center.skipBackwardCommand.preferredIntervals = [skip]
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) async -> Void) {
            command.isEnabled = true
            targets.append((command, command.addTarget { event in Task { @MainActor in await action(event) }; return .success }))
        }
        on(center.playCommand) { _ in if model.snapshot.state != .playing { await model.togglePlay() } }
        on(center.pauseCommand) { _ in if model.snapshot.state == .playing { await model.togglePlay() } }
        on(center.togglePlayPauseCommand) { _ in await model.togglePlay() }
        on(center.skipForwardCommand) { _ in await model.skip(PlaybackRules.skipSeconds) }
        on(center.skipBackwardCommand) { _ in await model.skip(-PlaybackRules.skipSeconds) }
        on(center.changePlaybackPositionCommand) { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { await model.seek(to: event.positionTime) }
        }
    }

    func update(title: String, subtitle: String, poster: String?, snapshot: EngineSnapshot) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: subtitle.isEmpty ? title : subtitle,
            MPMediaItemPropertyArtist: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.state == .playing ? 1.0 : 0.0,
        ]
        if snapshot.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(poster)
    }

    /// El póster para la pantalla bloqueada (una sola descarga por título).
    private func loadArtwork(_ poster: String?) {
        guard let poster, poster != artworkURL, let url = URL(string: poster) else { return }
        artworkURL = poster
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            artwork = Self.artwork(image)
        }
    }

    /// iOS pide la imagen desde su propia cola (no el hilo principal): armada aquí, fuera del actor principal, la función que
    /// la entrega no exige el hilo principal. Dentro de la clase (`@MainActor`) heredaba el aislamiento y en modo Swift 6 la
    /// app tronaba al empezar a reproducir con carátula (`dispatch_assert_queue`).
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func stop() {
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
