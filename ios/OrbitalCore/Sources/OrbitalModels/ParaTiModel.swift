import Foundation
import OrbitalCore

/// «Para ti»: el mosaico y las listas (Trakt y plataformas). Solo películas y series.
///
/// Con tu Orbital conectada, la curaduría se calcula una vez allá y aquí solo se enseña (mismas listas y
/// caché que la TV, por `RemoteForYou`); sin ella, o si no contesta, se calcula aquí mismo con `ForYou` local
/// (lo de siempre, sin aviso de error: la persona ni se entera de que falló el salto a la consola).
/// El porqué en un póster: sale pronto (ese día) o su puesto en una plataforma.
public enum PosterBadge: Sendable, Equatable {
    case airs(Date)
    case rank(Int, platform: String)
}

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
    /// «Todo», «Series» o «Películas» (`all`, `series`, `movie`): los estantes con `split` enseñan eso; «Todo» alterna ambos.
    public private(set) var kind = "all" { didSet { changed() } }
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
    /// «Porque viste X»: lo último que viste y lo que Trakt relaciona con él (nil sin Trakt o sin relacionados).
    public private(set) var because: (seed: TraktEntry, items: [Suggestion])? { didSet { changed() } }
    /// «Nuevo en tus plataformas» (TMDB): series con episodios recientes y películas recién llegadas, de tus plataformas.
    public private(set) var newOnPlatforms: [Suggestion] = [] { didSet { changed() } }
    /// El porqué de cada título en un póster (lo más fuerte: que sale pronto, o su puesto en una plataforma), por IMDb.
    public private(set) var badges: [String: PosterBadge] = [:] { didSet { if oldValue != badges { changed() } } }
    /// Cuántos días cubre `airings` desde hoy: crece de dos en dos semanas al deslizar la tira hasta el final.
    public private(set) var airingDays = ForYou.calendarDays { didSet { changed() } }
    /// Hasta dónde se puede deslizar la tira (Trakt contesta hasta 31 días por pedido; más allá casi no hay fechas).
    public static let maxAiringDays = 84
    private var loadingMoreAirings = false
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
    public var featured: Featured? { featuredSlides.first }

    /// El carrusel del destacado: varias de la misma lista de donde sale el primero (el Top 10 de Netflix, tus
    /// recomendaciones…), cada una con su motivo («N.º 2 en Netflix»).
    public var featuredSlides: [Featured] {
        let loaded = visibleShelves.map { (plan: $0, items: items(for: $0)) }
        if let pick = ShelfPlanner.featuredSlides(loaded, rotation: featuredRotation) {
            return pick.items.map { Featured(item: $0, shelfID: pick.plan.id, reason: Self.reason(of: $0, in: pick.plan)) }
        }
        let stand = ShelfPlan(id: "mosaic", list: ForYouList(id: "mosaic", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: false),
                              listIDs: [], style: .plain)
        if let pick = ShelfPlanner.featuredSlides([(stand, mosaic)], rotation: featuredRotation) {
            return pick.items.map { Featured(item: $0, shelfID: nil, reason: Self.reason(of: $0, in: pick.plan)) }
        }
        return []
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
        if services.forYouFromConsole, services.orbital.isConfigured {
            if await loadFromConsole() { return }
            // Cancelada (cambiaste de pestaña a media carga): no es que la consola no conteste; no se cae a las listas del
            // iPhone (sin Top 10 ni plataformas) ni se borran los estantes.
            guard !Task.isCancelled else { return }
        }
        await loadFromPhone()
    }

    /// Intenta traer «Para ti» de tu Orbital. `false` sin tocar nada: quien llama cae a la lógica local.
    /// Todo se pide a la vez: el mosaico y los estantes aparecen en cuanto llegan, sin esperar al calendario.
    private func loadFromConsole() async -> Bool {
        let remote = services.forYouRemote, forYou = services.forYou
        // Mientras contesta la consola, el mosaico de la última vez (guardado en el teléfono) aparece al instante.
        var showedSaved = false
        if mosaic.isEmpty {
            let saved = await forYou.cachedMosaic()
            if !saved.isEmpty { mosaic = saved; showedSaved = true }
        }
        async let fetchedLists = try? remote.lists()
        async let fetchedMosaic = try? remote.mosaic()
        // Si la consola no contesta, se cae a la lógica local sin esperar el calendario: este se pide solo si contestó.
        guard let newLists = await fetchedLists, let newMosaic = await fetchedMosaic else { return false }
        async let fetchedKeys = try? remote.watchlistKeys()
        async let fetchedBecause = forYou.becauseYouWatched()
        async let fetchedAirings = try? forYou.calendar()   // el calendario sale de tu Trakt (la consola trae la lista «estrenos», que aquí no se pinta como estante)
        if source != .console { railItems = [:] }   // venía del iPhone: los estantes de la otra fuente no se mezclan
        source = .console
        traktLinked = newLists.contains { $0.id == "watchlist" || $0.id == "mine" }
        lists = newLists
        shelves = ShelfPlanner.plan(newLists)
        // El nuevo se guarda para la próxima vez; si ya se veía el guardado, no se cambia bajo tu dedo («Actualizar» lo trae).
        await forYou.saveMosaic(newMosaic)
        if !showedSaved || mosaic.isEmpty { mosaic = newMosaic }
        isGeneric = false
        error = mosaic.isEmpty && lists.isEmpty ? "Tu Orbital no tiene sugerencias todavía." : nil
        async let shelvesLoaded: Void = loadShelves()
        watchlistKeys = await fetchedKeys ?? []
        if let fetched = await fetchedAirings, !Task.isCancelled {
            airings = fetched; airingDays = ForYou.calendarDays
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno» también con la consola
        }
        await shelvesLoaded
        because = await fetchedBecause
        await loadNewOnPlatforms()
        rebuildBadges()
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
        async let newBecause = forYou.becauseYouWatched()
        async let newMosaic = forYou.mosaic()
        // Al abrir la app, el de la última vez (guardado en el teléfono): el mosaico aparece al instante. El nuevo no lo
        // reemplaza en ese momento (lo movería bajo tu dedo): queda guardado para la próxima vez; «Actualizar» lo trae ya.
        var showedSaved = false
        if mosaic.isEmpty {
            let saved = await forYou.cachedMosaic()
            if !saved.isEmpty { mosaic = saved; showedSaved = true }
        }
        let fresh = await newMosaic
        if !showedSaved, !fresh.isEmpty || mosaic.isEmpty { mosaic = fresh }
        // Sin Trakt ni TMDB el mosaico no quedaría vacío: lo más popular de Stremio (Cinemeta no pide claves).
        isGeneric = mosaic.isEmpty
        if isGeneric { mosaic = await popular() }
        lists = await newLists
        shelves = ShelfPlanner.plan(lists)
        async let shelvesLoaded: Void = loadShelves()
        traktLinked = await linked
        watchlistKeys = await keys
        if let fetched = await newAirings, !Task.isCancelled {   // sin respuesta (o cancelado), el widget conserva lo que tenía
            airings = fetched; airingDays = ForYou.calendarDays
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno»
        }
        await shelvesLoaded
        because = await newBecause
        await loadNewOnPlatforms()
        rebuildBadges()
        // El aviso, solo si de verdad no hay nada que enseñar (las listas con puesto existen siempre, pero sin red llegan vacías).
        if mosaic.isEmpty && shelves.allSatisfy({ items(for: $0).isEmpty }) { error = services.appSettings.traktEnabled ? nil : "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias." }
        else { error = nil }
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

    /// Las dos semanas siguientes del calendario (al llegar al final de la tira de días). Sin Trakt o sin red, nada cambia.
    public func loadMoreAirings() async {
        guard !loadingMoreAirings, airingDays < Self.maxAiringDays else { return }
        loadingMoreAirings = true
        defer { loadingMoreAirings = false }
        let more = ForYou.calendarDays
        guard let fetched = try? await services.forYou.calendar(skip: airingDays, days: more), !Task.isCancelled else { return }
        let known = Set(airings.map(\.id))
        airings += fetched.filter { !known.contains($0.id) }
        airingDays += more
    }

    /// Una etiqueta por título: que sale pronto (calendario) gana a su puesto en una plataforma (Top 10 de Netflix, JustWatch).
    func rebuildBadges() {
        var out: [String: PosterBadge] = [:]
        for shelf in shelves where shelf.style == .top10 {
            let platform = Self.platformName(shelf.list)
            for item in items(for: shelf) { if let rank = item.rank, out[item.imdb] == nil { out[item.imdb] = .rank(rank, platform: platform) } }
        }
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        for airing in airings where airing.day < horizon { out[airing.series.imdb] = .airs(airing.day) }
        badges = out
    }

    /// «Series · Películas»: solo cambia los estantes con `split`; el resto sigue igual.
    public func setKind(_ kind: String) async {
        self.kind = ["movie", "series"].contains(kind) ? kind : "all"
        await loadShelves()
        await loadNewOnPlatforms()
        rebuildBadges()
    }

    /// Lo nuevo de tus plataformas, del tipo elegido (con «Todo», series y películas alternadas).
    private func loadNewOnPlatforms() async {
        let forYou = services.forYou
        if kind == "all" {
            async let series = forYou.newOnPlatforms(kind: "series")
            async let movies = forYou.newOnPlatforms(kind: "movie")
            let (a, b) = await (series, movies)
            var mixed: [Suggestion] = []
            for i in 0..<max(a.count, b.count) {
                if i < a.count { mixed.append(a[i]) }
                if i < b.count { mixed.append(b[i]) }
            }
            newOnPlatforms = mixed
        } else {
            newOnPlatforms = await forYou.newOnPlatforms(kind: kind)
        }
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
                    @Sendable func fetch(_ kind: String) async -> [Suggestion]? {
                        switch source {
                        case .console:
                            // Un estante que tarda (la consola refrescando JustWatch) tiene una segunda oportunidad.
                            if let found = try? await remote.items(listID: entry.listID, kind: kind) { return found }
                            guard !Task.isCancelled else { return nil }
                            return try? await remote.items(listID: entry.listID, kind: kind)
                        case .phone: return try? await local.items(listID: entry.listID, kind: kind)
                        }
                    }
                    guard kind == "all" else { return (entry.key, await fetch(kind)) }
                    // «Todo»: series y películas a la vez, alternadas (un estante que no separa trae lo mismo en ambas: sin repetir).
                    async let series = fetch("series")
                    async let movies = fetch("movie")
                    let (s, m) = await (series, movies)
                    if s == nil && m == nil { return (entry.key, nil) }
                    return (entry.key, Self.interleaved(s ?? [], m ?? []))
                }
            }
            for await (k, found) in group {
                loadingKeys.remove(k)
                // Si falló o se canceló (te fuiste a mitad de la carga), no se guarda vacío: la próxima carga lo vuelve a pedir.
                if let found, !Task.isCancelled { railItems[k] = found }
            }
        }
    }

    /// Una y una (serie, película…), sin repetir títulos: lo que queda de la más larga va al final.
    nonisolated static func interleaved(_ a: [Suggestion], _ b: [Suggestion]) -> [Suggestion] {
        var out: [Suggestion] = [], seen = Set<String>()
        for i in 0..<max(a.count, b.count) {
            for list in [a, b] where i < list.count && seen.insert(list[i].imdb).inserted { out.append(list[i]) }
        }
        return out
    }

    private func itemsFromCurrentSource(listID: String) async -> [Suggestion] {
        switch source {
        case .console: return (try? await services.forYouRemote.items(listID: listID, kind: kind)) ?? []
        case .phone: return (try? await services.forYou.items(listID: listID, kind: kind)) ?? []
        }
    }

    public func items(for list: ForYouList) -> [Suggestion] { railItems[key(list)] ?? [] }

    // MARK: tus plataformas
    /// Las plataformas con sus rankings (la fila en abanico de «Tus plataformas» y su página).
    public var platformHubs: [PlatformHub] { PlatformPlanner.hubs(lists) }
    public private(set) var rankingItems: [String: [Suggestion]] = [:] { didSet { changed() } }
    private var rankingLoading: Set<String> = []

    /// Un ranking ya cargado: lo pedido en la página o, si es del tipo que enseñan los estantes, lo de su estante.
    public func items(for ranking: PlatformRanking) -> [Suggestion] {
        rankingItems[ranking.id] ?? railItems["\(ranking.listID):\(ranking.kind)"] ?? []
    }

    public func isLoading(ranking: PlatformRanking) -> Bool { rankingLoading.contains(ranking.id) || (isLoading && items(for: ranking).isEmpty) }

    /// Los tres primeros de la plataforma (su tarjeta en abanico): del primer ranking que ya tenga algo.
    public func cover(of hub: PlatformHub) -> [Suggestion] {
        for ranking in hub.rankings {
            let found = items(for: ranking)
            if !found.isEmpty { return Array(found.prefix(3)) }
        }
        let fromShelves = railItems.filter { key, _ in hub.rankings.contains { key.hasPrefix($0.listID + ":") } }.values.first { !$0.isEmpty } ?? []
        return Array(fromShelves.prefix(3))
    }

    /// Pide todos los rankings de la plataforma que falten (series y películas), a la vez.
    public func loadRankings(_ hub: PlatformHub) async {
        let wanted = hub.rankings.filter { rankingItems[$0.id] == nil && !rankingLoading.contains($0.id) }
        guard !wanted.isEmpty else { return }
        rankingLoading.formUnion(wanted.map(\.id))
        let remote = services.forYouRemote, local = services.forYou, source = source
        await withTaskGroup(of: (String, [Suggestion]?).self) { group in
            for ranking in wanted {
                group.addTask {
                    switch source {
                    case .console: return (ranking.id, try? await remote.items(listID: ranking.listID, kind: ranking.kind))
                    case .phone: return (ranking.id, try? await local.items(listID: ranking.listID, kind: ranking.kind))
                    }
                }
            }
            for await (id, found) in group {
                rankingLoading.remove(id)
                if let found, !Task.isCancelled { rankingItems[id] = found }
            }
        }
    }

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
        case .phone:
            await services.forYou.dismiss(s.imdb)
            // La TV también deja de sugerirlo (si tu Orbital contesta; si no, queda en el iPhone).
            if services.orbital.isConfigured { await services.forYouRemote.dismiss(s.imdb) }
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
        rankingItems = [:]
        featuredRotation += 1
        await load()
    }
}
