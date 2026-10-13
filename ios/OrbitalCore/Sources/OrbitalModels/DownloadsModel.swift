import Foundation
import OrbitalCore

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

    /// Al terminar de ver un episodio descargado: se baja el siguiente si lo pediste, y se borra lo visto si lo pediste.
    public func afterWatching(_ item: DownloadItem) async {
        let settings = services.appSettings
        if settings.autoNextDownload, item.kind == "series", let meta = try? await services.cinemeta.meta(kind: item.kind, id: item.metaID) {
            for next in await services.downloads.nextToDownload(metaID: item.metaID, meta: meta) {
                let langs = services.titlePrefs.languages(for: item.metaID, settings: settings)
                guard let source = try? await services.finder.best(kind: item.kind, videoID: next, prefs: langs.prefs, purpose: .download), let url = source.playbackURL else { continue }
                let download = DownloadItem(id: DownloadItem.makeID(metaID: item.metaID, videoID: next), kind: item.kind, metaID: item.metaID, videoID: next, title: item.title,
                                            originalTitle: item.originalTitle, subtitle: "", poster: item.poster, addonURL: source.transportURL, sourceIndex: source.index,
                                            expectedBytes: source.size > 0 ? Int64(source.size) : nil,
                                            relativePath: DownloadFiles.relativePath(metaID: item.metaID, videoID: next, ext: DownloadFiles.fileExtension(for: url)),
                                            createdAt: Date().timeIntervalSince1970)
                try? await services.downloads.enqueue(download, url: url)
            }
        }
        if settings.deleteWhenWatched { await services.downloads.remove(item.id) }
    }
}
