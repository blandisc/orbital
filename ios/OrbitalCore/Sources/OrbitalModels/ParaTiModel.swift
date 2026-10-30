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
    /// De dónde salió lo que ves: la consola (misma curaduría que la TV) o este iPhone (lógica local).
    public enum Source: Equatable, Sendable { case console, phone }

    /// Abre en Listas (lo que más se usa); el mosaico, con el botón de arriba.
    public var mode: Mode = .lists { didSet { if mode != oldValue { changed() } } }
    public private(set) var mosaic: [Suggestion] = [] { didSet { if mosaic != oldValue { changed() } } }
    public private(set) var lists: [ForYouList] = [] { didSet { if lists != oldValue { changed() } } }
    /// Los estantes del feed de Listas, en su orden (`ShelfPlanner`). Los vacíos se descartan al terminar de cargar.
    public private(set) var shelves: [ShelfPlan] = [] { didSet { if shelves != oldValue { changed() } } }
    /// «Todo», «Series» o «Películas» (`all`, `series`, `movie`): los estantes con `split` enseñan eso; «Todo» alterna ambos.
    public private(set) var kind = "all" { didSet { if kind != oldValue { changed() } } }
    /// Las listas que aún se están pidiendo (su estante enseña esqueletos, no un hueco).
    public private(set) var loadingKeys = Set<String>() { didSet { if loadingKeys != oldValue { changed() } } }
    public private(set) var railItems: [String: [Suggestion]] = [:] { didSet { if railItems != oldValue { changed() } } }
    public private(set) var watchlistKeys = Set<String>() { didSet { if watchlistKeys != oldValue { changed() } } }
    public private(set) var traktLinked = false { didSet { if traktLinked != oldValue { changed() } } }
    public private(set) var isLoading = false { didSet { if isLoading != oldValue { changed() } } }
    /// Los episodios que salen de las series que sigues (Trakt), hoy y los próximos 14 días.
    public private(set) var airings: [Airing] = [] { didSet { if airings != oldValue { changed() } } }
    /// «Porque viste X» para «Decide por mí»: lo último que viste y lo que Trakt relaciona con él (nil sin Trakt o sin
    /// relacionados). «Por lo que viste», con su mazo para elegir, vive en Inicio (`BecauseModel`).
    public private(set) var because: (seed: TraktEntry, items: [Suggestion])? { didSet { changed() } }
    /// «Nuevo en tus plataformas» (TMDB): series con episodios recientes y películas recién llegadas, de tus plataformas.
    public private(set) var newOnPlatforms: [Suggestion] = [] { didSet { changed() } }
    /// El porqué de cada título en un póster (lo más fuerte: que sale pronto, o su puesto en una plataforma), por IMDb.
    public private(set) var badges: [String: PosterBadge] = [:] { didSet { if oldValue != badges { changed() } } }
    public private(set) var error: String? { didSet { changed() } }
    /// El mosaico es lo que está en tendencia en Trakt (nada tuyo todavía): la pantalla invita a conectar tus fuentes.
    public private(set) var isGeneric = false { didSet { changed() } }
    /// De dónde vino lo que se ve ahora: la pantalla lo enseña en un pie discreto.
    public private(set) var source: Source = .phone { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
        restoreSnapshot()
        // El corazón de una ficha (o «Quitar de favoritos» en «Tuyo»): la lista de Favoritos cambia al momento, sin recargar.
        favoriteObserver = NotificationCenter.default.addObserver(forName: FavoriteChange.name, object: nil, queue: .main) { [weak self] note in
            guard let change = FavoriteChange.read(note) else { return }
            MainActor.assumeIsolated { self?.setFavorite(change.suggestion, shown: change.add) }
        }
    }
    private var favoriteObserver: NSObjectProtocol?
    private var hiddenFavorites: [String: (Int, Suggestion)] = [:]

    /// Un título que entra o sale de tus favoritos («Tuyo › Favoritos»): sale al instante y, con «Deshacer», vuelve a su lugar.
    public func setFavorite(_ s: Suggestion, shown: Bool) {
        let k = key(listID: ForYou.favoritesList, splits: false)
        var items = railItems[k] ?? []
        if shown {
            guard !items.contains(where: { $0.imdb == s.imdb }) else { return }
            let (i, saved) = hiddenFavorites.removeValue(forKey: s.imdb) ?? (0, s)
            items.insert(saved, at: min(i, items.count))
        } else if let i = items.firstIndex(where: { $0.imdb == s.imdb }) {
            hiddenFavorites[s.imdb] = (i, items.remove(at: i))
        } else { return }
        railItems[k] = items
    }

    /// Pruebas: lo que trae un estante sin pasar por la red.
    func seedRailForTesting(listID: String, splits: Bool, _ items: [Suggestion]) { railItems[key(listID: listID, splits: splits)] = items }

    // MARK: lo de la última vez
    /// Los estantes de la última vez (sus listas y lo que traían), guardados en el teléfono: Para ti abre con ellos al instante
    /// y cada uno se cambia por el nuevo en cuanto llega (antes, la pestaña abría vacía hasta que contestaba la red).
    static let snapshotKey = "paraTi-snapshot"
    private struct Snapshot: Codable { var console: Bool; var kind: String; var lists: [ForYouList]; var rails: [String: Data] }

    private func restoreSnapshot() {
        guard let data = services.kv.data(Self.snapshotKey), let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
              saved.kind == kind else { return }
        source = saved.console ? .console : .phone
        lists = saved.lists
        shelves = ShelfPlanner.plan(saved.lists)
        railItems = saved.rails.mapValues { ForYou.decode($0) }.filter { !$0.value.isEmpty }
        staleKeys = Set(railItems.keys)   // se ven, pero se piden de nuevo
    }

    private func saveSnapshot() {
        guard !Task.isCancelled, !lists.isEmpty else { return }
        let rails = railItems.compactMapValues { ForYou.encode(Array($0.prefix(Self.snapshotRowLimit))) }
        services.kv.set(Self.snapshotKey, data: try? JSONEncoder().encode(Snapshot(console: source == .console, kind: kind, lists: lists, rails: rails)))
    }
    static let snapshotRowLimit = 20

    public var traktLists: [ForYouList] { lists.filter { $0.group != .platforms } }
    public var platformLists: [ForYouList] { lists.filter { $0.group == .platforms } }

    /// Los estantes que se pintan: con algo dentro, o todavía cargando (con esqueleto). Vacío o fallido: no se pinta.
    public var visibleShelves: [ShelfPlan] {
        let shown = shelves.filter { isLoading(shelf: $0) || !items(for: $0).isEmpty }
        // El respaldo de una marca se esconde si su lista con puesto sí trajo algo (o aún carga): la misma plataforma, una vez.
        let covered = Set(shown.filter { !$0.isFallback && $0.style == .top10 }.compactMap(\.list.brand))
        return shown.filter { !$0.isFallback || !covered.contains($0.list.brand ?? "") }
    }
    /// Ninguna fuente dio estantes: el feed cae a lo que está en tendencia y a la invitación a conectar fuentes.
    public var feedIsEmpty: Bool { !isLoading && visibleShelves.isEmpty }
    /// Mostrar «Conecta Trakt o tu Orbital»: no hay ninguna fuente tuya (solo lo que está en tendencia).
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

    private static func platformName(_ list: ForYouList) -> String {
        guard let brand = list.brand else { return list.title }
        // «Prime Video», no «Prime»: el nombre de JustWatch si TMDB no la tiene (la píldora la reconoce por ese nombre).
        return Tmdb.platforms.first { $0.brand == brand }?.name ?? Charts.justWatchPlatforms.first { $0.brand == brand }?.name ?? brand.capitalized
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
        // Si la consola no contesta, se cae a la lógica local. Con sus listas basta para empezar: los estantes ya no esperan
        // al mosaico (antes sí, y el destacado tardaba lo que tardara el mosaico).
        guard let newLists = await fetchedLists else { return false }
        async let fetchedKeys = try? remote.watchlistKeys()
        async let fetchedBecause = forYou.becauseYouWatched()
        async let fetchedAirings = try? forYou.calendar()   // el calendario sale de tu Trakt (la consola trae la lista «estrenos», que aquí no se pinta como estante)
        if source != .console { railItems = [:] }   // venía del iPhone: los estantes de la otra fuente no se mezclan
        source = .console
        traktLinked = newLists.contains { $0.id == "watchlist" || $0.id == "mine" }
        lists = newLists
        shelves = ShelfPlanner.plan(newLists)
        isGeneric = false
        async let shelvesLoaded: Void = loadShelves()
        async let platformsLoaded: Void = loadNewOnPlatforms()
        // El mosaico, cuando llegue: se guarda para la próxima vez; si ya se veía el guardado, no se cambia bajo tu dedo.
        if let newMosaic = await fetchedMosaic {
            await forYou.saveMosaic(newMosaic)
            if !showedSaved || mosaic.isEmpty { mosaic = newMosaic }
        }
        error = mosaic.isEmpty && lists.isEmpty ? "Tu Orbital no tiene sugerencias todavía." : nil
        watchlistKeys = await fetchedKeys ?? []
        if let fetched = await fetchedAirings, !Task.isCancelled {
            airings = fetched
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno» también con la consola
        }
        because = await fetchedBecause
        await shelvesLoaded
        await platformsLoaded
        rebuildBadges()
        await topUpMosaic()
        saveSnapshot()
        return true
    }

    /// Todo a la vez: los estantes empiezan en cuanto llegan las listas (antes esperaban al mosaico, que son varias
    /// peticiones a Trakt) y «Porque viste», lo nuevo en tus plataformas y el calendario aparecen cada uno al llegar.
    private func loadFromPhone() async {
        if source != .phone { railItems = [:] }
        source = .phone
        let forYou = services.forYou
        // Al abrir la app, el de la última vez (guardado en el teléfono): el mosaico aparece al instante. El nuevo no lo
        // reemplaza en ese momento (lo movería bajo tu dedo): queda guardado para la próxima vez; «Actualizar» lo trae ya.
        var showedSaved = false
        if mosaic.isEmpty {
            let saved = await forYou.cachedMosaic()
            if !saved.isEmpty { mosaic = saved; showedSaved = true }
        }
        let keepSaved = showedSaved
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.phoneShelves(forYou) }
            group.addTask { await self.phoneMosaic(forYou, keepSaved: keepSaved) }
            group.addTask { await self.phoneTrakt(forYou) }
            group.addTask { await self.phoneBecause(forYou) }
            group.addTask { await self.loadNewOnPlatforms() }
        }
        rebuildBadges()
        // El aviso, solo si de verdad no hay nada que enseñar (las listas con puesto existen siempre, pero sin red llegan vacías).
        if mosaic.isEmpty && shelves.allSatisfy({ items(for: $0).isEmpty }) { error = services.trakt?.linked == true ? nil : "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias." }
        else { error = nil }
        await topUpMosaic()
        saveSnapshot()
    }

    private func phoneShelves(_ forYou: ForYou) async {
        lists = await forYou.lists()
        shelves = ShelfPlanner.plan(lists)
        await loadShelves()
    }

    private func phoneMosaic(_ forYou: ForYou, keepSaved: Bool) async {
        let fresh = await forYou.mosaic()
        if !keepSaved, !fresh.isEmpty || mosaic.isEmpty { mosaic = fresh }
        // Sin nada tuyo el mosaico no quedaría vacío: lo que está en tendencia en Trakt (no pide tu sesión).
        isGeneric = mosaic.isEmpty
        if isGeneric { mosaic = await popular() }
    }

    private func phoneTrakt(_ forYou: ForYou) async {
        async let linked = forYou.traktLinked
        async let keys = forYou.watchlistKeys()
        async let newAirings = try? forYou.calendar()
        traktLinked = await linked
        watchlistKeys = await keys
        if let fetched = await newAirings, !Task.isCancelled {   // sin respuesta (o cancelado), el widget conserva lo que tenía
            airings = fetched
            services.publishWidget(airings: airings)   // el widget mediano enseña «Próximo estreno»
        }
    }

    private func phoneBecause(_ forYou: ForYou) async { because = await forYou.becauseYouWatched() }

    /// Con pocas sugerencias el mosaico repetía la misma portada en toda la pantalla: se completa con lo que ya
    /// trajeron los estantes (alternados, sin repetir) y, si aún faltan, con lo que está en tendencia en Trakt.
    private func topUpMosaic() async {
        guard mosaic.count < MosaicPool.minimumVariety else { return }
        let fromShelves = visibleShelves.map { items(for: $0) }
        var filled = MosaicPool.toppedUp(mosaic, with: fromShelves)
        if filled.count < MosaicPool.minimumVariety { filled = MosaicPool.toppedUp(filled, with: [await popular()]) }
        mosaic = filled
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
        let asked = kind
        if kind == "all" {
            async let series = forYou.newOnPlatforms(kind: "series")
            async let movies = forYou.newOnPlatforms(kind: "movie")
            let (a, b) = await (series, movies)
            var mixed: [Suggestion] = []
            for i in 0..<max(a.count, b.count) {
                if i < a.count { mixed.append(a[i]) }
                if i < b.count { mixed.append(b[i]) }
            }
            if kind == asked { newOnPlatforms = mixed }   // cambiaste de tipo mientras llegaba: gana el que pediste al último
        } else {
            let found = await forYou.newOnPlatforms(kind: asked)
            if kind == asked { newOnPlatforms = found }
        }
    }

    /// Lo que «Actualizar» marcó como viejo: se vuelve a pedir la próxima vez que haga falta (lo de antes se queda a la vista).
    private var staleKeys: Set<String> = [], staleRankings: Set<String> = []

    public func key(_ list: ForYouList) -> String { key(listID: list.id, splits: list.splitsKinds) }
    func key(listID: String, splits: Bool) -> String { "\(listID):\(splits ? kind : "-")" }

    /// Pide el contenido de todos los estantes a la vez (cada uno aparece cuando llega; el orden no cambia).
    private func loadShelves() async {
        var wanted: [(key: String, listID: String)] = []
        for shelf in shelves {
            for id in shelf.listIDs {
                let k = key(listID: id, splits: shelf.splitsKinds)
                if id != "estrenos", railItems[k] == nil || staleKeys.contains(k), !wanted.contains(where: { $0.key == k }) { wanted.append((k, id)) }
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
                if let found, !Task.isCancelled { railItems[k] = found; staleKeys.remove(k) }
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

    /// «¿Qué vemos?» › De qué listas: lo de una lista que aún no se abrió, pedido solo si la eliges (series y películas,
    /// alternadas). Tienes muchas listas: no se piden todas al abrir la hoja.
    public func decideLoader(for list: ForYouList) -> @Sendable () async -> [Suggestion] {
        let remote = services.forYouRemote, local = services.forYou, source = source, id = list.id
        return {
            @Sendable func fetch(_ kind: String) async -> [Suggestion] {
                switch source {
                case .console: return (try? await remote.items(listID: id, kind: kind)) ?? []
                case .phone: return (try? await local.items(listID: id, kind: kind)) ?? []
                }
            }
            async let series = fetch("series")
            async let movies = fetch("movie")
            return await ParaTiModel.interleaved(series, movies)
        }
    }

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
        let wanted = hub.rankings.filter { (rankingItems[$0.id] == nil || staleRankings.contains($0.id)) && !rankingLoading.contains($0.id) }
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
                if let found, !Task.isCancelled { rankingItems[id] = found; staleRankings.remove(id) }
            }
        }
    }

    /// Lo que más se está viendo ahora en Trakt («En tendencia»), series y películas alternadas, en tu idioma.
    private func popular() async -> [Suggestion] {
        async let series = popular("series"), movies = popular("movie")
        let dismissed = await services.forYou.dismissedIDs()
        return ForYou.interleave([await series, await movies], limit: ForYou.mosaicSize).filter { !dismissed.contains($0.imdb) }
    }

    private func popular(_ kind: String) async -> [Suggestion] {
        guard let found = try? await services.forYou.items(listID: "trend", kind: kind) else { return [] }
        let top = Array(found.prefix(ForYou.mosaicSize / 2))
        let metas = top.map { JSON.object(["id": .string($0.imdb), "name": .string($0.title)]) }
        let localized = await services.localizer.catalog(kind: kind, metas: metas)
        return zip(top, localized).map { s, translated in
            var s = s
            if let name = translated["name"]?.string, !name.isEmpty { s.title = name }
            if let overview = translated["description"]?.string, !overview.isEmpty { s.overview = overview }
            return s
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
        if let current = because { because = (current.seed, current.items.filter { $0.imdb != s.imdb }) }
    }

    /// El botón «Actualizar»: limpia la caché (de la consola o local, según de dónde viniera) y vuelve a cargar.
    public func refresh() async {
        switch source {
        case .console: await services.forYouRemote.clearCache()
        case .phone: await services.forYou.clearCache()
        }
        // Lo de antes se queda a la vista hasta que llega lo nuevo.
        // Todo lo que hay se marca viejo: se vuelve a pedir (aquí, al cambiar de tipo o al abrir una plataforma) y mientras
        // tanto se queda a la vista.
        staleKeys = Set(railItems.keys)
        staleRankings = Set(rankingItems.keys)
        await load()
    }
}
