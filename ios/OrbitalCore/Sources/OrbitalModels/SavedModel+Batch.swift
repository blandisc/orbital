import Foundation
import OrbitalCore

/// Elegir varios a la vez (G3-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»): «Editar» en Guardado elige pósters y la
/// barra de abajo los manda juntos a Vistas, a otra lista, a «Las dejé» o los quita. El tablero cambia al instante y Trakt
/// recibe un solo envío por lista (la cola los junta: `TraktOutbox.flush`); sin internet, espera.
/// docs/producto/live-activity-2026-11-08/gestor-ola2.html
extension SavedModel {
    /// Lo que ofrece la barra en cada lugar (la tabla de la propuesta).
    public enum BatchAction: String, Sendable, CaseIterable { case watched, drop, moveToList, toWatchlist, resume, remove }

    /// `place`: la lista que ves (`watchlist` o `list:<id>`) o un montón del tablero.
    public nonisolated static func batchActions(listID: String?, pile: TitleStatus?) -> [BatchAction] {
        if let listID, TitleActions.isEditable(listID: listID) {
            return listID == "watchlist" ? [.watched, .drop, .moveToList, .remove] : [.watched, .drop, .moveToList, .toWatchlist, .remove]
        }
        switch pile {
        case .watching: return [.toWatchlist, .drop, .moveToList]
        case .watched: return [.toWatchlist, .moveToList]
        case .dropped: return [.resume, .toWatchlist]
        default: return []
        }
    }

    /// El id de Trakt de una de tus listas (`list:123` → `123`); nil para Mi lista.
    nonisolated static func traktListID(_ listID: String) -> String? { listID.hasPrefix("list:") ? String(listID.dropFirst(5)) : nil }

    /// Pone o quita varios de Mi lista o de una de tus listas, al momento, y manda la cola una sola vez.
    public func setMany(_ items: [Suggestion], in listID: String, add: Bool) async {
        guard !items.isEmpty else { return }
        let outbox = services.traktOutbox
        if listID == Self.watchlist {
            for s in items {
                if add { if !watchlist.contains(where: { $0.imdb == s.imdb }) { watchlist.insert(s, at: 0) } }
                else { watchlist.removeAll { $0.imdb == s.imdb } }
                await services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: add, outbox: outbox, flush: false)
            }
            await services.forYou.clearCache(["trakt:watchlist"])
        } else if let id = Self.traktListID(listID) {
            for s in items where s.imdb.hasPrefix("tt") { outbox.enqueue(.init(target: id, imdb: s.imdb, series: s.kind == "series", add: add)) }
            listCounts[listID] = max(0, (listCounts[listID] ?? 0) + (add ? items.count : -items.count))
            await services.forYou.clearCache(["trakt:list:\(id)", "trakt:listkeys"])
        }
        if selected == listID { for s in items { setShown(s, shown: add) } }
        await outbox.flush(services.trakt)
    }

    /// «Vistas» con varios: solo las películas (las series se marcan por capítulo en su ficha); salen de Mi lista.
    @discardableResult
    public func markMoviesWatched(_ items: [Suggestion], at date: Date = Date()) async -> [Suggestion] {
        let movies = items.filter { $0.kind == "movie" }
        for s in movies { noteWatched(s, at: date); noteMoved(s.imdb, to: .watched) }
        let listed = movies.filter { s in watchlist.contains { $0.imdb == s.imdb } }
        await setMany(listed, in: Self.watchlist, add: false)
        for s in movies { try? await actions.markWatched(s, at: date) }
        return movies
    }

    /// El «Deshacer» de «Vistas» con varios.
    public func unmarkMoviesWatched(_ items: [Suggestion]) async {
        for s in items { await unmarkMovieWatched(s) }
    }

    /// Una lista nueva en Trakt («Lista nueva…» de «Mover a…»): nace «Solo tú». Devuelve su id (`list:<id>`) o el motivo.
    public func createList(named name: String) async -> Result<String, TraktError> {
        guard let trakt = services.trakt, trakt.linked else { return .failure(.auth("Conecta Trakt en Ajustes")) }
        do {
            let made = try await trakt.createList(name: name)
            let id = "list:\(made.id)"
            appendList(SavedList(id: id, name: made.name))
            services.traktOutbox.remember(lists: services.traktOutbox.cachedLists + [(made.id, made.name)])
            await services.forYou.clearCache(["trakt:lists"])
            return .success(id)
        } catch let error as TraktError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
