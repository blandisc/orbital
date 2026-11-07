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

extension EngineSnapshot {
    /// Igual salvo la posición (lo que cambia cuatro veces por segundo mientras suena).
    func sameExceptPosition(_ other: EngineSnapshot) -> Bool {
        var a = self
        a.position = other.position
        return a == other
    }
}

/// La posición y la duración del video, aparte del `PlayerModel`: solo lo que se mueve con el video (la barra de avance y sus
/// tiempos, la pantalla del iPod) se vuelve a pintar cuatro veces por segundo, no la pantalla entera del reproductor.
@MainActor
public final class PlayerTime: ObservableModel {
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0

    func update(position: Double, duration: Double) {
        guard position != self.position || duration != self.duration else { return }
        self.position = position; self.duration = duration
        changed()
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
    /// El título que va a sonar (el motor recuerda por título en qué pista viene cada variante de español).
    func prepare(titleKey: String) async
    var snapshots: AsyncStream<EngineSnapshot> { get }
    /// Al volver de segundo plano: rearma lo que el sistema le quitó al video (el motor suelta el decodificador y la conexión
    /// al irse a segundo plano en pausa) en el mismo punto, y sigue sonando si `resume`. `false`: no pudo (la fuente ya no
    /// contesta o su enlace caducó) y hay que volver a pedir el video.
    func restoreAfterBackground(resume: Bool) async -> Bool
}

public extension PlayerEngine {
    func restoreAfterBackground(resume: Bool) async -> Bool { true }
    func setRate(_ rate: Float) async {}
    func prepare(audioLanguages: [String], subtitleLanguages: [String], externalSubtitles: [URL]) async {}
    func prepare(titleKey: String) async {}
}
