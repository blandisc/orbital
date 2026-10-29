import Foundation

/// El arte alto de un título: su póster sin texto de TMDB, para un marco más alto que ancho (la portada de la ficha, «En
/// tendencia»). Un fondo 16:9 metido ahí solo dejaba ver la mitad de la escena, o un tercio. Se recuerda en disco, también
/// cuando no hay (la segunda vez sale desde el primer cuadro, sin esperar ni cambiar de imagen a media carga).
public final class TallArt: @unchecked Sendable {
    /// Lo que se sabe de un título sin pedir nada.
    public enum Answer: Equatable, Sendable {
        /// Aún no se sabe: hay que preguntar a TMDB.
        case unknown
        /// TMDB no tiene póster sin texto (o no hay clave): va el fondo.
        case none
        case poster(String)
    }

    private let tmdb: @Sendable () -> Tmdb
    private let clock: @Sendable () -> Date
    private let store: KeyValueStore?
    private let lock = NSLock()
    private var memory: [String: Saved]?
    private var inflight: [String: Task<String?, Never>] = [:]
    private var saveScheduled = false
    private struct Saved: Codable { var u: String?; var d: Double }
    static let diskKey = "tmdb-tall-art", diskSeconds: TimeInterval = 30 * 24 * 3600, diskLimit = 2000

    public init(tmdb: @escaping @Sendable () -> Tmdb, clock: @escaping @Sendable () -> Date = { Date() }, store: KeyValueStore? = nil) {
        self.tmdb = tmdb; self.clock = clock; self.store = store
    }

    private static func key(_ imdb: String, _ kind: String) -> String { "\(kind)|\(imdb)" }

    /// Lo que ya se sabe (memoria o disco), al instante.
    public func known(imdb: String, kind: String) -> Answer {
        guard imdb.hasPrefix("tt") else { return .none }
        return lock.withLock {
            guard let saved = loaded()[Self.key(imdb, kind)], clock().timeIntervalSince1970 - saved.d < Self.diskSeconds else { return .unknown }
            return saved.u.map(Answer.poster) ?? .none
        }
    }

    /// El póster sin texto, preguntando a TMDB si hace falta (nil: no hay, o no se pudo; un fallo de red no se recuerda).
    public func poster(imdb: String, kind: String) async -> String? {
        switch known(imdb: imdb, kind: kind) {
        case .poster(let url): return url
        case .none: return nil
        case .unknown: break
        }
        let tmdb = tmdb()
        guard tmdb.configured else { return nil }
        let key = Self.key(imdb, kind)
        let task: Task<String?, Never> = lock.withLock {
            if let running = inflight[key] { return running }
            let task = Task<String?, Never> { [weak self] in
                do {
                    let found = try await tmdb.findID(imdb: imdb, kind: kind)
                    let url = try await found.asyncMap { try await tmdb.textlessPoster(kind: kind, tmdbID: $0) } ?? nil
                    self?.remember(key, url)
                    return url
                } catch { return nil }
            }
            inflight[key] = task
            return task
        }
        let url = await task.value
        lock.withLock { inflight[key] = nil }
        return url
    }

    /// Llamar con el candado puesto.
    private func loaded() -> [String: Saved] {
        if memory == nil { memory = store?.data(Self.diskKey).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:] }
        return memory ?? [:]
    }

    private func remember(_ key: String, _ url: String?) {
        let flush: Bool = lock.withLock {
            _ = loaded()
            memory?[key] = Saved(u: url, d: clock().timeIntervalSince1970)
            if let count = memory?.count, count > Self.diskLimit, let oldest = memory?.sorted(by: { $0.value.d < $1.value.d }).prefix(count - Self.diskLimit).map(\.key) {
                for k in oldest { memory?[k] = nil }
            }
            guard store != nil, !saveScheduled else { return false }
            saveScheduled = true
            return true
        }
        guard flush else { return }
        Task { [weak self] in try? await Task.sleep(nanoseconds: 2_000_000_000); self?.flush() }   // ds-exception: se juntan las escrituras a disco
    }

    private func flush() {
        let data: Data? = lock.withLock { saveScheduled = false; return memory.flatMap { try? JSONEncoder().encode($0) } }
        if let data { store?.set(Self.diskKey, data: data) }
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
