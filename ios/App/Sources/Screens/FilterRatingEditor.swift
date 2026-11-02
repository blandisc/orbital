import SwiftUI
import OrbitalCore
import OrbitalModels

/// Búsqueda avanzada › Calificación (Fernando, 2 nov 2026; propuesta en
/// docs/producto/propuestas-2026-11-01/calificacion-deslizador-2.html): dos opiniones, cada una con su deslizador y en su
/// idioma, sin cajas y separadas por una línea fina. Arriba, lo elegido en grande; luego «El público» (TMDB, de 10: una
/// regla del 5 al 9) y «Los cinéfilos» (Letterboxd, de 5 estrellas que se llenan; solo películas). Cada una dice su nivel
/// (Buena, Muy buena, Excelente) y su número. Con «Series», las estrellas se apagan y dicen por qué.
struct FilterRatingEditor: View {
    let model: AdvancedFilterModel
    let hue: Color

    private var filter: AdvancedFilter { model.filter }
    private var tmdb: Binding<Double?> { Binding(get: { model.filter.minRating }, set: { v in edit { $0.minRating = v } }) }
    private var letterboxd: Binding<Double?> { Binding(get: { model.filter.minLetterboxd }, set: { v in edit { $0.minLetterboxd = v } }) }
    private func edit(_ change: (inout AdvancedFilter) -> Void) { var f = model.filter; change(&f); model.filter = f }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            summary
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                header(mark: AnyView(tmdbMark), title: Text("El público"), scale: Text("de 10"), detail: Text("Millones de votos en TMDB"))
                level(filter.minRating, RatingSlider.tmdb, prefix: "", color: hue)
                RatingRulerSlider(value: tmdb, scale: .tmdb, hue: hue, label: Text("El público"))
                    .accessibilityIdentifier("filter-tmdb-slider")
            }
            Divider().overlay(DS.hairline)
            letterboxdSection
        }
    }

    private var letterboxdSection: some View {
        let enabled = filter.format != .series
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            header(mark: AnyView(LetterboxdMark()), title: Text("Los cinéfilos"), scale: Text("de ★5 · solo películas"),
                   detail: enabled ? Text("Letterboxd · califican más duro") : Text("Letterboxd no califica series"))
            level(enabled ? filter.minLetterboxd : nil, RatingSlider.letterboxd, prefix: "★", color: DS.Letterboxd.leaf)
            RatingStarSlider(value: letterboxd, scale: .letterboxd, hue: DS.Letterboxd.leaf, label: Text("Los cinéfilos"))
                .accessibilityIdentifier("filter-letterboxd-slider")
        }
        .opacity(enabled ? 1 : DS.Opacity.faint)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
    }

    /// Lo elegido en grande: «Sin mínimo», «Muy buena · 7.5+ del público», «Excelente · ★4.2+ de los cinéfilos» o, con las
    /// dos, «7+ y ★3.8+».
    private var summary: some View {
        // Sin rótulo propio: el panel ya dice «Lo mínimo que quieres» arriba.
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            summaryLine.recipe(.section).monospacedDigit()
                .contentTransition(.numericText())
                .animation(DS.Motion.fade, value: filter.minRating)
                .animation(DS.Motion.fade, value: filter.minLetterboxd)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filter-rating-summary")
    }

    private var summaryLine: Text {
        let lb = filter.format == .series ? nil : filter.minLetterboxd
        switch (filter.minRating, lb) {
        case (nil, nil): return Text("Sin mínimo").foregroundStyle(DS.textMuted)
        case let (t?, nil): return line(t, RatingSlider.tmdb, prefix: "", whose: Text("del público"))
        case let (nil, l?): return line(l, RatingSlider.letterboxd, prefix: "★", whose: Text("de los cinéfilos"))
        case let (t?, l?):
            let and = Text("y").foregroundStyle(DS.textMuted)
            return Text("\(Text(verbatim: RatingLevels.short(t) + "+")) \(and) \(Text(verbatim: "★" + RatingLevels.short(l) + "+"))")
        }
    }

    private func line(_ value: Double, _ scale: RatingSlider, prefix: String, whose: Text) -> Text {
        let number = Text(verbatim: prefix + RatingLevels.short(value) + "+")
        guard let level = scale.level(value) else { return Text("\(number) \(whose)") }
        return Text("\(RatingLevels.name(level)) \(Text("· \(number) \(whose)").foregroundStyle(DS.textMuted))")
    }

    private var tmdbMark: some View {
        Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.tmdbMark).accessibilityLabel(Text(verbatim: "TMDB"))
    }

    /// El encabezado de una opinión: su marca, quién es, su escala y de dónde sale.
    private func header(mark: AnyView, title: Text, scale: Text, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                mark
                title.recipe(.labelLarge)
                Spacer()
                scale.recipe(.caption, color: DS.textMuted)
            }
            detail.recipe(.caption, color: DS.textMuted)
        }
    }

    /// El nivel en palabra y su número («Muy buena 7.5+»); sin mínimo, en gris.
    private func level(_ value: Double?, _ scale: RatingSlider, prefix: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            if let value {
                (scale.level(value).map(RatingLevels.name) ?? Text("Al menos")).recipe(.cardTitle)
                Text(verbatim: prefix + RatingLevels.short(value) + "+").recipe(.label, color: color).monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Text("Sin mínimo").recipe(.cardTitle, color: DS.textMuted)
            }
        }
        .animation(DS.Motion.fade, value: value)
        .accessibilityHidden(true)
    }
}

/// Qué tan buena, con las mismas palabras para las dos opiniones (Fernando, 2 nov 2026): el público (TMDB, de 10) y los
/// cinéfilos (Letterboxd, de 5 estrellas, que califican más duro). Cada palabra con su número.
enum RatingLevels {
    /// La palabra de cada nivel.
    static func name(_ level: Int) -> Text {
        switch level { case 0: Text("Buena"); case 1: Text("Muy buena"); default: Text("Excelente") }
    }
    static let tmdb = RatingSlider.tmdb.stops, letterboxd = RatingSlider.letterboxd.stops

    /// La palabra del nivel más alto que alcanza el valor (nil por debajo de «Buena»).
    static func level(_ value: Double, in presets: [Double]) -> Int? { presets.lastIndex { value >= $0 - 0.001 } }
    static func word(_ value: Double, in presets: [Double]) -> Text? { level(value, in: presets).map(name) }

    /// Lo elegido en corto, para el mosaico de Calificación: «Muy buena · 7.5+», «Excelente · ★4.2+» o «7+ y ★3.8+».
    static func summary(_ f: AdvancedFilter) -> Text? {
        func one(_ v: Double, _ presets: [Double], _ prefix: String) -> Text {
            let number = Text(verbatim: prefix + short(v) + "+")
            return word(v, in: presets).map { Text("\($0) · \(number)") } ?? number
        }
        switch (f.minRating, f.minLetterboxd) {
        case let (t?, l?): return Text("\(Text(verbatim: short(t) + "+")) y \(Text(verbatim: "★" + short(l) + "+"))")
        case let (t?, nil): return one(t, tmdb, "")
        case let (nil, l?): return one(l, letterboxd, "★")
        default: return nil
        }
    }

    /// «7», «7.5», «3.8»: sin decimal si es entero.
    static func short(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
