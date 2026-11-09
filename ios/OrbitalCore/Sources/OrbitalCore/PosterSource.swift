import Foundation

/// P1 (Fernando, 8 nov): primero el póster de TMDB y, si TMDB no lo tiene (o no hay clave), el de metahub. El de metahub de
/// «Star Wars: Clone Wars» (2003) es de un programa coreano. Como `ForYou.poster_source` de la TV: lo encontrado se recuerda
/// 30 días (también «no lo tiene», para no volver a preguntar).
public final class PosterSource: @unchecked Sendable {
    static let storeKey = "poster-source"
    public static let ttl: TimeInterval = 30 * 86400
    private struct Entry: Codable { var path: String; var at: Date }   // path vacío: TMDB no lo tiene

    private let lock = NSLock()
    private var map: [String: Entry]
    private let store: KeyValueStore
    private let lookup: @Sendable (String) async -> String??   // nil: no se pudo preguntar; .some(nil): no lo tiene
    private let clock: @Sendable () -> Date

    public init(store: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }, lookup: @escaping @Sendable (String) async -> String??) {
        self.store = store; self.lookup = lookup; self.clock = clock
        map = store.data(Self.storeKey).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
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
        if let entry = lock.withLock({ map[imdb] }), clock().timeIntervalSince(entry.at) < Self.ttl {
            return entry.path.isEmpty ? nil : URL(string: "\(Tmdb.images)/\(Self.tmdbSize(size))\(entry.path)")
        }
        guard let answer = await lookup(imdb) else { return nil }   // sin red o sin clave: no se recuerda
        let path = answer ?? ""
        let data: Data? = lock.withLock {
            map[imdb] = Entry(path: path, at: clock())
            let now = clock()
            if map.count > 4000 { map = map.filter { now.timeIntervalSince($0.value.at) < Self.ttl } }
            return try? JSONEncoder().encode(map)
        }
        store.set(Self.storeKey, data: data)
        return path.isEmpty ? nil : URL(string: "\(Tmdb.images)/\(Self.tmdbSize(size))\(path)")
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
