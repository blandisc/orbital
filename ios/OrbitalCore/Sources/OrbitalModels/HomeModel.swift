import Foundation
import OrbitalCore

/// Una fila de Inicio: un título con lo que hace falta para pintarlo y para seguir viéndolo.
public struct HomeItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String { metaID }
    public var metaID: String
    public var kind: String
    public var title: String           // en tu idioma
    public var originalTitle: String
    public var poster: String?
    public var background: String?
    public var videoID: String?
    public var progress: Double?
    public var season: Int?
    public var episode: Int?
    public var timeLeft: String
    public var leftMinutes: Int
    public var nextUp: Bool            // terminaste el anterior: «Sigue: T8 E24»
    public var isNew: Bool?            // ibas al día y ya salió el episodio que sigue: «Nuevo» (opcional: la caché vieja no lo trae)
}

/// Inicio: «Seguir viendo» y Mi lista (lo tuyo en el teléfono, al día con Trakt). Sin red se enseña lo del teléfono, no una
/// pantalla vacía.
@MainActor
public final class HomeModel: ObservableModel {
    public private(set) var continueWatching: [HomeItem] = [] { didSet { changed() } }
    public private(set) var myList: [HomeItem] = [] { didSet { changed() } }
    /// Mi lista como la pinta Inicio: lo del teléfono, con los datos de tu watchlist de Trakt (sinopsis, año) si ya llegaron.
    public private(set) var traktPending: [Suggestion] = [] { didSet { changed() } }
    /// Tu watchlist tal como la dio Trakt (con sus datos), para vestir Mi lista.
    private var watchlistDetails: [Suggestion] = []
    /// Tus favoritos de Trakt (el corazón de la ficha), lo último que marcaste primero. Vacío sin Trakt: la fila no se pinta.
    public private(set) var favorites: [Suggestion] = [] { didSet { changed() } }
    /// «Destacado»: lo que abre Inicio. Lo en tendencia, lo popular de la semana y lo recomendado para ti, películas y series
    /// entreveradas, sin lo que ya estás viendo.
    public private(set) var spotlight: [Suggestion] = [] { didSet { changed() } }
    /// Solo películas («movie»), solo series («series») o todo (nil).
    public var spotlightKind: String? { didSet { if oldValue != spotlightKind { changed() } } }
    public var spotlightShown: [Suggestion] { spotlightKind.map { k in spotlight.filter { $0.kind == k } } ?? spotlight }
    /// Cuántos títulos pasan por la portada de Inicio.
    public static let heroCount = 10
    /// «Para ti»: tus recomendaciones de Trakt (películas y series entreveradas), lo personal que antes iba arriba.
    public private(set) var forYouPicks: [Suggestion] = [] { didSet { changed() } }
    /// El Top 10 de un servicio: el de Netflix (oficial, semanal, en tu país) o la tendencia del día en JustWatch de los
    /// demás. Series y películas por separado (cada una con su propio 1 al 10).
    public struct TopService: Sendable, Identifiable {
        public let brand: String, name: String, logo: String?
        public var id: String { brand }
        /// Netflix publica su Top 10 por semana; JustWatch, la tendencia del día.
        public var weekly: Bool { brand == "netflix" }
        var listID: String { brand == "netflix" ? "chart:netflix" : "jw:\(brand)" }
    }
    public static let topServices: [TopService] = [TopService(brand: "netflix", name: "Netflix", logo: Charts.netflixLogo)]
        + Charts.justWatchPlatforms.map { TopService(brand: $0.brand, name: $0.name, logo: Charts.justWatchLogo($0.brand)) }
    /// El servicio elegido (se recuerda): su Top 10 es el que se ve.
    public private(set) var topBrand: String { didSet { changed() } }
    public var topService: TopService { Self.topServices.first { $0.brand == topBrand } ?? Self.topServices[0] }
    /// Lo que trajo cada servicio, por «marca:tipo» («netflix:series»).
    public private(set) var topItems: [String: [Suggestion]] = [:] { didSet { changed() } }
    public private(set) var loadingTop = false { didSet { changed() } }
    /// Hay algo de algún servicio (o se está trayendo): la fila se pinta.
    public var hasAnyTop: Bool { loadingTop || !topItems.isEmpty }
    public func top(kind: String) -> [Suggestion] { topItems["\(topBrand):\(kind)"] ?? [] }
    static let topBrandKey = "home-top-brand"

    /// Elegir otro servicio: su Top 10 (lo que ya se trajo sale al momento; lo demás se pide).
    public func selectTop(_ brand: String) async {
        guard brand != topBrand else { return }
        topBrand = brand
        services.kv.set(Self.topBrandKey, data: Data(brand.utf8))
        await loadTop(brand)
        if topBrand == brand { saveLists() }
    }
    static let spotlightLimit = 16, rowLimit = 20
    public private(set) var isLoading = false { didSet { changed() } }
    /// Lo que sale de tus series en los próximos días (Trakt): «Sale hoy» (portada) y «Sale pronto» en Inicio.
    public private(set) var upcoming: [Airing] = [] { didSet { changed() } }
    /// Lo primero que sale hoy: la portada de Inicio y el título al bajar («Sale hoy: Severance»).
    public var airingToday: Airing? { upcoming.first { Calendar.current.isDateInToday($0.day) } }
    /// Lo que salió de tus series en los últimos días (Trakt): la parte de «ya salió» de «Lo nuevo de lo tuyo».
    public private(set) var recentAirings: [Airing] = [] { didSet { changed() } }
    /// Cuántos días hacia atrás entra en «Lo nuevo de lo tuyo».
    static let recentDays = 7
    /// «Lo nuevo de lo tuyo»: lo que ya salió y lo que viene, en una sola línea de tiempo (de lo más viejo a lo que sigue).
    public var timeline: [Airing] { Self.timeline(recent: recentAirings, upcoming: upcoming) }
    /// Junta lo que salió y lo que viene sin repetir (Trakt puede dar el mismo día en las dos consultas) y lo ordena por hora.
    public nonisolated static func timeline(recent: [Airing], upcoming: [Airing]) -> [Airing] {
        var seen = Set<String>()
        return (recent + upcoming).filter { seen.insert($0.id).inserted }.sorted { ($0.aired, $0.series.title) < ($1.aired, $1.series.title) }
    }

    /// Dónde va la marca HOY en la línea de tiempo: antes de lo primero que todavía no sale (al final si ya salió todo).
    public nonisolated static func nowIndex(in timeline: [Airing], now: Date) -> Int {
        timeline.firstIndex { $0.aired > now } ?? timeline.count
    }
    public private(set) var offline = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private let services: Services
    static let cacheKey = "home-cache"

    private struct Cache: Codable { var continueWatching: [HomeItem]; var myList: [HomeItem] }
    /// Lo de la última vez (destacado, Para ti, Top 10, watchlist): Inicio abre con eso al instante mientras llega lo nuevo.
    static let listsKey = "home-lists"
    public init(_ services: Services) {
        self.services = services
        defer {
            // El corazón de una ficha (o «Quitar de favoritos» aquí): la fila cambia al momento, sin esperar la recarga.
            favoriteObserver = NotificationCenter.default.addObserver(forName: FavoriteChange.name, object: nil, queue: .main) { [weak self] note in
                guard let change = FavoriteChange.read(note) else { return }
                MainActor.assumeIsolated { self?.setFavorite(change.suggestion, shown: change.add) }
            }
        }
        topBrand = services.kv.data(Self.topBrandKey).flatMap { String(data: $0, encoding: .utf8) }.flatMap { b in Self.topServices.contains { $0.brand == b } ? b : nil } ?? "netflix"
        super.init()
        if let data = services.kv.data(Self.cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            continueWatching = cache.continueWatching; myList = cache.myList
        }
        defer {
            // Lo tuyo cambió (lo viste, lo guardaste, llegó algo de Trakt): Inicio se vuelve a armar con lo del teléfono.
            libraryObserver = NotificationCenter.default.addObserver(forName: LocalLibrary.changed, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; Task { await self.showLibrary() } }
            }
        }
        if let data = services.kv.data(Self.listsKey), let saved = try? JSONDecoder().decode([String: Data].self, from: data) {
            spotlight = ForYou.decode(saved["spotlight"]); forYouPicks = ForYou.decode(saved["forYou"])
            for kind in ["series", "movie"] {
                let k = "\(topBrand):\(kind)"
                let found = ForYou.decode(saved["top:" + k])
                if !found.isEmpty { topItems[k] = found }
            }
            watchlistDetails = ForYou.decode(saved["pending"])
            favorites = ForYou.decode(saved["favorites"])
        }
    }

    private func saveLists() {
        var lists: [String: [Suggestion]] = ["spotlight": spotlight, "forYou": forYouPicks, "pending": Array(watchlistDetails.prefix(Self.rowLimit * 3)),
                                                     "favorites": Array(favorites.prefix(Self.rowLimit))]
        for kind in ["series", "movie"] { lists["top:\(topBrand):\(kind)"] = top(kind: kind) }
        services.kv.set(Self.listsKey, data: try? JSONEncoder().encode(lists.compactMapValues { ForYou.encode($0) }))
    }

    /// Al volver a Inicio (otra pestaña, una ficha): solo si lo último tiene más de un minuto. Deslizar hacia abajo, volver de
    /// ver algo o abrir la app sí piden todo (`refresh`).
    public func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let last = lastRefresh, services.now().timeIntervalSince(last) < maxAge { return }
        await refresh()
    }

    private var lastRefresh: Date?

    public func refresh() async {
        // Una a la vez: deslizar, volver de ver algo y volver a la app pedían todo a la vez y la que terminaba al último
        // pisaba a las demás (y regresaba lo que acababas de quitar). La que llega mientras otra corre, espera a esa.
        // Si ya va una, al terminar se da otra pasada (lo que pidió esta, p. ej. tu avance recién guardado, ya no se pierde).
        if let running = refreshing { rerun = true; return await running.value }
        let task = Task {
            repeat { rerun = false; await self.load() } while rerun
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    private var rerun = false
    /// Lo que quitaste de «Seguir viendo» mientras se cargaba: una carga que ya venía no lo regresa.
    private var dismissed: Set<String> = []

    private var refreshing: Task<Void, Never>?

    /// Todo se pide a la vez y cada fila se pinta en cuanto llega lo suyo: antes «En tendencia» esperaba a tu biblioteca de
    /// Stremio, a sus nombres en español, a tu watchlist y al calendario de Trakt (y abría segundos después de lo necesario).
    private func load() async {
        lastRefresh = services.now()
        isLoading = true
        defer { isLoading = false }
        let forYou = services.forYou
        fetchedAirings = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadLibrary() }
            group.addTask { await self.loadSpotlight(forYou) }
            group.addTask { await self.loadTrakt(forYou) }
            group.addTask { await self.loadPicks(forYou) }
            group.addTask { await self.loadTop(self.topBrand) }
        }
        if !Task.isCancelled { saveLists() }
        offline = !services.isOnline()
        publishWidget(airings: Task.isCancelled ? nil : fetchedAirings)   // los estrenos también van al widget mediano
    }

    private var fetchedAirings: [Airing]?

    /// Tu watchlist, tus favoritos y lo que sale de tus series (Trakt).
    private func loadTrakt(_ forYou: ForYou) async {
        async let airings = try? forYou.calendar(), pending = try? forYou.items(listID: "watchlist")
        async let favs = try? forYou.items(listID: ForYou.favoritesList)
        async let past = try? forYou.calendar(skip: -Self.recentDays, days: Self.recentDays)
        let (fetchedPending, newAirings, fetchedFavorites, pastAirings) = await (pending, airings, favs, past)
        // Cancelado o sin respuesta de Trakt: no se vacía «Tu watchlist» ni el «Próximo estreno» del widget.
        guard !Task.isCancelled else { return }
        let linked = await forYou.traktLinked
        if let fetchedPending { watchlistDetails = fetchedPending }   // toda (el renglón enseña los primeros; «Ver todo», todas)
        else if !linked { watchlistDetails = [] }
        dressList()
        if let fetchedFavorites { favorites = fetchedFavorites }
        else if !linked { favorites = [] }      // ni favoritos
        if let newAirings { upcoming = Array(newAirings.prefix(10)); fetchedAirings = newAirings }
        if let pastAirings { recentAirings = pastAirings } else if !linked { recentAirings = [] }
    }

    /// «Para ti»: tus recomendaciones, películas y series entreveradas, sin lo que ya está arriba.
    private func loadPicks(_ forYou: ForYou) async {
        async let rm = try? forYou.items(listID: "recs", kind: "movie"), rs = try? forYou.items(listID: "recs", kind: "series")
        let (recsM, recsS) = await (rm, rs)
        guard !Task.isCancelled else { return }
        let seen = Set(spotlight.map(\.imdb) + continueWatching.map(\.metaID))
        let picks = Self.mixSpotlight([recsM ?? [], recsS ?? []], excluding: seen, limit: Self.rowLimit)
        if !picks.isEmpty { forYouPicks = picks }
    }

    /// El Top 10 de un servicio, series y películas a la vez.
    private func loadTop(_ brand: String) async {
        guard let service = Self.topServices.first(where: { $0.brand == brand }) else { return }
        let forYou = services.forYou
        loadingTop = top(kind: "series").isEmpty && top(kind: "movie").isEmpty
        defer { loadingTop = false }
        async let movies = try? forYou.items(listID: service.listID, kind: "movie"), series = try? forYou.items(listID: service.listID, kind: "series")
        let (m, sr) = await (movies, series)
        guard !Task.isCancelled else { return }
        if let sr, !sr.isEmpty { topItems["\(brand):series"] = Array(sr.prefix(10)) }
        if let m, !m.isEmpty { topItems["\(brand):movie"] = Array(m.prefix(10)) }
    }

    /// «Seguir viendo» y «Mi lista»: primero lo del teléfono (al instante), luego lo que cambió en Trakt.
    private func loadLibrary() async {
        await showLibrary()
        await services.syncLibrary()
        guard !Task.isCancelled else { return }
        await showLibrary()
    }

    /// Lo del teléfono, con los nombres en tu idioma.
    func showLibrary() async {
        let all = await services.watch.withReturning(await services.watch.library())
        let continueItems = all.filter { w in
            guard w.inContinue else { return false }
            let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.episode.episode != nil
            return nextUp || (w.progress ?? 1) >= PlaybackRules.continueMinProgress
        }
        // Mi lista en el orden en que la guardaste (lo último primero).
        let listed = Dictionary(services.library.all.filter(\.inList).map { ($0.metaID, $0.listedAt ?? 0) }, uniquingKeysWith: max)
        let mine = all.filter(\.inLibrary).sorted { (listed[$0.id] ?? 0) > (listed[$1.id] ?? 0) }
        async let continued = items(continueItems), saved = items(mine)   // las dos traducciones a la vez
        let (c, m) = await (continued, saved)
        guard !Task.isCancelled else { return }
        continueWatching = c.filter { !dismissed.contains($0.metaID) }
        myList = m
        offline = !services.isOnline(); error = nil   // sin red se enseña lo del teléfono y se dice (el corte A lo había apagado)
        dressList()
        // Lo que ya estás viendo no se repite arriba.
        let watching = Set(continueWatching.map(\.metaID))
        if spotlight.contains(where: { watching.contains($0.imdb) }) { spotlight.removeAll { watching.contains($0.imdb) } }
        services.kv.set(Self.cacheKey, data: try? JSONEncoder().encode(Cache(continueWatching: continueWatching, myList: myList)))
        publishWidget()
    }

    /// Mi lista con lo que trajo Trakt de cada título (sinopsis, año, géneros); lo que aún no está allá, con lo del teléfono.
    private func dressList() {
        let details = Dictionary(watchlistDetails.map { ($0.imdb, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = myList.map { item in details[item.metaID] ?? Self.suggestion(item) }
        let ids = Set(shown.map(\.imdb))
        // Lo que Trakt ya tiene y el teléfono aún no (la primera sincronización), al final; lo que quitaste aquí, no.
        let waiting = services.traktOutbox.pending.filter { $0.target == TraktOutbox.watchlist && !$0.add }.map(\.imdb)
        let extra = myList.isEmpty && services.library.isEmpty ? watchlistDetails.filter { !ids.contains($0.imdb) && !waiting.contains($0.imdb) } : []
        let next = (shown + extra).filter { hiddenPending[$0.imdb] == nil }
        if next != traktPending { traktPending = next }
    }

    static func suggestion(_ item: HomeItem) -> Suggestion {
        Suggestion(kind: item.kind, imdb: item.metaID, title: item.title, poster: item.poster ?? String(format: ForYou.metahubPoster, item.metaID),
                   wide: item.background ?? String(format: ForYou.metahubBackground, item.metaID), reason: .inList("Mi lista"))
    }

    private func loadSpotlight(_ forYou: ForYou) async {
        let lists = await spotlightLists(forYou)
        if !Task.isCancelled, lists.contains(where: { !$0.isEmpty }) {
            spotlight = Self.mixSpotlight(lists, excluding: Set(continueWatching.map(\.metaID)), limit: Self.spotlightLimit)
        }
    }

    /// Las listas de «Destacado», en el orden en que se entreveran: tendencia, para ti y popular, cada una en película y serie.
    private func spotlightLists(_ forYou: ForYou) async -> [[Suggestion]] {
        // Lo de todos (no lo tuyo): tendencia y popular, películas y series. Lo tuyo va abajo, en «Para ti».
        async let tm = try? forYou.items(listID: "trend", kind: "movie"), ts = try? forYou.items(listID: "trend", kind: "series")
        async let pm = try? forYou.items(listID: "popular", kind: "movie"), ps = try? forYou.items(listID: "popular", kind: "series")
        // Si Trakt no contesta, se queda el destacado guardado de la última vez (`loadSpotlight` no lo vacía).
        return await [tm ?? [], ts ?? [], pm ?? [], ps ?? []]
    }

    /// Entrevera las listas (una de cada una por vuelta), sin repetir y sin lo que ya estás viendo.
    public static func mixSpotlight(_ lists: [[Suggestion]], excluding: Set<String>, limit: Int) -> [Suggestion] {
        var seen = excluding, out: [Suggestion] = []
        let longest = lists.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in lists where i < list.count && out.count < limit {
                let s = list[i]
                guard !seen.contains(s.imdb) else { continue }
                seen.insert(s.imdb); out.append(s)
            }
            if out.count >= limit { break }
        }
        return out
    }

    /// Los títulos en tu idioma (Stremio guarda el original) y con lo que hace falta para seguir viendo.
    private func items(_ watchables: [Watchable]) async -> [HomeItem] {
        let usable = watchables.filter { ["movie", "series"].contains($0.type) }
        let localizer = services.localizer
        func metas(_ kind: String) -> [JSON] { usable.filter { $0.type == kind }.map { JSON.object(["id": .string($0.id), "name": .string($0.name)]) } }
        async let movies = localizer.catalog(kind: "movie", metas: metas("movie")), series = localizer.catalog(kind: "series", metas: metas("series"))
        var localized: [String: String] = [:]
        for meta in await movies + series {
            if let id = meta["id"]?.string, let name = meta["name"]?.string { localized[id] = name }
        }
        return usable.map { w in
            let (season, episode) = w.episode
            let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && episode != nil
            let left = w.duration > 0 && w.timeOffset > 0 ? Double(w.duration - w.timeOffset) / 1000 : 0
            return HomeItem(metaID: w.id, kind: w.type, title: localized[w.id] ?? w.name, originalTitle: w.name,
                            poster: w.id.hasPrefix("tt") ? String(format: ForYou.metahubPoster, w.id) : w.poster,
                            background: w.id.hasPrefix("tt") ? String(format: ForYou.metahubBackground, w.id) : nil,
                            videoID: w.videoID ?? (w.type == "movie" ? w.id : nil), progress: nextUp ? nil : w.progress, season: season, episode: episode,
                            timeLeft: PlaybackRules.timeLeft(left), leftMinutes: PlaybackRules.minutesLeft(left), nextUp: nextUp,
                            isNew: w.isNew ? true : nil)
        }
    }

    /// Lo que verá el widget «Lo siguiente para ti»: «Seguir viendo» tal como quedó (también la copia de la última vez, sin red).
    private func publishWidget(airings: [Airing]? = nil) {
        services.publishWidget(continueWatching: continueWatching, airings: airings)
        // Siri: «Seguir viendo» y tu lista (antes solo «Seguir viendo»: «pon Los Simpson» fallaba si no estaba ahí).
        services.onSiriTitles?((continueWatching + myList).map { [$0.originalTitle, $0.title] })
    }

    /// Quitado de Mi lista desde un menú (o regresado con «Deshacer»): cambia aquí al instante, en su mismo lugar.
    public func setShown(_ metaID: String, in destination: SaveDestination = .myList, shown: Bool) {
        if !shown {
            guard let i = traktPending.firstIndex(where: { $0.imdb == metaID }) else { return }
            hiddenPending[metaID] = (i, traktPending.remove(at: i))
        } else {
            guard let (i, s) = hiddenPending.removeValue(forKey: metaID), !traktPending.contains(where: { $0.imdb == metaID }) else { return }
            traktPending.insert(s, at: min(i, traktPending.count))
        }
    }
    private var hiddenPending: [String: (Int, Suggestion)] = [:]

    /// Un título que entra o sale de tus favoritos: entra al principio (o donde estaba, si fue «Deshacer»); sale al instante.
    public func setFavorite(_ s: Suggestion, shown: Bool) {
        if shown {
            guard !favorites.contains(where: { $0.imdb == s.imdb }) else { return }
            let (i, saved) = hiddenFavorites.removeValue(forKey: s.imdb) ?? (0, s)
            favorites.insert(saved, at: min(i, favorites.count))
        } else if let i = favorites.firstIndex(where: { $0.imdb == s.imdb }) {
            hiddenFavorites[s.imdb] = (i, favorites.remove(at: i))
        }
    }
    private var hiddenFavorites: [String: (Int, Suggestion)] = [:]
    private var favoriteObserver: NSObjectProtocol?
    private var libraryObserver: NSObjectProtocol?

    /// «Quitar de Seguir viendo».
    public func dismiss(_ item: HomeItem) async {
        dismissed.insert(item.metaID)   // al instante (sin esperar la carga en curso); la carga lo filtra
        continueWatching.removeAll { $0.metaID == item.metaID }
        publishWidget()
        await services.watch.dismissContinue(metaID: item.metaID, newEpisode: item.isNew == true ? item.videoID : nil)
    }
}

/// Aviso de que un título entró o salió de tus favoritos (desde la ficha o desde Inicio), para que Inicio lo refleje al momento.
public enum FavoriteChange {
    public static let name = Notification.Name("orbital.favorite-change")
    public static func post(_ suggestion: Suggestion, add: Bool) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["change": Box(suggestion: suggestion, add: add)])
    }
    static func read(_ note: Notification) -> Box? { note.userInfo?["change"] as? Box }
    final class Box: Sendable { let suggestion: Suggestion; let add: Bool; init(suggestion: Suggestion, add: Bool) { self.suggestion = suggestion; self.add = add } }
}
