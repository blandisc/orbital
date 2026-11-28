import Foundation
import OrbitalCore

/// DS1, DP2 y DB1 (Fernando, 8 nov): «¿Qué descargo?» de una serie (el siguiente, los siguientes 5, la temporada, toda la serie),
/// la temporada desde su encabezado y cuántos episodios tienes en el iPhone. https://claude.ai/artifact/CF24WJW7wQZ8xqQyeE2YFv
extension TitleModel {
    /// Los episodios en orden (sin especiales).
    /// Solo lo que ya salió: un episodio por estrenarse no tiene qué bajar (revisión del 28 nov 2026).
    public var allEpisodeIDs: [String] { videos(in: .series) }

    /// Los siguientes `count` desde el que sigue.
    public func nextEpisodeIDs(_ count: Int) -> [String] {
        let ids = allEpisodeIDs
        guard let from = continueVideoID, let i = ids.firstIndex(of: from) else { return Array(ids.prefix(count)) }
        return Array(ids.dropFirst(i).prefix(count))
    }

    /// Los de una temporada.
    public func seasonEpisodeIDs(_ season: Int) -> [String] {
        videos(in: .season(season))
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

    // MARK: descargar
    public enum DownloadOutcome: Equatable { case queued(Int), noSources, notEnoughSpace(String), already, failed(String) }

    /// Descarga uno o varios episodios con la fuente que mejor sirve para guardar (1080p, moderada).
    @discardableResult
    public func download(_ videoIDs: [String], source: Source? = nil, replace: Bool = false, keepBoth: Bool = false) async -> DownloadOutcome {
        // Se intentan todos: uno sin versión o que falla no detiene a los demás, y lo que sí se encoló se ve en sus renglones
        // (antes, si el primero no tenía versión, no se bajaba ninguno; revisión del 28 nov 2026). Sin espacio sí se para.
        var queued = 0, already = 0
        var failure: DownloadOutcome?
        for video in videoIDs {
            var label = ""
            if let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
            switch await services.queueDownload(kind: kind, metaID: metaID, videoID: video, title: title, originalTitle: sentTitle, subtitle: label, poster: poster, source: source, replace: replace, keepBoth: keepBoth) {
            case .queued: queued += 1
            case .noSources: continue
            case .already: already += 1
            case .notEnoughSpace(let message): failure = .notEnoughSpace(message)
            case .failed(let message): failure = failure ?? .failed(message); continue
            }
            if case .notEnoughSpace = failure { break }
        }
        await refreshState()
        if queued > 0 { return .queued(queued) }
        if let failure { return failure }
        return already > 0 && already == videoIDs.count ? .already : .noSources
    }

    /// «Descargar los siguientes N episodios».
    public func downloadNext(_ count: Int) async -> DownloadOutcome {
        let from = continueVideoID
        let ids = videos(in: .series)   // solo lo que ya salió
        guard let from, let i = ids.firstIndex(of: from) else { return .noSources }
        return await download(Array(ids.dropFirst(i).prefix(count)))
    }
}
