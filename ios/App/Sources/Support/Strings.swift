import Foundation
import OrbitalCore

/// Textos que no pasan por `Text(...)` (SwiftUI ya usa el idioma de la app en los `Text`). Se buscan en el
/// catálogo `Localizable.xcstrings` con el idioma elegido en Ajustes, que puede ser distinto del del sistema.
enum Strings {
    static func tr(_ key: String, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Un texto que el modelo arma en español (un error, un aviso) en el idioma de la app. Los fijos son su clave; los que
    /// llevan datos («No pude marcarlo: %@», «La descarga falló (código %@).») se reconocen por la forma de su clave en el
    /// catálogo y se vuelven a armar con la traducción (y lo de adentro, también traducido si es otro de estos textos).
    static func message(_ text: String, language: String) -> String {
        guard !language.hasPrefix("es") else { return text }
        let direct = tr(text, language: language)
        if direct != text { return direct }
        let range = NSRange(text.startIndex..., in: text)
        for form in forms(language) {
            guard let match = form.regex.firstMatch(in: text, range: range) else { continue }
            let parts = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
            let values: [CVarArg] = zip(form.numbers, parts).map { number, part in number ? (Int(part) ?? 0) as CVarArg : message(part, language: language) }
            return String(format: tr(form.key, language: language), arguments: values)
        }
        return text
    }

    /// Cuántas letras propias necesita una clave con datos para reconocer un mensaje por su forma.
    private static let minFormLetters = 10
    private struct Form { let key: String; let regex: NSRegularExpression; let numbers: [Bool] }
    nonisolated(unsafe) private static var formCache: [String: [Form]] = [:]
    private static let formLock = NSLock()

    /// Las claves con datos del catálogo, de la más larga a la más corta (la más específica gana).
    private static func forms(_ language: String) -> [Form] {
        formLock.lock(); defer { formLock.unlock() }
        if let cached = formCache[language] { return cached }
        var forms: [Form] = []
        if let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language),
           let table = NSDictionary(contentsOf: url) as? [String: String] {
            // Solo frases (avisos, errores): una etiqueta corta como «%@ de %@» o «Ver %@» calzaría con cualquier texto y lo
            // traduciría a medias («Club de Cuervos» → «Club of Cuervos»).
            for key in table.keys where (key.contains("%@") || key.contains("%lld"))
                && key.replacingOccurrences(of: "%lld", with: "").replacingOccurrences(of: "%@", with: "").filter(\.isLetter).count >= minFormLetters {
                var pattern = "^", numbers: [Bool] = [], rest = Substring(key)
                while let hole = rest.range(of: #"%@|%lld"#, options: .regularExpression) {
                    pattern += NSRegularExpression.escapedPattern(for: String(rest[..<hole.lowerBound]))
                    let number = rest[hole] == "%lld"
                    pattern += number ? #"(-?\d+)"# : "(.+?)"
                    numbers.append(number)
                    rest = rest[hole.upperBound...]
                }
                pattern += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) { forms.append(Form(key: key, regex: regex, numbers: numbers)) }
            }
        }
        forms.sort { $0.key.count > $1.key.count }
        formCache[language] = forms
        return forms
    }

    /// El episodio de lo que manda la TV en el idioma de la app («T2 E5» / «S2 E5», «Especial · E1» / «Special · E1»). Con los
    /// números de la consola; si no los manda (versión anterior), a partir de su etiqueta en español.
    static func tvEpisode(season: Int?, episode number: Int?, label: String, language: String) -> String {
        guard let number else { return tvEpisode(label, language: language) }
        if season == 0 { return tr("Especial", language: language) + " · " + episode(season: nil, episode: number, language: language) }
        return episode(season: season, episode: number, language: language)
    }

    /// La etiqueta que manda una consola de antes («T2 · E5», «T2 E5», «Especial · E1»; siempre en español) en el idioma de la app.
    static func tvEpisode(_ label: String, language: String) -> String {
        let text = label as NSString
        let range = NSRange(location: 0, length: text.length)
        if let m = tvEpisodePattern.firstMatch(in: label, range: range), let season = Int(text.substring(with: m.range(at: 1))), let number = Int(text.substring(with: m.range(at: 2))) {
            return episode(season: season, episode: number, language: language) + text.substring(from: m.range.upperBound)
        }
        if let m = tvSpecialPattern.firstMatch(in: label, range: range), let number = Int(text.substring(with: m.range(at: 1))) {
            return tr("Especial", language: language) + " · " + episode(season: nil, episode: number, language: language) + text.substring(from: m.range.upperBound)
        }
        return label
    }
    private static let tvEpisodePattern = try! NSRegularExpression(pattern: #"^T(\d+)\s*·?\s*E(\d+)"#)
    private static let tvSpecialPattern = try! NSRegularExpression(pattern: #"^Especial\s*·\s*E(\d+)"#)

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
