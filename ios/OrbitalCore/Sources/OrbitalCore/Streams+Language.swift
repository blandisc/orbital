import Foundation

/// Cuánto pesa el idioma de una versión con tus preferencias y tu orden de idiomas (Fernando, 3 nov: latino → el original →
/// inglés → castellano). Las mismas reglas que la TV (`streams.language_score`) y los escenarios comunes.
extension Streams {
    /// Cuánto vale el idioma que quieres según qué tan seguro es (`LANG_POINTS` de la TV): lo comprobado, lo que se dice y el
    /// original van arriba; lo que se supone, poco menos; «tal vez», apenas.
    static let languagePoints: [AudioLanguage.Evidence: Double] = [.checked: 340, .name: 300, .site: 300, .original: 300, .unknown: 260, .maybe: 60]
    /// Otro idioma pesa más que arrancar al instante (+1000): una en ruso lista no le gana a una en tu idioma que tarda.
    static let wrongLanguage = -1600.0

    /// Cuánto suma el idioma según qué tan seguro es (`language_score` de la TV). Una dual con tu idioma vale lo mismo que la
    /// que solo trae ese. Con una variante de español elegida (Ajustes, la voz, el título): el doblaje pedido primero, luego el
    /// español que no dice cuál y al final el otro.
    static func languageScore(_ src: Source, _ prefs: Preferences) -> Double {
        let audio = src.audio.isEmpty ? src.languages.map { AudioLanguage($0, .name) } : src.audio
        func points(_ code: String) -> Double? { audio.filter { $0.code == code }.compactMap { languagePoints[$0.evidence] }.max() }
        let ordered = orderScore(audio, src.originalLanguage, prefs)
        guard prefs.audio == "es" else { return max(points(prefs.audio) ?? wrongLanguage, ordered) }
        let wanted = spanishVariants.contains(prefs.spanish) ? prefs.spanish : nil
        var best = wrongLanguage
        for code in spanish {
            guard var value = points(code) else { continue }
            if wanted != nil && code == "es" { value -= 100 }   // español sin saber cuál: después del que pediste, antes que otro idioma
            else if let wanted, code != wanted {
                if prefs.order.contains(code) { continue }   // el otro doblaje está en tu orden: vale lo de su lugar
                value -= 250   // el otro doblaje
            }
            best = max(best, value)
        }
        return max(best, ordered)
    }

    /// Lo que vale un idioma de tu orden (`Preferences.order`: el original, inglés, castellano y tu plan B de Torrentio): debajo
    /// del que quieres y arriba de los demás idiomas, en ese orden. La mejor que arranca ya según tu orden le gana a la de tu
    /// idioma que hay que pedir, y la ficha ofrece pedir esa aparte (FQ1-A, Fernando, 3 nov). Un idioma fuera de tu orden pesa
    /// más que arrancar al instante.
    /// El primero de tu orden después del tuyo: 600 debajo del tuyo (más que lo que baja un nombre que no dice el título, −500:
    /// en tu idioma le sigue ganando, FQ3-A) y a menos de 1400 (arrancar al instante +1000 contra pedirla −400: la que arranca ya
    /// en tu orden le gana a la tuya por pedir, FQ1-A).
    static let orderTop = -300.0
    static func orderScore(_ audio: [AudioLanguage], _ original: String?, _ prefs: Preferences) -> Double {
        var best = wrongLanguage
        for (place, entry) in prefs.order.enumerated() {
            let matching = audio.filter { a in
                if entry == "original" { return a.evidence == .original || (original != nil && a.code == original) }
                return a.code == entry || (entry.hasPrefix("es") && a.code == "es")
            }
            guard let evidence = matching.compactMap({ languagePoints[$0.evidence] }).max() else { continue }
            best = max(best, orderTop - 40 * Double(min(place, 6)) + (evidence - 300))
        }
        return best
    }
}
