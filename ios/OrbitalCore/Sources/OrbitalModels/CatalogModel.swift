import Foundation
import OrbitalCore

public struct CatalogItem: Equatable, Identifiable, Sendable {
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

    public init(_ services: Services) { self.services = services; super.init() }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        async let m = rail("movie"), s = rail("series")
        let (movies, series) = await (m, s)
        self.movies = movies.items; self.series = series.items
        error = (movies.failed && series.failed) ? "No pude leer el catálogo de Stremio. Revisa tu conexión." : nil
    }

    private func rail(_ kind: String) async -> (items: [CatalogItem], failed: Bool) {
        guard let metas = try? await services.cinemeta.catalog(kind) else { return ([], true) }
        let top = Array(metas.prefix(30))
        let localized = await services.localizer.catalog(kind: kind, metas: top)
        return (zip(top, localized).compactMap { original, translated in
            guard let id = original["id"]?.string, let name = original["name"]?.string else { return nil }
            return CatalogItem(kind: kind, metaID: id, title: translated["name"]?.string ?? name, originalTitle: name,
                               poster: CinemetaParsing.medium(original["poster"]?.string), year: CinemetaParsing.describe(original).year)
        }, false)
    }
}
