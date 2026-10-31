import Foundation
import OrbitalCore

/// La repisa de Colecciones: los premios (al instante, vienen con la app) y las listas famosas (de MDBList, guardadas una
/// semana en el iPhone), con lo que ya viste para pintar cada póster. Marcar algo como visto se ve al momento.
@MainActor
public final class RepisaModel: ObservableModel {
    public private(set) var collections: [CanonCollection] { didSet { changed() } }
    public private(set) var watched: Set<String> = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    /// Las listas famosas que no llegaron (sin red, MDBList caído) y no hay copia guardada: la pantalla ofrece «Reintentar».
    public private(set) var failedLists: Set<String> = [] { didSet { changed() } }

    /// Cuánto se guarda una lista famosa antes de volver a pedirla (cambian poco).
    public nonisolated static let listTTL: TimeInterval = 7 * 86400
    static func cacheKey(_ id: String) -> String { "canon-list-\(id)" }
    private struct Cached: Codable { var at: Date; var rows: [[String]] }

    private let services: Services
    private let watchedSource: @MainActor () async -> Set<String>
    private let clock: @Sendable () -> Date

    /// `watched`: lo que ya viste (por IMDb), el mismo de toda la app (`CollectionsModel.watchedIDs`).
    public init(_ services: Services, watched: @escaping @MainActor () async -> Set<String>, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.services = services; self.watchedSource = watched; self.clock = clock
        collections = Canon.awards() + Canon.lists.map { CanonCollection(id: $0.id, family: .list, grouping: $0.grouping, items: [], total: $0.total) }
        super.init()
        for list in Canon.lists { if let items = cached(list.id, fresh: false) { replace(list.id, items) } }
    }

    public func collection(_ id: String) -> CanonCollection? { collections.first { $0.id == id } }

    /// Cuántos títulos distintos del canon ya viste (uno que está en tres colecciones cuenta una vez).
    public var seenTotal: Int { Set(collections.flatMap(\.items).map(\.imdb)).intersection(watched).count }

    /// Lo que viste y las listas (las que no estén guardadas o ya caducaron).
    public func load() async {
        await withTaskGroup(of: (String, [CanonCollection.Item]?).self) { group in
            for list in Canon.lists where cached(list.id, fresh: true) == nil {
                group.addTask { [http = services.http, trakt = services.trakt] in
                    switch list.source {
                    case .mdblist: return (list.id, try? await Canon.list(http: http, user: list.user, slug: list.slug))
                    case .trakt:
                        guard let trakt else { return (list.id, nil) }
                        return (list.id, try? await Canon.list(trakt: trakt, user: list.user, slug: list.slug))
                    case .mine:
                        // Una de tus listas, por su nombre: se copia en orden y ya no se vuelve a pedir (ver `cached`).
                        guard let trakt, let own = try? await trakt.ownLists().first(where: { Canon.matches($0.name, list.source) }),
                              let entries = try? await trakt.listItems(own.id) else { return (list.id, nil) }
                        var seen = Set<String>()
                        return (list.id, entries.filter { $0.imdb.hasPrefix("tt") && seen.insert($0.imdb).inserted }.enumerated()
                            .map { i, e in .init(imdb: e.imdb, kind: e.kind, title: e.title, year: e.year, rank: i + 1) })
                    }
                }
            }
            for await (id, items) in group {
                guard let items, !items.isEmpty else {
                    // Sin copia guardada, falló de verdad; con copia (aunque vieja), se sigue mostrando esa.
                    if collection(id)?.items.isEmpty ?? true { failedLists.insert(id) }
                    continue
                }
                failedLists.remove(id)
                replace(id, items)
                save(id, items)
            }
        }
        watched = await watchedSource()
        loaded = true
    }

    /// Lo acabas de ver (o lo marcaste): se pinta ya, sin esperar a Trakt.
    public func markSeen(_ imdb: String) { watched.insert(imdb) }

    /// En qué otras colecciones está un título (la ficha rápida: «También en Criterion»).
    public func others(_ imdb: String, besides id: String) -> [String] {
        collections.filter { $0.id != id && $0.items.contains { $0.imdb == imdb } }.map(\.id)
    }

    private func replace(_ id: String, _ items: [CanonCollection.Item]) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].items = items
        collections[i].total = max(collections[i].total, items.count)
    }

    private func cached(_ id: String, fresh: Bool) -> [CanonCollection.Item]? {
        guard let data = services.kv.data(Self.cacheKey(id)), let saved = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        // Las que vienen de tus listas se quedan fijas: no caducan.
        let fixed = Canon.lists.first { $0.id == id }.map { if case .mine = $0.source { true } else { false } } ?? false
        if fresh, !fixed, clock().timeIntervalSince(saved.at) > Self.listTTL { return nil }
        return saved.rows.compactMap { r in
            guard r.count == 5 else { return nil }
            return .init(imdb: r[0], kind: r[1], title: r[2], year: Int(r[3]), rank: Int(r[4]))
        }
    }

    private func save(_ id: String, _ items: [CanonCollection.Item]) {
        let rows = items.map { [$0.imdb, $0.kind, $0.title, $0.year.map(String.init) ?? "", $0.rank.map(String.init) ?? ""] }
        services.kv.set(Self.cacheKey(id), data: try? JSONEncoder().encode(Cached(at: clock(), rows: rows)))
    }
}
