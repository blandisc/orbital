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

    /// ET1: cómo va la descarga de una temporada. `fraction` solo mientras algo baja o espera (0…1, contando lo ya listo); `ready`
    /// solo cuando TODOS están en el iPhone (antes se decía «Temporada lista» en cuanto entraban a la fila; Fernando, 9 nov).
    public struct SeasonDownload: Equatable, Sendable {
        public var total = 0, done = 0, active = 0, missing = 0
        public var fraction: Double?
        public var ready: Bool { total > 0 && done == total }
    }

    public func seasonDownload(_ season: Int) -> SeasonDownload {
        let ids = seasonEpisodeIDs(season)
        var out = SeasonDownload(total: ids.count)
        var progress = 0.0
        for id in ids {
            switch downloadState(id) {
            case .done?: out.done += 1
            case .downloading?, .queued?, .paused?: out.active += 1; progress += downloadFraction(id) ?? 0
            default: out.missing += 1
            }
        }
        if out.active > 0 { out.fraction = min(1, (Double(out.done) + progress) / Double(out.done + out.active)) }
        return out
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
