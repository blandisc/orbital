import Foundation
import OrbitalCore

extension Services {
    /// La clave de la app en OpenSubtitles (Info.plist › `OrbitalOpenSubtitlesKey`, del ajuste `ORBITAL_OPENSUBTITLES_KEY` de
    /// `Secrets.xcconfig`, que no va a git). Vacía: no se usa la API y quedan los subtítulos del complemento.
    public nonisolated static var bundledOpenSubtitlesKey: String {
        let key = ((Bundle.main.object(forInfoDictionaryKey: "OrbitalOpenSubtitlesKey") as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.hasPrefix("$(") ? "" : key
    }

    nonisolated static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    /// La API de OpenSubtitles con tus idiomas de subtítulos (y el de la app y el inglés, que es lo que más hay).
    nonisolated static func makeOpenSubtitles(http: HTTPClient, secrets: SecretsStore, settings: SettingsStore,
                                              key: String = Services.bundledOpenSubtitlesKey) -> OpenSubtitlesAPI? {
        guard !key.isEmpty else { return nil }
        return OpenSubtitlesAPI(http: http, apiKey: key, secrets: secrets, version: appVersion) {
            let s = settings.value
            return [s.subtitles, s.uiLanguage, "en"].filter { !$0.isEmpty }
        }
    }
}
