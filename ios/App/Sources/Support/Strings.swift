import Foundation
import OrbitalCore

/// Textos que no pasan por `Text(...)` (SwiftUI ya usa el idioma de la app en los `Text`). Se buscan en el
/// catálogo `Localizable.xcstrings` con el idioma elegido en Ajustes, que puede ser distinto del del sistema.
enum Strings {
    static func tr(_ key: String, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// «T2 E5» en español, «S2 E5» en inglés (como la TV: el « · » separa datos, no la temporada del episodio).
    static func episode(season: Int?, episode: Int, language: String) -> String {
        guard let season else { return String(format: tr("E%lld", language: language), episode) }
        return String(format: tr("T%lld E%lld", language: language), season, episode)
    }

    /// «quedan 1 h 40 min» / «1 h 40 min left» (los minutos que faltan, con las horas y minutos de `Vocabulary`).
    static func timeLeft(minutes: Int, language: String) -> String {
        let (h, m) = Vocabulary.hoursAndMinutes(minutes)
        if h > 0 && m > 0 { return String(format: tr("quedan %lld h %lld min", language: language), h, m) }
        if h > 0 { return String(format: tr("quedan %lld h", language: language), h) }
        return String(format: tr("quedan %lld min", language: language), m)
    }

    /// «termina a las 23:21» / «ends at 11:21 PM» (como la TV): la hora (en el formato del idioma de la app) en que acabarías si empiezas ahora.
    static func endsAt(minutesLeft: Int, now: Date = Date(), language: String) -> String {
        let end = Vocabulary.endTime(minutesLeft: minutesLeft, now: now)
        let time = end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: language)))
        return String(format: tr("termina a las %@", language: language), time)
    }

    /// «Película» / «Serie» en el idioma de la app.
    static func kind(_ kind: String, language: String) -> String { tr(kind == "movie" ? "Película" : "Serie", language: language) }
}
