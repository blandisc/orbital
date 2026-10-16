import Foundation

/// Lo último que el iPhone le contó a Trakt (o por qué no pudo): para enseñarlo en Ajustes › Trakt y poder comprobar
/// en trakt.tv que el scrobble funciona. Vive en memoria y se guarda en el `KeyValueStore` (sobrevive a cerrar la app).
public struct ScrobbleStatus: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var title: String
        public var action: ScrobbleAction
        public var at: Date
        public init(title: String, action: ScrobbleAction, at: Date) { self.title = title; self.action = action; self.at = at }
    }
    public var last: Entry?
    /// El último problema, en palabras (nil si el último aviso salió bien).
    public var error: String?
    public init(last: Entry? = nil, error: String? = nil) { self.last = last; self.error = error }
}

extension ScrobbleAction: Codable {}

public final class ScrobbleLog: @unchecked Sendable {
    static let key = "scrobble-log"
    private let lock = NSLock()
    private let kv: KeyValueStore?
    private var current: ScrobbleStatus

    public init(kv: KeyValueStore? = nil) {
        self.kv = kv
        current = kv?.data(Self.key).flatMap { try? JSONDecoder().decode(ScrobbleStatus.self, from: $0) } ?? ScrobbleStatus()
    }

    public var status: ScrobbleStatus { lock.withLock { current } }

    /// Un aviso que Trakt aceptó (o que ya tenía): se olvida el error anterior.
    public func recordSent(title: String, action: ScrobbleAction, at: Date) {
        update { $0.last = .init(title: title, action: action, at: at); $0.error = nil }
    }

    /// Un aviso que no salió: se dice en palabras (la reproducción sigue como si nada).
    public func recordFailure(_ message: String) {
        update { $0.error = message }
    }

    /// Olvida todo (al cerrar sesión o desconectar Trakt).
    public func clear() { update { $0 = ScrobbleStatus() } }

    private func update(_ change: (inout ScrobbleStatus) -> Void) {
        let snapshot: ScrobbleStatus = lock.withLock { change(&current); return current }
        kv?.set(Self.key, data: try? JSONEncoder().encode(snapshot))
    }
}
