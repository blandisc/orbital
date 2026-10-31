import Foundation
import OrbitalCore

/// El cajón del filtro avanzado: lo que eliges (sin pedir nada mientras eliges: sin conteos en vivo) y, al tocar «Ver
/// resultados», la búsqueda en TMDB por páginas. Lo elegido se recuerda aunque cierres la app; lo que ya viste no sale.
@MainActor
public final class AdvancedFilterModel: ObservableModel {
    public var filter = AdvancedFilter() {
        didSet {
            guard filter != oldValue else { return }
            services.kv.set(Self.savedKey, data: try? JSONEncoder().encode(filter))
            changed()
        }
    }
    /// Tus plataformas en tu país (Netflix, Disney+, HBO Max…): su nombre, su id de TMDB y su logo.
    public struct Platform: Sendable, Equatable, Identifiable { public var brand: String; public var name: String; public var id: Int; public var logo: String? }
    public private(set) var platforms: [Platform] = [] { didSet { changed() } }
    static let savedKey = "advanced-filter"
    private let watchedSource: (@MainActor () async -> Set<String>)?
    private var watched: Set<String> = []
    public private(set) var results: [Suggestion] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var failed = false { didSet { changed() } }
    /// Ya no hay más páginas.
    public private(set) var exhausted = false
    private var page = 0
    private var searched: AdvancedFilter?

    private let services: Services
    /// `watched`: lo que ya viste (Trakt), para «Ocultar lo que ya vi».
    public init(_ services: Services, watched: (@MainActor () async -> Set<String>)? = nil) {
        self.services = services; self.watchedSource = watched
        super.init()
        if let data = services.kv.data(Self.savedKey), var saved = try? JSONDecoder().decode(AdvancedFilter.self, from: data) {
            let fresh = AdvancedFilter()
            saved.today = fresh.today; saved.currentYear = fresh.currentYear   // lo guardado no trae el día de hoy viejo
            filter = saved
        }
    }

    /// Las plataformas que hay en tu país (una vez; ForYou las recuerda). También pone tu país en el filtro.
    public func loadPlatforms() async {
        guard platforms.isEmpty else { return }
        let found = await services.forYou.platforms()
        platforms = Tmdb.platforms.compactMap { p in found[p.brand].map { Platform(brand: p.brand, name: p.name, id: $0.id, logo: $0.logo) } }
        let region = services.forYou.watchRegion
        if filter.region != region { filter.region = region }
    }

    /// Sin la clave de TMDB no hay de dónde buscar (la pantalla lo dice y lleva a Ajustes).
    public var available: Bool { services.tmdb.configured }

    /// Busca desde la primera página con el filtro de ahora (si es el mismo de la última vez, no vuelve a pedir).
    public func search() async {
        guard searched != filter || results.isEmpty else { return }
        searched = filter; page = 0; exhausted = false; results = []; failed = false
        if filter.hideWatched, let watchedSource { watched = await watchedSource() }
        await more()
    }

    /// La siguiente página (al llegar al final de la cuadrícula). Si una página no trae nada nuevo (todo ya estaba), pide la
    /// que sigue, hasta tres, para que la cuadrícula crezca y el «llegué al final» vuelva a dispararse.
    public func more() async {
        for _ in 0..<3 {
            let before = results.count
            await nextPage()
            if results.count > before || exhausted || failed || isLoading { return }
        }
    }

    private func nextPage() async {
        guard !isLoading, !exhausted, available else { return }
        let asked = filter
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await services.tmdb.discover(asked, page: page + 1)
            guard asked == filter else { return }   // cambiaste el filtro mientras llegaba: se descarta
            page += 1
            if rows.isEmpty { exhausted = true; return }
            let found = await ForYou.suggestions(rows, reason: .popular, tmdb: services.tmdb)
            let have = Set(results.map(\.imdb))
            let hidden = asked.hideWatched ? watched : []
            results += found.filter { !have.contains($0.imdb) && !hidden.contains($0.imdb) }
        } catch {
            failed = results.isEmpty
        }
    }

    /// Quitar todo (el «Limpiar» del cajón).
    public func clear() {
        var fresh = AdvancedFilter()
        fresh.region = filter.region; fresh.hideWatched = filter.hideWatched; fresh.sort = filter.sort   // tus preferencias se quedan
        filter = fresh; results = []; searched = nil
    }
}
