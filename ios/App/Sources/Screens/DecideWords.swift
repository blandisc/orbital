import SwiftUI
import NaturalLanguage
import OrbitalCore
import OrbitalModels

/// Los textos de «Decide por mí» (separados de DecideView por tamaño, 13 nov 2026): nombres de tiempos, ánimos, épocas y
/// filtros, lo que se dice de la propuesta y lo puesto en corto.
@MainActor
struct DecideWords {
    let language: String

    private func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    /// «4 opciones · de «Terror de octubre»» (de dónde salen, si elegiste listas).
    func optionsLine(_ m: DecideModel, _ count: Int) -> String {
        var line = count > 0 ? String(format: tr(count == 1 ? "%lld opción" : "%lld opciones"), count) : tr("Ninguna con estos filtros")
        let lists = m.chosenSourceNames
        if lists.count == 1 { line += " · " + String(format: tr("de «%@»"), lists[0]) }
        else if lists.count > 1 { line += " · " + String(format: tr("de %lld listas"), lists.count) }
        return line
    }

    /// La primera frase de su sinopsis (o lo que quepa en dos renglones): por qué verla.
    func pitch(_ s: Suggestion) -> String? {
        let text = s.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Solo en el idioma de la app: una sinopsis en inglés en la app en español se esconde (los datos de arriba bastan).
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let found = recognizer.dominantLanguage, found.rawValue != language { return nil }
        if let end = text.firstIndex(where: { ".!?".contains($0) }), text.distance(from: text.startIndex, to: end) > DS.Decide.pitchMin {
            return String(text[...end])
        }
        return text
    }

    /// «58 min · IMDb 8.4 · Ligero»: lo que se puede comprobar.
    func why(_ s: Suggestion, _ m: DecideModel) -> String {
        var parts: [String] = []
        // En una serie, lo que dura un capítulo («42 min por episodio», como la TV): se propone la serie, no un capítulo.
        if s.kind == "series" { parts.append(m.minutes.map { String(format: tr("%@ por episodio"), "\($0) min") } ?? tr("Serie")) }
        else if let minutes = m.minutes { parts.append("\(minutes) min") }
        if let r = m.imdbRating { parts.append(String(format: "IMDb %.1f", r)) }
        else if let r = TraktRatings.shown(s.imdb, fallback: s.traktRating) { parts.append("Trakt \(TraktRatings.percent(r))\u{00A0}%") }
        if let mood = m.mood { parts.append(tr(moodLabel(mood))) }
        return parts.joined(separator: " · ")
    }

    /// «Terror + 30 min»: lo puesto, en corto (el tiempo solo si lo elegiste: el de la hora no filtra).
    func activeSummary(_ m: DecideModel) -> String {
        var parts = m.genres.sorted().map { genreName($0, language: language) }
        if let mood = m.mood { parts.append(tr(moodLabel(mood))) }
        if let k = m.kind { parts.append(kindName(k)) }
        if !m.decades.isEmpty { parts.append(m.decades.sorted(by: >).map { decadeName($0) }.joined(separator: ", ")) }
        if m.minRating > 0 { parts.append(String(format: "%.0f+", m.minRating)) }
        if m.minLetterboxd > 0 { parts.append("\(FilterText.number(m.minLetterboxd))★ Letterboxd") }
        if m.fame != .any { parts.append(tr(Self.fameKey(m.fame))) }
        if !m.awards.isEmpty { parts.append(tr("Premios")) }
        if let t = m.shownTime { parts.append(timeName(t)) }
        return parts.joined(separator: " + ")
    }

    /// El nombre de «Fama» como clave de texto (para «Quitar Joyas ocultas»).
    static func fameKey(_ f: AdvancedFilter.Fame) -> String {
        switch f { case .gems: "Joyas ocultas"; case .classics: "Las de siempre"; case .niche: "Para pocos"; case .blockbusters: "Taquilleras"; case .any: "Cualquiera" }
    }

    func relaxName(_ r: DecideModel.Relax, _ m: DecideModel) -> String {
        switch r {
        case .genre(let g): return String(format: tr("Quitar %@"), genreName(g, language: language))
        case .mood: return tr("Cualquier ánimo")
        case .kind: return tr("Películas y series")
        case .decades: return tr("Cualquier época")
        case .rating: return tr("Sin mínimo")
        case .time(let t): return String(format: tr("Con %@"), timeName(t))
        case .lists: return tr("De todo lo sugerido")
        case .letterboxd: return String(format: tr("Quitar %@"), "Letterboxd")
        case .fame: return String(format: tr("Quitar %@"), tr(Self.fameKey(m.fame)))
        case .awards: return String(format: tr("Quitar %@"), tr("Premios"))
        }
    }

    func timeName(_ t: DecideModel.Time) -> String {
        switch t { case .short: tr("30 min"); case .hour: tr("1 h"); case .long: tr("2 h o más") }
    }

    /// La cápsula del tiempo: el que elegiste o «Cualquier duración» (F3: el de la hora no filtra y no se enseña puesto).
    func timeTitle(_ m: DecideModel) -> String { m.shownTime.map(timeName) ?? tr("Cualquier duración") }

    func kindName(_ k: String?) -> String {
        switch k { case "movie": tr("Películas"); case "series": tr("Series"); default: tr("Películas y series") }
    }

    func decadeName(_ d: Int) -> String { d == 1980 ? tr("Antes de los 90") : "\(d)s" }

    func moodSymbol(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "sun.max"; case .intense: "bolt"; case .think: "lightbulb"; case .together: "heart" }
    }

    func moodLabel(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "Ligero"; case .intense: "Intenso"; case .think: "Para pensar"; case .together: "En pareja" }
    }

    /// «7+», «3.5★» o «7+ · 3.5★»; sin mínimo, «Calificación».
    func ratingTitle(_ m: DecideModel) -> String {
        var parts: [String] = []
        if m.minRating > 0 { parts.append(String(format: "%.0f+", m.minRating)) }
        if m.minLetterboxd > 0 { parts.append("\(FilterText.number(m.minLetterboxd))★") }
        return parts.isEmpty ? tr("Calificación") : parts.joined(separator: " · ")
    }

    /// «★★★½»: las estrellas de Letterboxd.
    static func stars(_ value: Double) -> String {
        String(repeating: "★", count: Int(value)) + (value.truncatingRemainder(dividingBy: 1) >= 0.5 ? "½" : "")
    }
}
