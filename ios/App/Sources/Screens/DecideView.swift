import SwiftUI
import NaturalLanguage
import OrbitalCore
import OrbitalModels

/// «¿Qué vemos?»: dos niveles y un solo verbo («Barajar»). La hoja corta: tres carteles con su porqué, «Ver» y «Barajar», y
/// debajo una fila de filtros que se aplican al tocarlos (tiempo, ánimo, películas o series) con cuántas opciones quedan.
/// «Más filtros» es su propia página (géneros, época, de qué listas, bien calificada en IMDb, Trakt o TMDB, lo ya visto), y
/// de ahí «De qué listas», que aguanta muchas (buscar, por origen, las usadas hace poco). Si nada cumple, qué quitar.
struct DecideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var observer: ModelObserver<DecideModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    enum Page: Hashable { case more, lists }
    @State private var path: [Page] = []
    /// El alto de la hoja corta: el de su contenido, medido (sin hueco abajo).
    @State private var quickHeight: CGFloat = DS.Decide.quickHeight
    /// Si la elegida es una serie, el capítulo con que empieza «Ver» (el que vas o el primero), para decirlo en el botón.
    @State private var seriesStart: AppEnvironment.SeriesStart?
    let open: (TitleRoute) -> Void

    init(pool: [Suggestion], sources: [DecideModel.Source] = [], open: @escaping (TitleRoute) -> Void) {
        _observer = State(wrappedValue: ModelObserver(DecideModel(AppEnvironment.shared.services, pool: pool, sources: sources)))
        self.open = open
    }

    private var language: String { env.services.appSettings.uiLanguage }

    /// La imagen del mosaico de un género (en `Assets.xcassets/Decide`).
    static func tileImage(genre: String) -> String { "decide-genre-" + genre.replacingOccurrences(of: "-", with: "") }

    var body: some View {
        let m = observer.model
        NavigationStack(path: $path) {
            root(m)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .more: DecideMoreFilters(model: m, openLists: { path.append(.lists) }, done: { path.removeAll() })
                    case .lists: DecideListPicker(model: m, done: { path.removeLast() })
                    }
                }
        }
        .presentationDetents(path.isEmpty ? [.height(quickHeight)] : [.large])
        .fittedFormSizing(idealHeight: path.isEmpty ? quickHeight : WindowMetrics.size.height * DS.Sheet.maxShare)
        .presentationDragIndicator(.visible)
        .animation(DS.Motion.base(reduceMotion), value: m.pick?.imdb)
        .task {
            m.warmPosters = { await ImagePipeline.shared.warmPosters($0) }
            if m.pick == nil { await m.quick() }
        }
        .onDisappear { m.stop() }
        .task(id: m.pick?.imdb) {
            guard let s = m.pick, s.kind == "series" else { return seriesStart = nil }
            seriesStart = await env.seriesStart(s)
        }
        #if DEBUG
        .task { if Demo.isOn, let l = Demo.value(after: "-demo-decide-level") { path = l == "3" ? [.more, .lists] : l == "2" ? [.more] : [] } }
        #endif
    }

    // MARK: la hoja corta
    private func root(_ m: DecideModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                header(m)
                proposal(m)
                filterRow(m)
            }
            .dsSheetContent()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in quickHeight = min(h, WindowMetrics.size.height * DS.Sheet.maxShare) }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// «¿Qué vemos?» con cuántas opciones quedan y, a la derecha, «Todo ⌄» (películas o series), el mismo de Para ti.
    private func header(_ m: DecideModel) -> some View {
        let count = m.count()
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                DSSheetHeader(title: Text("Decide por mí"))
                Text(verbatim: optionsLine(m, count))
                    .recipe(.footnote).monospacedDigit().contentTransition(.numericText())
                    .accessibilityIdentifier("decide-count")
            }
            // Las mismas pestañas de toda la app, debajo del título (antes un menú junto a él).
            DSKindFilter(kind: Binding(get: { m.kind ?? "" }, set: { m.kind = $0.isEmpty ? nil : $0; Task { await m.apply() } }))
                .accessibilityIdentifier("decide-kind")
        }
    }

    /// «4 opciones · de «Terror de octubre»» (de dónde salen, si elegiste listas).
    private func optionsLine(_ m: DecideModel, _ count: Int) -> String {
        var line = count > 0 ? String(format: Strings.tr(count == 1 ? "%lld opción" : "%lld opciones", language: language), count)
                             : Strings.tr("Ninguna con estos filtros", language: language)
        let lists = m.chosenSourceNames
        if lists.count == 1 { line += " · " + String(format: Strings.tr("de «%@»", language: language), lists[0]) }
        else if lists.count > 1 { line += " · " + String(format: Strings.tr("de %lld listas", language: language), lists.count) }
        return line
    }

    /// Tres carteles lado a lado (la elegida, resaltada); debajo, su nombre, sus datos y por qué verla; luego Ver, Barajar y «⋯».
    @ViewBuilder private func proposal(_ m: DecideModel) -> some View {
        if let s = m.pick {
            let facts = why(s, m)
            // Siempre tres lugares (aunque queden una o dos): un solo cartel ya no ocupa todo el ancho ni empuja los filtros.
            HStack(spacing: DS.Space.s3) {
                ForEach(m.picks) { option in
                    let chosen = option.imdb == s.imdb
                    // Tocar otro cartel lo elige; tocar el elegido abre su ficha (la de la serie o la película).
                    Button { if chosen { dismiss(); open(option.route) } else { withAnimation(DS.Motion.base(reduceMotion)) { m.select(option) } } } label: {
                        PosterView(url: option.poster, title: option.title)
                            .dsSelectionRing(chosen, radius: DS.Radius.md)
                            .scaleEffect(chosen ? 1 : DS.Decide.otherScale)
                            .opacity(chosen ? 1 : DS.Opacity.dimmed)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(verbatim: option.title))
                    .accessibilityHint(chosen ? Text("Abre la ficha") : Text(verbatim: ""))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier(chosen ? "decide-chosen" : "decide-option")
                }
                ForEach(m.picks.count..<max(m.picks.count, DecideModel.trio), id: \.self) { _ in
                    Color.clear.aspectRatio(DS.Poster.aspect, contentMode: .fit).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
            }
            .dsFeedback(.selection, trigger: s.imdb)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: s.title).recipe(.cardTitle).lineLimit(1)
                if !facts.isEmpty { Text(verbatim: facts).recipe(.label, color: DS.accent).lineLimit(1) }
                if let pitch = pitch(s) { Text(verbatim: pitch).recipe(.footnote, color: DS.textMuted).lineLimit(2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismiss(); open(s.route) }
            // Lado a lado y del mismo tamaño; con letra de accesibilidad, uno debajo del otro.
            let buttonsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s3))
            buttonsLayout {
                // Ver ahora: la película, o en una serie el capítulo en que vas (el primero si no la has empezado). La ficha,
                // tocando el cartel o el nombre.
                let start = seriesStart?.metaID == s.imdb ? seriesStart : nil
                Button {
                    dismiss()
                    Task { await env.play(s, from: start) }
                } label: {
                    Group {
                        // Una serie se propone completa, no un capítulo (Fernando, 2 nov 2026): «Ver la serie» o «Continuar la
                        // serie», y arranca donde vas (el primero si no la has empezado).
                        if s.kind == "series" {
                            Label { start?.isResume == true ? Text("Continuar la serie") : Text("Ver la serie") } icon: { Image(systemName: "play.fill") }
                        } else {
                            Label("Ver", systemImage: "play.fill")
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                }
                .dsPrimaryButton().controlSize(.large)
                .accessibilityIdentifier("decide-watch")
                // Lo que se espera (rara vez: los siguientes ya están listos) se ve en el botón, no encima de los carteles.
                Button { Task { await m.next() } } label: {
                    HStack(spacing: DS.Space.s2) {
                        if m.isLoading {
                            ProgressView().controlSize(.small)   // ds-exception: la ruedita va dentro del botón que la pidió
                        } else { Image(systemName: "shuffle") }
                        Text("Barajar").lineLimit(1)
                    }
                    .foregroundStyle(DS.text).frame(maxWidth: .infinity)
                }
                .dsGlassButton().controlSize(.large).disabled(m.isLoading)
                .accessibilityIdentifier("decide-shuffle")
                DSMoreMenu {
                    Button("No me interesa", systemImage: "hand.thumbsdown", role: .destructive) { Task { await m.notInterested() } }
                    Button("Hoy no", systemImage: "moon.zzz") { Task { await m.skipToday() } }
                    Button("Ver la ficha", systemImage: "info.circle") { dismiss(); open(s.route) }
                }
            }
        } else if m.exhausted || (m.picks.isEmpty && !m.isLoading && m.activeFilters > 0) {
            nothing(m)
        } else {
            HStack(spacing: DS.Space.s3) {
                ForEach(0..<DecideModel.trio, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill).aspectRatio(DS.Poster.aspect, contentMode: .fit)
                }
            }
            .overlay { DSLoadingState() }
        }
    }

    /// Nada cumple: con qué, y los dos cambios que más abren («Quitar Terror · 6», «Con 1 h · 3»).
    private func nothing(_ m: DecideModel) -> some View {
        let relax = m.relaxations()
        return VStack(spacing: DS.Space.s3) {
            Image(systemName: "dice").font(DS.TextRecipe.title.font).foregroundStyle(DS.textMuted)
            Text(verbatim: String(format: Strings.tr("Nada con %@", language: language), activeSummary(m))).recipe(.cardTitle).multilineTextAlignment(.center)
            Text("Prueba quitando un filtro.").recipe(.footnote).multilineTextAlignment(.center)
            HStack(spacing: DS.Space.s2) {
                ForEach(Array(relax.enumerated()), id: \.offset) { index, item in
                    let title = Text(verbatim: "\(relaxName(item.relax, m)) · \(item.count)")
                    if index == 0 {
                        Button { Task { await m.relax(item.relax) } } label: { title.lineLimit(1) }.dsPrimaryButton()
                    } else {
                        Button { Task { await m.relax(item.relax) } } label: { title.lineLimit(1) }.dsGlassButton()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s5)
        .accessibilityIdentifier("decide-nothing")
    }

    // MARK: los filtros (se aplican al tocarlos)
    /// Cuatro cápsulas parejas (las mismas «Todo ⌄» de toda la app), en dos renglones: siempre caben y quedan alineadas.
    private func filterRow(_ m: DecideModel) -> some View {
        Grid(horizontalSpacing: DS.Space.s2, verticalSpacing: DS.Space.s2) {
            GridRow {
                Menu {
                    ForEach(DecideModel.Time.allCases, id: \.self) { t in
                        Button { m.time = t; m.timeChosen = true; Task { await m.apply() } } label: {
                            optionLabel(timeName(t), count: m.count(strictTime: true) { $0.time = t }, selected: m.time == t)
                        }
                    }
                } label: { DSCapsuleLabel(title: Text(verbatim: timeName(m.time)), symbol: "clock", selected: m.timeChosen, stretch: true, trailing: "chevron.down") }
                .accessibilityIdentifier("decide-time")
                Menu {
                    Button { m.mood = nil; Task { await m.apply() } } label: {
                        optionLabel(Strings.tr("Lo que sea", language: language), count: m.count { $0.mood = nil }, selected: m.mood == nil)
                    }
                    ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                        Button { m.mood = mood; Task { await m.apply() } } label: {
                            optionLabel(Strings.tr(moodLabel(mood), language: language), count: m.count { $0.mood = mood }, selected: m.mood == mood, symbol: moodSymbol(mood))
                        }
                    }
                } label: {
                    DSCapsuleLabel(title: m.mood.map { Text(LocalizedStringKey(moodLabel($0))) } ?? Text("Ánimo"), symbol: m.mood.map(moodSymbol) ?? "face.smiling",
                                   selected: m.mood != nil, stretch: true, trailing: "chevron.down")
                }
                .accessibilityIdentifier("decide-mood")
            }
            GridRow {
                ratingMenu(m)
                Button { path.append(.more) } label: {
                    DSCapsuleLabel(title: m.moreFilters > 0 ? Text("Más filtros · \(m.moreFilters)") : Text("Más filtros"), symbol: "slider.horizontal.3",
                                   selected: m.moreFilters > 0, stretch: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("decide-more")
            }
        }
    }

    /// «★ Calificación»: el mínimo (con cuántas quedan) y según qué plataformas (basta con que una llegue).
    private func ratingMenu(_ m: DecideModel) -> some View {
        Menu {
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
                        let title = r == 0 ? Strings.tr("Cualquiera", language: language) : "\(Self.stars(r))+"
                        if m.letterboxdReady { optionLabel(title, count: m.count { $0.minLetterboxd = r }, selected: m.minLetterboxd == r) }
                        else if m.minLetterboxd == r { Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") } }
                        else { Text(verbatim: title) }
                    }
                }
            }
        } label: {
            DSCapsuleLabel(title: Text(verbatim: ratingTitle(m)), symbol: "star",
                           selected: m.minRating > 0 || m.minLetterboxd > 0, stretch: true, trailing: "chevron.down")
        }
        .accessibilityIdentifier("decide-rating")
    }

    /// «7+», «3.5★» o «7+ · 3.5★»; sin mínimo, «Calificación».
    private func ratingTitle(_ m: DecideModel) -> String {
        var parts: [String] = []
        if m.minRating > 0 { parts.append(String(format: "%.0f+", m.minRating)) }
        if m.minLetterboxd > 0 { parts.append("\(FilterText.number(m.minLetterboxd))★") }
        return parts.isEmpty ? Strings.tr("Calificación", language: language) : parts.joined(separator: " · ")
    }

    /// «★★★½»: las estrellas de Letterboxd.
    static func stars(_ value: Double) -> String {
        String(repeating: "★", count: Int(value)) + (value.truncatingRemainder(dividingBy: 1) >= 0.5 ? "½" : "")
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

    // MARK: textos
    /// La primera frase de su sinopsis (o lo que quepa en dos renglones): por qué verla.
    private func pitch(_ s: Suggestion) -> String? {
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
    private func why(_ s: Suggestion, _ m: DecideModel) -> String {
        var parts: [String] = []
        // En una serie, lo que dura un capítulo («42 min por episodio», como la TV): se propone la serie, no un capítulo.
        if s.kind == "series" { parts.append(m.minutes.map { String(format: Strings.tr("%@ por episodio", language: language), "\($0) min") } ?? Strings.tr("Serie", language: language)) }
        else if let minutes = m.minutes { parts.append("\(minutes) min") }
        if let r = m.imdbRating { parts.append(String(format: "IMDb %.1f", r)) }
        else if let r = s.traktRating { parts.append(String(format: "Trakt %.1f", r)) }
        if let mood = m.mood { parts.append(Strings.tr(moodLabel(mood), language: language)) }
        return parts.joined(separator: " · ")
    }

    /// «Terror + 30 min»: lo puesto, en corto.
    private func activeSummary(_ m: DecideModel) -> String {
        var parts = m.genres.sorted().map { genreName($0, language: language) }
        if let mood = m.mood { parts.append(Strings.tr(moodLabel(mood), language: language)) }
        if let k = m.kind { parts.append(kindName(k)) }
        if !m.decades.isEmpty { parts.append(m.decades.sorted(by: >).map { decadeName($0) }.joined(separator: ", ")) }
        if m.minRating > 0 { parts.append(String(format: "%.0f+", m.minRating)) }
        if m.minLetterboxd > 0 { parts.append("\(FilterText.number(m.minLetterboxd))★ Letterboxd") }
        if m.fame != .any { parts.append(Strings.tr(Self.fameKey(m.fame), language: language)) }
        if !m.awards.isEmpty { parts.append(Strings.tr("Premios", language: language)) }
        if m.timeChosen || parts.isEmpty { parts.append(timeName(m.time)) }
        return parts.joined(separator: " + ")
    }

    /// El nombre de «Qué tan conocida» como clave de texto (para «Quitar Joyas ocultas»).
    static func fameKey(_ f: AdvancedFilter.Fame) -> String {
        switch f { case .gems: "Joyas ocultas"; case .classics: "Las de siempre"; case .niche: "Para pocos"; case .blockbusters: "Taquilleras"; case .any: "Cualquiera" }
    }

    private func relaxName(_ r: DecideModel.Relax, _ m: DecideModel) -> String {
        let tr = { (k: String) in Strings.tr(k, language: language) }
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

    private func timeName(_ t: DecideModel.Time) -> String {
        switch t { case .short: Strings.tr("30 min", language: language); case .hour: Strings.tr("1 h", language: language); case .long: Strings.tr("2 h o más", language: language) }
    }

    private func kindName(_ k: String?) -> String {
        switch k { case "movie": Strings.tr("Películas", language: language); case "series": Strings.tr("Series", language: language); default: Strings.tr("Películas y series", language: language) }
    }

    private func decadeName(_ d: Int) -> String { d == 1980 ? Strings.tr("Antes de los 90", language: language) : "\(d)s" }

    private func moodSymbol(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "sun.max"; case .intense: "bolt"; case .think: "lightbulb"; case .together: "heart" }
    }

    private func moodLabel(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "Ligero"; case .intense: "Intenso"; case .think: "Para pensar"; case .together: "En pareja" }
    }
}
