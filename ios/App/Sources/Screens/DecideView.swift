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
    @StateObject private var observer: ModelObserver<DecideModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    enum Page: Hashable { case more, lists }
    @State private var path: [Page] = []
    /// El alto de la hoja corta: el de su contenido, medido (sin hueco abajo).
    @State private var quickHeight: CGFloat = DS.Decide.quickHeight
    let open: (TitleRoute) -> Void

    init(pool: [Suggestion], sources: [DecideModel.Source] = [], open: @escaping (TitleRoute) -> Void) {
        _observer = StateObject(wrappedValue: ModelObserver(DecideModel(AppEnvironment.shared.services, pool: pool, sources: sources)))
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
        .presentationDragIndicator(.visible)
        .animation(DS.Motion.base(reduceMotion), value: m.pick?.imdb)
        .task {
            m.warmPosters = { await ImagePipeline.shared.warmPosters($0) }
            if m.pick == nil { await m.quick() }
        }
        .onDisappear { m.stop() }
        #if DEBUG
        .task { if Demo.isOn, let l = Demo.value(after: "-demo-decide-level") { path = l == "3" ? [.more, .lists] : l == "2" ? [.more] : [] } }
        #endif
    }

    // MARK: la hoja corta
    private func root(_ m: DecideModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                header(m)
                proposal(m)
                filterRow(m)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s5).padding(.bottom, DS.Space.s4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in quickHeight = min(h, UIScreen.main.bounds.height * DS.Remote.maxShare) }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// «¿Qué vemos?» con cuántas opciones quedan y, a la derecha, «Todo ⌄» (películas o series), el mismo de Para ti.
    private func header(_ m: DecideModel) -> some View {
        let count = m.count()
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("¿Qué vemos?").recipe(.title)
                Text(verbatim: optionsLine(m, count))
                    .recipe(.footnote).monospacedDigit().contentTransition(.numericText())
                    .accessibilityIdentifier("decide-count")
            }
            Spacer()
            DSKindFilter(kind: Binding(get: { m.kind ?? "" }, set: { m.kind = $0.isEmpty ? nil : $0; Task { await m.apply() } }), menu: true)
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
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { m.select(option) } } label: {
                        PosterView(url: option.poster, title: option.title)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(chosen ? DS.accent : .clear, lineWidth: DS.Decide.chosenStroke))
                            .scaleEffect(chosen ? 1 : DS.Decide.otherScale)
                            .opacity(chosen ? 1 : DS.Decide.otherOpacity)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(verbatim: option.title))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
                ForEach(m.picks.count..<max(m.picks.count, DecideModel.trio), id: \.self) { _ in
                    Color.clear.aspectRatio(DS.Poster.aspect, contentMode: .fit).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.selection, trigger: s.imdb)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: s.title).recipe(.cardTitle).lineLimit(1)
                if !facts.isEmpty { Text(verbatim: facts).recipe(.footnote, color: DS.accent).fontWeight(.semibold).lineLimit(1) }
                if let pitch = pitch(s) { Text(verbatim: pitch).recipe(.footnote, color: DS.textMuted).lineLimit(2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismiss(); open(s.route) }
            // Lado a lado y del mismo tamaño; con letra de accesibilidad, uno debajo del otro.
            let buttonsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s3))
            buttonsLayout {
                Button {
                    dismiss()
                    if s.kind == "series" { open(s.route) } else { Task { await env.play(s) } }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        if s.kind == "series" { Label("Ver la serie", systemImage: "play.fill").lineLimit(1).fixedSize() }
                        Label("Ver", systemImage: "play.fill").lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .dsPrimaryButton().controlSize(.large)
                // Lo que se espera (rara vez: los siguientes ya están listos) se ve en el botón, no encima de los carteles.
                Button { Task { await m.next() } } label: {
                    HStack(spacing: DS.Space.s2) {
                        if m.isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "shuffle") }
                        Text("Barajar").lineLimit(1)
                    }
                    .foregroundStyle(DS.text).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).controlSize(.large).disabled(m.isLoading)
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
            .overlay { ProgressView() }
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
                        Button { Task { await m.relax(item.relax) } } label: { title.lineLimit(1) }.buttonStyle(.glass)
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
        } label: {
            DSCapsuleLabel(title: m.minRating > 0 ? Text(verbatim: String(format: "%.0f+", m.minRating)) : Text("Calificación"), symbol: "star",
                           selected: m.minRating > 0, stretch: true, trailing: "chevron.down")
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
        if let minutes = m.minutes { parts.append("\(minutes) min") }
        if let r = m.imdbRating { parts.append(String(format: "IMDb %.1f", r)) }
        else if let r = s.traktRating { parts.append(String(format: "Trakt %.1f", r)) }
        if let mood = m.mood { parts.append(Strings.tr(moodLabel(mood), language: language)) }
        return parts.joined(separator: " · ")
    }

    /// «Terror + 30 min»: lo puesto, en corto.
    private func activeSummary(_ m: DecideModel) -> String {
        var parts = m.genres.sorted().map(genreName)
        if let mood = m.mood { parts.append(Strings.tr(moodLabel(mood), language: language)) }
        if let k = m.kind { parts.append(kindName(k)) }
        if !m.decades.isEmpty { parts.append(m.decades.sorted(by: >).map { decadeName($0) }.joined(separator: ", ")) }
        if m.minRating > 0 { parts.append(String(format: "%.0f+", m.minRating)) }
        if m.timeChosen || parts.isEmpty { parts.append(timeName(m.time)) }
        return parts.joined(separator: " + ")
    }

    private func relaxName(_ r: DecideModel.Relax, _ m: DecideModel) -> String {
        let tr = { (k: String) in Strings.tr(k, language: language) }
        switch r {
        case .genre(let g): return String(format: tr("Quitar %@"), genreName(g))
        case .mood: return tr("Cualquier ánimo")
        case .kind: return tr("Películas y series")
        case .decades: return tr("Cualquier época")
        case .rating: return tr("Sin mínimo")
        case .time(let t): return String(format: tr("Con %@"), timeName(t))
        case .lists: return tr("De todo lo sugerido")
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

// MARK: - Más filtros
/// «Más filtros»: géneros, época, de qué listas, bien calificada (según IMDb, Trakt o TMDB: basta una) y lo ya visto. Cuenta
/// cuántas quedan mientras eliges; «Ver N» regresa y lo aplica.
struct DecideMoreFilters: View {
    let model: DecideModel
    let openLists: () -> Void
    let done: () -> Void
    @StateObject private var observer: ModelObserver<DecideModel>
    @EnvironmentObject private var env: AppEnvironment

    init(model: DecideModel, openLists: @escaping () -> Void, done: @escaping () -> Void) {
        self.model = model; self.openLists = openLists; self.done = done
        _observer = StateObject(wrappedValue: ModelObserver(model))
    }

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let m = observer.model
        let count = m.count()
        let unknown = count == 0 ? m.unknownCount() : 0
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                PanelGroupTitle(title: "Géneros")
                // Mosaicos con el arte de tus sugerencias de cada género (el `id` con lo elegido: ver `FlowChips`).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                    ForEach(DecideModel.genreChoices, id: \.self) { g in
                        DecideTile(title: Text(verbatim: genreName(g)), image: DecideView.tileImage(genre: g), selected: m.genres.contains(g), height: DS.Decide.genreTile) {
                            if m.genres.contains(g) { m.genres.remove(g) } else { m.genres.insert(g) }
                        }
                    }
                }
                .id(m.genres)   // que se redibuje al elegir (ver `FlowChips`)
                .onChange(of: m.genres) { m.resolveUnknown() }
                PanelGroupTitle(title: "Época")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: DecideModel.decadeChoices.count), spacing: DS.Space.s2) {
                    ForEach(DecideModel.decadeChoices, id: \.self) { d in
                        DecideTile(title: d == 1980 ? Text("Antes") : Text(verbatim: d >= 2000 ? "\(d)s" : "\(d % 100)s"), image: "decide-era-\(d)",
                                   selected: m.decades.contains(d), height: DS.Decide.eraTile, centered: true) {
                            if m.decades.contains(d) { m.decades.remove(d) } else { m.decades.insert(d) }
                        }
                    }
                }
                .id(m.decades)
                .onChange(of: m.decades) { m.resolveUnknown() }
                if !m.sources.isEmpty { lists(m) }
                Toggle(isOn: Binding(get: { m.includeWatched }, set: { m.includeWatched = $0 })) { Text("Incluir lo que ya vi").recipe(.secondary, color: DS.text) }
                    .tint(DS.accent)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            Button { done() } label: {
                Text(count > 0 ? String(format: Strings.tr("Ver %lld", language: language), count)
                     : unknown > 0 ? Strings.tr("Buscando opciones…", language: language) : Strings.tr("Sin opciones con eso", language: language))
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-more-done")
        }
        .navigationTitle(Text("Más filtros")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Limpiar") { Task { await m.clearMoreFilters() } }.disabled(m.moreFilters == 0) } }
        // Al volver (con «Ver», deslizando o con ‹), los carteles ya son de lo elegido.
        .onDisappear { Task { await m.apply() } }
    }

    /// «De dónde»: un renglón con lo elegido (abre «De qué listas») y las usadas hace poco, a un toque.
    @ViewBuilder private func lists(_ m: DecideModel) -> some View {
        let chosen = m.sources.filter { m.sourceIDs.contains($0.id) }
        PanelGroupTitle(title: "De dónde")
        Button(action: openLists) {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(chosen.isEmpty ? Strings.tr("Todo lo sugerido", language: language)
                         : String(format: Strings.tr(chosen.count == 1 ? "%lld lista" : "%lld listas", language: language), chosen.count))
                        .recipe(.secondary, color: DS.text).fontWeight(.semibold)
                    if !chosen.isEmpty { Text(verbatim: chosen.map(\.name).joined(separator: " · ")).recipe(.caption).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: String(format: Strings.tr("de %lld", language: language), m.sources.count)).recipe(.caption)
                Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            }
            .padding(DS.Space.s3)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("decide-lists")
        let recent = m.recentSourceIDs.compactMap { id in m.sources.first { $0.id == id } }.prefix(3)
        if !recent.isEmpty {
            FlowChips {
                PanelChip(title: Text("Todo lo sugerido"), selected: m.sourceIDs.isEmpty) { Task { await m.setSources([]) } }
                ForEach(Array(recent)) { source in
                    PanelChip(title: Text(verbatim: source.name), selected: m.sourceIDs == [source.id]) { Task { await m.setSources([source.id]) } }
                }
            }
            .id(m.sourceIDs)
        }
    }

}

// MARK: - De qué listas
/// Elegir de qué listas sale la propuesta, aunque sean muchas: buscar, por origen (Trakt, Orbital, Sugerencias), las
/// elegidas arriba, las usadas hace poco y todas de la A a la Z. Varias a la vez; «Listo» las aplica.
struct DecideListPicker: View {
    let model: DecideModel
    let done: () -> Void
    @State private var selection: Set<String>
    @State private var query = ""
    @State private var origin: String?
    @EnvironmentObject private var env: AppEnvironment

    init(model: DecideModel, done: @escaping () -> Void) {
        self.model = model; self.done = done
        _selection = State(initialValue: model.sourceIDs)
    }

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let all = model.sources
        let origins = Dictionary(grouping: all, by: \.origin).filter { !$0.key.isEmpty }.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        let matching = all.filter { s in
            (origin == nil || s.origin == origin) && (query.isEmpty || s.name.localizedCaseInsensitiveContains(query))
        }
        let chosen = matching.filter { selection.contains($0.id) }
        let recent = model.recentSourceIDs.compactMap { id in matching.first { $0.id == id && !selection.contains(id) } }
        let rest = matching.filter { s in !selection.contains(s.id) && !recent.contains(where: { $0.id == s.id }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        List {
            if origins.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        PanelChip(title: Text(verbatim: String(format: Strings.tr("Todas · %lld", language: language), all.count)), selected: origin == nil) { origin = nil }
                        ForEach(origins, id: \.0) { name, count in
                            PanelChip(title: Text(verbatim: "\(Strings.tr(name, language: language)) · \(count)"), selected: origin == name) { origin = name }
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: DS.Space.gutter, bottom: 0, trailing: DS.Space.gutter))
            }
            section("Elegidas", chosen)
            section("Usadas hace poco", recent)
            section("Todas, de la A a la Z", rest)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(verbatim: String(format: Strings.tr("Buscar entre tus %lld listas", language: language), all.count)))
        .safeAreaInset(edge: .bottom) {
            Button {
                let ids = selection
                done()
                Task { await model.setSources(ids) }
            } label: {
                Text(selection.isEmpty ? Strings.tr("Listo · todo lo sugerido", language: language)
                     : String(format: Strings.tr(selection.count == 1 ? "Listo · %lld lista" : "Listo · %lld listas", language: language), selection.count))
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-lists-done")
        }
        .navigationTitle(Text("De qué listas")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Todas") { selection = [] }.disabled(selection.isEmpty) } }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ sources: [DecideModel.Source]) -> some View {
        if !sources.isEmpty {
            Section {
                ForEach(sources) { source in
                    DecideListRow(name: source.name, detail: detail(source), posters: model.items(of: source).prefix(2).map(\.poster),
                                  selected: selection.contains(source.id)) {
                        if selection.contains(source.id) { selection.remove(source.id) } else { selection.insert(source.id) }
                    }
                    .listRowBackground(Color.clear)
                }
            } header: { Text(title).recipe(.caption, color: DS.textMuted).fontWeight(.semibold) }
        }
    }

    /// «Trakt · 23 títulos» (sin el número si aún no se abre).
    private func detail(_ s: DecideModel.Source) -> String {
        var parts: [String] = []
        if !s.origin.isEmpty { parts.append(Strings.tr(s.origin, language: language)) }
        if let n = model.itemCount(s) { parts.append(String(format: Strings.tr(n == 1 ? "%lld título" : "%lld títulos", language: language), n)) }
        return parts.joined(separator: " · ")
    }
}
