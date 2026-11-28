import Foundation
import OrbitalCore

/// Las descargas de la ficha: pausar, cancelar o seguir la copia que se enseña.
extension TitleModel {
    /// La copia que se enseña de un video (con «Bajar también esta» hay dos: la segunda lleva otro id). Antes «Cancelar la
    /// descarga» de la segunda borraba la primera, la ya lista (revisión del 27 nov 2026).
    func downloadID(_ videoID: String) -> String { downloadIDs[videoID] ?? DownloadItem.makeID(metaID: metaID, videoID: videoID) }

    /// Seguir una descarga en pausa o que falló (donde iba, con la misma fuente), en vez de empezarla de cero.
    public func resumeDownload(_ videoID: String) async {
        await services.downloads.resume(downloadID(videoID))
        await refreshState()
    }

    /// Pausar o cancelar (borrar lo bajado) una descarga de este título.
    public func pauseDownload(_ videoID: String) async {
        await services.downloads.pause(downloadID(videoID))
        await refreshState()
    }

    public func cancelDownload(_ videoID: String) async {
        await services.downloads.remove(downloadID(videoID))
        await refreshState()
    }

    /// La copia que ya tienes (o se está bajando) de este video, para preguntar antes de cambiarla por otra fuente.
    public func existingDownload(_ videoID: String) async -> DownloadItem? { await services.downloads.item(downloadID(videoID)) }
}
