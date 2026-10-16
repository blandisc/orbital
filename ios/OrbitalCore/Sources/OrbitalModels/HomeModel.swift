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
    public private(set) var isLoading = false { didSet { changed() } }
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

    public func refresh() async {
        guard services.isSignedIn else { return }
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
        async let airings = try? forYou.calendar(), pending = try? forYou.items(listID: "watchlist")
        let (fetchedPending, fetchedAirings) = await (pending, airings)
        guard !Task.isCancelled else { return }   // cancelado: no se vacía «Tu watchlist» ni el «Próximo estreno» del widget
        if let fetchedPending { traktPending = Array(fetchedPending.prefix(12)) }
        else if !(await forYou.traktLinked) { traktPending = [] }   // desconectaste Trakt: ya no hay watchlist que enseñar
        if let fetchedAirings { publishWidget(airings: fetchedAirings) }   // los estrenos también van al widget mediano
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
