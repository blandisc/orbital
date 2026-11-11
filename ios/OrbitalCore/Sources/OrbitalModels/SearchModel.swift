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
    /// Cuánto se espera a que alguien conteste antes de decir que no se pudo (revisión del 11 nov: tras 45 s seguía el
    /// esqueleto). Las pruebas lo acortan.
    public var timeout: UInt64 = 10_000_000_000

    /// Qué enseña la pantalla para lo que está escrito. Vive aquí (no en la vista) para que una búsqueda siempre termine:
    /// con resultados, sin resultados o con un error que se puede reintentar.
    public enum Status: Equatable {
        /// Menos de dos letras: las sugerencias, no resultados.
        case idle
        /// Esperando la primera respuesta de lo escrito: el esqueleto.
        case waiting
        /// Hay resultados (aunque falten los nombres en tu idioma o la otra fuente).
        case found
        /// Contestaron y no hay nada con ese nombre.
        case empty
        /// Nadie contestó o tardaron demasiado: aviso con «Reintentar».
        case failed(String)
    }

    /// El estado para el texto del campo (puede ir una letra adelante de la última búsqueda).
    public func status(for text: String) -> Status {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return .idle }
        guard searchedQuery == query else { return .waiting }
        if let error, !isSearching { return .failed(error) }
        if !results.isEmpty { return .found }
        return isSearching ? .waiting : .empty
    }

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
            let answer = try await within(timeout) { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.find(query) { [weak self] partial in
                guard let self, ticket == self.latest else { return }
                let known = await self.knownNames(partial)
                guard ticket == self.latest else { return }
                self.results = partial.map { Result(kind: $0.kind, metaID: $0.metaID, title: known[$0.metaID] ?? $0.title, originalTitle: $0.title,
                                                    poster: $0.poster, year: $0.year) }
                self.error = nil
                self.searchedQuery = query
                }
            }
            guard ticket == latest else { return }
            isSearching = false
            // Tardaron demasiado: lo que ya llegó se queda (sin recordarse); si no llegó nada, se dice y se puede reintentar.
            // Si la respuesta llega después, igual se pone (la búsqueda sigue siendo esta).
            guard let (found, complete) = answer else {
                if searchedQuery != query || results.isEmpty { results = []; error = SearchFailure(slow: true).description; searchedQuery = query }
                return
            }
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
            // Contestaron y no trajeron nada: también es una respuesta (antes la pantalla esperaba para siempre).
            searchedQuery = query
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

    /// Lo de Cinemeta en su orden y, después, lo que solo trajo Trakt (en el suyo), sin repetir; lo de otro alfabeto al final.
    nonisolated static func merged(cinemeta: [SearchResult], trakt: [SearchResult]) -> [SearchResult] {
        var seen = Set(cinemeta.map(\.metaID))
        // Lo escrito en otro alfabeto («Бархан») al final: no se esconde, pero no se mezcla con lo que lees (11 nov).
        return OtherScript.readableFirst(cinemeta + trakt.filter { seen.insert($0.metaID).inserted }) { $0.title }
    }

    /// `work` o nil si pasa `limit` antes. No espera a que `work` se rinda (la red no siempre atiende la cancelación): sigue
    /// por su cuenta y lo que traiga se pone si la búsqueda sigue siendo la misma. Si cancelan la búsqueda, se cancela también.
    private func within<T: Sendable>(_ limit: UInt64, _ work: @escaping @MainActor @Sendable () async throws -> T) async throws -> T? {
        let gate = Gate<T?>()
        let job = Task { @MainActor in
            do { gate.open(.success(try await work())) } catch { gate.open(.failure(error)) }
        }
        let clock = Task { try? await Task.sleep(nanoseconds: limit); gate.open(.success(nil)) }
        return try await withTaskCancellationHandler {
            let value = try await gate.wait()
            clock.cancel()
            return value
        } onCancel: {
            job.cancel(); clock.cancel(); gate.open(.failure(CancellationError()))
        }
    }

    /// Ni Trakt ni Cinemeta contestaron.
    struct SearchFailure: Error, CustomStringConvertible {
        var slow = false
        var description: String { slow ? "La búsqueda tardó demasiado. Revisa tu conexión." : "No pude buscar. Revisa tu conexión." }
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

/// Una respuesta que se da una sola vez: la primera que llega (el trabajo, el reloj o la cancelación) gana.
private final class Gate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    private var waiter: CheckedContinuation<T, Error>?

    func open(_ value: Result<T, Error>) {
        let resume: CheckedContinuation<T, Error>? = lock.withLock {
            guard result == nil else { return nil }
            result = value
            defer { waiter = nil }
            return waiter
        }
        resume?.resume(with: value)
    }

    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            let ready: Result<T, Error>? = lock.withLock {
                if let result { return result }
                waiter = c
                return nil
            }
            if let ready { c.resume(with: ready) }
        }
    }
}
