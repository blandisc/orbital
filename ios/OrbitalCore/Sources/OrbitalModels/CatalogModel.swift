import Foundation
import OrbitalCore

public struct CatalogItem: Equatable, Identifiable, Sendable, Codable {
    public var id: String { "\(kind):\(metaID)" }
    public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
}

/// Buscar: lo que más se está viendo ahora en Trakt («En tendencia»), en películas y series, con los títulos en tu idioma.
/// Si Trakt no contesta, se queda la última copia guardada.
@MainActor
public final class CatalogModel: ObservableModel {
    public private(set) var movies: [CatalogItem] = [] { didSet { changed() } }
    public private(set) var series: [CatalogItem] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    /// Por qué no hay «Lo más popular hoy» (ni géneros): Trakt sin conectar, sin internet o Trakt que no contesta. nil: todo bien
    /// (o se enseña la última copia, sin aviso).
    public private(set) var degraded: Degraded? { didSet { if degraded != oldValue { changed() } } }
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
    /// Cuántos de cada tipo trae «Lo más popular hoy» (su lista completa llega a 100, películas y series alternadas).
    static let popularLimit = 50
    /// Cuántos de cada tipo trae un género; si «En tendencia» trae menos de `genreShort`, se completa con lo popular reciente.
    static let genreLimit = 30, genreShort = 20, genreRecentYears = 3

    /// Primero lo de Trakt tal cual (rápido: se ve en cuanto llega); luego, en tu idioma, solo lo que se enseña.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        async let m = trending("movie"), s = trending("series")
        let (movieMetas, seriesMetas) = await (m, s)
        guard !Task.isCancelled else { return }   // se fue de la pantalla a medias: se queda lo que ya había, sin error falso
        let failed = movieMetas == nil && seriesMetas == nil
        // Sin respuesta pero con copia: se enseña la copia, sin aviso (la de hoy llega al volver a abrir Buscar). Sin Trakt no
        // es la conexión: lo popular y los géneros salen de ahí (antes decía «Revisa tu conexión» con internet).
        if services.trakt?.configured != true { degraded = .notConnected(.trakt) }
        else { degraded = failed && movies.isEmpty && series.isEmpty ? Degraded.classify(nil, service: .trakt, online: services.isOnline()) : nil }
        guard !failed else { return }
        // Sin copia anterior, lo de Trakt tal cual mientras se traduce; con copia, se queda la traducida (no parpadea).
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


    /// Los géneros de «Explora» (nombres en inglés: la pantalla los traduce con `Vocabulary.genres`).
    public static let exploreGenres = ["Action", "Comedy", "Drama", "Sci-Fi", "Horror", "Thriller", "Animation", "Romance", "Crime", "Documentary"]

    /// El nombre de cada género para Trakt (`genres=`).
    static func traktGenre(_ name: String) -> String {
        name == "Sci-Fi" ? "science-fiction" : name.lowercased()
    }

    /// Lo más popular hoy, películas y series alternadas (la lista con puesto de Buscar).
    public var popular: [CatalogItem] { Self.interleave(movies, series) }

    /// Lo más visto ahora de un género, películas y series alternadas: `update` recibe primero lo de Trakt (se ve ya) y
    /// luego lo mismo en tu idioma.
    public func genre(_ name: String, update: @MainActor ([CatalogItem]) -> Void) async {
        async let m = genreMetas("movie", name), s = genreMetas("series", name)
        let (movieMetas, seriesMetas) = await (m, s)
        guard !Task.isCancelled else { return }
        update(Self.interleave(Self.items("movie", movieMetas), Self.items("series", seriesMetas)))
        async let tm = translated("movie", movieMetas, first: .max), ts = translated("series", seriesMetas, first: .max)
        let (movies, series) = await (tm, ts)
        guard !Task.isCancelled else { return }
        update(Self.interleave(movies, series))
    }

    static func interleave(_ movies: [CatalogItem], _ series: [CatalogItem]) -> [CatalogItem] {
        var out: [CatalogItem] = []
        for i in 0..<max(movies.count, series.count) {
            if i < movies.count { out.append(movies[i]) }
            if i < series.count { out.append(series[i]) }
        }
        return out
    }

    /// Lo que más se está viendo en Trakt (nil si no contestó o no hay Trakt), como fichas cortas.
    private func trending(_ kind: String) async -> [JSON]? {
        guard let trakt = services.trakt, trakt.configured,
              let found = try? await trakt.trending(kind: kind, limit: Self.popularLimit) else { return nil }
        return Self.metas(found)
    }

    /// Un género: «En tendencia» y, si sale corto, lo popular de los últimos años (sin repetir).
    private func genreMetas(_ kind: String, _ name: String) async -> [JSON] {
        guard let trakt = services.trakt, trakt.configured else { return [] }
        let slug = Self.traktGenre(name)
        var found = (try? await trakt.trending(kind: kind, limit: Self.genreLimit, genres: slug)) ?? []
        if found.count < Self.genreShort {
            let year = Calendar(identifier: .gregorian).component(.year, from: services.now())
            let recent = (try? await trakt.popular(kind: kind, limit: Self.genreLimit, years: "\(year - Self.genreRecentYears + 1)-\(year)", genres: slug)) ?? []
            let seen = Set(found.map(\.imdb))
            found += recent.filter { !seen.contains($0.imdb) }
        }
        return Self.metas(Array(found.prefix(Self.genreLimit)))
    }

    /// Lo de Trakt con la forma de una ficha de catálogo (para traducirlo igual que todo): id, nombre y año; el póster, de metahub.
    static func metas(_ entries: [TraktEntry]) -> [JSON] {
        entries.map { e in
            var meta: [String: JSON] = ["id": .string(e.imdb), "name": .string(e.title), "poster": .string(String(format: ForYou.metahubPoster, e.imdb))]
            if let year = e.year { meta["releaseInfo"] = .string(String(year)) }
            return .object(meta)
        }
    }

    /// Los primeros `first` en tu idioma (TMDB); el resto, como vienen de Trakt.
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
                               poster: original["poster"]?.string, year: CinemetaParsing.describe(original).year)
        }
    }
}
