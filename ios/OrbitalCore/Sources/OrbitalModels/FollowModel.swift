import Foundation
import OrbitalCore

/// Seguir o dejar de seguir una serie (como en Trakt): la que dejas de seguir ya no sale en tus estrenos («Lo nuevo de lo
/// tuyo») ni te manda avisos. Se marca al momento en el iPhone y se guarda en Trakt (oculta de tu calendario y tu progreso).
@MainActor
public final class FollowModel: ObservableModel {
    public private(set) var unfollowed: Set<String> { didSet { if oldValue != unfollowed { changed() } } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        unfollowed = ForYou.unfollowed(services.kv)
        super.init()
    }

    public var available: Bool { services.trakt?.linked == true }
    public func isFollowing(_ imdb: String) -> Bool { !unfollowed.contains(imdb) }

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
