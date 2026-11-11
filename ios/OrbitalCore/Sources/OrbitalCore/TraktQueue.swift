import Foundation

/// Lo que Trakt no aceptó y ya no se va a volver a intentar (F4): queda escrito para que la app lo pueda decir («No se pudo
/// guardar en Trakt: …») en vez de perderse sin rastro.
public struct TraktDiscard: Codable, Equatable, Sendable {
    /// Qué era, en palabras cortas: «Mi lista · tt1160419», «Visto · tt0386676 T2 E5».
    public var what: String
    /// Por qué: lo que dijo Trakt («Trakt respondió 422») o «venció».
    public var reason: String
    public var at: Double
    public init(what: String, reason: String, at: Double) { self.what = what; self.reason = reason; self.at = at }
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

    /// Anota un descarte (con tope).
    nonisolated func record(_ what: String, _ reason: String, at: Double) {
        store.update { work in
            work.discards.append(TraktDiscard(what: what, reason: reason, at: at))
            if work.discards.count > Self.discardsKept { work.discards.removeFirst(work.discards.count - Self.discardsKept) }
        }
    }

    /// ¿Está vaciándose ahora? (otro que pida vaciar regresa al momento: lo suyo queda en la cola y sale en esta vuelta o la
    /// siguiente, nunca se pierde).
    func enter() -> Bool { if running { return false }; running = true; return true }
    func leave() { running = false }

    /// Manda cada cosa; devuelve lo que vale la pena reintentar. Lo que Trakt rechaza, o lo que ya venció, se anota y sale.
    /// `age`: desde cuándo espera (segundos de 1970); nil si no se sabe (entonces no vence).
    func attempt<T: Sendable>(_ items: [T], what: (T) -> String, age: (T) -> Double?, _ send: (T) async throws -> Void) async -> (retry: [T], dropped: [T]) {
        var again: [T] = [], dropped: [T] = []
        let now = clock().timeIntervalSince1970
        for item in items {
            do { try await send(item) } catch {
                if Self.retry(error) {
                    if let since = age(item), now - since > Self.expiry { record(what(item), "venció sin poder mandarse", at: now); dropped.append(item) }
                    else { again.append(item) }
                } else {
                    record(what(item), Self.reason(error), at: now)
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
