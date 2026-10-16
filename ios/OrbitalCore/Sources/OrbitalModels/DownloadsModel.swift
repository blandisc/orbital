import Foundation
import OrbitalCore

/// Lo descargado de un mismo título (una película, o los episodios de una serie): un renglón en Descargas.
public struct DownloadGroup: Identifiable, Equatable, Sendable {
    public var id: String { metaID }
    public var metaID: String, kind: String, title: String, poster: String?
    public var items: [DownloadItem]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.writtenBytes } }

    /// Agrupa por título en el orden en que llegaron (lo más reciente primero dentro de cada grupo se respeta tal cual).
    public static func group(_ items: [DownloadItem]) -> [DownloadGroup] {
        var order: [String] = [], groups: [String: DownloadGroup] = [:]
        for item in items {
            if groups[item.metaID] == nil {
                order.append(item.metaID)
                groups[item.metaID] = DownloadGroup(metaID: item.metaID, kind: item.kind, title: item.title, poster: item.poster, items: [])
            }
            groups[item.metaID]?.items.append(item)
        }
        return order.compactMap { groups[$0] }
    }
}

@MainActor
public final class DownloadsModel: ObservableModel {
    public private(set) var items: [DownloadItem] = [] { didSet { changed() } }
    public private(set) var freeBytes: Int64 = 0 { didSet { changed() } }
    private let services: Services
    private let freeSpace: @Sendable () -> Int64

    public init(_ services: Services, freeSpace: @escaping @Sendable () -> Int64) {
        self.services = services; self.freeSpace = freeSpace
        super.init()
    }

    /// Escucha los cambios de la cola (la pantalla lo lanza en una tarea mientras está abierta).
    public func run() async {
        items = await services.downloads.all
        freeBytes = freeSpace()
        for await snapshot in services.downloads.makeUpdates() { items = snapshot; freeBytes = freeSpace() }
    }

    public var active: [DownloadItem] { items.filter { $0.state != .done } }
    public var ready: [DownloadItem] { items.filter { $0.state == .done } }
    /// Lo listo para ver, agrupado por título (los episodios de una serie en un solo renglón).
    public var readyGroups: [DownloadGroup] { DownloadGroup.group(ready) }
    public var usedBytes: Int64 { items.reduce(0) { $0 + $1.writtenBytes } }

    public func pause(_ id: String) async { await services.downloads.pause(id) }
    public func resume(_ id: String) async { await services.downloads.resume(id) }
    public func remove(_ id: String) async { await services.downloads.remove(id) }

    /// Para ver una descarga sin conexión.
    public func playRequest(_ item: DownloadItem) async -> PlayRequest {
        let file = await services.downloads.fileURL(item)
        let subs = item.subtitleFiles.map { file.deletingLastPathComponent().appendingPathComponent($0) }
        return PlayRequest(kind: item.kind, metaID: item.metaID, videoID: item.videoID, originalTitle: item.originalTitle, displayTitle: item.title,
                           episodeLabel: item.subtitle, poster: item.poster, meta: try? await services.cinemeta.meta(kind: item.kind, id: item.metaID),
                           localFile: file, localSubtitles: subs)
    }

    /// «T2 · E6 · Halloween» para una descarga (sin esto, varios episodios de la misma serie se ven iguales en la lista).
    static func episodeLabel(_ videoID: String, meta: JSON, services: Services) -> String {
        for season in CinemetaParsing.seasons(meta) {
            if let episode = season.episodes.first(where: { $0.id == videoID }) {
                return services.episodeLabel(season.season, episode.episode) + (episode.hasTitle ? " · \(episode.title)" : "")
            }
        }
        return ""
    }

    /// Al terminar de ver un episodio descargado: se baja el siguiente si lo pediste, y se borra lo visto si lo pediste.
    public func afterWatching(_ item: DownloadItem) async {
        let settings = services.appSettings
        if settings.autoNextDownload, item.kind == "series", let meta = try? await services.cinemeta.meta(kind: item.kind, id: item.metaID) {
            for next in await services.downloads.nextToDownload(metaID: item.metaID, meta: meta) {
                let langs = services.titlePrefs.languages(for: item.metaID, settings: settings)
                guard let source = try? await services.finder.best(kind: item.kind, videoID: next, prefs: langs.prefs, purpose: .download), let url = source.playbackURL else { continue }
                let download = DownloadItem(id: DownloadItem.makeID(metaID: item.metaID, videoID: next), kind: item.kind, metaID: item.metaID, videoID: next, title: item.title,
                                            originalTitle: item.originalTitle, subtitle: Self.episodeLabel(next, meta: meta, services: services), poster: item.poster, addon: source.addon, release: source.release, sourceIndex: source.index,
                                            expectedBytes: source.size > 0 ? Int64(source.size) : nil,
                                            relativePath: DownloadFiles.relativePath(metaID: item.metaID, videoID: next, ext: DownloadFiles.fileExtension(for: url)),
                                            createdAt: Date().timeIntervalSince1970)
                try? await services.downloads.enqueue(download, url: url)
            }
        }
        if settings.deleteWhenWatched { await services.downloads.remove(item.id) }
    }
}
