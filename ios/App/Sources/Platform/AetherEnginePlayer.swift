// AetherEngine: el motor principal (FFmpeg + VideoToolbox: MKV, HDR10, Dolby Vision, Atmos, PGS/ASS, PiP).
// https://github.com/superuser404notfound/AetherEngine (LGPL-3.0 con excepción de App Store). Fijar la versión exacta.
//
// Revisado contra el código fuente de la versión 7.35.1 (nombres de miembros y tipos), pero NO compilado ni probado en un iPhone.
// Si el nombre de algún miembro cambió, el compilador lo marcará aquí y solo aquí. Se activa con la bandera de compilación
// AETHER_ENGINE (en project.yml); sin ella la app usa AVPlayer y compila igual.
#if AETHER_ENGINE
import AetherEngine
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
        Publishers.MergeMany(changes).sink { [weak self] in self?.publish() }.store(in: &cancellables)
    }

    func load(url: URL, startAt: Double) async throws {
        hub.send(EngineSnapshot(state: .loading))
        try await engine.load(url: url, startPosition: startAt)
        engine.play()
    }

    func play() async { engine.play() }
    func pause() async { engine.pause() }
    func seek(to seconds: Double) async { await engine.seek(to: seconds) }
    func stop() async { engine.stop(); hub.send(EngineSnapshot(state: .idle)) }
    // Los ids de pista son los de AetherEngine (`TrackInfo.id`), no la posición en la lista.
    func selectAudio(_ id: Int?) async { if let id { engine.selectAudioTrack(index: id) } }
    func selectSubtitle(_ id: Int?) async { if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() } }
    func addSubtitle(url: URL, language: String?) async {
        _ = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: url, name: language ?? "Externo", language: language))
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
#endif
