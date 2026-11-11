import Foundation

/// Lo que Trakt no aceptó y ya no se va a volver a intentar (F4): queda escrito para que la app lo pueda decir («No se pudo
/// guardar en Trakt: …») en vez de perderse sin rastro. Desde el 11 nov 2026 lo dice en Ajustes › Cuentas › Trakt, con qué
/// fue, cuándo y por qué en palabras llanas, y «Reintentar» para lo que venció.
public struct TraktDiscard: Codable, Equatable, Sendable {
    /// Qué era, en palabras cortas para la bitácora: «Mi lista · tt1160419», «Visto · tt0386676 T2 E5».
    public var what: String
    /// Por qué, para la bitácora: lo que dijo Trakt («Trakt respondió 422») o «venció».
    public var reason: String
    public var at: Double
    /// Qué era, para la pantalla (los de antes del 11 nov no lo traen).
    public var kind: Kind?
    /// El título (y el episodio) al que tocaba.
    public var target: TraktTarget?
    /// Cuántos eran (una temporada entera, varias vistas borradas).
    public var count: Int?
    /// Por qué, para la pantalla.
    public var cause: Cause?
    /// Lo que dijo Trakt (el código), si dijo algo.
    public var status: Int?
    /// Lo que vuelve a la cola con «Reintentar» (solo lo que venció: lo que Trakt rechazó, reintentarlo no lo arregla).
    public var retry: TraktRetry?

    public enum Kind: String, Codable, Sendable { case watched, unwatched, rewatched, viewingRemovals, continueRemoval, progress, watchlist, favorites, rating, hidden, note, list }
    public enum Cause: String, Codable, Sendable { case expired, refused, invalid }

    public init(what: String, reason: String, at: Double) { self.what = what; self.reason = reason; self.at = at }

    /// ¿Tiene sentido «Reintentar»?
    public var canRetry: Bool { retry?.isEmpty == false }
}

/// Lo que «Reintentar» vuelve a meter en la cola (las mismas piezas que `PendingWork`, sin la bitácora).
public struct TraktRetry: Codable, Equatable, Sendable {
    public var traktWatched: [PendingWork.TraktWatched] = []
    public var traktUnwatched: [TraktTarget] = []
    public var traktProgress: [ProgressEvent] = []
    public var playbackRemovals: [PendingWork.TraktWatched] = []
    public var traktViewingRemovals: [Int] = []
    public var traktRewatched: [PendingWork.TraktWatched] = []
    public var outbox: [TraktOutbox.Item] = []
    public init(traktWatched: [PendingWork.TraktWatched] = [], traktUnwatched: [TraktTarget] = [], traktProgress: [ProgressEvent] = [],
                playbackRemovals: [PendingWork.TraktWatched] = [], traktViewingRemovals: [Int] = [], traktRewatched: [PendingWork.TraktWatched] = [],
                outbox: [TraktOutbox.Item] = []) {
        self.traktWatched = traktWatched; self.traktUnwatched = traktUnwatched; self.traktProgress = traktProgress
        self.playbackRemovals = playbackRemovals; self.traktViewingRemovals = traktViewingRemovals; self.traktRewatched = traktRewatched
        self.outbox = outbox
    }
    public var isEmpty: Bool { self == TraktRetry() }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        traktWatched = try c.decodeIfPresent([PendingWork.TraktWatched].self, forKey: .traktWatched) ?? []
        traktUnwatched = try c.decodeIfPresent([TraktTarget].self, forKey: .traktUnwatched) ?? []
        traktProgress = try c.decodeIfPresent([ProgressEvent].self, forKey: .traktProgress) ?? []
        playbackRemovals = try c.decodeIfPresent([PendingWork.TraktWatched].self, forKey: .playbackRemovals) ?? []
        traktViewingRemovals = try c.decodeIfPresent([Int].self, forKey: .traktViewingRemovals) ?? []
        traktRewatched = try c.decodeIfPresent([PendingWork.TraktWatched].self, forKey: .traktRewatched) ?? []
        outbox = try c.decodeIfPresent([TraktOutbox.Item].self, forKey: .outbox) ?? []
    }
    enum CodingKeys: String, CodingKey { case traktWatched, traktUnwatched, traktProgress, playbackRemovals, traktViewingRemovals, traktRewatched, outbox }
}

/// Cómo se describe en la bitácora algo que se intentó mandar.
struct TraktAttempt {
    var what: String
    var kind: TraktDiscard.Kind
    var target: TraktTarget?
    var count = 1
    var retry: TraktRetry
}

/// La única cola de lo que va a Trakt (F4, revisión del 10 nov 2026). Antes había dos con reglas distintas: `TraktOutbox`
/// (en UserDefaults, reintentaba el 401) y `PendingWork` de `WatchService` (en un archivo, no lo reintentaba), y lo que Trakt
/// rechazaba se descartaba sin registro. Ahora todo vive en un solo archivo (`PendingStore`, escritura atómica), se vacía
/// aquí, de uno en uno aunque haya dos `WatchService` (al rearmar los servicios), con UNA política de reintento y
/// vencimiento, y cada descarte queda en `discards`.
public actor TraktQueue {
    /// Cuánto espera algo que no se pudo mandar antes de darse por perdido (y quedar en la bitácora como «venció»).
    public static let expiry: TimeInterval = 30 * 24 * 3600
    /// Cuántos descartes se guardan (los más nuevos).
    public static let discardsKept = 30

    /// ¿Vale la pena volver a intentarlo? Sin red, sin sesión ahora (401: al reconectar Trakt se manda), Trakt ocupado o caído:
    /// sí. Un título inválido o una lista que ya no existe: no (reintentarlo no lo arregla). Lo que no es de Trakt (sin red
    /// antes de llegar): sí; el vencimiento le pone fin.
    public static func retry(_ error: Error) -> Bool {
        guard let trakt = error as? TraktError else { return true }
        switch trakt {
        case .network, .auth: return true
        case .http(let status): return status == 401 || status == 408 || status == 429 || status >= 500
        case .invalid: return false
        }
    }

    public nonisolated let store: PendingStore
    let clock: @Sendable () -> Date
    private var running = false
    /// Cómo se manda tu avance (`start` + `pause`): lo sabe `WatchService`.
    public typealias Checkpoint = @Sendable (ProgressEvent, TraktTarget) async throws -> Void
    /// Alguien pidió vaciar mientras ya se vaciaba: una vuelta más al terminar.
    var again: (trakt: Trakt, checkpoint: Checkpoint?)?
    /// Cuántos de tus listas, calificaciones y notas llegaron a Trakt desde que abriste la app (`TraktOutbox.flush` lo usa para
    /// decir cuántos salieron en una vuelta).
    private(set) var outboxSent = 0
    func countSent(_ n: Int) { outboxSent += n }

    public init(store: PendingStore, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.clock = clock
    }

    /// Lo que se descartó, lo más nuevo al final.
    public nonisolated var discards: [TraktDiscard] { store.load().discards }

    /// Anota un descarte (con tope) y lo deja también en el registro del sistema.
    nonisolated func record(_ item: TraktAttempt, error: Error?, at: Double) {
        var discard = TraktDiscard(what: item.what, reason: error.map(Self.reason) ?? "venció sin poder mandarse", at: at)
        discard.kind = item.kind; discard.target = item.target; discard.count = item.count
        if let error {
            if let trakt = error as? TraktError, case .http(let status) = trakt { discard.status = status; discard.cause = .refused } else { discard.cause = .invalid }
        } else {
            discard.cause = .expired; discard.retry = item.retry
        }
        Log.network.error("No llegó a Trakt y ya no se reintenta: \(discard.what, privacy: .public) (\(discard.reason, privacy: .public))")
        store.update { work in
            work.discards.append(discard)
            if work.discards.count > Self.discardsKept { work.discards.removeFirst(work.discards.count - Self.discardsKept) }
        }
    }

    /// «Reintentar» (Ajustes › Trakt): lo que venció vuelve a la cola como nuevo (cuenta otra vez desde hoy) y sale de la bitácora.
    public nonisolated func retry(_ discard: TraktDiscard) {
        guard let again = discard.retry else { return }
        store.update { work in
            guard let i = work.discards.firstIndex(of: discard) else { return }
            work.discards.remove(at: i)
            func fresh(_ w: [PendingWork.TraktWatched]) -> [PendingWork.TraktWatched] { w.map { var x = $0; x.queuedAt = nil; return x } }
            work.traktWatched += fresh(again.traktWatched).filter { !work.traktWatched.contains($0) }
            work.traktUnwatched += again.traktUnwatched.filter { !work.traktUnwatched.contains($0) }
            work.traktProgress += again.traktProgress.filter { !work.traktProgress.contains($0) }
            work.playbackRemovals += fresh(again.playbackRemovals).filter { !work.playbackRemovals.contains($0) }
            work.traktViewingRemovals += again.traktViewingRemovals.filter { !work.traktViewingRemovals.contains($0) }
            work.traktRewatched += fresh(again.traktRewatched).filter { !work.traktRewatched.contains($0) }
            let now = clock().timeIntervalSince1970
            for var item in again.outbox where !work.outbox.contains(where: { $0.target == item.target && $0.imdb == item.imdb }) {
                item.queuedAt = now
                work.outbox.append(item)
            }
        }
    }

    /// Olvida la bitácora (lo que ya viste).
    public nonisolated func clearDiscards() { store.update { $0.discards = [] } }

    /// ¿Está vaciándose ahora? (otro que pida vaciar regresa al momento: lo suyo queda en la cola y sale en esta vuelta o la
    /// siguiente, nunca se pierde).
    func enter() -> Bool { if running { return false }; running = true; return true }
    func leave() { running = false }

    /// Manda cada cosa; devuelve lo que vale la pena reintentar. Lo que Trakt rechaza, o lo que ya venció, se anota y sale.
    /// `age`: desde cuándo espera (segundos de 1970); nil si no se sabe (entonces no vence).
    func attempt<T: Sendable>(_ items: [T], what: (T) -> TraktAttempt, age: (T) -> Double?, _ send: (T) async throws -> Void) async -> (retry: [T], dropped: [T]) {
        var again: [T] = [], dropped: [T] = []
        let now = clock().timeIntervalSince1970
        for item in items {
            do { try await send(item) } catch {
                if Self.retry(error) {
                    if let since = age(item), now - since > Self.expiry { record(what(item), error: nil, at: now); dropped.append(item) }
                    else { again.append(item) }
                } else {
                    record(what(item), error: error, at: now)
                    dropped.append(item)
                }
            }
        }
        return (again, dropped)
    }

    static func reason(_ error: Error) -> String {
        if let trakt = error as? TraktError, case .http(let status) = trakt { return "Trakt respondió \(status)" }
        return String(describing: error)
    }
}
