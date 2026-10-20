import Foundation
import OrbitalCore

@MainActor
public final class SearchModel: ObservableModel {
    public struct Result: Equatable, Identifiable {
        public var id: String { "\(kind):\(metaID)" }
        public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
    }

    // Solo se avisa si cambió de verdad (antes, cada letra mandaba cuatro avisos aunque nada cambiara).
    public private(set) var results: [Result] = [] { didSet { if results != oldValue { changed() } } }
    public private(set) var isSearching = false { didSet { if isSearching != oldValue { changed() } } }
    public private(set) var error: String? { didSet { if error != oldValue { changed() } } }
    /// Lo que se buscó para los `results` de ahora: hasta que la búsqueda nueva contesta, la pantalla no dice «Sin resultados».
    public private(set) var searchedQuery: String? { didSet { if searchedQuery != oldValue { changed() } } }
    public private(set) var recent: [String] { didSet { changed() } }
    private let services: Services
    private var latest = 0

    public init(_ services: Services) {
        self.services = services
        recent = services.kv.data("recent-searches").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        super.init()
    }

    /// Busca películas y series; la última búsqueda manda (si escribes rápido, las viejas se descartan).
    /// Películas y series se ven cada una en cuanto llega (no se espera a la más lenta), con los nombres en tu idioma que ya
    /// se conocen; los que faltan (TMDB, uno por título) se ponen después. Lo ya buscado sale al instante de memoria.
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        latest += 1
        let ticket = latest
        guard query.count >= 2 else { results = []; error = nil; isSearching = false; searchedQuery = nil; return }
        let key = query.lowercased()
        if let cached = memory[key] { results = cached; error = nil; searchedQuery = query; isSearching = false; return }
        isSearching = true
        error = nil   // un error de la búsqueda anterior no tapa lo que está cargando
        defer { if ticket == latest { isSearching = false } }
        do {
            let found = try await find(query) { [weak self] partial in
                guard let self, ticket == self.latest else { return }
                let known = await self.knownNames(partial)
                guard ticket == self.latest else { return }
                self.results = partial.map { Result(kind: $0.kind, metaID: $0.metaID, title: known[$0.metaID] ?? $0.title, originalTitle: $0.title,
                                                    poster: $0.poster, year: $0.year) }
                self.error = nil
                self.searchedQuery = query
            }
            guard ticket == latest else { return }
            isSearching = false
            // Los nombres en tu idioma, a la vez (películas y series), y solo si la búsqueda sigue siendo esta.
            async let movieNames = names(found, kind: "movie")
            async let seriesNames = names(found, kind: "series")
            let names = await movieNames.merging(seriesNames) { a, _ in a }
            let localized = found.map { r in Result(kind: r.kind, metaID: r.metaID, title: names[r.metaID] ?? r.title, originalTitle: r.title,
                                                    poster: r.poster, year: r.year) }
            // Solo se recuerda si la traducción terminó (cancelada por otra letra, se habrían guardado los nombres en inglés).
            if !Task.isCancelled { remember(results: localized, for: key) }
            guard ticket == latest else { return }
            if localized != results { results = localized }
        } catch {
            // Escribir otra letra cancela la búsqueda en vuelo: eso no es un error de red (ni vacía lo que ya se veía).
            guard !Task.isCancelled, ticket == latest else { return }
            results = []; self.error = "\(error)"; searchedQuery = query
        }
    }

    /// Una pieza de la búsqueda: un tipo de Cinemeta (nil = falló dos veces) o lo que contestó Trakt.
    private enum Piece: Sendable { case kind(String, [JSON]?), trakt([SearchResult]) }

    /// Películas y series de Cinemeta por separado: cada una se enseña (`show`) en cuanto llega, y si una falla, se
    /// reintenta solo esa (antes, un error de una tiraba también la otra). Si en `hedgeDelay` no ha llegado nada, se le
    /// pregunta también a Trakt (si está configurado), sin cancelar a Cinemeta: lo que llegue primero se ve; Cinemeta, en
    /// cuanto llega, toma su lugar. Solo si todo falla se dice que no se pudo.
    private func find(_ query: String, show: @escaping @MainActor ([SearchResult]) async -> Void) async throws -> [SearchResult] {
        let cinemeta = services.cinemeta, trakt = services.trakt
        var parts: [String: [JSON]] = [:], failed = Set<String>(), fromTrakt: [SearchResult]?, shown: [SearchResult] = []
        await withTaskGroup(of: Piece.self) { group in
            for kind in ["movie", "series"] {
                group.addTask {
                    for attempt in 0..<2 {
                        if attempt > 0 { try? await Task.sleep(nanoseconds: Self.retryDelay) }
                        if Task.isCancelled { break }
                        if let found = try? await cinemeta.search(kind, query: query) { return .kind(kind, found) }
                    }
                    return .kind(kind, nil)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.hedgeDelay)
                guard !Task.isCancelled, let trakt, trakt.configured, let found = try? await trakt.search(query) else { return .trakt([]) }
                return .trakt(found.map { SearchResult(kind: $0.kind, metaID: $0.imdb, title: $0.title,
                                                       poster: String(format: ForYou.metahubPoster, $0.imdb), year: $0.year.map(String.init) ?? "") })
            }
            for await piece in group {
                switch piece {
                case .kind(let kind, let found?): parts[kind] = found
                case .kind(let kind, nil): failed.insert(kind)
                case .trakt(let found): fromTrakt = found
                }
                let settled = parts.count + failed.count == 2
                var now: [SearchResult] = []
                if !parts.isEmpty {
                    now = CinemetaParsing.searchResults(query: query, movies: parts["movie"] ?? [], series: parts["series"] ?? [], limit: Self.resultLimit)
                    // Del tipo que Cinemeta no ha dado (o no pudo), lo que haya traído Trakt.
                    let ids = Set(now.map(\.metaID))
                    now += (fromTrakt ?? []).filter { parts[$0.kind] == nil && !ids.contains($0.metaID) }
                } else if let fromTrakt { now = fromTrakt }
                if !now.isEmpty, now != shown { shown = now; await show(now) }
                // Listo cuando contestaron los dos tipos (y, si ninguno pudo, también Trakt).
                if settled && (!parts.isEmpty || fromTrakt != nil) { group.cancelAll(); break }
            }
        }
        if Task.isCancelled { throw CancellationError() }
        if parts.isEmpty && shown.isEmpty && failed.count == 2 { throw CinemetaError.network("Cinemeta no contestó") }
        return shown
    }

    /// Los nombres en tu idioma que ya se conocen (sin pedir nada).
    private func knownNames(_ found: [SearchResult]) async -> [String: String] {
        var names: [String: String] = [:]
        for kind in ["movie", "series"] {
            let ids = found.filter { $0.kind == kind }.map(\.metaID)
            if !ids.isEmpty { names.merge(await services.localizer.knownTitles(kind: kind, ids: ids)) { a, _ in a } }
        }
        return names
    }

    static let retryDelay: UInt64 = 600_000_000
    /// Todo lo que contesta Cinemeta (hasta 100 por tipo). Antes eran 18 en total, alternando tipos: el filtro decía
    /// siempre «Películas 9 · Series 9» aunque hubiera más de uno y menos del otro.
    static let resultLimit = 200
    /// Si Cinemeta no ha contestado nada en este tiempo, también se le pregunta a Trakt.
    static let hedgeDelay: UInt64 = 1_200_000_000

    /// Lo buscado en esta sesión (las últimas `memoryLimit` búsquedas), por texto en minúsculas.
    private var memory: [String: [Result]] = [:]
    private var memoryOrder: [String] = []
    private static let memoryLimit = 40

    private func remember(results: [Result], for key: String) {
        memory[key] = results
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        if memoryOrder.count > Self.memoryLimit { memory[memoryOrder.removeFirst()] = nil }
    }

    private func names(_ found: [SearchResult], kind: String) async -> [String: String] {
        let metas = found.filter { $0.kind == kind }.map { JSON.object(["id": .string($0.metaID), "name": .string($0.title)]) }
        guard !metas.isEmpty else { return [:] }
        var names: [String: String] = [:]
        for meta in await services.localizer.catalog(kind: kind, metas: metas) {
            if let id = meta["id"]?.string, let name = meta["name"]?.string { names[id] = name }
        }
        return names
    }

    /// Recuerda lo que buscaste (solo cuando abres un resultado).
    public func remember(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        recent = Array(([query] + recent.filter { $0.lowercased() != query.lowercased() }).prefix(8))
        services.kv.set("recent-searches", data: try? JSONEncoder().encode(recent))
    }

    public func clearRecent() { recent = []; services.kv.set("recent-searches", data: nil) }
}
