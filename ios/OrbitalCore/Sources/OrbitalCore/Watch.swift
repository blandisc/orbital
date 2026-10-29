import Foundation

/// Constantes de reproducción (las mismas que `playback.py`).
public enum PlaybackRules {
    public static let startupTimeout: TimeInterval = 45      // s sin imagen: esa fuente no sirve, se prueba otra
    public static let saveEvery: TimeInterval = 60           // s entre guardados del avance en Stremio
    public static let rememberChoiceAfter: Double = 60       // s vistos: desde ahí se recuerda la fuente y las pistas (como la TV)
    public static let upNextLookahead: TimeInterval = 180    // s antes del final: se busca ya el siguiente episodio
    public static let upNextAt: TimeInterval = 30            // s antes del final (o al empezar los créditos): tarjeta
    public static let upNextCountdown: TimeInterval = 8
    public static let stillWatchingAfter = 3                 // episodios seguidos sin tocar la pantalla → «¿Sigues viendo?»
    public static let streamScrubInterval: UInt64 = 250_000_000   // ns entre búsquedas al arrastrar la barra de un video de internet
    public static let maxSourceRetries = 4                   // «otra fuente si falla»
    public static let skipSeconds: Double = 10               // los botones y el doble toque de ±10 s
    public static let fastForwardRate: Float = 2             // mantener el dedo en el gesto de 2×
    /// Un salto de más de esto (adelantar, regresar, otra fuente) se le vuelve a avisar a Trakt: su «Viendo ahora»
    /// calcula a qué hora terminas con el avance del último aviso (como lo hace Infuse).
    public static let rescrobbleJump: Double = 30
    /// Menos de 1 % (lo abriste un momento): no ensucia «Seguir viendo».
    public static let continueMinProgress = 0.01
    /// Se abrió y cerró sin ver nada: no se toca tu biblioteca.
    public static let minWatchedToSave: TimeInterval = 20
    public static let minPositionToSave: TimeInterval = 60

    static let intro = try! NSRegularExpression(pattern: #"\b(intro|opening|op|recap|previously|resumen|anteriormente|apertura)\b"#, options: [.caseInsensitive])
    static let credits = try! NSRegularExpression(pattern: #"\b(credits?|ending|ed|outro|créditos|creditos)\b"#, options: [.caseInsensitive])

    public enum ChapterKind: Sendable, Equatable { case intro, credits }

    /// «intro» (se puede saltar), «credits» (aparece el siguiente episodio) o nil.
    public static func chapterKind(_ title: String) -> ChapterKind? {
        let range = NSRange(title.startIndex..., in: title)
        if credits.firstMatch(in: title, range: range) != nil { return .credits }
        if intro.firstMatch(in: title, range: range) != nil { return .intro }
        return nil
    }

    /// ¿Toca mostrar «Siguiente episodio»? A `upNextAt` s del final, o al empezar los créditos.
    public static func shouldShowUpNext(position: TimeInterval, duration: TimeInterval, inCredits: Bool = false) -> Bool {
        guard duration > 0 else { return false }
        return inCredits || duration - position <= upNextAt
    }

    /// Minutos que faltan (0 si falta menos de uno): la interfaz arma «quedan 1 h 40 min» en su idioma.
    public static func minutesLeft(_ seconds: Double) -> Int { Vocabulary.minutesLeft(seconds: seconds) }

    /// «quedan 11 min» / «quedan 1 h 40 min» (vacío si falta menos de un minuto): ver `Vocabulary.timeLeft`.
    public static func timeLeft(_ seconds: Double) -> String { Vocabulary.timeLeft(seconds: seconds) }

    /// Código de pista («spa», «es-MX», «eng») → el de Ajustes («es», «en»); «» = sin subtítulos; nil si es otro idioma.
    public static func languageCode(_ code: String?) -> String? {
        if code == "" { return "" }
        let lower = (code ?? "").lowercased()
        if lower.hasPrefix("es") || lower.hasPrefix("spa") { return "es" }
        if lower.hasPrefix("en") { return "en" }
        return nil
    }
}

/// Lo que se sabe de lo que se está viendo, para guardar el avance. `originalTitle` es el nombre de Cinemeta
/// (en inglés), NUNCA el traducido: es lo que se escribe en tu cuenta de Stremio.
public struct ProgressEvent: Sendable, Equatable, Codable {
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var originalTitle: String
    public var position: Double
    public var duration: Double
    public var watched: Double       // segundos vistos desde el guardado anterior
    public var at: Double            // cuándo ocurrió (epoch)
    public var finished: Bool        // se terminó (o se pasó al siguiente): se marca como visto aunque falte un poco

    public init(kind: String, metaID: String, videoID: String, originalTitle: String, position: Double, duration: Double, watched: Double, at: Double, finished: Bool = false) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.originalTitle = originalTitle
        self.position = position; self.duration = duration; self.watched = watched; self.at = at; self.finished = finished
    }

    /// Tolerante con lo guardado antes: un campo nuevo no hace perder la cola entera.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(String.self, forKey: .kind); metaID = try c.decode(String.self, forKey: .metaID); videoID = try c.decode(String.self, forKey: .videoID)
        originalTitle = try c.decodeIfPresent(String.self, forKey: .originalTitle) ?? ""
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0; duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        watched = try c.decodeIfPresent(Double.self, forKey: .watched) ?? 0; at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
    }
    enum Keys: String, CodingKey { case kind, metaID, videoID, originalTitle, position, duration, watched, at, finished }
}

/// Dónde seguir: el segundo exacto (lo de este teléfono, o Trakt convertido con la duración conocida) o, si de Trakt solo se
/// sabe el porcentaje y aún no la duración, la fracción (0–1) para buscarla en cuanto el reproductor la diga.
public struct ResumePoint: Sendable, Equatable {
    public var seconds: Double
    public var fraction: Double?
    /// Segundos que se regresan al usar la fracción (vino de otro aparato).
    public var rewind: Double = 0
    public init(seconds: Double = 0, fraction: Double? = nil, rewind: Double = 0) { self.seconds = seconds; self.fraction = fraction; self.rewind = rewind }
    public static let start = ResumePoint()
    /// Al seguir donde ibas en OTRO aparato se regresan 10 s (como la consola): cubre el redondeo de Trakt y los logos.
    public static let otherDeviceRewind = 10.0

    /// El segundo donde seguir con una duración ya conocida (0 si no se sabe dónde).
    public func seconds(duration: Double) -> Double {
        guard let fraction else { return seconds }
        return duration > 0 ? max(0, fraction * duration - rewind) : seconds
    }

    /// Lo MÁS RECIENTE entre este teléfono y la pausa de Trakt (`paused_at`, `progress`): así se sigue donde lo dejaste en
    /// otro aparato aunque aquí no se haya visto. El porcentaje de Trakt se vuelve segundos con la duración que este teléfono
    /// conoce de ese mismo video; sin ella, queda como fracción (el reproductor la usa con la duración del archivo).
    public static func latest(local entry: LibraryEntry?, videoID: String, trakt: TraktPlayback?) -> ResumePoint {
        let same = entry.map { $0.videoID == videoID && !$0.nextUp } ?? false
        var mine = ResumePoint.start
        if same, let entry, entry.position > 0,
           !StremioLibrary.finished(position: entry.position, duration: entry.duration, kind: entry.kind) {
            mine = entry.fraction.map { ResumePoint(seconds: entry.position, fraction: $0, rewind: otherDeviceRewind) } ?? ResumePoint(seconds: entry.position)
        }
        guard let trakt else { return mine }
        // Lo de aquí es más nuevo (o es lo que este teléfono mismo le mandó a Trakt): manda aquí.
        if same, let entry, trakt.pausedAt.timeIntervalSince1970 <= entry.localStamp { return mine }
        let fraction = trakt.progress / 100
        // Casi nada, o ya casi visto (Trakt lo marca visto desde el 80 %): lo de aquí.
        guard fraction >= PlaybackRules.continueMinProgress, fraction < StremioLibrary.watchedAt else { return mine }
        if same, let entry, entry.duration > 0, entry.fraction == nil {
            return ResumePoint(seconds: max(0, fraction * entry.duration - otherDeviceRewind))
        }
        return ResumePoint(seconds: 0, fraction: fraction, rewind: otherDeviceRewind)
    }
}

/// Lo que espera para subirse cuando vuelva la red: la copia a Stremio, y lo que va a Trakt (vistos, desmarcados, tu avance y
/// lo que quitaste de «Seguir viendo»). Lo del teléfono ya quedó guardado: esto solo es el viaje.
public struct PendingWork: Sendable, Equatable, Codable {
    /// La copia a Stremio (mientras dure la prueba).
    public var progress: [ProgressEvent] = []
    public var traktWatched: [TraktWatched] = []
    /// «Marcar como no vista» que aún no llega a Trakt (y que una sincronización no debe regresar).
    public var traktUnwatched: [TraktTarget] = []
    /// Tu avance que no llegó a Trakt: al volver la red se manda solo si Trakt no tiene uno más nuevo.
    public var traktProgress: [ProgressEvent] = []
    /// Lo que quitaste de «Seguir viendo» (id del título y cuándo): se borra de Trakt lo que estaba a medias hasta esa hora.
    public var playbackRemovals: [TraktWatched] = []
    public init() {}
    public struct TraktWatched: Sendable, Equatable, Codable {
        public var target: TraktTarget
        public var at: Double
        public init(target: TraktTarget, at: Double) { self.target = target; self.at = at }
    }
    public var isEmpty: Bool { progress.isEmpty && traktWatched.isEmpty && traktUnwatched.isEmpty && traktProgress.isEmpty && playbackRemovals.isEmpty }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        progress = try c.decodeIfPresent([ProgressEvent].self, forKey: .progress) ?? []
        traktWatched = try c.decodeIfPresent([TraktWatched].self, forKey: .traktWatched) ?? []
        traktUnwatched = try c.decodeIfPresent([TraktTarget].self, forKey: .traktUnwatched) ?? []
        traktProgress = try c.decodeIfPresent([ProgressEvent].self, forKey: .traktProgress) ?? []
        playbackRemovals = try c.decodeIfPresent([TraktWatched].self, forKey: .playbackRemovals) ?? []
    }
    enum Keys: String, CodingKey { case progress, traktWatched, traktUnwatched, traktProgress, playbackRemovals }
}

public protocol PendingStore: Sendable {
    func load() -> PendingWork
    func save(_ work: PendingWork)
}

public final class InMemoryPendingStore: PendingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var work = PendingWork()
    public init() {}
    public func load() -> PendingWork { lock.withLock { work } }
    public func save(_ work: PendingWork) { lock.withLock { self.work = work } }
}

/// La cola en un archivo JSON (Application Support): sobrevive a que cierren la app.
public final class FilePendingStore: PendingStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    public init(url: URL) { self.url = url }
    public func load() -> PendingWork {
        lock.withLock { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PendingWork.self, from: $0) } ?? PendingWork() }
    }
    public func save(_ work: PendingWork) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(work) { try? data.write(to: url, options: .atomic) }
        }
    }
}

public enum PlaybackPhase: Sendable, Equatable {
    case started                  // empezó o reanudó
    case tick                     // cada minuto
    case paused
    /// La app se fue a segundo plano (el audio puede seguir sonando): se guarda y a Trakt se le manda una pausa.
    case background
    case stopped(finished: Bool)  // se cerró el reproductor (finished: llegó al final)
}

public struct ReportOutcome: Sendable, Equatable {
    /// Quedó guardado en el teléfono.
    public var saved = false
    /// La copia a Stremio quedó en la cola (sin conexión).
    public var queued = false
}

/// Un solo vaciado de la cola a la vez en toda la app (aunque se rearmen los servicios al cambiar una clave).
public final class FlushGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    public init() {}
    func enter() -> Bool { lock.withLock { if busy { return false }; busy = true; return true } }
    func leave() { lock.withLock { busy = false } }
}

enum WatchError: Error, CustomStringConvertible {
    case noTitle
    var description: String { "No encontré ese título." }
}

