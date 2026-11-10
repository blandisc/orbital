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
    /// Las que escondiste (SS1-A): no salen en la lista, ni en tus estrenos, ni en «Sigue viendo», ni te avisan.
    public private(set) var hidden: Set<String> { didSet { if oldValue != hidden { changed() } } }
    /// Las escondidas según Trakt, con su nombre (para «Escondidas»).
    private var hiddenFromTrakt: [TraktHiddenShow] = [] { didSet { if oldValue != hiddenFromTrakt { changed() } } }
    /// La última que escondiste y si la seguías: lo que regresa «Deshacer».
    public private(set) var lastHidden: (imdb: String, wasFollowing: Bool)?
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        unfollowed = ForYou.unfollowed(services.kv)
        hidden = ForYou.hidden(services.kv)
        super.init()
    }

    /// La lista de «Series que sigues»: las que viste, sin las escondidas.
    public var visibleSeries: [TraktWatchedTitle] { series.filter { !hidden.contains($0.imdb) } }
    /// «Escondidas»: con el nombre de Trakt o, si aún no contesta, el de lo que viste.
    public var hiddenSeries: [TraktHiddenShow] {
        let named = Dictionary((hiddenFromTrakt.map { ($0.imdb, $0) } + series.map { ($0.imdb, TraktHiddenShow(imdb: $0.imdb, traktID: $0.traktID, title: $0.title)) }),
                               uniquingKeysWith: { a, b in a.title.isEmpty ? b : a })
        let order = series.map(\.imdb) + hiddenFromTrakt.map(\.imdb)
        var seen = Set<String>()
        return order.filter { hidden.contains($0) && seen.insert($0).inserted }.compactMap { named[$0] }
    }

    public var available: Bool { services.trakt?.linked == true }
    public func isFollowing(_ imdb: String) -> Bool { !unfollowed.contains(imdb) }

    /// Las series que has visto, para elegir cuáles sigues (Fernando, 2 nov 2026: «editar dentro de la aplicación qué series
    /// sigues y qué no, porque me llegan notificaciones de series que ya no me interesan»).
    public func loadSeries() async {
        guard let trakt = services.trakt, trakt.linked else { series = []; return }
        loadingSeries = true
        defer { loadingSeries = false }
        async let hiddenNow = try? trakt.hiddenShows()
        do {
            series = try await trakt.watchedTitles(kind: "series").sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            seriesProblem = nil
            // Trakt manda: lo que escondiste en otro aparato también se va de aquí (y lo que mostraste allá, regresa).
            if let found = await hiddenNow {
                hiddenFromTrakt = found
                hidden = ForYou.hiddenFrom(trakt: found.map(\.imdb), kv: services.kv, pending: services.traktOutbox.pendingHidden)
                ForYou.setHidden(hidden, kv: services.kv)
            }
        } catch {
            seriesProblem = "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }

    /// Cambia al momento; si Trakt no lo acepta, regresa y devuelve el motivo.
    public func setFollowing(_ imdb: String, _ following: Bool) async -> String? {
        let before = unfollowed, hiddenBefore = hidden
        if following { unfollowed.remove(imdb) } else { unfollowed.insert(imdb) }
        ForYou.setUnfollowed(unfollowed, kv: services.kv)
        // Seguirla otra vez (desde su ficha) también la saca de «Escondidas»: Trakt la vuelve a mostrar.
        if following, hidden.contains(imdb) { hidden.remove(imdb); ForYou.setHidden(hidden, kv: services.kv) }
        guard let trakt = services.trakt, trakt.linked else { return nil }
        do {
            try await trakt.setFollowing(imdb: imdb, following: following)
            await services.forYou.clearCache(["trakt:calendar"])
            return nil
        } catch {
            unfollowed = before; hidden = hiddenBefore
            ForYou.setUnfollowed(before, kv: services.kv); ForYou.setHidden(hiddenBefore, kv: services.kv)
            return "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }

    /// «Esconder» (SS1-A): sale de la lista, de tus estrenos, de «Sigue viendo» y de los avisos, aquí y en Trakt (oculta de tu
    /// progreso y tu calendario) y, desde «La dejé» (G1-A), también en sus «dejadas». Lo que viste se queda. Sin internet se
    /// queda hecho y espera a Trakt; si Trakt no lo acepta, regresa y devuelve el motivo.
    public func hide(_ imdb: String) async -> String? {
        let wasFollowing = isFollowing(imdb)
        let before = (hidden, unfollowed)
        lastHidden = (imdb, wasFollowing)
        await apply(hidden: hidden.union([imdb]), unfollowed: unfollowed.union([imdb]))
        guard let trakt = services.trakt, trakt.linked else { return nil }
        do {
            try await trakt.setHidden(imdb: imdb, hidden: true, sections: Trakt.droppedSections)
            return nil
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.hidden(imdb: imdb, true, sections: Trakt.droppedSections))
            return nil
        } catch {
            await apply(hidden: before.0, unfollowed: before.1)
            lastHidden = nil
            return "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }

    /// «Mostrar otra vez» (desde «Escondidas») o «Deshacer»: regresa a la lista. `following`: si vuelve a avisarte (al deshacer,
    /// como estaba antes de esconderla).
    public func unhide(_ imdb: String, following: Bool = true) async -> String? {
        let before = (hidden, unfollowed)
        await apply(hidden: hidden.subtracting([imdb]), unfollowed: following ? unfollowed.subtracting([imdb]) : unfollowed.union([imdb]))
        guard let trakt = services.trakt, trakt.linked else { return nil }
        // Apagada se queda oculta del calendario (así no te avisa); solo vuelve a tu progreso. Y deja de contar como dejada.
        let sections = following ? Trakt.droppedSections : ["progress_watched", "dropped"]
        do {
            try await trakt.setHidden(imdb: imdb, hidden: false, sections: sections)
            hiddenFromTrakt.removeAll { $0.imdb == imdb }
            return nil
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.hidden(imdb: imdb, false, sections: sections))
            hiddenFromTrakt.removeAll { $0.imdb == imdb }
            return nil
        } catch {
            await apply(hidden: before.0, unfollowed: before.1)
            return "Trakt no contestó. Intenta de nuevo en un momento."
        }
    }

    /// «Deshacer» del aviso «Escondida»: como estaba.
    public func undoHide() async -> String? {
        guard let last = lastHidden else { return nil }
        lastHidden = nil
        return await unhide(last.imdb, following: last.wasFollowing)
    }

    /// Guarda las dos listas y avisa a lo que las lee: tus estrenos (y los avisos), «Sigue viendo» en Inicio y los widgets.
    private func apply(hidden newHidden: Set<String>, unfollowed newUnfollowed: Set<String>) async {
        hidden = newHidden; unfollowed = newUnfollowed
        ForYou.setHidden(newHidden, kv: services.kv)
        ForYou.setUnfollowed(newUnfollowed, kv: services.kv)
        await services.forYou.clearCache(["trakt:calendar", "trakt:watching"])
        services.publishWidget()
        NotificationCenter.default.post(name: LocalLibrary.changed, object: nil)
    }
}
