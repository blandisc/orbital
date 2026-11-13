import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los controles de «Decide por mí» (pulido de DE2, Fernando, 13 nov 2026: «las veo un poco crudas»): un solo renglón debajo
/// de las pestañas, el mismo en las dos, con «Todo · Películas · Series» a la izquierda y los filtros a la derecha como
/// íconos en una pastilla como la del tipo (`DSFilterPill` con `DSFilterIcon`: duración, ánimo, calificación y «Afinar»; en «Una por una» solo los que aplican,
/// calificación y «Afinar»). Lo puesto se dice en una línea debajo («1 h · Ligero · 7+»); al tocarla ofrece quitarlo. Si no
/// hay nada puesto, la línea no existe. Regla en `docs/ios-interfaz.md` § «Una hoja, un renglón de controles».
struct DecideControls: View {
    let model: DecideModel
    /// «Una por una»: el tiempo y el ánimo no aplican al mazo.
    let deck: Bool
    let openMore: () -> Void
    @Environment(AppEnvironment.self) private var env

    private var words: DecideWords { DecideWords(language: env.services.appSettings.uiLanguage) }
    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let m = model
        let parts = words.setParts(m, deck: deck)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // En un renglón; si no cabe (SE, letra grande), el tipo arriba y los filtros debajo, nunca cortados.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s3) { kind(m); Spacer(minLength: 0); filters(m) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { kind(m); filters(m) }
            }
            if !parts.isEmpty { setLine(m, parts).transition(.opacity) }
        }
        .animation(DS.Motion.fade, value: parts)
    }

    private func kind(_ m: DecideModel) -> some View {
        DSKindFilter(kind: Binding(get: { m.kind ?? "" }, set: { m.kind = $0.isEmpty ? nil : $0; Task { await m.apply() } }))
            .fixedSize()
            .accessibilityIdentifier("decide-kind")
    }

    private func filters(_ m: DecideModel) -> some View {
        DSFilterPill {
            if !deck { timeMenu(m); moodMenu(m) }
            ratingMenu(m)
            DSFilterIcon(symbol: "slider.horizontal.3", label: Text("Afinar"), count: m.moreFilters, action: openMore)
                .accessibilityIdentifier("decide-more")
        }
    }

    /// «1 h · Ligero · 7+ · Comedia»: lo puesto, en una línea. Tocarla abre «Quitar …» por filtro y «Quitar filtros».
    private func setLine(_ m: DecideModel, _ parts: [String]) -> some View {
        Menu {
            if !deck, let t = m.shownTime {
                Button(String(format: Strings.tr("Quitar %@", language: language), words.timeName(t)), systemImage: "clock") { Task { await m.chooseTime(nil) } }
            }
            if !deck, let mood = m.mood {
                Button(String(format: Strings.tr("Quitar %@", language: language), Strings.tr(words.moodLabel(mood), language: language)), systemImage: words.moodSymbol(mood)) {
                    m.mood = nil; Task { await m.apply() }
                }
            }
            if m.minRating > 0 || m.minLetterboxd > 0 {
                Button(String(format: Strings.tr("Quitar %@", language: language), words.ratingTitle(m)), systemImage: "star") {
                    m.minRating = 0; m.minLetterboxd = 0; Task { await m.apply() }
                }
            }
            if m.moreFilters > 0 {
                Button(String(format: Strings.tr("Quitar %@", language: language), Strings.tr("Afinar", language: language)), systemImage: "slider.horizontal.3") {
                    Task { await m.clearMoreFilters() }
                }
            }
            Divider()
            Button("Quitar filtros", systemImage: "xmark", role: .destructive) {
                if !deck { m.mood = nil }
                m.minRating = 0; m.minLetterboxd = 0
                Task { if !deck { await m.chooseTime(nil) }; await m.clearMoreFilters() }
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Text(verbatim: parts.joined(separator: " · ")).recipe(.footnote, color: DS.textMuted).lineLimit(1)
                Image(systemName: "chevron.down").font(DS.TextRecipe.badge.font).foregroundStyle(DS.textMuted)
            }
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Filtros puestos"))
        .accessibilityValue(Text(verbatim: parts.joined(separator: ", ")))
        .accessibilityIdentifier("decide-set")
    }

    /// «Cualquier duración» hasta que eliges uno (F3: un filtro que se ve puesto, filtra).
    private func timeMenu(_ m: DecideModel) -> some View {
        DSFilterIcon(symbol: "clock", label: Text(verbatim: words.timeTitle(m)), value: m.shownTime.map { Text(verbatim: words.timeName($0)) }) {
            Button { Task { await m.chooseTime(nil) } } label: {
                optionLabel(Strings.tr("Cualquier duración", language: language), count: m.count(strictTime: false), selected: m.shownTime == nil)
            }
            ForEach(DecideModel.Time.allCases, id: \.self) { t in
                Button { Task { await m.chooseTime(t) } } label: {
                    optionLabel(words.timeName(t), count: m.count(strictTime: true) { $0.time = t }, selected: m.shownTime == t)
                }
            }
        }
        .accessibilityIdentifier("decide-time")
    }

    private func moodMenu(_ m: DecideModel) -> some View {
        DSFilterIcon(symbol: m.mood.map(words.moodSymbol) ?? "face.smiling", label: Text("Ánimo"),
                     value: m.mood.map { Text(LocalizedStringKey(words.moodLabel($0))) }) {
            Button { m.mood = nil; Task { await m.apply() } } label: {
                optionLabel(Strings.tr("Lo que sea", language: language), count: m.count { $0.mood = nil }, selected: m.mood == nil)
            }
            ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                Button { m.mood = mood; Task { await m.apply() } } label: {
                    optionLabel(Strings.tr(words.moodLabel(mood), language: language), count: m.count { $0.mood = mood }, selected: m.mood == mood, symbol: words.moodSymbol(mood))
                }
            }
        }
        .accessibilityIdentifier("decide-mood")
    }

    /// «★ Calificación»: el mínimo (con cuántas quedan) y según qué plataformas (basta con que una llegue).
    private func ratingMenu(_ m: DecideModel) -> some View {
        let set = m.minRating > 0 || m.minLetterboxd > 0
        return DSFilterIcon(symbol: "star", label: Text("Calificación"), value: set ? Text(verbatim: words.ratingTitle(m)) : nil) {
            Section {
                ForEach(DecideModel.ratingSteps, id: \.self) { r in
                    Button { m.minRating = r; Task { await m.apply() } } label: {
                        optionLabel(r == 0 ? Strings.tr("Cualquiera", language: language) : String(format: "%.0f+", r),
                                    count: m.count { $0.minRating = r }, selected: m.minRating == r)
                    }
                }
            }
            Section(Strings.tr("Según (basta una)", language: language)) {
                ForEach(DecideModel.RatingSource.allCases, id: \.self) { source in
                    Toggle(isOn: Binding(get: { m.ratingSources.contains(source) }, set: { on in
                        if on { m.ratingSources.insert(source) } else if m.ratingSources.count > 1 { m.ratingSources.remove(source) }
                        if m.minRating > 0 { Task { await m.apply() } }
                    })) { Text(verbatim: ratingSourceName(source)) }
                    .disabled(source == .tmdb && !env.services.tmdb.configured)
                }
            }
            // Letterboxd, como en el filtro avanzado (Fernando, 2 nov 2026): solo películas. Cuántas quedan se dice cuando ya se
            // sabe el promedio de todas (se pide al elegir un mínimo y se recuerda).
            Section(Strings.tr("Letterboxd · solo películas", language: language)) {
                ForEach(DecideModel.letterboxdSteps, id: \.self) { r in
                    Button { m.minLetterboxd = r; Task { await m.apply() } } label: {
                        let title = r == 0 ? Strings.tr("Cualquiera", language: language) : "\(DecideWords.stars(r))+"
                        if m.letterboxdReady { optionLabel(title, count: m.count { $0.minLetterboxd = r }, selected: m.minLetterboxd == r) }
                        else if m.minLetterboxd == r { Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") } }
                        else { Text(verbatim: title) }
                    }
                }
            }
        }
        .accessibilityIdentifier("decide-rating")
    }

    private func ratingSourceName(_ s: DecideModel.RatingSource) -> String {
        switch s { case .imdb: "IMDb"; case .trakt: "Trakt"; case .tmdb: env.services.tmdb.configured ? "TMDB" : Strings.tr("TMDB (falta su clave)", language: language) }
    }

    /// Un renglón de menú: el nombre, cuántas quedarían y la palomita en el que está puesto.
    private func optionLabel(_ title: String, count: Int, selected: Bool, symbol: String? = nil) -> some View {
        let text = Text(verbatim: "\(title) · \(count)")
        return Group {
            if selected { Label { text } icon: { Image(systemName: "checkmark") } }
            else if let symbol { Label { text } icon: { Image(systemName: symbol) } }
            else { text }
        }
    }
}
