import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Decide por mí»: una sola puerta con dos maneras (DE2, 13 nov 2026), como la TV: «Tres que caben» (tres carteles con su
/// porqué, «Ver» y «Barajar») y «Una por una» (el mazo). Arriba, un renglón de controles que se aplican al tocarlos
/// (`DecideControls`: películas o series, tiempo, ánimo, calificación y «Afinar») con cuántas opciones quedan junto al
/// título. «Afinar» es su propia página (géneros, época, de qué listas, bien calificada en IMDb, Trakt o TMDB, lo ya visto), y
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
    /// El alto del contenido de la hoja corta, medido (sin hueco abajo).
    @State private var contentHeight: CGFloat = 0
    private var quickHeight: CGFloat {
        contentHeight > 0 ? min(contentHeight - bottomInset, WindowMetrics.size.height * DS.Sheet.maxShare) : DS.Decide.quickHeight
    }
    /// Lo que la hoja aparta abajo para la barrita de inicio: el contenido baja hasta la orilla y su aire de abajo es el mismo
    /// de los lados («Aire parejo»; antes quedaba un hueco del doble bajo los botones).
    @State private var bottomInset: CGFloat = 0
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
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
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
        // Capturas con filtros puestos (la línea de lo puesto y los íconos llenos).
        .task { if Demo.isOn, Demo.has("-demo-decide-set") { m.mood = .light; m.minRating = 7; m.genres.insert("comedy"); await m.chooseTime(.long) } }
        #endif
    }

    // MARK: «Una por una»
    /// El mazo con los mismos filtros (DE2): el tipo arriba, la calificación y «Afinar» debajo; el tiempo y el ánimo son de
    /// «Tres que caben». Al cambiar un filtro, el mazo se vuelve a barajar con lo que queda.
    private func deckRoot(_ m: DecideModel) -> some View {
        let pool = m.deckPool()
        return VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            header(m)
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
        .ignoresSafeArea(.container, edges: .bottom)   // el aire de abajo es el de los lados (Aire parejo)
    }

    // MARK: la hoja corta
    private func root(_ m: DecideModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                header(m)
                proposal(m)
            }
            .dsSheetContent()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                contentHeight = h
                overflows = h > WindowMetrics.size.height * DS.Sheet.maxShare
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(.container, edges: .bottom)   // el aire de abajo es el de los lados (Aire parejo)
    }

    /// «Decide por mí» con cuántas opciones quedan junto al título y ✕; debajo, las dos maneras y un solo renglón de controles
    /// (`DecideControls`: el tipo y los filtros de ícono, con lo puesto dicho en una línea). El mismo en las dos pestañas.
    private func header(_ m: DecideModel) -> some View {
        let count = mode == .deck ? m.deckPool().count : m.count()
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            // La cuenta junto al título; si con la letra grande no caben en un renglón, debajo de él (el título no se parte).
            ViewThatFits(in: .horizontal) {
                DSSheetHeader(title: Text("Decide por mí")) { countText(m, count); close }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    DSSheetHeader(title: Text("Decide por mí")) { close }
                    countText(m, count)
                }
            }
            DSTextTabs(options: [.init(id: DecideModel.Mode.trio, title: Text("Tres que caben"), symbol: DS.Symbol.decideTrio),
                                 .init(id: .deck, title: Text("Una por una"), symbol: DS.Symbol.decideDeck)],
                       selection: $mode.animation(DS.Motion.base(reduceMotion)))
                .accessibilityIdentifier("decide-mode")
            DecideControls(model: m, deck: mode == .deck, openMore: { path.append(.more) })
        }
    }

    private func countText(_ m: DecideModel, _ count: Int) -> some View {
        Text(verbatim: words.optionsLine(m, count))
            .recipe(.footnote).monospacedDigit().contentTransition(.numericText())
            .lineLimit(1)
            .accessibilityIdentifier("decide-count")
    }

    private var close: some View {
        DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { dismiss() }
            .accessibilityIdentifier("decide-close")
    }

    /// Tres carteles lado a lado (la elegida, resaltada); debajo, su nombre, sus datos y por qué verla; luego Ver, Barajar y «⋯».
    @ViewBuilder private func proposal(_ m: DecideModel) -> some View {
        if let s = m.pick {
            let facts = words.why(s, m)
            // Cada cartel mide un tercio aunque queden uno o dos, centrados y sin huecos (F4).
            DecideTrioLayout {
                ForEach(Array(m.picks.enumerated()), id: \.element.imdb) { index, option in
                    let chosen = option.imdb == s.imdb
                    // Crece hacia adentro: la de la orilla no se sale del margen.
                    let anchor: UnitPoint = m.picks.count > 1 && index == 0 ? .bottomLeading : m.picks.count > 1 && index == m.picks.count - 1 ? .bottomTrailing : .bottom
                    // Tocar otro cartel lo elige; tocar el elegido abre su ficha (la de la serie o la película).
                    // Un solo juego: mismo tamaño y misma base. La elegida crece un poco desde abajo y se levanta con su sombra
                    // (`grow`); la que deja de serlo se recoge (`fold`). Sin marco ni las otras apagadas (pulido de DE2).
                    Button { if chosen { dismiss(); open(option.route) } else { m.select(option) } } label: {
                        PosterView(url: option.poster, title: option.title)
                            .shadow(chosen ? DS.Elevation.high : DS.Elevation.high.color(.clear))
                            .scaleEffect(chosen ? DS.Decide.chosenScale : 1, anchor: anchor)
                            .animation(chosen ? DS.Motion.grow(reduceMotion) : DS.Motion.fold(reduceMotion), value: chosen)
                            .zIndex(chosen ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: option.title))
                    .accessibilityHint(chosen ? Text("Abre la ficha") : Text(verbatim: ""))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier(chosen ? "decide-chosen" : "decide-option")
                }
            }
            .padding(.top, DS.Space.s2)   // lo que crece la elegida, sin encimarse en los controles
            .dsFeedback(.selection, trigger: s.imdb)
            // Sus datos al margen, con el mismo alto siempre (los renglones se apartan aunque vengan vacíos): al cambiar de
            // elegida el texto se funde y nada brinca.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: titleName(s.title, id: s.imdb, kind: s.kind)).recipe(.cardTitle).lineLimit(typeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
                Text(verbatim: facts).recipe(.label, color: DS.accent).lineLimit(1, reservesSpace: true)
                Text(verbatim: words.pitch(s) ?? "").recipe(.footnote, color: DS.textMuted).lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(DS.Motion.fade, value: s.imdb)
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

    /// Ver · Barajar · ⋯ en un renglón del mismo alto, de margen a margen: «Ver» se estira y Barajar y «⋯» son círculos de la
    /// familia de `DSIconButton` (pulido de DE2).
    private func actions(_ m: DecideModel, _ s: Suggestion) -> some View {
        HStack(spacing: DS.Space.s3) {
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
            DSIconButton(symbol: "shuffle", label: "Barajar", steady: true, busy: m.isLoading) { Task { await m.next() } }
                .disabled(m.isLoading || !m.canShuffle)
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
}
