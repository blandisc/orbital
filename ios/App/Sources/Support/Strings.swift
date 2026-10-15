import Foundation

/// Textos que no pasan por `Text(...)` (SwiftUI ya usa el idioma de la app en los `Text`). Se buscan en el
/// catálogo `Localizable.xcstrings` con el idioma elegido en Ajustes, que puede ser distinto del del sistema.
enum Strings {
    static func tr(_ key: String, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// «T2 · E5» en español, «S2 · E5» en inglés.
    static func episode(season: Int?, episode: Int, language: String) -> String {
        guard let season else { return String(format: tr("E%lld", language: language), episode) }
        return String(format: tr("T%lld · E%lld", language: language), season, episode)
    }
}
