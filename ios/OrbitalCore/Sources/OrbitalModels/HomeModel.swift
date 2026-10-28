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

/// Inicio: «Seguir viendo», tu lista de Stremio y lo pendiente de tu watchlist de Trakt. Si no hay red se enseña
/// lo último que se vio (con aviso), no una pantalla vacía.
@MainActor
public final class HomeModel: ObservableModel {
    public private(set) var continueWatching: [HomeItem] = [] { didSet { changed() } }
    public private(set) var myList: [HomeItem] = [] { didSet { changed() } }
    public private(set) var traktPending: [Suggestion] = [] { didSet { changed() } }
    /// «Destacado»: lo que abre Inicio. Lo en tendencia, lo popular de la semana y lo recomendado para ti, películas y series
    /// entreveradas, sin lo que ya estás viendo.
    public private(set) var spotlight: [Suggestion] = [] { didSet { changed() } }
    /// Solo películas («movie»), solo series («series») o todo (nil).
    public var spotlightKind: String? { didSet { if oldValue != spotlightKind { changed() } } }
    public var spotlightShown: [Suggestion] { spotlightKind.map { k in spotlight.filter { $0.kind == k } } ?? spotlight }
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
    public private(set) var offline = false { didSet { changed() } }
    /// Stremio cerró tu sesión (no es falta de red): Inicio lo dice y deja volver a entrar.
    public private(set) var sessionExpired = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private let services: Services
    static let cacheKey = "home-cache"

    private struct Cache: Codable { var continueWatching: [HomeItem]; var myList: [HomeItem] }
    /// Lo de la última vez (destacado, Para ti, Top 10, watchlist): Inicio abre con eso al instante mientras llega lo nuevo.
    static let listsKey = "home-lists"
    public init(_ services: Services) {
        self.services = services
        topBrand = services.kv.data(Self.topBrandKey).flatMap { String(data: $0, encoding: .utf8) }.flatMap { b in Self.topServices.contains { $0.brand == b } ? b : nil } ?? "netflix"
        super.init()
        if let data = services.kv.data(Self.cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            continueWatching = cache.continueWatching; myList = cache.myList
        }
        if let data = services.kv.data(Self.listsKey), let saved = try? JSONDecoder().decode([String: Data].self, from: data) {
            spotlight = ForYou.decode(saved["spotlight"]); forYouPicks = ForYou.decode(saved["forYou"])
            for kind in ["series", "movie"] {
                let k = "\(topBrand):\(kind)"
                let found = ForYou.decode(saved["top:" + k])
                if !found.isEmpty { topItems[k] = found }
            }
            traktPending = ForYou.decode(saved["pending"])
        }
    }

    private func saveLists() {
        var lists: [String: [Suggestion]] = ["spotlight": spotlight, "forYou": forYouPicks, "pending": Array(traktPending.prefix(Self.rowLimit))]
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
        guard services.isSignedIn else { return }
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
        publishWidget(airings: Task.isCancelled ? nil : fetchedAirings)   // los estrenos también van al widget mediano
    }

    private var fetchedAirings: [Airing]?

    /// Tu watchlist y lo que sale de tus series (Trakt).
    private func loadTrakt(_ forYou: ForYou) async {
        async let airings = try? forYou.calendar(), pending = try? forYou.items(listID: "watchlist")
        let (fetchedPending, newAirings) = await (pending, airings)
        // Cancelado o sin respuesta de Trakt: no se vacía «Tu watchlist» ni el «Próximo estreno» del widget.
        guard !Task.isCancelled else { return }
        if let fetchedPending { traktPending = fetchedPending }   // toda (el renglón enseña los primeros; «Ver todo», todas)
        else if !(await forYou.traktLinked) { traktPending = [] }   // desconectaste Trakt: ya no hay watchlist que enseñar
        if let newAirings { upcoming = Array(newAirings.prefix(10)); fetchedAirings = newAirings }
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

    /// «Seguir viendo» y «Mi lista» (Stremio, con los nombres en tu idioma).
    private func loadLibrary() async {
        do {
            _ = await services.watch.flushPending()          // primero se sube lo pendiente; así la lista ya lo trae
            let all = await services.watch.withReturning(try await services.watch.library())
            let continueItems = all.filter { w in
                guard w.inContinue else { return false }
                let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.episode.episode != nil
                return nextUp || (w.progress ?? 1) >= PlaybackRules.continueMinProgress
            }
            let mine = all.filter(\.inLibrary)
            async let continued = items(continueItems), listed = items(mine)   // las dos traducciones a la vez
            continueWatching = await continued.filter { !dismissed.contains($0.metaID) }
            myList = await listed
            offline = false; sessionExpired = false; error = nil
            // Lo que ya estás viendo no se repite arriba.
            let watching = Set(continueWatching.map(\.metaID))
            if spotlight.contains(where: { watching.contains($0.imdb) }) { spotlight.removeAll { watching.contains($0.imdb) } }
            services.kv.set(Self.cacheKey, data: try? JSONEncoder().encode(Cache(continueWatching: continueWatching, myList: myList)))
        } catch where !Task.isCancelled {   // cancelado (cambio de pestaña): no es estar sin conexión
            // La sesión caducó: Stremio contesta (no es la red), pero ya no reconoce la clave.
            if case StremioError.api(let message) = error, message.lowercased().contains("session") {
                sessionExpired = true; offline = false
            } else { offline = true }
            self.error = "\(error)"
        } catch {}
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
        let trakt = await [tm ?? [], ts ?? [], pm ?? [], ps ?? []]
        if trakt.contains(where: { !$0.isEmpty }) { return trakt }
        // Sin Trakt: lo popular de hoy en Stremio (Cinemeta), para que Inicio no abra vacío.
        async let cm = try? services.cinemeta.catalog("movie"), cs = try? services.cinemeta.catalog("series")
        let (movies, series) = await (cm, cs)
        return [Self.popularSuggestions("movie", movies ?? []), Self.popularSuggestions("series", series ?? [])]
    }

    private static func popularSuggestions(_ kind: String, _ metas: [JSON]) -> [Suggestion] {
        metas.compactMap { meta in
            guard let id = meta["id"]?.string, id.hasPrefix("tt"), let name = meta["name"]?.string else { return nil }
            let info = CinemetaParsing.describe(meta)
            var s = Suggestion(kind: kind, imdb: id, title: name, year: Int(info.year.prefix(4)), overview: info.description,
                               poster: String(format: ForYou.metahubPoster, id), wide: String(format: ForYou.metahubBackground, id),
                               logo: String(format: ForYou.metahubLogo, id), reason: .popular)
            s.genres = info.genres
            return s
        }
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

    /// Quitado de tu watchlist o de Mi lista desde un menú (o regresado con «Deshacer»): cambia aquí al instante, en su
    /// mismo lugar; la lista de verdad vive en Trakt o en Stremio y la siguiente carga ya llega así.
    public func setShown(_ metaID: String, in destination: SaveDestination, shown: Bool) {
        switch (destination, shown) {
        case (.traktWatchlist, false):
            guard let i = traktPending.firstIndex(where: { $0.imdb == metaID }) else { return }
            hiddenPending[metaID] = (i, traktPending.remove(at: i))
        case (.traktWatchlist, true):
            guard let (i, s) = hiddenPending.removeValue(forKey: metaID), !traktPending.contains(where: { $0.imdb == metaID }) else { return }
            traktPending.insert(s, at: min(i, traktPending.count))
        case (.stremioLibrary, false):
            guard let i = myList.firstIndex(where: { $0.metaID == metaID }) else { return }
            hiddenMine[metaID] = (i, myList.remove(at: i))
        case (.stremioLibrary, true):
            guard let (i, item) = hiddenMine.removeValue(forKey: metaID), !myList.contains(where: { $0.metaID == metaID }) else { return }
            myList.insert(item, at: min(i, myList.count))
        }
    }
    private var hiddenPending: [String: (Int, Suggestion)] = [:]
    private var hiddenMine: [String: (Int, HomeItem)] = [:]

    /// «Quitar de Seguir viendo».
    public func dismiss(_ item: HomeItem) async {
        dismissed.insert(item.metaID)   // al instante (sin esperar la carga en curso); la carga lo filtra
        continueWatching.removeAll { $0.metaID == item.metaID }
        publishWidget()
        try? await services.watch.dismissContinue(metaID: item.metaID, newEpisode: item.isNew == true ? item.videoID : nil)
    }
}
