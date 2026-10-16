import Foundation
import OrbitalCore

extension Services {
    /// Pone en la cola de descargas un video (película o episodio) con la fuente que mejor sirve para guardar. Es el
    /// camino de «Descargar» de la ficha y también el de lo que la TV manda con «Descargar en el iPhone»: «Solo con
    /// Wi‑Fi» lo respeta el transporte de descargas (la cola espera a tener Wi‑Fi), no quien la llena.
    public func queueDownload(kind: String, metaID: String, videoID: String, title: String, originalTitle: String,
                              subtitle: String, poster: String?) async -> TitleModel.DownloadOutcome {
        let langs = titlePrefs.languages(for: metaID, settings: appSettings)
        do {
            guard let source = try await finder.best(kind: kind, videoID: videoID, prefs: langs.prefs, purpose: .download), let url = source.playbackURL else {
                return .noSources
            }
            let item = DownloadItem(id: DownloadItem.makeID(metaID: metaID, videoID: videoID), kind: kind, metaID: metaID, videoID: videoID, title: title, originalTitle: originalTitle,
                                    subtitle: subtitle, poster: poster, addon: source.addon, release: source.release, sourceIndex: source.index, expectedBytes: source.size > 0 ? Int64(source.size) : nil,
                                    relativePath: DownloadFiles.relativePath(metaID: metaID, videoID: videoID, ext: DownloadFiles.fileExtension(for: url)),
                                    createdAt: Date().timeIntervalSince1970)
            try await downloads.enqueue(item, url: url)
            return .queued(1)
        } catch let error as DownloadError {
            if case .alreadyDownloaded = error { return .already }
            if case .notEnoughSpace = error { return .notEnoughSpace(error.description) }
            return .failed(error.description)
        } catch { return .failed("\(error)") }
    }
}
