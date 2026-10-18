import Foundation
import OrbitalCore

public struct Chapter: Sendable, Equatable { public var title: String; public var time: Double
    public init(title: String, time: Double) { self.title = title; self.time = time } }

public enum EngineState: Sendable, Equatable { case idle, loading, buffering, playing, paused, ended, failed(String) }

/// Lo que el motor sabe en un momento (se emite unas 10 veces por segundo).
public struct EngineSnapshot: Sendable, Equatable {
    public var state: EngineState
    public var position: Double
    public var duration: Double
    public var audioTracks: [MediaTrack]
    public var subtitleTracks: [MediaTrack]
    public var selectedAudio: Int?
    public var selectedSubtitle: Int?
    public var chapters: [Chapter]

    public init(state: EngineState = .idle, position: Double = 0, duration: Double = 0, audioTracks: [MediaTrack] = [], subtitleTracks: [MediaTrack] = [],
                selectedAudio: Int? = nil, selectedSubtitle: Int? = nil, chapters: [Chapter] = []) {
        self.state = state; self.position = position; self.duration = duration; self.audioTracks = audioTracks; self.subtitleTracks = subtitleTracks
        self.selectedAudio = selectedAudio; self.selectedSubtitle = selectedSubtitle; self.chapters = chapters
    }
}

/// El reproductor de video. El motor principal es AetherEngine; SwiftVLC es el repuesto; Infuse es otra vía
/// (`Infuse`), que no es un motor porque no informa mientras se reproduce.
public protocol PlayerEngine: AnyObject, Sendable {
    func load(url: URL, startAt: Double) async throws
    func play() async
    func pause() async
    func seek(to seconds: Double) async
    func stop() async
    func selectAudio(_ id: Int?) async
    func selectSubtitle(_ id: Int?) async
    func addSubtitle(url: URL, language: String?) async
    /// Velocidad (1 = normal). El motor la regresa a 1 con cada video nuevo; el modelo la vuelve a poner.
    func setRate(_ rate: Float) async
    /// Lo que conviene saber antes de abrir el video: el idioma del audio y de los subtítulos que quieres (se eligen desde el
    /// primer cuadro) y los subtítulos externos que ya se tienen (una descarga), declarados al cargar para que también salgan
    /// en la ventana de PiP.
    func prepare(audioLanguages: [String], subtitleLanguages: [String], externalSubtitles: [URL]) async
    var snapshots: AsyncStream<EngineSnapshot> { get }
}

public extension PlayerEngine {
    func setRate(_ rate: Float) async {}
    func prepare(audioLanguages: [String], subtitleLanguages: [String], externalSubtitles: [URL]) async {}
}
