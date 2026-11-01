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
            if total != nil, filter.withoutClock != oldValue.withoutClock { total = nil }   // ya es otra búsqueda: el número viejo no aplica
            changed()
        }
    }
    /// Tus plataformas en tu país (Netflix, Disney+, HBO Max…): su nombre, su id de TMDB y su logo.
    public struct Platform: Sendable, Equatable, Identifiable { public var brand: String; public var name: String; public var id: Int; public var logo: String? }
    public private(set) var platforms: [Platform] = [] { didSet { changed() } }
    static let savedKey = "advanced-filter"
    static let totalKey = "advanced-filter.total"
    /// Cuántos títulos encontró la última búsqueda con este mismo filtro (la puerta de Buscar lo dice); nil: aún no se busca.
    public private(set) var total: Int? {
        didSet {
            services.kv.set(Self.totalKey, data: total.map { Data(String($0).utf8) })
            changed()
        }
    }
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
        total = services.kv.data(Self.totalKey).flatMap { Int(String(decoding: $0, as: UTF8.self)) }
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

    /// Cuántos títulos nuevos trae cada «más» como mínimo: una pantalla llena.
    static let fillTarget = 20
    /// Al llegar al final de la cuadrícula mientras aún cargaba: se pide otra vez al terminar.
    private var wantsMore = false

    /// Las páginas que sigan hasta juntar una pantalla de títulos nuevos (hasta cinco). Antes paraba con uno solo: con
    /// «Sin lo que ya vi» la primera página quedaba en tres o cuatro y, si el último ya se veía, nunca pedía la segunda.
    public func more() async {
        guard !isLoading else { wantsMore = true; return }
        repeat {
            wantsMore = false
            let before = results.count
            for _ in 0..<5 {
                await nextPage()
                if results.count - before >= Self.fillTarget || exhausted || failed { break }
            }
        } while wantsMore && !exhausted && !failed
    }

    private func nextPage() async {
        // Los premios vienen con la app: no necesitan la clave de TMDB (sin ella, «Óscar» daba cero resultados).
        guard !isLoading, !exhausted, available || !filter.awards.isEmpty else { return }
        let asked = filter
        isLoading = true
        defer { isLoading = false }
        do {
            // Premios: sus ganadores, que vienen con la app (una sola «página»).
            if !asked.awards.isEmpty {
                let hidden = asked.hideWatched ? watched : []
                results = asked.awardWinners(hiding: hidden)
                total = results.count; page = 1; exhausted = true
                return
            }
            let (rows, count) = try await services.tmdb.discoverCounting(asked, page: page + 1)
            guard asked.withoutClock == filter.withoutClock else { return }   // cambiaste el filtro mientras llegaba: se descarta
            if page == 0 { total = count }
            page += 1
            if rows.isEmpty { exhausted = true; return }
            // Cada título sale en cuanto llega su detalle (en orden), no cuando llegan los veinte (o los cientos de «Repartido
            // por décadas»): antes la pantalla esperaba a la última ficha para enseñar la primera.
            var have = Set(results.map(\.imdb))
            let hidden = asked.hideWatched ? watched : []
            _ = await ForYou.streamSuggestions(rows, reason: .popular, tmdb: services.tmdb) { [weak self] batch in
                guard let self, asked.withoutClock == self.filter.withoutClock else { return false }   // cambiaste el filtro: lo demás ya no sirve
                let fresh = batch.filter { !hidden.contains($0.imdb) && have.insert($0.imdb).inserted }
                if !fresh.isEmpty { self.results += fresh }
                return true
            }
        } catch {
            failed = results.isEmpty
        }
    }

    /// Quitar todo (el «Limpiar» del cajón).
    public func clear() {
        var fresh = AdvancedFilter()
        fresh.region = filter.region; fresh.hideWatched = filter.hideWatched; fresh.sort = filter.sort   // tus preferencias se quedan
        filter = fresh; results = []; searched = nil; total = nil
    }

    /// La hora de ahora en el filtro (al elegir «Que acabe antes de las…»), para que la cuenta de lo que cabe sea de hoy.
    public func refreshClock() { filter.nowMinute = AdvancedFilter.minuteOfDay(Date()) }
}
