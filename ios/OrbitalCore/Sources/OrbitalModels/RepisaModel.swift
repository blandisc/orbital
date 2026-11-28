import Foundation
import OrbitalCore

/// La repisa de Colecciones: los premios (al instante, vienen con la app) y las listas famosas (de MDBList, guardadas una
/// semana en el iPhone), con lo que ya viste para pintar cada póster. Marcar algo como visto se ve al momento.
@MainActor
public final class RepisaModel: ObservableModel {
    /// Las listas de «Hoy» (por ánimo y recetas): llevan un tope de títulos, no son listas cortas.
    public static let todayPrefix = "hoy-"
    public private(set) var collections: [CanonCollection] { didSet { changed() } }
    public private(set) var watched: Set<String> = [] { didSet { changed() } }
    public private(set) var loaded = false { didSet { changed() } }
    /// Las listas famosas que no llegaron (sin red, MDBList caído) y no hay copia guardada: la pantalla ofrece «Reintentar».
    public private(set) var failedLists: Set<String> = [] { didSet { changed() } }
    /// «Esta semana» en Explorar (`ExploreTable`): las listas que tocan hoy, en orden, y sus títulos.
    public private(set) var weekly: [CanonCollection] = [] { didSet { changed() } }
    public private(set) var weeklyLists: [ExploreList] = [] { didSet { changed() } }
    /// Los capítulos de las listas de capítulos que ya viste («tt0096697:7:11»), según tu avance en Trakt: cuentan como vistos.
    private var episodesSeen: Set<String> = []

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
        if let table = savedTable(fresh: false) { arrange(table) }
    }

    public func collection(_ id: String) -> CanonCollection? { collections.first { $0.id == id } ?? weekly.first { $0.id == id } }
    public func weeklyList(_ id: String) -> ExploreList? { weeklyLists.first { $0.id == id } }

    /// Cuánto vale la tabla de «Esta semana» antes de volver a pedirla.
    public nonisolated static let tableTTL: TimeInterval = 86400
    static let tableKey = "explore-table"
    private struct SavedTable: Codable { var at: Date; var table: ExploreTable }

    /// Cuánto vale lo de «Esta semana» ya armado antes de volver a revisarlo al regresar a Explorar.
    public nonisolated static let weeklyMaxAge: TimeInterval = 600
    private var weeklyAt: Date?

    /// La tabla (guardada un día; sin red, la última que llegó) y las listas que tocan esta semana, con sus títulos.
    /// Con lo de hace menos de diez minutos no hace nada: antes cada visita a Explorar volvía a leer la tabla y cada lista del
    /// disco en el hilo de la pantalla, las volvía a poner (repintando Explorar) y le pedía a Trakt tu avance (~0.2 s de
    /// pantalla congelada en cada visita en la Mac, 23 nov 2026).
    public func loadWeekly() async {
        if let weeklyAt, clock().timeIntervalSince(weeklyAt) < Self.weeklyMaxAge, !weekly.isEmpty { return }
        var table = savedTable(fresh: true)
        if table == nil, let response = try? await services.http.send(HTTPRequest(url: ExploreTable.url, headers: ["User-Agent": "Orbital"], timeout: 15)),
           response.status == 200, let fetched = ExploreTable.parse(response.data) {
            table = fetched
            let saved = SavedTable(at: clock(), table: fetched)
            services.caches.set(Self.tableKey) { try? JSONEncoder().encode(saved) }
        }
        guard let table = table ?? savedTable(fresh: false) else { return }
        arrange(table)
        await withTaskGroup(of: (String, [CanonCollection.Item]?).self) { group in
            for list in weeklyLists where list.items == nil && cached(list.id, fresh: true) == nil {
                group.addTask { [http = services.http, trakt = services.trakt] in
                    let parts = (list.mdblist ?? list.trakt ?? "").split(separator: "/").map(String.init)
                    guard parts.count == 2 else { return (list.id, nil) }
                    if list.mdblist != nil { return (list.id, try? await Canon.list(http: http, user: parts[0], slug: parts[1])) }
                    guard let trakt else { return (list.id, nil) }
                    return (list.id, try? await Canon.list(trakt: trakt, user: parts[0], slug: parts[1]))
                }
            }
            for await (id, items) in group {
                guard let items, !items.isEmpty else { continue }
                save(id, items)
                if let i = weekly.firstIndex(where: { $0.id == id }) { weekly[i].items = items; weekly[i].total = items.count }
            }
        }
        // Nunca una tarjeta vacía: la que no llegó y no tiene copia guardada no sale.
        await loadToday(table)
        weekly.removeAll { $0.items.isEmpty }
        weeklyAt = clock()
        await loadEpisodesSeen()
    }

    /// Tu avance en cada serie de las listas de capítulos (una llamada por serie): lo visto se pinta y cuenta como en una película.
    private func loadEpisodesSeen() async {
        guard let trakt = services.trakt else { return }
        let shows = Set(weekly.flatMap(\.items).compactMap { $0.episode?.show })
        guard !shows.isEmpty else { return }
        var seen = Set<String>()
        await withTaskGroup(of: [String].self) { group in
            for show in shows {
                group.addTask { (try? await trakt.showProgress(show, imdb: show)).map { p in p.completed.map(p.videoID) } ?? [] }
            }
            for await ids in group { seen.formUnion(ids) }
        }
        episodesSeen = seen
        watched.formUnion(seen)
    }

    /// Cuántos títulos lleva una lista de «Hoy».
    public nonisolated static let todayCount = 20

    /// «Hoy» (LD-C y LV-A, Fernando, 25 nov 2026: «no sé qué ver»): las recetas del día, antes de las listas famosas. Sin
    /// «Porque viste…» (Fernando, 26 nov 2026: ya vive en Inicio; aquí van grupos hechos por ánimo, «MOOD» en la tabla). Sin lo que ya viste. Se guardan el día: mañana salen otras.
    private func loadToday(_ table: ExploreTable) async {
        // Lo visto aún no llega si Explorar abrió hace un momento (lo trae `load()`, más abajo): se pide aquí.
        if watched.isEmpty { watched = await watchedSource().union(episodesSeen) }
        let watchedNow = watched
        let hide: ([CanonCollection.Item]) -> [CanonCollection.Item] = { items in
            Array(items.filter { !watchedNow.contains($0.imdb) }.prefix(Self.todayCount)).enumerated().map { i, it in var x = it; x.rank = i + 1; return x }
        }
        do { let tmdb = services.tmdb
            await withTaskGroup(of: (String, [CanonCollection.Item]?).self) { group in
                for recipe in table.recipesToday(clock()) where cached(recipe.list.id, fresh: true, ttl: 86400) == nil {
                    group.addTask {
                        guard let rows = try? await tmdb.discover(recipe.filter) else { return (recipe.list.id, nil) }
                        let found = await ForYou.suggestions(rows, reason: .popular, tmdb: tmdb)
                        return (recipe.list.id, found.map { .init(imdb: $0.imdb, kind: $0.kind, title: $0.title, year: $0.year) })
                    }
                }
                for await (id, items) in group { if let items, !items.isEmpty { save(id, items) } }
            }
        }
        let today: [(ExploreList, [CanonCollection.Item])] = table.recipesToday(clock()).compactMap { r in
            let items = hide(cached(r.list.id, fresh: false) ?? [])
            return items.isEmpty ? nil : (r.list, items)
        }
        weeklyLists.removeAll { $0.id.hasPrefix(Self.todayPrefix) }
        weekly.removeAll { $0.id.hasPrefix(Self.todayPrefix) }
        let at = weeklyLists.firstIndex { !$0.dated } ?? weeklyLists.count
        weeklyLists.insert(contentsOf: today.map(\.0), at: at)
        weekly.insert(contentsOf: today.map { CanonCollection(id: $0.0.id, family: .list, grouping: .rank, items: $0.1) }, at: at)
    }

    /// Las de esta semana con lo que ya se tiene (escritas en la tabla o guardadas).
    /// Las de «Hoy» que ya estaban se quedan mientras se vuelven a pedir (antes desaparecían y regresaban en cada recarga).
    private func arrange(_ table: ExploreTable) {
        let todayLists = weeklyLists.filter { $0.id.hasPrefix(Self.todayPrefix) }
        let todayItems = weekly.filter { $0.id.hasPrefix(Self.todayPrefix) }
        weeklyLists = table.thisWeek(clock())
        weekly = weeklyLists.map { list in
            let items = list.written ?? cached(list.id, fresh: false) ?? []
            return CanonCollection(id: list.id, family: .list, grouping: .rank, items: items)
        }
        let at = weeklyLists.firstIndex { !$0.dated } ?? weeklyLists.count
        weeklyLists.insert(contentsOf: todayLists, at: at)
        weekly.insert(contentsOf: todayItems, at: min(at, weekly.count))
    }

    private func savedTable(fresh: Bool) -> ExploreTable? {
        guard let data = services.caches.data(Self.tableKey), let saved = try? JSONDecoder().decode(SavedTable.self, from: data) else { return nil }
        if fresh, clock().timeIntervalSince(saved.at) > Self.tableTTL { return nil }
        return saved.table
    }

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
        watched = await watchedSource().union(episodesSeen)
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

    private func cached(_ id: String, fresh: Bool, ttl: TimeInterval = RepisaModel.listTTL) -> [CanonCollection.Item]? {
        guard let data = services.caches.data(Self.cacheKey(id)), let saved = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        // Las que vienen de tus listas se quedan fijas: no caducan.
        let fixed = Canon.lists.first { $0.id == id }.map { if case .mine = $0.source { true } else { false } } ?? false
        if fresh, !fixed, clock().timeIntervalSince(saved.at) > ttl { return nil }
        return saved.rows.compactMap { r in
            guard r.count == 5 else { return nil }
            return .init(imdb: r[0], kind: r[1], title: r[2], year: Int(r[3]), rank: Int(r[4]))
        }
    }

    private func save(_ id: String, _ items: [CanonCollection.Item]) {
        let rows = items.map { [$0.imdb, $0.kind, $0.title, $0.year.map(String.init) ?? "", $0.rank.map(String.init) ?? ""] }
        let cached = Cached(at: clock(), rows: rows)
        services.caches.set(Self.cacheKey(id)) { try? JSONEncoder().encode(cached) }
    }
}
