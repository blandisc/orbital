import Foundation
import OrbitalCore
import OrbitalAddons

/// «Tus idiomas» (N4-A, Fernando, 4 nov: «asegúrate que sea fácil cambiar tus idiomas preferidos, que esté claro en
/// ajustes»): un solo lugar, Ajustes › Tus idiomas. De ahí salen la puntuación de las versiones, el plan B del reproductor y
/// los «Idiomas primero» de Torrentio (que ya no se cambian en su página).
extension Services {
    /// Los idiomas que se pueden agregar, en el orden de la lista de «Agregar idioma».
    public static let addableLanguages = ["es-419", "es-ES", "es", "en", "original", "ja", "ko", "fr", "it", "de", "pt", "zh", "ru", "hi", "pl", "tr", "nl",
                                          "sv", "da", "no", "fi", "cs", "hu", "ro", "uk", "el", "he", "ar", "th", "vi", "id"]

    /// Cambia «Tus idiomas»: se guarda, Torrentio pone primero esos mismos (sin «original» ni inglés) y lo buscado se olvida.
    public func setLanguages(_ list: [String]) {
        let before = appSettings
        settings.update { $0.setLanguages(list) }
        guard appSettings != before else { return }
        syncTorrentioLanguages()
        Task { await finder.forgetAll() }
    }

    /// Torrentio dice primero lo de «Tus idiomas» (la dirección `language=` sale de tu orden menos «original»).
    func syncTorrentioLanguages() {
        guard let torrentio = addonList.torrentio else { return }
        let keys = TorrentioConfig.keys(fromLanguages: appSettings.yourLanguages)
        var options = torrentio.options ?? TorrentioConfig.recommended
        guard options.languages != keys else { return }
        options.languages = keys
        addonList.setOptions(torrentio.id, options)
    }

    /// La primera vez con «Tus idiomas»: lo que ya tenías (tu audio, latino o castellano, y los «Idiomas primero» que pusiste
    /// en Torrentio, al final y sin repetir) queda como tu lista. No se pierde nada de lo que elegiste.
    func migrateLanguages() {
        guard appSettings.languages == nil else { return }
        var list = appSettings.yourLanguages
        for code in TorrentioConfig.fallbackCodes(addonList.torrentio?.options) where !list.contains(code) { list.append(code) }
        settings.update { $0.setLanguages(list) }
    }
}
