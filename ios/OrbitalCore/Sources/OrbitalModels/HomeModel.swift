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
    static let spotlightLimit = 16
    public private(set) var isLoading = false { didSet { changed() } }
    /// Lo que sale de tus series en los próximos días (Trakt): «Sale hoy» (portada) y «Sale pronto» en Inicio.
    public private(set) var upcoming: [Airing] = [] { didSet { changed() } }
    /// Lo primero que sale hoy: la portada de Inicio y el título al bajar («Sale hoy: Severance»).
    public var airingToday: Airing? { upcoming.first { Calendar.current.isDateInToday($0.day) } }
    public private(set) var offline = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private let services: Services
    static let cacheKey = "home-cache"

    private struct Cache: Codable { var continueWatching: [HomeItem]; var myList: [HomeItem] }

    public init(_ services: Services) {
        self.services = services
        super.init()
        if let data = services.kv.data(Self.cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            continueWatching = cache.continueWatching; myList = cache.myList
        }
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
        lastRefresh = services.now()
        isLoading = true
        defer { isLoading = false }
        do {
            _ = await services.watch.flushPending()          // primero se sube lo pendiente; así la lista ya lo trae
            let all = try await services.watch.library()
            let continueItems = all.filter { w in
                guard w.inContinue else { return false }
                let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.episode.episode != nil
                return nextUp || (w.progress ?? 1) >= PlaybackRules.continueMinProgress
            }
            let mine = all.filter(\.inLibrary)
            async let continued = items(continueItems), listed = items(mine)   // las dos traducciones a la vez
            continueWatching = await continued
            myList = await listed
            offline = false; error = nil
            services.kv.set(Self.cacheKey, data: try? JSONEncoder().encode(Cache(continueWatching: continueWatching, myList: myList)))
        } catch where !Task.isCancelled {   // cancelado (cambio de pestaña): no es estar sin conexión
            offline = true
            self.error = "\(error)"
        } catch {}
        let forYou = services.forYou
        async let mix = spotlightLists(forYou)
        async let airings = try? forYou.calendar(), pending = try? forYou.items(listID: "watchlist")
        let (fetchedPending, fetchedAirings) = await (pending, airings)
        // Cancelado o sin respuesta de Trakt: no se vacía «Tu watchlist» ni el «Próximo estreno» del widget (nil = se queda el
        // que había). «Seguir viendo» sí va al widget siempre.
        let cancelled = Task.isCancelled
        if !cancelled {
            if let fetchedPending { traktPending = Array(fetchedPending.prefix(12)) }
            else if !(await forYou.traktLinked) { traktPending = [] }   // desconectaste Trakt: ya no hay watchlist que enseñar
        }
        if !cancelled, let fetchedAirings { upcoming = Array(fetchedAirings.prefix(10)) }
        let lists = await mix
        if !cancelled, lists.contains(where: { !$0.isEmpty }) {
            spotlight = Self.mixSpotlight(lists, excluding: Set(continueWatching.map(\.metaID)), limit: Self.spotlightLimit)
        }
        publishWidget(airings: cancelled ? nil : fetchedAirings)   // los estrenos también van al widget mediano
    }

    /// Las listas de «Destacado», en el orden en que se entreveran: tendencia, para ti y popular, cada una en película y serie.
    private func spotlightLists(_ forYou: ForYou) async -> [[Suggestion]] {
        async let tm = try? forYou.items(listID: "trend", kind: "movie"), ts = try? forYou.items(listID: "trend", kind: "series")
        async let rm = try? forYou.items(listID: "recs", kind: "movie"), rs = try? forYou.items(listID: "recs", kind: "series")
        async let pm = try? forYou.items(listID: "popular", kind: "movie"), ps = try? forYou.items(listID: "popular", kind: "series")
        let trakt = await [tm ?? [], ts ?? [], rm ?? [], rs ?? [], pm ?? [], ps ?? []]
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
                            timeLeft: PlaybackRules.timeLeft(left), leftMinutes: PlaybackRules.minutesLeft(left), nextUp: nextUp)
        }
    }

    /// Lo que verá el widget «Lo siguiente para ti»: «Seguir viendo» tal como quedó (también la copia de la última vez, sin red).
    private func publishWidget(airings: [Airing]? = nil) {
        services.publishWidget(continueWatching: continueWatching, airings: airings)
    }

    /// «Quitar de Seguir viendo».
    public func dismiss(_ item: HomeItem) async {
        continueWatching.removeAll { $0.metaID == item.metaID }
        publishWidget()
        try? await services.watch.dismissContinue(metaID: item.metaID)
    }
}
