import Foundation
import OrbitalCore

/// «Para ti»: el mosaico y las listas (Trakt y plataformas). Solo películas y series.
///
/// Con tu Orbital conectada, la curaduría se calcula una vez allá y aquí solo se enseña (mismas listas y
/// caché que la TV, por `RemoteForYou`); sin ella, o si no contesta, se calcula aquí mismo con `ForYou` local
/// (lo de siempre, sin aviso de error: la persona ni se entera de que falló el salto a la consola).
@MainActor
public final class ParaTiModel: ObservableModel {
    public enum Mode: Equatable { case mosaic, lists }
    /// Por qué el destacado «Para ti hoy» es lo que es (la etiqueta sobre el arte).
    public enum FeaturedReason: Equatable {
        case recommendedByTrakt, rank(Int, platform: String), trending, other(SuggestionReason)
    }
    public struct Featured: Equatable {
        public var item: Suggestion
        public var shelfID: String?
        public var reason: FeaturedReason
    }
    /// «Próximos estrenos»: por día (lista) o la semana (una tira de días).
    public enum CalendarLayout: Equatable { case byDay, week }
    /// De dónde salió lo que ves: la consola (misma curaduría que la TV) o este iPhone (lógica local).
    public enum Source: Equatable, Sendable { case console, phone }

    public var mode: Mode = .mosaic { didSet { changed() } }
    public private(set) var mosaic: [Suggestion] = [] { didSet { changed() } }
    public private(set) var lists: [ForYouList] = [] { didSet { changed() } }
    /// Los estantes del feed de Listas, en su orden (`ShelfPlanner`). Los vacíos se descartan al terminar de cargar.
    public private(set) var shelves: [ShelfPlan] = [] { didSet { changed() } }
    public private(set) var kind = "series" { didSet { changed() } }
    /// Las listas que aún se están pidiendo (su estante enseña esqueletos, no un hueco).
    public private(set) var loadingKeys = Set<String>() { didSet { changed() } }
    /// Cuántas veces se pidió «Actualizar»: el destacado pasa al siguiente de su estante.
    public private(set) var featuredRotation = 0 { didSet { changed() } }
    public private(set) var railItems: [String: [Suggestion]] = [:] { didSet { changed() } }
    public private(set) var watchlistKeys = Set<String>() { didSet { changed() } }
    public private(set) var traktLinked = false { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    /// Los episodios que salen de las series que sigues (Trakt), hoy y los próximos 14 días.
    public private(set) var airings: [Airing] = [] { didSet { changed() } }
    public var calendarLayout: CalendarLayout = .byDay { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    /// El mosaico es lo popular de Stremio (sin Trakt ni TMDB todavía): la pantalla invita a conectarlos.
    public private(set) var isGeneric = false { didSet { changed() } }
    /// De dónde vino lo que se ve ahora: la pantalla lo enseña en un pie discreto.
    public private(set) var source: Source = .phone { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) { self.services = services; super.init() }

    public var traktLists: [ForYouList] { lists.filter { $0.group != .platforms } }
    public var platformLists: [ForYouList] { lists.filter { $0.group == .platforms } }

    /// Los estantes que se pintan: con algo dentro, o todavía cargando (con esqueleto). Vacío o fallido: no se pinta.
    public var visibleShelves: [ShelfPlan] {
        let shown = shelves.filter { isLoading(shelf: $0) || !items(for: $0).isEmpty }
        // El respaldo de una marca se esconde si su lista con puesto sí trajo algo (o aún carga): la misma plataforma, una vez.
        let covered = Set(shown.filter { !$0.isFallback && $0.style == .top10 }.compactMap(\.list.brand))
        return shown.filter { !$0.isFallback || !covered.contains($0.list.brand ?? "") }
    }
    /// Ninguna fuente dio estantes: el feed cae a lo popular de Stremio y a la invitación a conectar fuentes.
    public var feedIsEmpty: Bool { !isLoading && visibleShelves.isEmpty }
    /// Mostrar «Conecta Trakt o tu Orbital»: no hay ninguna fuente tuya (solo lo popular de Stremio).
    public var needsSources: Bool { feedIsEmpty || isGeneric }
    /// «Series · Películas» solo tiene sentido si algún estante lo respeta.
    public var hasKindSplit: Bool { shelves.contains(where: \.splitsKinds) }

    public func isLoading(shelf: ShelfPlan) -> Bool {
        shelf.listIDs.contains { id in
            let k = key(listID: id, splits: shelf.splitsKinds)
            return loadingKeys.contains(k) || (isLoading && railItems[k] == nil)
        }
    }

    /// Lo que enseña un estante: las listas que lo forman, sin repetir títulos.
    public func items(for shelf: ShelfPlan) -> [Suggestion] {
        var seen = Set<String>()
        return shelf.listIDs.flatMap { railItems[key(listID: $0, splits: shelf.splitsKinds)] ?? [] }.filter { seen.insert($0.imdb).inserted }
    }

    /// «Para ti hoy»: la primera sugerencia con arte ancho del primer estante que la tenga (rota con «Actualizar»);
    /// sin estantes, la primera de lo popular del mosaico.
    public var featured: Featured? {
        let loaded = visibleShelves.map { (plan: $0, items: items(for: $0)) }
        if let pick = ShelfPlanner.featured(loaded, rotation: featuredRotation) {
            return Featured(item: pick.item, shelfID: pick.plan.id, reason: Self.reason(of: pick.item, in: pick.plan))
        }
        let stand = ShelfPlan(id: "mosaic", list: ForYouList(id: "mosaic", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: false),
                              listIDs: [], style: .plain)
        if let pick = ShelfPlanner.featured([(stand, mosaic)], rotation: featuredRotation) {
            return Featured(item: pick.item, shelfID: nil, reason: Self.reason(of: pick.item, in: pick.plan))
        }
        return nil
    }

    static func reason(of item: Suggestion, in plan: ShelfPlan) -> FeaturedReason {
        if plan.style == .top10, let rank = item.rank { return .rank(rank, platform: platformName(plan.list)) }
        switch item.reason {
        case .recommended: return .recommendedByTrakt
        case .trending: return .trending
        default: return .other(item.reason)
        }
    }

    private static func platformName(_ list: ForYouList) -> String {
        guard let brand = list.brand else { return list.title }
        return Tmdb.platforms.first { $0.brand == brand }?.name ?? brand.capitalized
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        // Lo que ya se ve se queda mientras se refresca (antes los estantes se vaciaban cada vez que volvías a la pestaña);
        // `loadShelves` solo pide lo que falta y «Actualizar» sí limpia.
        if services.orbital.isConfigured, await loadFromConsole() { return }
        await loadFromPhone()
    }

    /// Intenta traer «Para ti» de tu Orbital. `false` sin tocar nada: quien llama cae a la lógica local.
    /// Todo se pide a la vez: el mosaico y los estantes aparecen en cuanto llegan, sin esperar al calendario.
    private func loadFromConsole() async -> Bool {
        let remote = services.forYouRemote, forYou = services.forYou
        async let fetchedLists = try? remote.lists()
        async let fetchedMosaic = try? remote.mosaic()
        // Si la consola no contesta, se cae a la lógica local sin esperar el calendario: este se pide solo si contestó.
        guard let newLists = await fetchedLists, let newMosaic = await fetchedMosaic else { return false }
        async let fetchedKeys = try? remote.watchlistKeys()
        async let fetchedAirings = try? forYou.calendar()   // el calendario sale de tu Trakt (la consola trae la lista «estrenos», que aquí no se pinta como estante)
        if source != .console { railItems = [:] }   // venía del iPhone: los estantes de la otra fuente no se mezclan
        source = .console
        traktLinked = newLists.contains { $0.id == "watchlist" || $0.id == "mine" }
        lists = newLists
        shelves = ShelfPlanner.plan(newLists)
        mosaic = newMosaic
        isGeneric = false
        error = mosaic.isEmpty && lists.isEmpty ? "Tu Orbital no tiene sugerencias todavía." : nil
        async let shelvesLoaded: Void = loadShelves()
        watchlistKeys = await fetchedKeys ?? []
        if let fetched = await fetchedAirings, !Task.isCancelled {
            airings = fetched
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno» también con la consola
        }
        await shelvesLoaded
        await topUpMosaic()
        return true
    }

    private func loadFromPhone() async {
        if source != .phone { railItems = [:] }
        source = .phone
        let forYou = services.forYou
        async let linked = forYou.traktLinked
        async let newLists = forYou.lists()
        async let keys = forYou.watchlistKeys()
        async let newAirings = try? forYou.calendar()
        async let newMosaic = forYou.mosaic()
        // El mosaico es lo primero que se ve: en cuanto llega se pinta.
        mosaic = await newMosaic
        // Sin Trakt ni TMDB el mosaico no quedaría vacío: lo más popular de Stremio (Cinemeta no pide claves).
        isGeneric = mosaic.isEmpty
        if isGeneric { mosaic = await popular() }
        lists = await newLists
        shelves = ShelfPlanner.plan(lists)
        async let shelvesLoaded: Void = loadShelves()
        traktLinked = await linked
        watchlistKeys = await keys
        if let fetched = await newAirings, !Task.isCancelled {   // sin respuesta (o cancelado), el widget conserva lo que tenía
            airings = fetched
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno»
        }
        if mosaic.isEmpty && lists.isEmpty { error = services.appSettings.traktEnabled ? nil : "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias." }
        else { error = nil }
        await shelvesLoaded
        await topUpMosaic()
    }

    /// Con pocas sugerencias el mosaico repetía la misma portada en toda la pantalla: se completa con lo que ya
    /// trajeron los estantes (alternados, sin repetir) y, si aún faltan, con lo popular de Stremio.
    private func topUpMosaic() async {
        guard mosaic.count < MosaicPool.minimumVariety else { return }
        let fromShelves = visibleShelves.map { items(for: $0) }
        var filled = MosaicPool.toppedUp(mosaic, with: fromShelves)
        if filled.count < MosaicPool.minimumVariety { filled = MosaicPool.toppedUp(filled, with: [await popular()]) }
        mosaic = filled
    }

    /// «Series · Películas»: solo cambia los estantes con `split`; el resto sigue igual.
    public func setKind(_ kind: String) async {
        self.kind = kind == "movie" ? "movie" : "series"
        await loadShelves()
    }

    public func key(_ list: ForYouList) -> String { key(listID: list.id, splits: list.splitsKinds) }
    func key(listID: String, splits: Bool) -> String { "\(listID):\(splits ? kind : "-")" }

    /// Pide el contenido de todos los estantes a la vez (cada uno aparece cuando llega; el orden no cambia).
    private func loadShelves() async {
        var wanted: [(key: String, listID: String)] = []
        for shelf in shelves {
            for id in shelf.listIDs {
                let k = key(listID: id, splits: shelf.splitsKinds)
                if id != "estrenos", railItems[k] == nil, !wanted.contains(where: { $0.key == k }) { wanted.append((k, id)) }
            }
        }
        guard !wanted.isEmpty else { return }
        loadingKeys.formUnion(wanted.map(\.key))
        let remote = services.forYouRemote, local = services.forYou, source = source, kind = kind
        await withTaskGroup(of: (String, [Suggestion]?).self) { group in
            for entry in wanted {
                group.addTask {
                    switch source {
                    case .console: return (entry.key, try? await remote.items(listID: entry.listID, kind: kind))
                    case .phone: return (entry.key, try? await local.items(listID: entry.listID, kind: kind))
                    }
                }
            }
            for await (k, found) in group {
                loadingKeys.remove(k)
                // Si falló o se canceló (te fuiste a mitad de la carga), no se guarda vacío: la próxima carga lo vuelve a pedir.
                if let found, !Task.isCancelled { railItems[k] = found }
            }
        }
    }

    private func itemsFromCurrentSource(listID: String) async -> [Suggestion] {
        switch source {
        case .console: return (try? await services.forYouRemote.items(listID: listID, kind: kind)) ?? []
        case .phone: return (try? await services.forYou.items(listID: listID, kind: kind)) ?? []
        }
    }

    public func items(for list: ForYouList) -> [Suggestion] { railItems[key(list)] ?? [] }

    /// Lo más popular de Cinemeta, series y películas alternadas, en tu idioma.
    private func popular() async -> [Suggestion] {
        async let series = popular("series"), movies = popular("movie")
        let dismissed = await services.forYou.dismissedIDs()
        return ForYou.interleave([await series, await movies], limit: ForYou.mosaicSize).filter { !dismissed.contains($0.imdb) }
    }

    private func popular(_ kind: String) async -> [Suggestion] {
        guard let metas = try? await services.cinemeta.catalog(kind) else { return [] }
        let top = Array(metas.prefix(ForYou.mosaicSize / 2))
        let localized = await services.localizer.catalog(kind: kind, metas: top)
        return zip(top, localized).compactMap { original, translated in
            guard let id = original["id"]?.string, id.hasPrefix("tt"), let name = original["name"]?.string,
                  let poster = CinemetaParsing.medium(original["poster"]?.string) else { return nil }
            let info = CinemetaParsing.describe(translated)
            let minutes = Int(CinemetaParsing.runtimeSeconds(info.runtime) / 60)
            return Suggestion(kind: kind, imdb: id, title: translated["name"]?.string ?? name, year: Int(info.year.prefix(4)),
                              runtime: minutes > 0 ? minutes : nil,
                              overview: info.description, poster: poster, wide: original["background"]?.string ?? poster,
                              logo: "https://images.metahub.space/logo/medium/\(id)/img", reason: .popular)
        }
    }

    /// «No me interesa».
    public func dismiss(_ s: Suggestion) async {
        switch source {
        case .console: await services.forYouRemote.dismiss(s.imdb)
        case .phone: await services.forYou.dismiss(s.imdb)
        }
        mosaic.removeAll { $0.imdb == s.imdb }
        railItems = railItems.mapValues { $0.filter { $0.imdb != s.imdb } }
        airings.removeAll { $0.series.imdb == s.imdb }
    }

    /// El botón «Actualizar»: limpia la caché (de la consola o local, según de dónde viniera) y vuelve a cargar.
    public func refresh() async {
        switch source {
        case .console: await services.forYouRemote.clearCache()
        case .phone: await services.forYou.clearCache()
        }
        railItems = [:]
        featuredRotation += 1
        await load()
    }
}
