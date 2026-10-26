import Foundation
import OrbitalCore

extension Services {
    /// Pone en la cola de descargas un video (película o episodio) con la fuente que mejor sirve para guardar. Es el
    /// camino de «Descargar» de la ficha y también el de lo que la TV manda con «Descargar en el iPhone»: «Solo con
    /// Wi‑Fi» lo respeta el transporte de descargas (la cola espera a tener Wi‑Fi), no quien la llena.
    public func queueDownload(kind: String, metaID: String, videoID: String, title: String, originalTitle: String,
                              subtitle: String, poster: String?, source chosen: Source? = nil, replace: Bool = false,
                              keepBoth: Bool = false) async -> TitleModel.DownloadOutcome {
        let langs = titlePrefs.languages(for: metaID, settings: appSettings)
        introDB.warm(videoID: videoID)   // «Saltar intro» también sin conexión: las marcas se guardan con la descarga
        do {
            // La que elegiste en «Elegir la fuente» (si tiene enlace); si no, la que mejor sirve para guardar.
            // Una lista de reproducción (HLS/DASH) no es un archivo: esa no se baja aunque la elijas.
            var picked = chosen.flatMap { c in c.playbackURL.map { ["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } == false ? c : nil }
            if picked == nil { picked = try await finder.best(kind: kind, videoID: videoID, prefs: langs.prefs, purpose: .download) }
            guard let source = picked, let url = source.playbackURL else {
                return .noSources
            }
            // «Bajar también esta»: otra versión junto a la que tienes, con su propio id y su propio archivo.
            let version = keepBoth ? "v\(Int(Date().timeIntervalSince1970))" : nil
            let id = DownloadItem.makeID(metaID: metaID, videoID: videoID) + (version.map { "|\($0)" } ?? "")
            let item = DownloadItem(id: id, kind: kind, metaID: metaID, videoID: videoID, title: title, originalTitle: originalTitle,
                                    subtitle: subtitle, poster: poster, addon: source.addon, release: source.release, sourceIndex: source.index, expectedBytes: source.size > 0 ? Int64(source.size) : nil,
                                    relativePath: DownloadFiles.relativePath(metaID: metaID, videoID: version.map { "\(videoID)-\($0)" } ?? videoID, ext: DownloadFiles.fileExtension(for: url)),
                                    createdAt: Date().timeIntervalSince1970)
            // Cambiar la copia que ya tienes por otra fuente (una sola por película o episodio): la de antes se borra hasta que la
            // nueva ya tiene enlace y cabe (contando lo que libera la vieja); si algo falla antes, te quedas con la que tenías.
            if replace, let old = await downloads.item(item.id) {
                guard await downloads.canFit(item, freeing: old.id) else {
                    return .notEnoughSpace(DownloadError.notEnoughSpace(needed: item.expectedBytes ?? 0, free: freeSpace() + old.writtenBytes).description)
                }
                DownloadsModel.clearShared()   // un enlace de «Compartir» mantendría ocupado el espacio de la vieja
                await downloads.remove(old.id)
            }
            try await downloads.enqueue(item, url: url)
            return .queued(1)
        } catch let error as DownloadError {
            if case .alreadyDownloaded = error { return .already }
            if case .notEnoughSpace = error { return .notEnoughSpace(error.description) }
            return .failed(error.description)
        } catch let error as StreamFinderError { return .failed(error.description)
        } catch { return .failed("Intenta de nuevo en un momento.") }
    }
}
