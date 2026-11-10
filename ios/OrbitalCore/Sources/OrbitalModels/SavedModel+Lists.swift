import Foundation
import OrbitalCore

/// El «···» de cada lista tuya (G4-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»): cambiar nombre, quién la ve,
/// ordenar a mano, duplicar, compartir y borrar. Mi lista solo se ordena a mano (desde «Ordenar y filtrar»). Necesita conexión.
/// docs/producto/live-activity-2026-11-08/gestor-ola2.html
extension SavedModel {
    static func orderKey(_ listID: String) -> String { "saved-order.\(listID)" }

    /// Lo que ordenaste a mano manda; lo nuevo (que no estaba cuando ordenaste) va primero, como llega.
    nonisolated static func manualOrder(_ items: [Suggestion], _ order: [String]?) -> [Suggestion] {
        guard let order, !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let fresh = items.filter { rank[$0.imdb] == nil }
        let placed = items.filter { rank[$0.imdb] != nil }.sorted { rank[$0.imdb]! < rank[$1.imdb]! }
        return fresh + placed
    }

    private func refreshLists(_ id: String? = nil) async {
        var keys = ["trakt:lists", "trakt:listkeys"]
        if let id { keys.append("trakt:list:\(id)") }
        await services.forYou.clearCache(keys)
    }

    private func requireTrakt() throws -> Trakt {
        guard let trakt = services.trakt, trakt.linked else { throw TraktError.auth("Conecta Trakt en Ajustes") }
        return trakt
    }

    /// El nombre de una de tus listas.
    public func name(of listID: String) -> String { lists.first { $0.id == listID }?.name ?? "" }

    public func renameList(_ listID: String, to name: String) async throws {
        guard let id = Self.traktListID(listID) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await requireTrakt().updateList(id, name: clean)
        replaceList(listID, with: SavedList(id: listID, name: clean))
        services.traktOutbox.remember(lists: services.traktOutbox.cachedLists.map { $0.id == id ? (id, clean) : $0 })
        await refreshLists()
    }

    public func setPrivacy(_ listID: String, _ privacy: String) async throws {
        guard let id = Self.traktListID(listID) else { return }
        try await requireTrakt().updateList(id, privacy: privacy)
        privacies[listID] = privacy
        await refreshLists()
    }

    /// Borra la lista (sin deshacer) y vuelve a Mi lista.
    public func deleteList(_ listID: String) async throws {
        guard let id = Self.traktListID(listID) else { return }
        try await requireTrakt().deleteList(id)
        removeList(listID)
        services.traktOutbox.remember(lists: services.traktOutbox.cachedLists.filter { $0.id != id })
        services.kv.set(Self.orderKey(listID), data: nil)
        await refreshLists(id)
        if selected == listID { await choose(Self.watchlist) }
    }

    /// «Copia de …», Solo tú, con los mismos títulos en el mismo orden. Devuelve su id (`list:<id>`).
    @discardableResult
    public func duplicateList(_ listID: String, name: String) async throws -> String {
        guard let id = Self.traktListID(listID) else { throw TraktError.invalid("Lista inválida") }
        let source = selected == listID ? items : ((try? await services.forYou.items(listID: listID)) ?? [])
        let made = try await requireTrakt().duplicateList(id, name: name, items: source.map { ($0.imdb, $0.kind == "series") })
        let newID = "list:\(made.id)"
        appendList(SavedList(id: newID, name: made.name))
        listCounts[newID] = source.count
        listPosters[newID] = Array(source.prefix(3).map(\.poster))
        privacies[newID] = "private"
        services.traktOutbox.remember(lists: services.traktOutbox.cachedLists + [(made.id, made.name)])
        await refreshLists()
        return newID
    }

    /// «Ordenar a mano»: el orden nuevo se ve ya y se guarda en Trakt (Mi lista también).
    public func reorder(_ listID: String, imdbs: [String]) async throws {
        let traktID = listID == Self.watchlist ? "watchlist" : Self.traktListID(listID)
        guard let traktID else { return }
        services.kv.set(Self.orderKey(listID), data: try? JSONEncoder().encode(imdbs))
        if selected == listID { items = Self.manualOrder(items, imdbs) }
        try await requireTrakt().reorder(traktID, imdbs: imdbs)
        await refreshLists(listID == Self.watchlist ? nil : traktID)
    }
}
