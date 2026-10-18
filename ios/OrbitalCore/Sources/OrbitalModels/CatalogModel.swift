import Foundation
import OrbitalCore

public struct CatalogItem: Equatable, Identifiable, Sendable, Codable {
    public var id: String { "\(kind):\(metaID)" }
    public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
}

/// «Ver»: lo más popular de Cinemeta, en películas y series, con los títulos en tu idioma.
@MainActor
public final class CatalogModel: ObservableModel {
    public private(set) var movies: [CatalogItem] = [] { didSet { changed() } }
    public private(set) var series: [CatalogItem] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private let services: Services

    /// La última copia de lo popular: Buscar la enseña al instante y la cambia cuando llega la de hoy.
    static let cacheKey = "catalog-popular"
    private struct Cache: Codable { var movies: [CatalogItem]; var series: [CatalogItem] }

    public init(_ services: Services) {
        self.services = services
        super.init()
        if let data = services.kv.data(Self.cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            movies = cache.movies; series = cache.series
        }
    }

    /// Cuántos de cada tipo se traducen para Buscar (la lista con puesto enseña 5, películas y series alternadas).
    static let translatedForSearch = 6

    /// Primero lo de Cinemeta tal cual (rápido: se ve en cuanto llega); luego, en tu idioma, solo lo que se enseña.
    /// Antes se esperaba a traducir 60 títulos con TMDB para enseñar 5, y Buscar tardaba en aparecer.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        async let m = fetch("movie"), s = fetch("series")
        let (movieMetas, seriesMetas) = await (m, s)
        guard !Task.isCancelled else { return }   // se fue de la pantalla a medias: se queda lo que ya había, sin error falso
        error = (movieMetas == nil && seriesMetas == nil) ? "No pude leer el catálogo de Stremio. Revisa tu conexión." : nil
        guard movieMetas != nil || seriesMetas != nil else { return }
        // Sin copia anterior, lo de Cinemeta tal cual mientras se traduce; con copia, se queda la traducida (no parpadea).
        if movies.isEmpty { movies = Self.items("movie", movieMetas ?? []) }
        if series.isEmpty { series = Self.items("series", seriesMetas ?? []) }
        let top = Self.translatedForSearch
        async let tm = translated("movie", movieMetas ?? [], first: top), ts = translated("series", seriesMetas ?? [], first: top)
        let (newMovies, newSeries) = await (tm, ts)
        guard !Task.isCancelled else { return }
        if !newMovies.isEmpty { movies = newMovies }
        if !newSeries.isEmpty { series = newSeries }
        services.kv.set(Self.cacheKey, data: try? JSONEncoder().encode(Cache(movies: Array(movies.prefix(Self.translatedForSearch)), series: Array(series.prefix(Self.translatedForSearch)))))
    }

    /// Los géneros de «Explora» (nombres de Cinemeta, en inglés: la pantalla los traduce con `Vocabulary.genres`).
    public static let exploreGenres = ["Action", "Comedy", "Drama", "Sci-Fi", "Horror", "Thriller", "Animation", "Romance", "Crime", "Documentary"]

    /// Lo más popular hoy, películas y series alternadas (la lista con puesto de Buscar).
    public var popular: [CatalogItem] { Self.interleave(movies, series) }

    /// Lo más popular de un género, películas y series alternadas: `update` recibe primero lo de Cinemeta (se ve ya) y
    /// luego lo mismo en tu idioma.
    public func genre(_ name: String, update: @MainActor ([CatalogItem]) -> Void) async {
        async let m = fetch("movie", genre: name), s = fetch("series", genre: name)
        let (movieMetas, seriesMetas) = await (m, s)
        guard !Task.isCancelled else { return }
        update(Self.interleave(Self.items("movie", movieMetas ?? []), Self.items("series", seriesMetas ?? [])))
        async let tm = translated("movie", movieMetas ?? [], first: .max), ts = translated("series", seriesMetas ?? [], first: .max)
        let (movies, series) = await (tm, ts)
        guard !Task.isCancelled else { return }
        update(Self.interleave(movies, series))
    }

    private static func interleave(_ movies: [CatalogItem], _ series: [CatalogItem]) -> [CatalogItem] {
        var out: [CatalogItem] = []
        for i in 0..<max(movies.count, series.count) {
            if i < movies.count { out.append(movies[i]) }
            if i < series.count { out.append(series[i]) }
        }
        return out
    }

    /// Lo popular de Cinemeta (nil si no contestó).
    private func fetch(_ kind: String, genre: String? = nil) async -> [JSON]? {
        guard let metas = try? await services.cinemeta.catalog(kind, genre: genre) else { return nil }
        return Array(metas.prefix(30))
    }

    /// Los primeros `first` en tu idioma (TMDB); el resto, como vienen de Cinemeta.
    private func translated(_ kind: String, _ metas: [JSON], first: Int) async -> [CatalogItem] {
        let head = Array(metas.prefix(first))
        let localized = await services.localizer.catalog(kind: kind, metas: head)
        return Self.items(kind, metas, names: localized)
    }

    private static func items(_ kind: String, _ metas: [JSON], names: [JSON] = []) -> [CatalogItem] {
        metas.enumerated().compactMap { i, original in
            guard let id = original["id"]?.string, let name = original["name"]?.string else { return nil }
            let translated = names.indices.contains(i) ? names[i]["name"]?.string : nil
            return CatalogItem(kind: kind, metaID: id, title: translated ?? name, originalTitle: name,
                               poster: CinemetaParsing.medium(original["poster"]?.string), year: CinemetaParsing.describe(original).year)
        }
    }
}
