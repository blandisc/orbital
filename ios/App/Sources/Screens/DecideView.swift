import SwiftUI
import OrbitalCore
import OrbitalModels

/// «¿Qué vemos?»: una sola hoja en tres alturas. Corta: la propuesta al instante (con la hora y lo que sigues) y
/// «Barajar». Estirada: tiempo, ánimo, series o películas, géneros. Hasta arriba: de qué lista, época y calificación
/// mínima. La propuesta queda siempre arriba y cambia al tocar «Decide por mí».
struct DecideView: View {
    @StateObject private var observer: ModelObserver<DecideModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var level: PresentationDetent = Self.quick
    let open: (TitleRoute) -> Void

    static let quick = PresentationDetent.height(DS.Decide.quickHeight)
    static let more = PresentationDetent.fraction(DS.Decide.moreShare)

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
                    if level != Self.quick { questions(m).transition(.opacity) }
                    if level == .large { precision(m).transition(.opacity) }
                }
                .padding(DS.Space.s5)
                .padding(.bottom, level == Self.quick ? 0 : DS.Space.s14)
            }
            .scrollDisabled(level == Self.quick)
            .safeAreaInset(edge: .bottom) {
                if level != Self.quick {
                    Button { Task { await m.decide(); withAnimation(DS.Motion.base(false)) { proxy.scrollTo("top", anchor: .top) } } } label: {
                        HStack { if m.isLoading { ProgressView() }; Text("Decide por mí") }.frame(maxWidth: .infinity)
                    }
                    .dsPrimaryButton().controlSize(.large).disabled(m.isLoading)
                    .padding(.horizontal, DS.Space.s5).padding(.bottom, DS.Space.s2)
                    .accessibilityIdentifier("decide-go")
                }
            }
        }
        .presentationDetents([Self.quick, Self.more, .large], selection: $level)
        .presentationDragIndicator(.visible)
        .animation(DS.Motion.base(false), value: level)
        .animation(DS.Motion.base(false), value: m.pick?.imdb)
        .task { if m.pick == nil { await m.quick() } }
        #if DEBUG
        .task { if Demo.isOn, let l = Demo.value(after: "-demo-decide-level") { level = l == "3" ? .large : l == "2" ? Self.more : Self.quick } }
        #endif
    }

    // MARK: nivel 1
    private func header(_ m: DecideModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("¿Qué vemos?").recipe(.title)
                Text(level == Self.quick ? "Una para ahora · desliza hacia arriba para elegir" : "Elige y toca «Decide por mí»").recipe(.footnote)
            }
            Spacer()
        }
    }

    @ViewBuilder private func proposal(_ m: DecideModel) -> some View {
        if let s = m.pick {
            let facts = why(s, m)
            CoverCard(art: s.wide, logo: s.logo, title: s.title, why: facts.isEmpty ? Text(badgeKey(s.reason)) : Text(verbatim: facts),
                      detail: facts.isEmpty ? nil : Text(badgeKey(s.reason)))
                .frame(height: DS.Decide.cardHeight)
                .onTapGesture { dismiss(); open(s.route) }
            HStack(spacing: DS.Space.s3) {
                Button {
                    dismiss()
                    if s.kind == "series" { open(s.route) } else { Task { await env.play(s) } }
                } label: { Label(s.kind == "series" ? "Ver la serie" : "Ver", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .dsPrimaryButton().controlSize(.large)
                Button { Task { await m.next() } } label: { Label("Barajar", systemImage: "shuffle").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).controlSize(.large).disabled(m.isLoading)
                    .accessibilityIdentifier("decide-shuffle")
            }
            Button("Hoy no") { Task { await m.skipToday() } }
                .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless).foregroundStyle(DS.textMuted)
        } else if m.exhausted {
            DSNotice(text: "No encontré una con eso: prueba con otro filtro o más tiempo.")
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).fill(DS.fill)
                .frame(height: DS.Decide.cardHeight)
                .overlay { ProgressView() }
        }
    }

    /// «58 min · terminas 23:15 · IMDb 8.4 · Ligero»: lo que se puede comprobar.
    private func why(_ s: Suggestion, _ m: DecideModel) -> String {
        let language = env.services.appSettings.uiLanguage
        var parts: [String] = []
        if let minutes = m.minutes {
            parts.append("\(minutes) min")
            parts.append(Strings.endsAt(minutesLeft: minutes, now: env.services.now(), language: language))
        }
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
        if level == Self.more {
            Label("Desliza hasta arriba para más precisión: de qué lista, época y calificación", systemImage: "chevron.compact.up")
                .recipe(.caption, color: DS.textFaint)
        }
    }

    // MARK: nivel 3
    @ViewBuilder private func precision(_ m: DecideModel) -> some View {
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
