import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Decide por mí»: una sola puerta con dos maneras (DE2, 13 nov 2026), como la TV: «Tres que caben» (tres carteles con su
/// porqué, «Ver» y «Barajar») y «Una por una» (el mazo). Arriba, un renglón de controles (`DecideControls`: películas o
/// series y un solo botón «Filtros») con cuántas opciones quedan junto al título. «Filtros» es su propia página
/// (`DecideFilters`: duración, ánimo, calificación, géneros, época, fama, premios, de dónde y lo ya visto, por secciones), y
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
    /// El alto del encabezado y el de los tres carteles con sus botones, medidos: la hoja corta mide eso (sin hueco abajo).
    @State private var headerHeight: CGFloat = 0
    @State private var trioHeight: CGFloat = 0
    private var contentHeight: CGFloat {
        headerHeight > 0 && trioHeight > 0 ? DS.Space.sheetTop + headerHeight + DS.Layout.titleToContent + trioHeight : 0
    }
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
    /// Las cartas que de verdad quedan en el mazo (las dice `MatchDeckScreen`): la cuenta de «Una por una».
    @State private var deckCount: Int?
    /// Barajar: las tres salen (en cascada) antes de pedir las nuevas, que entran igual; y el ícono salta.
    @State private var leaving = false
    @State private var shuffles = 0
    /// La vuelta de «Barajar» en curso: se cancela al cerrar la hoja (ninguna tarea sobrevive a su vista).
    @State private var shuffling: Task<Void, Never>?
    /// El mazo vive aquí, no en su pestaña: ir y volver no lo vuelve a cargar (ni enseña su esqueleto) y el cartel elegido
    /// puede volverse su carta de arriba (`hero`).
    @State private var deckModel: MatchDeckModel?
    /// Cartel → carta: el elegido de «Tres que caben» crece hasta volverse la carta de arriba del mazo, y de regreso.
    @Namespace private var hero
    /// El color del cartel elegido (`ArtTint`, el mismo cálculo y la misma memoria que el fondo de la ficha): un resplandor
    /// suave detrás de los tres.
    @State private var art = ArtTint()
    @Environment(\.colorScheme) private var scheme
    /// Esta vez que se abrió la hoja: su contenido entra escalonado una sola vez.
    @State private var opened = UUID().uuidString
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
        let _ = BodyCount.tick("decide", why: Self._printChanges)   // cuántas veces se pinta (`-perf-bodies`)
        let m = observer.model
        NavigationStack(path: $path) {
            sheet(m)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .more: DecideFilters(model: m, deck: mode == .deck, openLists: { path.append(.lists) }, done: { path.removeAll() })
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
        .onDisappear { m.stop(); shuffling?.cancel(); shuffling = nil }
        .task(id: m.pick?.poster) { await art.load(m.pick?.poster) }
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

    // MARK: la hoja
    /// El encabezado (título, pestañas y controles) es uno solo y se queda quieto; debajo cambia el contenido de la pestaña,
    /// entrando de su lado (`tabTransition`). El encabezado va encima (`zIndex`): ningún gesto ni carta del contenido lo
    /// tapa (regla «Un gesto de contenido nunca tapa los controles de la hoja»; Fernando, 13 nov 2026: «ya no deja
    /// regresar»). Antes cada pestaña traía su propio encabezado y la rayita de las pestañas no podía viajar.
    private func sheet(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            header(m)
                .zIndex(1)   // ds-exception: el encabezado va encima del contenido (regla «Un gesto de contenido nunca tapa los controles»)
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { h in if h != headerHeight { headerHeight = h } }
            ZStack(alignment: .top) {
                if mode == .deck { deckBody(m).transition(tabTransition(.deck)) } else { trioBody(m).transition(tabTransition(.trio)) }
            }
            .frame(maxHeight: mode == .deck || overflows ? .infinity : nil, alignment: .top)
            .entrance("decide-\(opened)-content", order: 3)
        }
        .dsSheetContent(bottom: false)   // cada pestaña pone su aire de abajo
        .frame(maxHeight: .infinity, alignment: .top)
        // «Tres que caben» baja hasta la orilla con el aire de los lados (Aire parejo); el mazo se queda sobre el área segura:
        // sus botones y sus nombres nunca bajo la barrita de inicio.
        .ignoresSafeArea(.container, edges: mode == .trio ? .bottom : [])
    }

    /// Cada pestaña entra de su lado y sale hacia él («Tres que caben» a la izquierda, «Una por una» a la derecha), con un
    /// fundido; se puede interrumpir a medias. Con «Reducir movimiento», solo el fundido.
    private func tabTransition(_ tab: DecideModel.Mode) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .offset(x: tab == .deck ? DS.DecideLive.tabShift : -DS.DecideLive.tabShift).combined(with: .opacity)
    }

    // MARK: «Una por una»
    /// El mazo con los mismos filtros (DE2): el tipo y «Filtros» arriba (en su hoja, solo lo que le aplica); el tiempo y el
    /// ánimo son de «Tres que caben». Al cambiar un filtro, el mazo se vuelve a barajar con lo que queda.
    private func deckBody(_ m: DecideModel) -> some View {
        let pool = m.deckPool()
        return MatchDeckScreen(model: $deckModel, lead: heroID, hero: reduceMotion ? nil : hero, pool: pool, poolKey: m.deckKey, filtered: m.moreFilters > 0 || m.kind != nil || m.minRating > 0 || m.minLetterboxd > 0,
                               reload: reload.map { load in { let fresh = await load(); await m.retry(pool: fresh.pool, sources: fresh.sources); return m.deckPool() } },
                               onCount: { deckCount = $0 },
                               onOpenTitle: { dismiss(); open($0) },
                               onPlay: { route in
                                   // Una película suena ya; una serie abre su ficha (un episodio suelto casi nunca es el bueno).
                                   dismiss()
                                   if let s = pool.first(where: { $0.imdb == route.metaID }), s.kind == "movie" { Task { await env.play(s) } } else { open(route) }
                               })
            .padding(.bottom, DS.Space.s4)
    }

    // MARK: «Tres que caben»
    /// Los tres carteles y sus botones. Se desliza solo si no cabe (letra grande, F6); el alto de la hoja es el del
    /// encabezado más esto, medido (sin hueco abajo).
    private func trioBody(_ m: DecideModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) { proposal(m) }
                .padding(.bottom, DS.Space.s4)
                // Solo un cambio de verdad mueve el alto de la hoja: medio punto de ida y vuelta no vuelve a pedirle tamaño
                // (la hoja mide su contenido y el contenido se acomoda a la hoja; sin este piso podían perseguirse).
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { h in if h != trioHeight { trioHeight = h } }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()   // la sombra de la elegida y el resplandor no se cortan en el margen
        .frame(height: overflows || trioHeight == 0 ? nil : trioHeight)
        .onChange(of: contentHeight, initial: true) {
            let over = contentHeight > WindowMetrics.size.height * DS.Sheet.maxShare
            if over != overflows { overflows = over }
        }
    }

    /// «Decide por mí» con cuántas opciones quedan junto al título y ✕; debajo, las dos maneras y un solo renglón de controles
    /// (`DecideControls`: el tipo y los filtros de ícono, con lo puesto dicho en una línea). El mismo en las dos pestañas.
    private func header(_ m: DecideModel) -> some View {
        let count = mode == .deck ? deckCount ?? m.deckPool().count : m.count()
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            // La cuenta junto al título; con letra de accesibilidad, debajo de él (el título no se parte). Se decide por el tamaño
            // de letra, no con `ViewThatFits`: medir dos encabezados alineados por línea base en cada pasada congelaba la hoja
            // (0x8BADF00D, 13 nov 2026; regla «ViewThatFits no se anida ni vive bajo alineación por línea base»).
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        DSSheetHeader(title: Text("Decide por mí")) { close }
                        countText(m, count)
                    }
                } else {
                    DSSheetHeader(title: Text("Decide por mí")) { countText(m, count); close }
                }
            }
            .entrance("decide-\(opened)-title", order: 0)
            DSSelector(options: [.init(id: DecideModel.Mode.trio, title: Text("Tres que caben"), symbol: DS.Symbol.decideTrio),
                                 .init(id: .deck, title: Text("Una por una"), symbol: DS.Symbol.decideDeck)],
                       selection: Binding(get: { mode }, set: { switchMode(to: $0, m) }), adapts: false)
                .accessibilityIdentifier("decide-mode")
                .entrance("decide-\(opened)-tabs", order: 1)
            DecideControls(model: m, deck: mode == .deck, openFilters: { path.append(.more) })
                .entrance("decide-\(opened)-controls", order: 2)
        }
    }

    /// Cambiar de pestaña con continuidad (Fernando, 13 nov 2026): a «Una por una», el mazo empieza por el cartel elegido (si
    /// pasa sus filtros) y ese cartel crece hasta ser la carta; de regreso, la carta de arriba vuelve a ser la elegida si está
    /// entre los tres. Ni el trío ni el mazo se vuelven a barajar.
    private func switchMode(to new: DecideModel.Mode, _ m: DecideModel) {
        guard new != mode else { return }
        if new == .deck {
            let lead = m.pick.flatMap { p in m.deckPool().contains { $0.imdb == p.imdb } ? p.imdb : nil }
            deckModel?.lead = lead
            heroID = lead
        } else if let top = deckModel?.cards.first, let same = m.picks.first(where: { $0.imdb == top.imdb }) {
            m.select(same)
            heroID = same.imdb
        } else {
            heroID = nil
        }
        withAnimation(DS.Motion.base(reduceMotion)) { mode = new }
    }

    /// El título que viaja entre el cartel y la carta (nil: transición de lado normal).
    @State private var heroID: String?

    private func countText(_ m: DecideModel, _ count: Int) -> some View {
        Text(verbatim: words.optionsLine(m, count))
            .recipe(.footnote).monospacedDigit().contentTransition(.numericText())
            .lineLimit(1)
            .accessibilityIdentifier("decide-count")
    }

    private var close: some View {
        DSIconButton(symbol: "xmark", label: "Cerrar", size: .large) { dismiss() }   // del tamaño de «Filtros», en su misma orilla (≥ 44 pt)
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
                    // Se hunde tantito al apretarlo (`DSPressStyle`). Al barajar sale encogiéndose y la nueva entra subiendo, una
                    // tras otra (`DecideTrioLayout.shuffle`).
                    Button { if chosen { dismiss(); open(option.route) } else { m.select(option) } } label: {
                        PosterView(url: option.poster, title: option.title)
                            .matchedGeometryEffect(id: DecideView.heroKey(option.imdb), in: hero, isSource: true)
                            .shadow(chosen ? DS.Elevation.high : DS.Elevation.high.color(.clear))
                            .scaleEffect(chosen ? DS.Decide.chosenScale : 1, anchor: anchor)
                            .animation(chosen ? DS.Motion.grow(reduceMotion) : DS.Motion.fold(reduceMotion), value: chosen)
                    }
                    .buttonStyle(DSPressStyle())
                    .zIndex(chosen ? 1 : 0)
                    .scaleEffect(leaving ? DS.DecideLive.shuffleFrom : 1, anchor: .bottom)
                    .opacity(leaving ? 0 : 1)
                    .animation(DS.Motion.fold(reduceMotion)?.delay(Double(index) * DS.DecideLive.shuffleStagger), value: leaving)
                    .transition(DecideTrioLayout.shuffle(index: index, reduceMotion: reduceMotion))
                    .accessibilityLabel(Text(verbatim: titleName(option.title, id: option.imdb, kind: option.kind)))   // lo mismo que se lee debajo
                    .accessibilityHint(chosen ? Text("Abre la ficha") : Text(verbatim: ""))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier(chosen ? "decide-chosen" : "decide-option")
                }
            }
            .padding(.top, DS.Space.s2)   // lo que crece la elegida, sin encimarse en los controles
            .background { glow }
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
                // Una serie se propone completa, no un capítulo (Fernando, 2 nov 2026). Con letra de accesibilidad dice solo «Ver»
                // (antes «Ver la se…» cortado); se decide por el tamaño de letra, sin `ViewThatFits`.
                Group {
                    if s.kind == "series", !typeSize.isAccessibilitySize {
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
            DSIconButton(symbol: DS.Symbol.shuffle, label: "Barajar", steady: true, busy: m.isLoading, kick: shuffles) { shuffle(m) }
                .disabled(m.isLoading || !m.canShuffle)
                .accessibilityIdentifier("decide-shuffle")
            DSMoreMenu {
                Button("No me interesa", systemImage: "hand.thumbsdown", role: .destructive) { remove(m, s, dismissed: true) }
                Button("Hoy no", systemImage: "moon.zzz") { remove(m, s, dismissed: false) }
                Button("Ver la ficha", systemImage: "info.circle") { dismiss(); open(s.route) }
            }
            .accessibilityIdentifier("decide-more")
        }
    }

    /// Barajar de verdad: los tres salen encogiéndose uno tras otro, se piden los nuevos y entran subiendo en cascada
    /// (`DecideTrioLayout.shuffle`). Se puede volver a tocar a medias. Con «Reducir movimiento», solo se funden.
    private func shuffle(_ m: DecideModel) {
        shuffles += 1
        shuffling?.cancel()
        shuffling = Task {
            if !reduceMotion {
                leaving = true   // cada cartel lleva su propia animación, escalonada
                try? await Task.sleep(for: DS.DecideLive.leave)
            }
            guard !Task.isCancelled else { return }
            await m.next()
            leaving = false
        }
    }

    /// La llave compartida del cartel y la carta de un mismo título (`matchedGeometryEffect`).
    static func heroKey(_ imdb: String) -> String { "decide-hero-" + imdb }

    /// Un resplandor suave del color del cartel elegido detrás de los tres (`ArtTint`): en oscuro su tono claro, en claro ese
    /// tono sobre el papel. Cambia con un fundido al elegir otro.
    private var glow: some View {
        let tone = art.colors.map { scheme == .dark ? $0.accent : $0.accent.mix(with: DS.paper, by: DS.Backdrop.lightMix) } ?? .clear
        return RadialGradient(colors: [tone.opacity(DS.DecideLive.glow), .clear], center: .center, startRadius: 0, endRadius: DS.DecideLive.glowReach)
            .padding(-DS.Space.s8)
            .animation(DS.Motion.tint(reduceMotion) ?? DS.Motion.fade, value: art.colors)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
