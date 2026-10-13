import Foundation

/// Constantes de reproducción (las mismas que `playback.py`).
public enum PlaybackRules {
    public static let startupTimeout: TimeInterval = 45      // s sin imagen: esa fuente no sirve, se prueba otra
    public static let saveEvery: TimeInterval = 60           // s entre guardados del avance en Stremio
    public static let upNextLookahead: TimeInterval = 180    // s antes del final: se busca ya el siguiente episodio
    public static let upNextAt: TimeInterval = 30            // s antes del final (o al empezar los créditos): tarjeta
    public static let upNextCountdown: TimeInterval = 8
    public static let stillWatchingAfter = 3                 // episodios seguidos sin tocar la pantalla → «¿Sigues viendo?»
    public static let maxSourceRetries = 4                   // «otra fuente si falla»
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

    /// «quedan 11 min» / «quedan 1 h 40 min» (vacío si falta menos de un minuto).
    public static func timeLeft(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 1 else { return "" }
        let (h, m) = (minutes / 60, minutes % 60)
        return h > 0 && m > 0 ? "quedan \(h) h \(m) min" : h > 0 ? "quedan \(h) h" : "quedan \(m) min"
    }

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

    public init(kind: String, metaID: String, videoID: String, originalTitle: String, position: Double, duration: Double, watched: Double, at: Double) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.originalTitle = originalTitle
        self.position = position; self.duration = duration; self.watched = watched; self.at = at
    }
}

/// Lo que espera para subirse cuando vuelva la red (avance a Stremio y vistos a Trakt).
public struct PendingWork: Sendable, Equatable, Codable {
    public var progress: [ProgressEvent] = []
    public var traktWatched: [TraktWatched] = []
    public init() {}
    public struct TraktWatched: Sendable, Equatable, Codable {
        public var target: TraktTarget
        public var at: Double
        public init(target: TraktTarget, at: Double) { self.target = target; self.at = at }
    }
    public var isEmpty: Bool { progress.isEmpty && traktWatched.isEmpty }
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
    case stopped(finished: Bool)  // se cerró el reproductor (finished: llegó al final)
}

public struct ReportOutcome: Sendable, Equatable {
    public var savedToStremio = false
    public var queued = false
}

/// Guarda lo que ves: en tu cuenta de Stremio (eje de todo, lo leen la app, Orbital y Stremio) y en Trakt
/// (scrobble). Lo que no se pueda subir (sin internet) espera en una cola y se sube al volver, sin pisar
/// cambios más nuevos hechos en otro lado.
public actor WatchService {
    private let stremio: StremioAPI
    private let authKey: @Sendable () -> String?
    private let cinemeta: Cinemeta
    private let trakt: Trakt?
    private let pending: PendingStore
    private let clock: @Sendable () -> Date

    public init(stremio: StremioAPI, authKey: @escaping @Sendable () -> String?, cinemeta: Cinemeta, trakt: Trakt? = nil,
                pending: PendingStore, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.stremio = stremio; self.authKey = authKey; self.cinemeta = cinemeta; self.trakt = trakt; self.pending = pending; self.clock = clock
    }

    func authKeyValue() -> String? { authKey() }
    func stremioClient() -> StremioAPI { stremio }

    /// Dónde ibas según Stremio (0 si no se sabe).
    public func resumePosition(metaID: String, videoID: String) async -> Double {
        guard let key = authKey(), let item = try? await stremio.libraryItem(authKey: key, id: metaID) else { return 0 }
        return StremioLibrary.resumeSeconds(item, videoID: videoID)
    }

    /// `scrobbleToTrakt: false` para Infuse, que ya avisa a Trakt con su propia conexión (así no se duplica).
    @discardableResult
    public func report(_ event: ProgressEvent, phase: PlaybackPhase, scrobbleToTrakt: Bool = true) async -> ReportOutcome {
        var outcome = ReportOutcome()
        if scrobbleToTrakt { await scrobble(event, phase) }
        switch phase {
        case .started: return outcome
        case .tick, .paused:
            outcome = await saveProgress(event, final: false)
        case .stopped:
            outcome = await saveProgress(event, final: true)
        }
        return outcome
    }

    private func scrobble(_ event: ProgressEvent, _ phase: PlaybackPhase) async {
        guard let trakt, trakt.linked, let target = TraktTarget(videoID: event.videoID, kind: event.kind), event.duration > 0 else { return }
        let percent = min(100, max(0, event.position / event.duration * 100))
        let action: ScrobbleAction
        switch phase {
        case .started: action = .start
        case .tick: return                 // Trakt ya sabe que sigues viendo
        case .paused: action = .pause
        case .stopped: action = .stop
        }
        do { try await trakt.scrobble(action, target, progress: percent) }
        catch let error as TraktError {
            // Sin internet al terminar: lo visto (≥ 80 %) se sube después con su fecha real.
            if case .network = error, case .stopped = phase, percent >= 80 {
                var work = pending.load()
                work.traktWatched.append(.init(target: target, at: event.at))
                pending.save(work)
            }
        } catch {}
    }

    /// Guarda en Stremio dónde te quedaste. `final`: se cerró el reproductor.
    private func saveProgress(_ event: ProgressEvent, final: Bool) async -> ReportOutcome {
        var outcome = ReportOutcome()
        guard authKey() != nil else { return outcome }
        if final && event.watched < PlaybackRules.minWatchedToSave && event.position < PlaybackRules.minPositionToSave { return outcome }
        do {
            try await write(event)
            outcome.savedToStremio = true
        } catch {
            var work = pending.load()
            work.progress.append(event)
            pending.save(work)
            outcome.queued = true
        }
        return outcome
    }

    private func write(_ event: ProgressEvent) async throws {
        guard let key = authKey() else { return }
        let info = try? await cinemeta.meta(kind: event.kind, id: event.metaID)  // la ficha ORIGINAL
        let videoIDs = info.map { CinemetaParsing.seasonVideoIDs($0) } ?? []
        let next = event.kind == "series" ? info.flatMap { CinemetaParsing.nextEpisode($0, after: event.videoID) } : nil
        let raw = try await stremio.libraryItem(authKey: key, id: event.metaID)
        let item = StremioLibrary.withProgress(
            raw, metaID: event.metaID, kind: event.kind, name: info?["name"]?.nonEmptyString ?? event.originalTitle, poster: info?["poster"]?.string,
            videoID: event.videoID, position: event.position, duration: event.duration, watched: event.watched, nextVideo: next,
            now: event.at, videoIDs: videoIDs.isEmpty ? nil : videoIDs)
        try await stremio.saveLibraryItem(authKey: key, item: item)
    }

    /// Sube lo que quedó esperando. Un avance viejo no pisa algo más nuevo hecho en otro dispositivo (Orbital, Stremio).
    @discardableResult
    public func flushPending() async -> PendingWork {
        var work = pending.load()
        guard !work.isEmpty else { return work }
        var remaining = PendingWork()
        for event in work.progress.sorted(by: { $0.at < $1.at }) {
            guard let key = authKey() else { remaining.progress.append(event); continue }
            do {
                if let raw = try await stremio.libraryItem(authKey: key, id: event.metaID),
                   let newer = StremioLibrary.epoch(raw["_mtime"]), newer > event.at + 1 { continue }  // el remoto es más nuevo: no se pisa
                try await write(event)
            } catch { remaining.progress.append(event) }
        }
        for watched in work.traktWatched {
            guard let trakt, trakt.linked else { remaining.traktWatched.append(watched); continue }
            do { try await trakt.addToHistory(watched.target, watchedAt: Date(timeIntervalSince1970: watched.at)) }
            catch let error as TraktError { if case .network = error { remaining.traktWatched.append(watched) } } catch {}
        }
        work = remaining
        pending.save(work)
        return work
    }

    // MARK: biblioteca de Stremio
    public func library() async throws -> [Watchable] {
        guard let key = authKey() else { throw StremioError.api("Conecta tu cuenta de Stremio en Ajustes") }
        return StremioLibrary.parseLibrary(try await stremio.library(authKey: key))
    }

    /// «Seguir viendo»: lo que dejaste a medias (o el siguiente episodio), sin lo que abriste un momento.
    public func continueWatching() async throws -> [Watchable] {
        try await library().filter { w in
            guard w.inContinue else { return false }
            let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.episode.episode != nil
            return nextUp || (w.progress ?? 1) >= PlaybackRules.continueMinProgress
        }
    }

    public func setInLibrary(kind: String, metaID: String, title: String, poster: String?, add: Bool) async throws {
        guard let key = authKey() else { throw StremioError.api("Conecta tu cuenta de Stremio en Ajustes") }
        let raw = try await stremio.libraryItem(authKey: key, id: metaID)
        try await stremio.saveLibraryItem(authKey: key, item: StremioLibrary.libraryToggled(raw, metaID: metaID, kind: kind, name: title, poster: poster, add: add, now: clock().timeIntervalSince1970))
    }

    /// «Quitar de Seguir viendo».
    public func dismissContinue(metaID: String) async throws {
        guard let key = authKey(), let raw = try await stremio.libraryItem(authKey: key, id: metaID) else { return }
        try await stremio.saveLibraryItem(authKey: key, item: StremioLibrary.dismissed(raw, now: clock().timeIntervalSince1970))
    }
}

extension CinemetaParsing {
    /// Los ids de todos los videos en el orden del catálogo (para el bitfield de «visto»).
    public static func seasonVideoIDs(_ meta: JSON) -> [String] {
        (meta["videos"]?.array ?? []).compactMap { $0["id"]?.nonEmptyString }
    }
}

extension WatchService {
    /// El libraryItem tal cual lo guarda Stremio (para leer el bitfield de «visto» y dónde ibas).
    public func rawItem(metaID: String) async -> JSON? {
        guard let key = authKeyValue(), let item = try? await stremioClient().libraryItem(authKey: key, id: metaID) else { return nil }
        return item
    }
}
