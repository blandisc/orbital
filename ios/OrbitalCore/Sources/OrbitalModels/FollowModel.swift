import Foundation
import OrbitalCore

/// Seguir o dejar de seguir una serie (como en Trakt): la que dejas de seguir ya no sale en tus estrenos («Lo nuevo de lo
/// tuyo») ni te manda avisos. Se marca al momento en el iPhone y se guarda en Trakt (oculta de tu calendario y tu progreso).
@MainActor
public final class FollowModel: ObservableModel {
    public private(set) var unfollowed: Set<String> { didSet { if oldValue != unfollowed { changed() } } }
    /// Las series que has visto en Trakt (la más reciente primero): las que puedes seguir o dejar de seguir en Ajustes ›
    /// Avisos › Series que sigues.
    public private(set) var series: [TraktWatchedTitle] = [] { didSet { if oldValue != series { changed() } } }
    public private(set) var loadingSeries = false { didSet { if oldValue != loadingSeries { changed() } } }
    public private(set) var seriesProblem: String? { didSet { if oldValue != seriesProblem { changed() } } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        unfollowed = ForYou.unfollowed(services.kv)
        super.init()
    }

    public var available: Bool { services.trakt?.linked == true }
    public func isFollowing(_ imdb: String) -> Bool { !unfollowed.contains(imdb) }

    /// Las series que has visto, para elegir cuáles sigues (Fernando, 2 nov 2026: «editar dentro de la aplicación qué series
    /// sigues y qué no, porque me llegan notificaciones de series que ya no me interesan»).
    public func loadSeries() async {
        guard let trakt = services.trakt, trakt.linked else { series = []; return }
        loadingSeries = true
        defer { loadingSeries = false }
        do {
            series = try await trakt.watchedTitles(kind: "series").sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            seriesProblem = nil
        } catch {
            seriesProblem = "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }

    /// Cambia al momento; si Trakt no lo acepta, regresa y devuelve el motivo.
    public func setFollowing(_ imdb: String, _ following: Bool) async -> String? {
        let before = unfollowed
        if following { unfollowed.remove(imdb) } else { unfollowed.insert(imdb) }
        ForYou.setUnfollowed(unfollowed, kv: services.kv)
        guard let trakt = services.trakt, trakt.linked else { return nil }
        do {
            try await trakt.setFollowing(imdb: imdb, following: following)
            await services.forYou.clearCache(["trakt:calendar"])
            return nil
        } catch {
            unfollowed = before
            ForYou.setUnfollowed(before, kv: services.kv)
            return "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }
}
