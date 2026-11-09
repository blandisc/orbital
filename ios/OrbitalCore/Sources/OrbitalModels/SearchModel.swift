import Foundation
import OrbitalCore

@MainActor
public final class SearchModel: ObservableModel {
    public struct Result: Equatable, Identifiable {
        public var id: String { "\(kind):\(metaID)" }
        public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
        /// El póster de TMDB, si metahub no tiene el suyo (uno de cada cuatro resultados salía gris, Fernando 5 nov).
        public var fallbackPoster: String? = nil
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
            let (found, complete) = try await find(query) { [weak self] partial in
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
            let (movies, series) = await (movieNames, seriesNames)
            let names = movies.names.merging(series.names) { a, _ in a }, posters = movies.posters.merging(series.posters) { a, _ in a }
            // El póster de TMDB primero: el de metahub a veces es de otro título (Fernando, 8 nov: «Star Wars: Clone Wars» de
            // 2003 salía con el de un programa coreano). Si TMDB no tiene, el de Cinemeta.
            let localized = found.map { r in Result(kind: r.kind, metaID: r.metaID, title: names[r.metaID] ?? r.title, originalTitle: r.title,
                                                    poster: posters[r.metaID] ?? r.poster, year: r.year,
                                                    fallbackPoster: posters[r.metaID] == nil ? nil : r.poster) }
            // Solo se recuerda si contestaron todos y la traducción terminó (antes una búsqueda a medias, o vacía porque algo
            // falló, se quedaba guardada toda la sesión; cancelada por otra letra, se habrían guardado los nombres en inglés).
            if complete, !Task.isCancelled { remember(results: localized, for: key) }
            guard ticket == latest else { return }
            if localized != results { results = localized }
        } catch {
            // Escribir otra letra cancela la búsqueda en vuelo: eso no es un error de red (ni vacía lo que ya se veía).
            guard !Task.isCancelled, ticket == latest else { return }
            results = []; self.error = "\(error)"; searchedQuery = query
        }
    }

    /// Una pieza de la búsqueda: lo que contestó Trakt (nil = falló), un tipo de Cinemeta (nil = falló dos veces), o la
    /// señal de que Cinemeta tarda y ya se puede enseñar lo de Trakt solo.
    private enum Piece: Sendable { case trakt([SearchResult]?), kind(String, [JSON]?), hedge }

    /// Cinemeta y Trakt a la vez (Fernando, 2 nov 2026: desde que Trakt iba primero salían menos y menos conocidas, porque
    /// Trakt ordena por parecido del texto y, si traía algo, lo de Cinemeta se tiraba). Manda el orden de Cinemeta (lo más
    /// conocido primero, lo exacto arriba) y Trakt suma lo que Cinemeta no trajo. Lo de Trakt solo se enseña antes si
    /// Cinemeta tarda `hedgeDelay`. `complete`: contestaron todos (si no, la búsqueda no se recuerda). Solo si nadie
    /// contesta se dice que no se pudo.
    private func find(_ query: String, show: @escaping @MainActor ([SearchResult]) async -> Void) async throws -> (results: [SearchResult], complete: Bool) {
        let cinemeta = services.cinemeta, trakt = services.trakt.flatMap { $0.configured ? $0 : nil }
        var parts: [String: [JSON]] = [:], failed = Set<String>(), fromTrakt: [SearchResult]?, traktSettled = trakt == nil
        var waited = false, shown: [SearchResult] = []
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
            if let trakt {
                group.addTask {
                    guard let found = try? await trakt.search(query, limit: Self.traktLimit) else { return .trakt(nil) }
                    return .trakt(found.map { SearchResult(kind: $0.kind, metaID: $0.imdb, title: $0.title,
                                                           poster: String(format: ForYou.metahubPoster, $0.imdb), year: $0.year.map(String.init) ?? "") })
                }
                group.addTask { try? await Task.sleep(nanoseconds: Self.hedgeDelay); return .hedge }
            }
            for await piece in group {
                switch piece {
                case .trakt(let found): traktSettled = true; fromTrakt = found
                case .hedge: waited = true
                case .kind(let kind, let found?): parts[kind] = found
                case .kind(let kind, nil): failed.insert(kind)
                }
                let cinemetaSettled = parts.count + failed.count == 2
                let fromCinemeta = parts.isEmpty ? [] : CinemetaParsing.searchResults(query: query, movies: parts["movie"] ?? [], series: parts["series"] ?? [], limit: Self.resultLimit)
                // Lo de Trakt entra cuando ya está Cinemeta (o tardó): así no salta el orden al llegar.
                let now = Self.merged(cinemeta: fromCinemeta, trakt: cinemetaSettled || waited ? fromTrakt ?? [] : [])
                if !now.isEmpty, now != shown { shown = now; await show(now) }
                if traktSettled && cinemetaSettled { group.cancelAll(); break }
            }
        }
        if Task.isCancelled { throw CancellationError() }
        if shown.isEmpty && fromTrakt == nil && parts.isEmpty { throw SearchFailure() }
        return (shown, failed.isEmpty && (trakt == nil || fromTrakt != nil))
    }

    /// Lo de Cinemeta en su orden y, después, lo que solo trajo Trakt (en el suyo), sin repetir.
    nonisolated static func merged(cinemeta: [SearchResult], trakt: [SearchResult]) -> [SearchResult] {
        var seen = Set(cinemeta.map(\.metaID))
        return cinemeta + trakt.filter { seen.insert($0.metaID).inserted }
    }

    /// Ni Trakt ni Cinemeta contestaron.
    struct SearchFailure: Error, CustomStringConvertible { var description: String { "No pude buscar. Revisa tu conexión." } }

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
    /// Todo lo que contesta Cinemeta (hoy, hasta 20 por tipo) más lo de Trakt. Antes eran 18 en total, alternando tipos:
    /// el filtro decía siempre «Películas 9 · Series 9» aunque hubiera más de uno y menos del otro.
    static let resultLimit = 200
    /// Cuántos resultados se le piden a Trakt (películas y series juntas).
    static let traktLimit = 50
    /// Si Cinemeta no ha contestado en este tiempo, se enseña lo de Trakt solo (y Cinemeta, al llegar, pone su orden).
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

    /// Los nombres en tu idioma y, de reserva, los pósters de TMDB (la misma consulta).
    private func names(_ found: [SearchResult], kind: String) async -> (names: [String: String], posters: [String: String]) {
        let metas = found.filter { $0.kind == kind }.map { JSON.object(["id": .string($0.metaID), "name": .string($0.title)]) }
        guard !metas.isEmpty else { return ([:], [:]) }
        var names: [String: String] = [:], posters: [String: String] = [:]
        for meta in await services.localizer.catalog(kind: kind, metas: metas) {
            guard let id = meta["id"]?.string else { continue }
            if let name = meta["name"]?.string { names[id] = name }
            if let poster = meta[Localizer.posterKey]?.nonEmptyString { posters[id] = poster }
        }
        return (names, posters)
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
