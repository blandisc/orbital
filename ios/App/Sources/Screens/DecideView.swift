import SwiftUI
import OrbitalCore
import OrbitalModels

/// «¿Qué vemos?»: una sola hoja en tres alturas. Corta: la propuesta al instante (con la hora y lo que sigues) y
/// «Barajar». Estirada: tiempo, ánimo, series o películas, géneros. Hasta arriba: de qué lista, época y calificación
/// mínima. La propuesta queda siempre arriba y cambia al tocar «Decide por mí».
struct DecideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var observer: ModelObserver<DecideModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    /// En qué nivel está la hoja (no el detent: el alto de la corta cambia al medirse y no debe cambiar el nivel).
    @State private var stage: Stage = .quick
    enum Stage { case quick, more, precise }
    /// El alto de la hoja corta: el de su contenido, medido (sin hueco abajo).
    @State private var quickHeight: CGFloat = DS.Decide.quickHeight
    @State private var measuredQuick: CGFloat = 0
    let open: (TitleRoute) -> Void

    private var quick: PresentationDetent { .height(quickHeight) }
    static let more = PresentationDetent.fraction(DS.Decide.moreShare)
    private var detent: Binding<PresentationDetent> {
        Binding(get: { stage == .quick ? quick : stage == .more ? Self.more : .large },
                set: { d in stage = d == .large ? .precise : d == Self.more ? .more : .quick })
    }

    init(pool: [Suggestion], sources: [DecideModel.Source] = [], open: @escaping (TitleRoute) -> Void) {
        _observer = StateObject(wrappedValue: ModelObserver(DecideModel(AppEnvironment.shared.services, pool: pool, sources: sources)))
        self.open = open
    }

    var body: some View {
        let m = observer.model
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    header(m).id("top")
                    proposal(m)
                    if stage != .quick { questions(m).transition(.opacity) }
                    if stage == .precise { precision(m).transition(.opacity) }
                    if stage != .quick {
                        // Al final de lo que elegiste (no flotando encima de las opciones).
                        Button { Task { await m.decide(); withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo("top", anchor: .top) } } } label: {
                            HStack { if m.isLoading { ProgressView() }; Text(stage == .precise ? "Encuéntrala" : "Decide por mí") }.frame(maxWidth: .infinity)
                        }
                        .dsPrimaryButton().controlSize(.large).disabled(m.isLoading)
                        .accessibilityIdentifier("decide-go")
                    }
                }
                .padding(DS.Space.s5)
                // La hoja corta mide lo que su contenido (sin hueco abajo).
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if stage == .quick { measuredQuick = h; quickHeight = min(h, UIScreen.main.bounds.height * DS.Remote.maxShare) } }
            }
            // Con letra grande la hoja corta puede no caber: entonces sí se desliza (si no, Ver y Barajar quedaban fuera).
            .scrollDisabled(stage == .quick && measuredQuick <= quickHeight)
        }
        .presentationDetents([quick, Self.more, .large], selection: detent)
        .presentationDragIndicator(.visible)
        .animation(DS.Motion.base(reduceMotion), value: stage)
        .animation(DS.Motion.base(reduceMotion), value: m.pick?.imdb)
        .task { if m.pick == nil { await m.quick() } }
        #if DEBUG
        .task { if Demo.isOn, let l = Demo.value(after: "-demo-decide-level") { stage = l == "3" ? .precise : l == "2" ? .more : .quick } }
        #endif
    }

    // MARK: nivel 1
    private func header(_ m: DecideModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if stage == .precise {
                    Label("Afinemos", systemImage: "sparkles").recipe(.title)
                    Text("Dime con precisión qué quieres: de qué lista, de qué época y qué tan bien calificada.").recipe(.footnote)
                } else {
                    Text("¿Qué vemos?").recipe(.title)
                    Text(stage == .quick ? "Una para ahora · desliza hacia arriba para elegir" : "Elige y toca «Decide por mí»").recipe(.footnote)
                }
            }
            Spacer()
        }
    }

    /// Tres carteles lado a lado (la elegida, resaltada); debajo, su nombre, sus datos y por qué verla; luego Ver, Barajar
    /// (otras tres) y «⋯».
    @ViewBuilder private func proposal(_ m: DecideModel) -> some View {
        if let s = m.pick {
            let facts = why(s, m)
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
            }
            .frame(maxHeight: stage == .quick ? nil : DS.Decide.trioCompactHeight)
            .sensoryFeedback(.selection, trigger: s.imdb)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: s.title).recipe(.cardTitle).lineLimit(1)
                if !facts.isEmpty { Text(verbatim: facts).recipe(.footnote, color: DS.accent).fontWeight(.semibold).lineLimit(1) }
                // Por qué verla: el arranque de su sinopsis.
                if stage == .quick, let pitch = pitch(s) { Text(verbatim: pitch).recipe(.footnote, color: DS.textMuted).lineLimit(2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismiss(); open(s.route) }
            // Lado a lado; con letra de accesibilidad, uno debajo del otro (si no, «Barajar» salía letra por letra).
            let buttonsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s3))
            buttonsLayout {
                Button {
                    dismiss()
                    if s.kind == "series" { open(s.route) } else { Task { await env.play(s) } }
                } label: { Label(s.kind == "series" ? "Ver la serie" : "Ver", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .dsPrimaryButton().controlSize(.large)
                Button { Task { await m.next() } } label: { Label("Barajar", systemImage: "shuffle").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).controlSize(.large).disabled(m.isLoading)
                    .accessibilityIdentifier("decide-shuffle")
                Menu {
                    Button("Hoy no", systemImage: "moon.zzz") { Task { await m.skipToday() } }
                    Button("Ver la ficha", systemImage: "info.circle") { dismiss(); open(s.route) }
                } label: { Image(systemName: "ellipsis") }
                    .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                    .accessibilityLabel(Text("Más"))
            }
        } else if m.exhausted {
            DSNotice(text: "No encontré una con eso: prueba con otro filtro o más tiempo.")
        } else {
            HStack(spacing: DS.Space.s3) {
                ForEach(0..<DecideModel.trio, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill).aspectRatio(DS.Poster.aspect, contentMode: .fit)
                }
            }
            .overlay { ProgressView() }
        }
    }

    /// La primera frase de su sinopsis (o lo que quepa en dos renglones): por qué verla.
    private func pitch(_ s: Suggestion) -> String? {
        let text = s.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let end = text.firstIndex(where: { ".!?".contains($0) }), text.distance(from: text.startIndex, to: end) > DS.Decide.pitchMin {
            return String(text[...end])
        }
        return text
    }

    /// «58 min · IMDb 8.4 · Ligero»: lo que se puede comprobar.
    private func why(_ s: Suggestion, _ m: DecideModel) -> String {
        let language = env.services.appSettings.uiLanguage
        var parts: [String] = []
        if let minutes = m.minutes { parts.append("\(minutes) min") }
        if let r = m.imdbRating { parts.append(String(format: "IMDb %.1f", r)) }
        else if let r = s.traktRating { parts.append(String(format: "Trakt %.1f", r)) }
        if let mood = m.mood { parts.append(Strings.tr(moodLabel(mood), language: language)) }
        return parts.joined(separator: " · ")
    }

    // MARK: nivel 2
    @ViewBuilder private func questions(_ m: DecideModel) -> some View {
        PanelGroupTitle(title: "Tengo")
        FlowChips {
            ForEach(DecideModel.Time.allCases, id: \.self) { t in
                PanelChip(title: timeName(t), selected: m.time == t, font: DS.TextRecipe.body.font) { m.time = t }
            }
        }
        PanelGroupTitle(title: "Quiero algo")
        FlowChips {
            PanelChip(title: Text("Lo que sea"), selected: m.mood == nil, font: DS.TextRecipe.body.font) { m.mood = nil }
            ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                PanelChip(title: moodName(mood), selected: m.mood == mood, font: DS.TextRecipe.body.font, symbol: moodSymbol(mood)) { m.mood = mood }
            }
        }
        PanelGroupTitle(title: "Qué")
        FlowChips {
            PanelChip(title: Text("Todo"), selected: m.kind == nil, font: DS.TextRecipe.body.font) { m.kind = nil }
            PanelChip(title: Text("Series"), selected: m.kind == "series", font: DS.TextRecipe.body.font, symbol: "tv") { m.kind = "series" }
            PanelChip(title: Text("Películas"), selected: m.kind == "movie", font: DS.TextRecipe.body.font, symbol: "film") { m.kind = "movie" }
        }
        PanelGroupTitle(title: "Géneros")
        FlowChips {
            ForEach(DecideModel.genreChoices, id: \.self) { g in
                PanelChip(title: Text(verbatim: genreName(g)), selected: m.genres.contains(g)) {
                    if m.genres.contains(g) { m.genres.remove(g) } else { m.genres.insert(g) }
                }
            }
        }
        if !m.genres.isEmpty { Text("Con géneros elegidos, el ánimo no cuenta.").recipe(.caption) }
        if stage == .more {
            Label("Desliza hasta arriba para más precisión: de qué lista, época y calificación", systemImage: "chevron.compact.up")
                .recipe(.caption, color: DS.textFaint)
        }
    }

    // MARK: nivel 3
    private func precision(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) { precisionGroups(m) }
            .padding(DS.Space.s4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    @ViewBuilder private func precisionGroups(_ m: DecideModel) -> some View {
        if !m.sources.isEmpty {
            PanelGroupTitle(title: "De dónde")
            FlowChips {
                PanelChip(title: Text("De todo lo sugerido"), selected: m.sourceID == nil) { m.sourceID = nil }
                ForEach(m.sources) { source in
                    PanelChip(title: Text(verbatim: source.name), selected: m.sourceID == source.id) { m.sourceID = source.id }
                }
            }
        }
        PanelGroupTitle(title: "Época")
        FlowChips {
            ForEach(DecideModel.decadeChoices, id: \.self) { d in
                PanelChip(title: decadeName(d), selected: m.decades.contains(d)) {
                    if m.decades.contains(d) { m.decades.remove(d) } else { m.decades.insert(d) }
                }
            }
        }
        PanelGroupTitle(title: "Calificación mínima")
        DSSegmented(options: [(DecideModel.RatingService.imdb, LocalizedStringKey("IMDb")), (DecideModel.RatingService.trakt, LocalizedStringKey("Trakt"))],
                    selection: Binding(get: { m.ratingService }, set: { m.ratingService = $0 }))
        FlowChips {
            ForEach(DS.Decide.ratingSteps, id: \.self) { r in
                PanelChip(title: r == 0 ? Text("Cualquiera") : Text(verbatim: String(format: "%.0f+", r)), selected: m.minRating == r) { m.minRating = r }
            }
        }
        Toggle(isOn: Binding(get: { m.includeWatched }, set: { m.includeWatched = $0 })) { Text("Incluir lo que ya vi").recipe(.secondary, color: DS.text) }
            .tint(DS.accent)
    }

    private func decadeName(_ d: Int) -> Text {
        d == 1980 ? Text("Antes de los 90") : Text(verbatim: "\(d)s")
    }

    private func timeName(_ t: DecideModel.Time) -> Text {
        switch t { case .short: Text("30 min"); case .hour: Text("1 h"); case .long: Text("2 h o más") }
    }

    private func moodName(_ m: DecideModel.Mood) -> Text { Text(LocalizedStringKey(moodLabel(m))) }

    private func moodSymbol(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "sun.max"; case .intense: "bolt"; case .think: "lightbulb"; case .together: "heart" }
    }

    private func moodLabel(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "Ligero"; case .intense: "Intenso"; case .think: "Para pensar"; case .together: "En pareja" }
    }
}
