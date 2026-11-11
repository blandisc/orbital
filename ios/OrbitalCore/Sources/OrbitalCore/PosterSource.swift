import Foundation

/// P1 (Fernando, 8 nov): primero el póster de TMDB y, si TMDB no lo tiene (o no hay clave), el de metahub. El de metahub de
/// «Star Wars: Clone Wars» (2003) es de un programa coreano. Como `ForYou.poster_source` de la TV: lo encontrado se recuerda
/// 30 días (también «no lo tiene», para no volver a preguntar).
public final class PosterSource: @unchecked Sendable {
    static let storeKey = "poster-source"
    public static let ttl: TimeInterval = 30 * 86400
    static let maxEntries = 4000
    /// Cuántas consultas a TMDB a la vez (A12, 10 nov 2026): una fila, no decenas de golpe al abrir Explorar.
    static let concurrentLookups = 4
    /// Lo encontrado se escribe un rato después y de una vez (no un archivo entero por cada póster).
    static let writeDelay: Duration = .seconds(3)
    private struct Entry: Codable { var path: String; var at: Date }   // path vacío: TMDB no lo tiene

    private let lock = NSLock()
    private var map: [String: Entry]
    private let save: @Sendable (Data) -> Void
    private let lookup: @Sendable (String) async -> String??   // nil: no se pudo preguntar; .some(nil): no lo tiene
    private let clock: @Sendable () -> Date
    /// Una sola consulta por título aunque lo pidan dos tamaños (o dos pantallas) a la vez.
    private var inflight: [String: Task<String??, Never>] = [:]
    private var saveScheduled = false
    private let gate = PosterLookupGate(limit: PosterSource.concurrentLookups)

    /// `load` lee lo guardado (una vez, al crearse) y `save` lo escribe (fuera del hilo principal, con retraso).
    public init(load: () -> Data?, save: @escaping @Sendable (Data) -> Void, clock: @escaping @Sendable () -> Date = { Date() },
                lookup: @escaping @Sendable (String) async -> String??) {
        self.save = save; self.lookup = lookup; self.clock = clock
        map = load().flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// El tope de verdad (revisión del 11 nov 2026): antes, al pasar de `maxEntries` solo se quitaba lo vencido, y con más de
    /// 4000 títulos vistos en 30 días la memoria crecía sin fin. Ahora se quita lo vencido y, si aún sobra, lo más viejo.
    static func capped<V>(_ map: [String: V], at: (V) -> Date, now: Date, max: Int = maxEntries) -> [String: V] {
        let fresh = map.filter { now.timeIntervalSince(at($0.value)) < ttl }
        guard fresh.count > max else { return fresh }
        return Dictionary(uniqueKeysWithValues: fresh.sorted { at($0.value) > at($1.value) }.prefix(max).map { ($0.key, $0.value) })
    }

    /// Guardado en un almacén de claves (pruebas).
    public convenience init(store: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }, lookup: @escaping @Sendable (String) async -> String??) {
        self.init(load: { store.data(Self.storeKey) }, save: { store.set(Self.storeKey, data: $0) }, clock: clock, lookup: lookup)
    }

    /// Guardado en un archivo (en Caches: iOS puede borrarlo y solo se vuelve a preguntar). Lo que había en `legacy`
    /// (UserDefaults, hasta el 10 nov 2026: el mapa entero se leía y escribía ahí) se pasa al archivo y se borra de ahí.
    public convenience init(file: URL, legacy: KeyValueStore?, tmdb: @escaping @Sendable () -> Tmdb?) {
        self.init(load: {
            if let data = try? Data(contentsOf: file) { legacy?.set(Self.storeKey, data: nil); return data }
            let old = legacy?.data(Self.storeKey)
            if let old {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? old.write(to: file, options: .atomic)
                legacy?.set(Self.storeKey, data: nil)
            }
            return old
        }, save: { data in
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try data.write(to: file, options: .atomic) } catch { Log.cache.error("Pósters de TMDB: no se pudo guardar (\(error.localizedDescription, privacy: .public))") }
        }, lookup: { imdb in
            guard let tmdb = tmdb(), tmdb.configured else { return nil }
            do { return .some(try await tmdb.posterPath(imdb: imdb)) } catch { return nil }
        })
    }

    /// Con la clave de TMDB de la app (`tmdb()` nil o sin clave: se queda el de metahub).
    public convenience init(store: KeyValueStore, tmdb: @escaping @Sendable () -> Tmdb?) {
        self.init(store: store) { imdb in
            guard let tmdb = tmdb(), tmdb.configured else { return nil }
            do { return .some(try await tmdb.posterPath(imdb: imdb)) } catch { return nil }
        }
    }

    /// El id de IMDb y el tamaño de un póster de metahub («…/poster/medium/tt0361243/img»). nil: no es un póster de metahub.
    public static func metahub(_ url: String) -> (imdb: String, size: String)? {
        guard url.hasPrefix("https://images.metahub.space/poster/") else { return nil }
        let parts = url.dropFirst("https://images.metahub.space/poster/".count).split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[1].range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return nil }
        return (parts[1], parts[0])
    }

    /// El tamaño de TMDB que corresponde al de metahub (small 300, medium 500, large 780 de ancho).
    static func tmdbSize(_ metahub: String) -> String { ["small": "w342", "large": "w780"][metahub, default: "w500"] }

    /// Lo ya sabido, sin preguntar: la URL de TMDB, o nil (no es de metahub, TMDB no lo tiene o aún no se sabe).
    public func known(_ url: String) -> URL? {
        guard let (imdb, size) = Self.metahub(url), let entry = lock.withLock({ map[imdb] }),
              clock().timeIntervalSince(entry.at) < Self.ttl, !entry.path.isEmpty else { return nil }
        return URL(string: "\(Tmdb.images)/\(Self.tmdbSize(size))\(entry.path)")
    }

    /// La URL de TMDB para un póster de metahub; pregunta si hace falta. nil: quedarse con la de metahub.
    public func resolve(_ url: String) async -> URL? {
        guard let (imdb, size) = Self.metahub(url) else { return nil }
        let now = clock()
        let (cached, task): (Entry?, Task<String??, Never>?) = lock.withLock {
            if let entry = map[imdb], now.timeIntervalSince(entry.at) < Self.ttl { return (entry, nil) }
            if let running = inflight[imdb] { return (nil, running) }
            let task = Task<String??, Never> { [self] in
                let answer = await gate.run { await self.lookup(imdb) }
                remember(imdb, answer)
                return answer
            }
            inflight[imdb] = task
            return (nil, task)
        }
        if let cached { return cached.path.isEmpty ? nil : URL(string: "\(Tmdb.images)/\(Self.tmdbSize(size))\(cached.path)") }
        guard let answer = await task?.value, let path = answer else { return nil }   // sin red o sin clave, o TMDB no lo tiene
        return URL(string: "\(Tmdb.images)/\(Self.tmdbSize(size))\(path)")
    }

    /// Se recuerda la respuesta (también «no lo tiene»; «no se pudo preguntar», no) y se agenda la escritura.
    private func remember(_ imdb: String, _ answer: String??) {
        let schedule: Bool = lock.withLock {
            inflight[imdb] = nil
            guard let answer else { return false }
            let now = clock()
            map[imdb] = Entry(path: answer ?? "", at: now)
            if map.count > Self.maxEntries { map = Self.capped(map, at: \.at, now: now) }
            guard !saveScheduled else { return false }
            saveScheduled = true
            return true
        }
        guard schedule else { return }
        Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(for: Self.writeDelay)
            flush()
        }
    }

    /// Escribe ya lo que falte (al irse a segundo plano y en pruebas).
    public func flush() {
        let data: Data? = lock.withLock { saveScheduled = false; return try? JSONEncoder().encode(map) }
        if let data { save(data) }
    }
}

/// La fila de consultas de pósters: a lo más `limit` a la vez; las demás esperan su turno.
actor PosterLookupGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        if running < limit { running += 1 } else { await withCheckedContinuation { waiting.append($0) } }   // el lugar lo pasa quien termina
        let value = await work()
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
        return value
    }
}

extension Tmdb {
    /// El póster de TMDB de un título de IMDb (película o serie), como «/abc.jpg». nil: TMDB no lo tiene (`PosterSource`).
    public func posterPath(imdb: String) async throws -> String? {
        guard imdb.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil else { return nil }
        let data = try await get("/find/\(imdb)", [("external_source", "imdb_id")])
        let rows = (data["movie_results"]?.array ?? []) + (data["tv_results"]?.array ?? [])
        return rows.lazy.compactMap { $0["poster_path"]?.string }.first { $0.hasPrefix("/") }
    }
}
