import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Decide por mí»: una sola puerta con dos maneras (DE2, 13 nov 2026), como la TV: «Tres que caben» (tres carteles con su
/// porqué, «Ver» y «Barajar») y «Una por una» (el mazo). Debajo, filtros que se aplican al tocarlos (tiempo, ánimo, películas
/// o series) con cuántas opciones quedan; los dos comparten los de «Afinar». «Afinar» es su propia página (géneros, época, de qué listas, bien calificada en IMDb, Trakt o TMDB, lo ya visto), y
/// de ahí «De qué listas», que aguanta muchas (buscar, por origen, las usadas hace poco). Si nada cumple, dice por qué: sin
/// conexión (con «Reintentar»), sin sugerencias, o qué filtro quitar.
struct DecideView: View {
    @Environment(\.titleName) var titleName
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var observer: ModelObserver<DecideModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    enum Page: Hashable { case more, lists }
    @State private var path: [Page] = []
    /// «Tres que caben» o «Una por una» (el mazo).
    @State private var mode: DecideModel.Mode = .trio
    /// El alto de la hoja corta: el de su contenido, medido (sin hueco abajo).
    @State private var quickHeight: CGFloat = DS.Decide.quickHeight
    /// El contenido no cabe en la hoja corta (letra grande): se abre completa y se desliza (F6).
    @State private var overflows = false
    /// Si la elegida es una serie, el capítulo con que empieza «Ver» (el que vas o el primero), para decirlo en el botón.
    @State private var seriesStart: AppEnvironment.SeriesStart?
    let open: (TitleRoute) -> Void
    /// «Reintentar» sin red: lo que se sugiere, pedido otra vez por quien abrió la hoja.
    var reload: (() async -> (pool: [Suggestion], sources: [DecideModel.Source]))?

    init(pool: [Suggestion], sources: [DecideModel.Source] = [], reload: (() async -> (pool: [Suggestion], sources: [DecideModel.Source]))? = nil,
         open: @escaping (TitleRoute) -> Void) {
        _observer = State(wrappedValue: ModelObserver(DecideModel(AppEnvironment.shared.services, pool: pool, sources: sources)))
        self.reload = reload
        self.open = open
    }

    private var words: DecideWords { DecideWords(language: env.services.appSettings.uiLanguage) }
    private var language: String { env.services.appSettings.uiLanguage }

    /// La imagen del mosaico de un género (en `Assets.xcassets/Decide`).
    static func tileImage(genre: String) -> String { "decide-genre-" + genre.replacingOccurrences(of: "-", with: "") }

    var body: some View {
        let m = observer.model
        NavigationStack(path: $path) {
            Group { if mode == .deck { deckRoot(m) } else { root(m) } }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .more: DecideMoreFilters(model: m, openLists: { path.append(.lists) }, done: { path.removeAll() })
                    case .lists: DecideListPicker(model: m, done: { path.removeLast() })
                    }
                }
        }
        .presentationDetents(path.isEmpty && !overflows && mode == .trio ? [.height(quickHeight)] : [.large])
        .fittedFormSizing(idealHeight: path.isEmpty && mode == .trio ? quickHeight :WindowMetrics.size.height * DS.Sheet.maxShare)
        .presentationDragIndicator(.visible)
        .animation(DS.Motion.base(reduceMotion), value: m.pick?.imdb)
        // «No me interesa · Deshacer» dentro de la hoja (la hoja tapa la raíz, que es donde van los avisos).
        // En el mazo los avisos van sobre sus botones (los pone él).
        .overlay(alignment: .bottom) { if mode == .trio { BannerView().padding(.bottom, DS.Space.s2) } }
        .animation(DS.Motion.enter(reduceMotion), value: env.notices.current?.serial)
        .onAppear { env.ui.coverShowsNotices = true }
        .onDisappear { env.ui.coverShowsNotices = false }
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
        .task { if Demo.isOn, Demo.value(after: "-demo-decide-tab") == "deck" || Demo.open == "match" { mode = .deck } }
        #endif
    }

    // MARK: «Una por una»
    /// El mazo con los mismos filtros (DE2): el tipo arriba, la calificación y «Afinar» debajo; el tiempo y el ánimo son de
    /// «Tres que caben». Al cambiar un filtro, el mazo se vuelve a barajar con lo que queda.
    private func deckRoot(_ m: DecideModel) -> some View {
        let pool = m.deckPool()
        return VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            header(m)
            Grid(horizontalSpacing: DS.Space.s2, verticalSpacing: DS.Space.s2) {
                if typeSize.isAccessibilitySize { GridRow { ratingMenu(m) }; GridRow { moreButton(m) } }
                else { GridRow { ratingMenu(m); moreButton(m) } }
            }
            MatchDeckScreen(pool: pool, poolKey: m.deckKey, filtered: m.moreFilters > 0 || m.kind != nil || m.minRating > 0 || m.minLetterboxd > 0,
                            reload: reload.map { load in { let fresh = await load(); await m.retry(pool: fresh.pool, sources: fresh.sources); return m.deckPool() } },
                            onOpenTitle: { dismiss(); open($0) },
                            onPlay: { route in
                                // Una película suena ya; una serie abre su ficha (un episodio suelto casi nunca es el bueno).
                                dismiss()
                                if let s = pool.first(where: { $0.imdb == route.metaID }), s.kind == "movie" { Task { await env.play(s) } } else { open(route) }
                            })
        }
        .dsSheetContent()
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                let most = WindowMetrics.size.height * DS.Sheet.maxShare
                quickHeight = min(h, most)
                overflows = h > most
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// «Decide por mí» con cuántas opciones quedan y ✕; debajo, las dos maneras y «Todo · Películas · Series», el mismo de
    /// toda la app.
    private func header(_ m: DecideModel) -> some View {
        let count = mode == .deck ? m.deckPool().count : m.count()
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                DSSheetHeader(title: Text("Decide por mí")) {
                    DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { dismiss() }
                        .accessibilityIdentifier("decide-close")
                }
                Text(verbatim: words.optionsLine(m, count))
                    .recipe(.footnote).monospacedDigit().contentTransition(.numericText())
                    .accessibilityIdentifier("decide-count")
            }
            DSTextTabs(options: [.init(id: DecideModel.Mode.trio, title: Text("Tres que caben"), symbol: DS.Symbol.decideTrio),
                                 .init(id: .deck, title: Text("Una por una"), symbol: DS.Symbol.decideDeck)],
                       selection: $mode.animation(DS.Motion.base(reduceMotion)))
                .accessibilityIdentifier("decide-mode")
            DSKindFilter(kind: Binding(get: { m.kind ?? "" }, set: { m.kind = $0.isEmpty ? nil : $0; Task { await m.apply() } }))
                .accessibilityIdentifier("decide-kind")
        }
    }

    /// Tres carteles lado a lado (la elegida, resaltada); debajo, su nombre, sus datos y por qué verla; luego Ver, Barajar y «⋯».
    @ViewBuilder private func proposal(_ m: DecideModel) -> some View {
        if let s = m.pick {
            let facts = words.why(s, m)
            // Cada cartel mide un tercio aunque queden uno o dos, centrados y sin huecos (F4).
            DecideTrioLayout {
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
                    .accessibilityLabel(Text(verbatim: option.title))
                    .accessibilityHint(chosen ? Text("Abre la ficha") : Text(verbatim: ""))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier(chosen ? "decide-chosen" : "decide-option")
                }
            }
            .dsFeedback(.selection, trigger: s.imdb)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: titleName(s.title, id: s.imdb, kind: s.kind)).recipe(.cardTitle).lineLimit(1)
                if !facts.isEmpty { Text(verbatim: facts).recipe(.label, color: DS.accent).lineLimit(1) }
                if let pitch = words.pitch(s) { Text(verbatim: pitch).recipe(.footnote, color: DS.textMuted).lineLimit(2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismiss(); open(s.route) }
            actions(m, s)
        } else if let empty = m.empty {
            nothing(m, empty)
        } else {
            DecideTrioLayout {
                ForEach(0..<DecideModel.trio, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill).aspectRatio(DS.Poster.aspect, contentMode: .fit)
                }
            }
            .overlay { DSLoadingState() }
        }
    }

    /// Ver · Barajar · ⋯ (lado a lado y del mismo tamaño; con letra de accesibilidad, uno debajo del otro).
    private func actions(_ m: DecideModel, _ s: Suggestion) -> some View {
        let buttonsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s3))
        return buttonsLayout {
            // Ver ahora: la película, o en una serie el capítulo en que vas (el primero si no la has empezado).
            let start = seriesStart?.metaID == s.imdb ? seriesStart : nil
            Button {
                dismiss()
                Task { await env.play(s, from: start) }
            } label: {
                Group {
                    // Una serie se propone completa, no un capítulo (Fernando, 2 nov 2026).
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
            // Lo que se espera se ve en el botón; con una o dos opciones no hay a qué barajar (F4).
            Button { Task { await m.next() } } label: {
                HStack(spacing: DS.Space.s2) {
                    if m.isLoading {
                        ProgressView().controlSize(.small)   // ds-exception: la ruedita va dentro del botón que la pidió
                    } else { Image(systemName: "shuffle") }
                    Text("Barajar").lineLimit(1)
                }
                .foregroundStyle(m.canShuffle ? DS.text : DS.textFaint).frame(maxWidth: .infinity)
            }
            .dsGlassButton().controlSize(.large).disabled(m.isLoading || !m.canShuffle)
            .accessibilityIdentifier("decide-shuffle")
            DSMoreMenu {
                Button("No me interesa", systemImage: "hand.thumbsdown", role: .destructive) { remove(m, s, dismissed: true) }
                Button("Hoy no", systemImage: "moon.zzz") { remove(m, s, dismissed: false) }
                Button("Ver la ficha", systemImage: "info.circle") { dismiss(); open(s.route) }
            }
        }
    }

    /// Lo que quitas se puede deshacer (F5): «Ya no te la sugiero · Deshacer» o «Hoy no · Deshacer».
    private func remove(_ m: DecideModel, _ s: Suggestion, dismissed: Bool) {
        Task {
            if dismissed { await m.notInterested() } else { await m.skipToday() }
            env.notify(dismissed ? "Ya no te la sugiero" : "Hoy no", detail: titleName(s.title, id: s.imdb, kind: s.kind), tone: .info,
                       actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { Task { await m.undoRemoval() } }
        }
    }

    /// Nada que proponer, con el porqué (F2): sin conexión o sin sugerencias, «Reintentar»; por los filtros, los dos
    /// cambios que más abren («Quitar Terror · 6», «Con 1 h · 3»).
    @ViewBuilder private func nothing(_ m: DecideModel, _ empty: DecideModel.Empty) -> some View {
        switch empty {
        case .offline, .nothingSuggested:
            VStack(spacing: DS.Space.s3) {
                Image(systemName: empty == .offline ? DS.Symbol.offline : "rectangle.stack").font(DS.TextRecipe.title.font).foregroundStyle(DS.textMuted)
                (empty == .offline ? Text("Sin conexión") : Text("Aún no hay sugerencias")).recipe(.cardTitle).multilineTextAlignment(.center)
                (empty == .offline ? Text("Cuando vuelva el internet, aquí salen tres de tus sugerencias.") : Text("Cuando Explorar cargue sus listas, aquí salen."))
                    .recipe(.footnote).multilineTextAlignment(.center)
                if let reload {
                    Button { Task { let fresh = await reload(); await m.retry(pool: fresh.pool, sources: fresh.sources) } } label: {
                        Label("Reintentar", systemImage: "arrow.clockwise")
                    }
                    .dsGlassButton().controlSize(.large)
                    .accessibilityIdentifier("decide-retry")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s5)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("decide-offline")
        case .filters:
            let relax = m.relaxations()
            VStack(spacing: DS.Space.s3) {
                Image(systemName: DS.Symbol.decide).font(DS.TextRecipe.title.font).foregroundStyle(DS.textMuted)
                Text(verbatim: String(format: Strings.tr("Nada con %@", language: language), words.activeSummary(m))).recipe(.cardTitle).multilineTextAlignment(.center)
                Text("Prueba quitando un filtro.").recipe(.footnote).multilineTextAlignment(.center)
                HStack(spacing: DS.Space.s2) {
                    ForEach(Array(relax.enumerated()), id: \.offset) { index, item in
                        let title = Text(verbatim: "\(words.relaxName(item.relax, m)) · \(item.count)")
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("decide-nothing")
        }
    }

    // MARK: los filtros (se aplican al tocarlos)
    /// Cuatro cápsulas parejas (las mismas «Todo ⌄» de toda la app), en dos renglones; con letra de accesibilidad, una por
    /// renglón (F6: antes «Calificación» y «Afinar» quedaban fuera de la hoja).
    @ViewBuilder private func filterRow(_ m: DecideModel) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: DS.Space.s2) { timeMenu(m); moodMenu(m); ratingMenu(m); moreButton(m) }
        } else {
            Grid(horizontalSpacing: DS.Space.s2, verticalSpacing: DS.Space.s2) {
                GridRow { timeMenu(m); moodMenu(m) }
                GridRow { ratingMenu(m); moreButton(m) }
            }
        }
    }

    /// «Cualquier duración» hasta que eliges uno (F3: un filtro que se ve puesto, filtra).
    private func timeMenu(_ m: DecideModel) -> some View {
        Menu {
            Button { Task { await m.chooseTime(nil) } } label: {
                optionLabel(Strings.tr("Cualquier duración", language: language), count: m.count(strictTime: false), selected: m.shownTime == nil)
            }
            ForEach(DecideModel.Time.allCases, id: \.self) { t in
                Button { Task { await m.chooseTime(t) } } label: {
                    optionLabel(words.timeName(t), count: m.count(strictTime: true) { $0.time = t }, selected: m.shownTime == t)
                }
            }
        } label: { DSCapsuleLabel(title: Text(verbatim: words.timeTitle(m)), symbol: "clock", selected: m.shownTime != nil, stretch: true, trailing: "chevron.down") }
        .accessibilityIdentifier("decide-time")
    }

    private func moodMenu(_ m: DecideModel) -> some View {
        Menu {
            Button { m.mood = nil; Task { await m.apply() } } label: {
                optionLabel(Strings.tr("Lo que sea", language: language), count: m.count { $0.mood = nil }, selected: m.mood == nil)
            }
            ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                Button { m.mood = mood; Task { await m.apply() } } label: {
                    optionLabel(Strings.tr(words.moodLabel(mood), language: language), count: m.count { $0.mood = mood }, selected: m.mood == mood, symbol: words.moodSymbol(mood))
                }
            }
        } label: {
            DSCapsuleLabel(title: m.mood.map { Text(LocalizedStringKey(words.moodLabel($0))) } ?? Text("Ánimo"), symbol: m.mood.map(words.moodSymbol) ?? "face.smiling",
                           selected: m.mood != nil, stretch: true, trailing: "chevron.down")
        }
        .accessibilityIdentifier("decide-mood")
    }

    private func moreButton(_ m: DecideModel) -> some View {
        Button { path.append(.more) } label: {
            DSCapsuleLabel(title: m.moreFilters > 0 ? Text("Afinar · \(m.moreFilters)") : Text("Afinar"), symbol: "slider.horizontal.3",
                           selected: m.moreFilters > 0, stretch: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("decide-more")
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
                        let title = r == 0 ? Strings.tr("Cualquiera", language: language) : "\(DecideWords.stars(r))+"
                        if m.letterboxdReady { optionLabel(title, count: m.count { $0.minLetterboxd = r }, selected: m.minLetterboxd == r) }
                        else if m.minLetterboxd == r { Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") } }
                        else { Text(verbatim: title) }
                    }
                }
            }
        } label: {
            DSCapsuleLabel(title: Text(verbatim: words.ratingTitle(m)), symbol: "star",
                           selected: m.minRating > 0 || m.minLetterboxd > 0, stretch: true, trailing: "chevron.down")
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
