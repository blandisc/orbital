import SwiftUI
import OrbitalCore
import OrbitalModels

/// Búsqueda avanzada › Calificación (Fernando, 2 nov 2026; propuesta en docs/producto/propuestas-2026-11-01/calificacion.html):
/// dos opiniones que hablan igual. Arriba, un resumen de lo elegido; debajo, «El público» (TMDB, de 10) y «Los cinéfilos»
/// (Letterboxd, de 5 estrellas, solo películas), cada una con Sin mínimo · Buena · Muy buena · Excelente y su número y
/// «Ajustar el número» para lo fino. Con «Series», los cinéfilos se apagan y dicen por qué.
struct FilterRatingEditor: View {
    let model: AdvancedFilterModel
    let hue: Color
    @State private var fineTMDB = false
    @State private var fineLetterboxd = false

    private var filter: AdvancedFilter { model.filter }
    private func edit(_ change: (inout AdvancedFilter) -> Void) { var f = model.filter; change(&f); model.filter = f }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            summary
            source(title: Text("El público"), scale: Text("de 10"), detail: Text("Millones de votos en TMDB"), mark: AnyView(tmdbMark),
                   value: filter.minRating, presets: RatingLevels.tmdb, prefix: "",
                   range: 1...9, fine: $fineTMDB, enabled: true, id: "tmdb") { v in edit { $0.minRating = v } }
            source(title: Text("Los cinéfilos"), scale: Text("de ★5 · solo películas"), detail: Text("Letterboxd · califican más duro"),
                   mark: AnyView(LetterboxdMark()), value: filter.minLetterboxd, presets: RatingLevels.letterboxd, prefix: "★",
                   range: 0.5...5, fine: $fineLetterboxd,
                   enabled: filter.format != .series, id: "letterboxd") { v in edit { $0.minLetterboxd = v } }
        }
    }

    /// Lo elegido en una línea: «Sin mínimo», «Muy buena · 7.5+ del público», «Excelente · ★4.2+ de los cinéfilos» o, con las
    /// dos, «7+ y ★3.8+».
    private var summary: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(filter.minRating != nil && filter.minLetterboxd != nil ? "Calificación · las dos" : "Calificación").recipe(.caption, color: DS.textMuted)
            summaryLine.recipe(.cardTitle)
            .contentTransition(.numericText())
            .animation(DS.Motion.fade, value: filter.minRating)
            .animation(DS.Motion.fade, value: filter.minLetterboxd)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filter-rating-summary")
    }

    private var summaryLine: Text {
        switch (filter.minRating, filter.minLetterboxd) {
        case (nil, nil): Text("Sin mínimo").foregroundStyle(DS.textMuted)
        case let (t?, nil): line(t, RatingLevels.tmdb, prefix: "", whose: Text("del público"))
        case let (nil, l?): line(l, RatingLevels.letterboxd, prefix: "★", whose: Text("de los cinéfilos"))
        case let (t?, l?): Text("\(Text(verbatim: RatingLevels.short(t) + "+")) y \(Text(verbatim: "★" + RatingLevels.short(l) + "+"))")
        }
    }

    private func line(_ value: Double, _ presets: [Double], prefix: String, whose: Text) -> Text {
        let number = Text(verbatim: prefix + RatingLevels.short(value) + "+")
        guard let word = RatingLevels.word(value, in: presets) else { return Text("\(number) \(whose)") }
        return Text("\(word) \(Text("· \(number) \(whose)").foregroundStyle(DS.textMuted))")
    }

    private var tmdbMark: some View {
        Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.tmdbMark).accessibilityLabel(Text(verbatim: "TMDB"))
    }

    /// Una opinión: su encabezado, los cuatro niveles con su número, un ejemplo y, si lo pides, el deslizador.
    private func source(title: Text, scale: Text, detail: Text, mark: AnyView, value: Double?, presets: [Double], prefix: String,
                        range: ClosedRange<Double>, fine: Binding<Bool>, enabled: Bool, id: String,
                        set: @escaping (Double?) -> Void) -> some View {
        let level = value.flatMap { RatingLevels.level($0, in: presets) }
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                mark
                title.recipe(.labelLarge)
                Spacer()
                scale.recipe(.caption, color: DS.textMuted)
            }
            (enabled ? detail : Text("Letterboxd no califica series")).recipe(.caption, color: DS.textMuted)
            HStack(spacing: DS.Space.s2) {
                chip(Text("Sin"), Text("mínimo"), on: value == nil) { set(nil) }
                    .accessibilityLabel(Text("Sin mínimo")).accessibilityIdentifier("filter-\(id)-none")
                ForEach(presets.indices, id: \.self) { i in
                    // El número del nivel elegido es el tuyo si lo ajustaste («7.8+» en Muy buena).
                    let shown = level == i ? value! : presets[i]
                    chip(RatingLevels.name(i), Text(verbatim: prefix + RatingLevels.short(shown) + "+"), on: level == i) { set(presets[i]) }
                        .accessibilityIdentifier("filter-\(id)-\(i)")
                }
            }
            if fine.wrappedValue, enabled {
                let binding = Binding(get: { value ?? range.lowerBound }, set: { v in set((v * 10).rounded() / 10) })
                Slider(value: binding, in: range, step: 0.1) { title }
                    .tint(hue)
                    .accessibilityIdentifier("filter-\(id)-slider")
            }
            HStack {
                Spacer()
                if enabled {
                    Button { fine.wrappedValue.toggle() } label: {
                        (fine.wrappedValue ? Text("Listo") : Text("Ajustar el número")).recipe(.caption, color: hue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("filter-\(id)-fine")
                }
            }
        }
        .padding(DS.Space.s3)
        .dsCard()
        .overlay(RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous).strokeBorder(value != nil && enabled ? hue : .clear, lineWidth: DS.Stroke.regular))
        .opacity(enabled ? 1 : DS.Opacity.faint)
        .disabled(!enabled)
        .animation(DS.Motion.fade, value: fine.wrappedValue)
        .accessibilityElement(children: .contain)
    }

    /// Un nivel: la palabra arriba y su número abajo (o «Sin / mínimo»).
    private func chip(_ top: Text, _ bottom: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                top.recipe(.label, color: on ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                bottom.recipe(.caption, color: on ? hue : DS.textMuted).monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
            .dsCard(fill: on ? DS.Filter.limeFill : nil)
            .overlay(RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous).strokeBorder(on ? hue : .clear, lineWidth: DS.Stroke.regular))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Qué tan buena, con las mismas palabras para las dos opiniones (Fernando, 2 nov 2026): el público (TMDB, de 10) y los
/// cinéfilos (Letterboxd, de 5 estrellas, que califican más duro). Cada palabra con su número.
enum RatingLevels {
    /// La palabra de cada nivel.
    static func name(_ level: Int) -> Text {
        switch level { case 0: Text("Buena"); case 1: Text("Muy buena"); default: Text("Excelente") }
    }
    static let tmdb: [Double] = [7, 7.5, 8]
    static let letterboxd: [Double] = [3.5, 3.8, 4.2]

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
