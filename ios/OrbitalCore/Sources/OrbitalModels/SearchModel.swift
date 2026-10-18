import Foundation
import OrbitalCore

@MainActor
public final class SearchModel: ObservableModel {
    public struct Result: Equatable, Identifiable {
        public var id: String { "\(kind):\(metaID)" }
        public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
    }

    public private(set) var results: [Result] = [] { didSet { changed() } }
    public private(set) var isSearching = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    /// Lo que se buscó para los `results` de ahora: hasta que la búsqueda nueva contesta, la pantalla no dice «Sin resultados».
    public private(set) var searchedQuery: String? { didSet { changed() } }
    public private(set) var recent: [String] { didSet { changed() } }
    private let services: Services
    private var latest = 0

    public init(_ services: Services) {
        self.services = services
        recent = services.kv.data("recent-searches").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        super.init()
    }

    /// Busca películas y series; la última búsqueda manda (si escribes rápido, las viejas se descartan).
    /// Los resultados de Cinemeta se ven en cuanto llegan; los nombres en tu idioma (TMDB, uno por título) se ponen
    /// después, sin hacerte esperar. Lo ya buscado (borrar una letra, volver a escribirla) sale al instante de memoria.
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
            let found = try await find(query)
            guard ticket == latest else { return }
            results = found.map { Result(kind: $0.kind, metaID: $0.metaID, title: $0.title, originalTitle: $0.title, poster: $0.poster, year: $0.year) }
            error = nil
            searchedQuery = query
            isSearching = false
            // Los nombres en tu idioma, a la vez (películas y series), y solo si la búsqueda sigue siendo esta.
            async let movieNames = names(found, kind: "movie")
            async let seriesNames = names(found, kind: "series")
            let names = await movieNames.merging(seriesNames) { a, _ in a }
            let localized = results.map { r in var r = r; r.title = names[r.metaID] ?? r.title; return r }
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

    /// Cinemeta, con un reintento (a veces contesta con un error pasajero, como un 550); si sigue sin contestar, Trakt
    /// (si está configurado). Solo si los dos fallan se dice que no se pudo.
    private func find(_ query: String) async throws -> [SearchResult] {
        do { return try await services.cinemeta.searchAll(query) } catch where !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.retryDelay)
            do { return try await services.cinemeta.searchAll(query) } catch where !Task.isCancelled {
                guard let trakt = services.trakt, trakt.configured, let found = try? await trakt.search(query), !found.isEmpty else { throw error }
                return found.map { SearchResult(kind: $0.kind, metaID: $0.imdb, title: $0.title, poster: String(format: ForYou.metahubPoster, $0.imdb), year: $0.year.map(String.init) ?? "") }
            }
        }
    }

    static let retryDelay: UInt64 = 600_000_000

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
