import Foundation
import OrbitalCore

/// DS1, DP2 y DB1 (Fernando, 8 nov): «¿Qué descargo?» de una serie (el siguiente, los siguientes 5, la temporada, toda la serie),
/// la temporada desde su encabezado y cuántos episodios tienes en el iPhone. https://claude.ai/artifact/CF24WJW7wQZ8xqQyeE2YFv
extension TitleModel {
    /// Los episodios en orden (sin especiales).
    public var allEpisodeIDs: [String] { seasons.filter { !$0.isSpecials }.flatMap { $0.episodes.map(\.id) } }

    /// Los siguientes `count` desde el que sigue.
    public func nextEpisodeIDs(_ count: Int) -> [String] {
        let ids = allEpisodeIDs
        guard let from = continueVideoID, let i = ids.firstIndex(of: from) else { return Array(ids.prefix(count)) }
        return Array(ids.dropFirst(i).prefix(count))
    }

    /// Los de una temporada.
    public func seasonEpisodeIDs(_ season: Int) -> [String] {
        seasons.first { $0.season == season }?.episodes.map(\.id) ?? []
    }

    /// Lo que falta bajar (ni listo ni en camino).
    public func notDownloaded(_ ids: [String]) -> [String] {
        ids.filter { id in
            switch downloadState(id) { case .done?, .downloading?, .queued?, .paused?: false; default: true }
        }
    }

    /// DB1: cuántos episodios (o la película) ya están en el iPhone.
    public var downloadedCount: Int {
        (kind == "movie" ? [metaID] : allEpisodeIDs).filter { downloadState($0) == .done }.count
    }

    /// Cuánto pesarían `count` episodios: el tamaño de la versión que se bajaría (la recomendada) por episodio. nil si no se sabe.
    public func estimatedBytes(episodes count: Int) -> Int64? {
        guard let size = recommendedSource?.size, size > 0, count > 0 else { return nil }
        return Int64(size) * Int64(count)
    }
}
