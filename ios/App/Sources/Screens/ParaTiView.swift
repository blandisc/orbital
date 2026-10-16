import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Para ti»: el mosaico (como en la TV, solo películas y series) y las listas (Trakt y plataformas).
struct ParaTiView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model: ModelObserver<ParaTiModel>
    @StateObject private var tint = ArtTint()
    /// El arte de la pieza enfocada del mosaico: el fondo de toda la pantalla toma su tono (nil en el ambiente o en Listas).
    @State private var focusedArt: String?
    /// La sugerencia enfocada del mosaico (su información va bajo él).
    @State private var focused: Suggestion?
    /// Una ficha abierta desde la franja del mosaico («Ver la serie»).
    @State private var openTitle: TitleRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init() { _model = StateObject(wrappedValue: ModelObserver(ParaTiModel(AppEnvironment.shared.services))) }

    var body: some View {
        let m = model.model
        VStack(spacing: DS.Space.s2) {
            DSSegmented<ParaTiModel.Mode>(options: [(.mosaic, "Mosaico"), (.lists, "Listas")], selection: Binding(get: { m.mode }, set: { m.mode = $0 }))
                .padding(.horizontal, DS.Space.gutter)
            if m.isGeneric, m.mode == .mosaic, !m.mosaic.isEmpty {
                Text("Lo más popular en Stremio. Conecta Trakt en Ajustes y el mosaico se arma con lo tuyo.")
                    .font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.gutter)
            }
            if let error = m.error, m.mosaic.isEmpty, m.lists.isEmpty { DSNotice(text: LocalizedStringKey(error)).padding(.horizontal, DS.Space.gutter) }
            switch m.mode {
            case .mosaic:
                Mosaic(items: m.mosaic, watchlistKeys: m.watchlistKeys, demoFocus: demoFocusImdb, onDismiss: { s in Task { await m.dismiss(s) } },
                       onFocusChange: { focused = $0; focusedArt = $0?.wide })
                // La pieza enfocada, contada bajo el mosaico (todas las piezas son del mismo tamaño: su información va aquí).
                if DS.Mosaic.uniform, let item = focused {
                    // Como la TV: el motivo tal cual, y una serie sugerida abre su ficha («Ver la serie»), no un episodio al azar.
                    MosaicCaption(reason: Text(badgeKey(item.reason)), title: item.title, logo: item.logo,
                                  data: factStrings(item).first.map { [$0] } ?? [], accent: tint.colors, isSeries: item.kind == "series",
                                  watch: { if item.kind == "series" { openTitle = item.route } else { Task { await env.play(item) } } }) {
                        SuggestionActions(suggestion: item, includeWatch: false) { s in Task { await m.dismiss(s) } }
                    }
                    .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(item.imdb)
                }
            case .lists: ListsView(observer: model)
            }
        }
        .padding(.top, DS.Space.s2)
        .background(Backdrop(tint: m.mode == .mosaic ? tint.colors : nil))
        .task(id: m.mode == .mosaic ? focusedArt : nil) { await tint.load(m.mode == .mosaic ? focusedArt : nil) }
        .navigationTitle("Para ti").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        // De dónde salió lo que ves, en el mismo lugar que «Stremio al día» en Inicio (no un chip y un pie sueltos).
        .navigationSubtitle(subtitle(m))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(m.isLoading).accessibilityLabel(Text("Actualizar"))
            }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .task {
            #if DEBUG
            if Demo.isOn, Demo.open == "lists" || Demo.mode == "lists" { m.mode = .lists }
            #endif
            await m.load()
        }
        .refreshable { await m.refresh() }
        .animation(DS.Motion.base(reduceMotion), value: m.mode)
        .animation(DS.Motion.base(reduceMotion), value: focused?.imdb)
    }

    /// «De tu Orbital · Trakt al día» o «Calculado en el iPhone»: el subtítulo de la barra, como en Inicio.
    private func subtitle(_ m: ParaTiModel) -> Text {
        let source = m.source == .console ? Text("De tu Orbital") : Text("Calculado en el iPhone")
        return m.traktLinked ? Text("\(source) · \(Text("Trakt al día"))") : source
    }

    /// Modo demostración (`-demo-mosaic-focus N`): qué sugerencia enfocar al abrir, para las capturas de CEN-36.
    private var demoFocusImdb: String? {
        #if DEBUG
        guard Demo.isOn, let index = Demo.mosaicFocus, model.model.mosaic.indices.contains(index) else { return nil }
        return model.model.mosaic[index].imdb
        #else
        return nil
        #endif
    }
}

/// Las acciones de una sugerencia (mantener el dedo sobre un póster, o «Más» en el destacado): ver, Mi lista, descargar, la TV y «No me interesa».
struct SuggestionActions: View {
    @EnvironmentObject private var env: AppEnvironment
    let suggestion: Suggestion
    var includeWatch = true
    let onDismiss: (Suggestion) -> Void

    var body: some View {
        if includeWatch { Button("Ver", systemImage: "play.fill") { Task { await env.play(suggestion) } } }
        Button("Mi lista", systemImage: "plus") { Task { await env.addToLibrary(suggestion) } }
        Button("Descargar", systemImage: "arrow.down.circle") { Task { await env.download(suggestion) } }
        if env.services.orbital.isConfigured {
            Button("Ver en la TV", systemImage: "tv") { Task { await env.playOnTV(kind: suggestion.kind, metaID: suggestion.imdb, videoID: env.videoID(for: suggestion), title: suggestion.title) } }
        }
        Button("No me interesa", systemImage: "hand.thumbsdown", role: .destructive) { onDismiss(suggestion) }
    }
}

/// Un póster de un estante: toca para abrir la ficha (con una háptica suave), mantén para el menú.
struct ShelfPoster: View {
    let suggestion: Suggestion
    let style: ShelfPlan.Style
    let inList: Bool
    let onDismiss: (Suggestion) -> Void
    @State private var taps = 0

    var body: some View {
        Group {
            if style == .top10, let rank = suggestion.rank {
                NavigationLink(value: suggestion.route) { RankedPosterCard(rank: rank, title: suggestion.title, poster: suggestion.poster, movement: suggestion.movement, isNew: suggestion.isNew).titleZoomSource(suggestion.route) }.buttonStyle(.plain)
            } else {
                TitleLink(route: suggestion.route, bookmarked: inList, rank: style == .platform ? suggestion.rank : nil,
                          detail: yearAndKind(year: suggestion.year.map(String.init) ?? "", kind: suggestion.kind))
            }
        }
        .simultaneousGesture(TapGesture().onEnded { taps += 1 })
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
        .contextMenu { SuggestionActions(suggestion: suggestion, onDismiss: onDismiss) }
    }
}

/// Los nombres de los estantes: los de la consola vienen ya con su texto; los de este iPhone se nombran por su id.
@MainActor func shelfTitle(_ plan: ShelfPlan) -> Text {
    // En español se usa el texto de la TV tal cual; en inglés, las listas conocidas con su nombre traducido (la TV manda español).
    let english = AppEnvironment.shared.services.appSettings.uiLanguage == "en"
    if english, let known = knownShelfTitle(plan) { return known }
    if !plan.title.isEmpty { return Text(verbatim: plan.title) }
    if let known = knownShelfTitle(plan) { return known }
    return Text(verbatim: plan.list.brand.flatMap { brand in Tmdb.platforms.first { $0.brand == brand }?.name } ?? plan.id)
}

/// El nombre de una lista que el iPhone conoce (para nombrarla en su idioma); nil si es un catálogo de complemento.
@MainActor private func knownShelfTitle(_ plan: ShelfPlan) -> Text? {
    let brand = plan.list.brand.flatMap { brand in Tmdb.platforms.first { $0.brand == brand }?.name } ?? plan.list.brand ?? ""
    if plan.id.hasPrefix("chart:") { return Text("Top 10 en \(brand)") }
    if plan.id.hasPrefix("jw:") { return Text("Tendencias en \(brand)") }
    switch plan.id {
    case "mine": return Text("Tus series")
    case "watchlist": return Text("Tu watchlist")
    case "recs": return Text("Recomendadas")
    case "trend": return Text("En tendencia")
    case "popular": return Text("Lo más popular")
    default: return nil
    }
}

@MainActor func shelfMeta(_ plan: ShelfPlan) -> Text? {
    let english = AppEnvironment.shared.services.appSettings.uiLanguage == "en"
    if !plan.list.meta.isEmpty, !english { return Text(verbatim: plan.list.meta) }
    if plan.id.hasPrefix("chart:") { return Text("Esta semana en México") }
    if plan.id.hasPrefix("jw:") { return Text("Tendencia en JustWatch · México") }
    switch plan.id {
    case "mine": return Text("Las que estás viendo")
    case "watchlist": return Text("Lo que dejaste pendiente")
    case "recs": return Text("Por lo que has visto")
    case "trend": return Text("Lo más visto esta semana")
    case "popular": return Text("De todos los tiempos")
    default: return plan.style == .platform ? Text("Lo más popular") : nil
    }
}

func shelfSymbol(_ plan: ShelfPlan) -> String {
    switch plan.id {
    case "mine", "watchlist": "bookmark"
    case "recs": "sparkles"
    case "trend": "chart.line.uptrend.xyaxis"
    case "popular": "flame"
    default: plan.style == .plain ? "square.stack" : "play.rectangle"
    }
}

/// «Para ti › Listas»: un destacado, el selector Series · Películas y los estantes (cada uno dice de dónde viene).
struct ListsView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openTitle: TitleRoute?
    /// Los colores del arte del destacado: su «Ver» toma el color claro, como en la TV.
    @StateObject private var featuredTint = ArtTint()
    private var model: ParaTiModel { observer.model }

    var body: some View {
        ScrollViewReader { proxy in scroller.task { await demoScroll(proxy) } }
    }

    /// Modo demostración (`-demo-shelf id`): baja hasta ese estante al abrir, para las capturas.
    private func demoScroll(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard Demo.isOn, let id = Demo.shelf else { return }
        try? await Task.sleep(for: .seconds(3))
        proxy.scrollTo(id, anchor: .top)
        #endif
    }

    private var scroller: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s6, pinnedViews: [.sectionHeaders]) {
                // El arte a sangre ya pone su margen (en claro es tarjeta; en oscuro va de borde a borde).
                if let featured = model.featured {
                    featuredTile(featured).task(id: featured.item.wide) { await featuredTint.load(featured.item.wide) }
                }
                if !model.airings.isEmpty {   // justo después del destacado; vacío → no se pinta (el calendario completo ya existe: `UpcomingView`)
                    Shelf(title: Text("Próximos estrenos"), meta: Text("Lo que sale de las series que sigues"), symbol: "calendar", route: ShelfRoute(id: "estrenos")) {
                        ForEach(model.airings.prefix(12)) { AiringCard(airing: $0) }
                    }
                }
                Section {
                    ForEach(model.visibleShelves) { plan in shelf(plan).id(plan.id) }
                    if model.needsSources { sourcesFallback }
                } header: {
                    if model.hasKindSplit {
                        DSSegmented(options: [("series", "Series"), ("movie", "Películas")], selection: Binding(get: { model.kind }, set: { new in Task { await model.setKind(new) } }))
                            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
                            .background(.bar)
                    }
                }
            }
            .padding(.bottom, DS.Space.s14)   // aire bajo la última fila: la barra de pestañas no la tapa
        }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .navigationDestination(for: ShelfRoute.self) { route in
            if route.id == "estrenos" { UpcomingScreen(observer: observer) } else { ListGridView(observer: observer, shelfID: route.id) }
        }
    }

    // MARK: estantes
    private func shelf(_ plan: ShelfPlan) -> some View {
        let items = model.items(for: plan)
        return Shelf(title: shelfTitle(plan), meta: shelfMeta(plan), logo: plan.style == .plain ? nil : plan.list.logo, symbol: shelfSymbol(plan),
                     route: ShelfRoute(id: plan.id), loading: model.isLoading(shelf: plan) && items.isEmpty) {
            ForEach(items) { s in
                ShelfPoster(suggestion: s, style: plan.style, inList: plan.id != "watchlist" && model.watchlistKeys.contains(s.imdb)) { dismissed in Task { await model.dismiss(dismissed) } }   // en «Lo tuyo» todo está en tu lista: la etiqueta sobra
            }
        }
    }

    /// Sin ninguna fuente tuya: lo más popular de Stremio y una invitación (un botón, no una tarjeta gris).
    @ViewBuilder private var sourcesFallback: some View {
        if !model.mosaic.isEmpty {
            Shelf(title: Text("Lo más popular en Stremio"), meta: Text("Sin Trakt ni Orbital, esto es lo que ve todo el mundo"), symbol: "flame") {
                ForEach(model.mosaic) { s in
                    ShelfPoster(suggestion: s, style: .plain, inList: false) { dismissed in Task { await model.dismiss(dismissed) } }
                }
            }
        }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Label { Text("Conecta Trakt o tu Orbital").font(DS.TextRecipe.cardTitle.font.weight(.semibold)).foregroundStyle(DS.text) } icon: { Image(systemName: "link").foregroundStyle(DS.textMuted) }
            Text("Tu watchlist, tus recomendaciones y el Top 10 de tus plataformas aparecen aquí.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            NavigationLink(value: SettingsRoute()) { Label("Abrir Ajustes", systemImage: "gearshape") }
                .buttonStyle(.glass).controlSize(.large)
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    // MARK: destacado
    private func featuredTile(_ featured: ParaTiModel.Featured) -> some View {
        let s = featured.item
        let route = s.route
        return HeroCard(title: s.title, background: s.wide, logo: s.logo, eyebrow: Text(reasonKey(featured.reason)), accentEyebrow: true,
                        data: factStrings(s).first.map { [$0] } ?? []) {
            // «Ver» y «Más» en un renglón; con letra grande, uno debajo del otro.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) { watchButton(s); moreMenu(s) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { watchButton(s); moreMenu(s) }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
        .onTapGesture { openTitle = route }
        .accessibilityAction(named: Text("Ver ficha")) { openTitle = route }
    }

    /// «Ver» (película) o «Ver la serie» (abre su ficha: sugerir un episodio suelto casi siempre es el equivocado), como la TV.
    private func watchButton(_ s: Suggestion) -> some View {
        Button {
            if s.kind == "series" { openTitle = s.route } else { Task { await env.play(s) } }
        } label: {
            Label(s.kind == "series" ? "Ver la serie" : "Ver", systemImage: "play.fill").lineLimit(1)
        }
        .dsArtButton(featuredTint.colors)
    }

    private func moreMenu(_ s: Suggestion) -> some View {
        Menu { SuggestionActions(suggestion: s, includeWatch: false) { dismissed in Task { await model.dismiss(dismissed) } } } label: {
            Label("Más", systemImage: "ellipsis").lineLimit(1)
        }
        .buttonStyle(.glass)
    }

    private func reasonKey(_ reason: ParaTiModel.FeaturedReason) -> LocalizedStringKey {
        switch reason {
        case .recommendedByTrakt: "Recomendada por Trakt"
        case .rank(let n, let platform): "N.º \(n) en \(platform)"
        case .trending: "En tendencia"
        case .other(let r): badgeKey(r)
        }
    }
}

/// La lista completa de un estante, en cuadrícula (el mismo título y logo del encabezado que se tocó).
struct ListGridView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    let shelfID: String
    private var model: ParaTiModel { observer.model }

    var body: some View {
        ScrollView {
            if let plan = model.shelves.first(where: { $0.id == shelfID }) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    HStack(spacing: DS.Space.s3) {
                        if plan.style != .plain, let logo = plan.list.logo { DSPlatformLogo(url: logo) }
                        if let meta = shelfMeta(plan) { meta.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(2) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    if plan.splitsKinds {
                        DSSegmented(options: [("series", "Series"), ("movie", "Películas")], selection: Binding(get: { model.kind }, set: { new in Task { await model.setKind(new) } }))
                            .padding(.horizontal, DS.Space.gutter)
                    }
                    let items = model.items(for: plan)
                    if items.isEmpty && !model.isLoading(shelf: plan) {
                        DSNotice(text: "Nada por aquí por ahora.").padding(.horizontal, DS.Space.gutter)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                            ForEach(items) { s in
                                ShelfPoster(suggestion: s, style: plan.style == .top10 ? .platform : plan.style, inList: model.watchlistKeys.contains(s.imdb)) { dismissed in Task { await model.dismiss(dismissed) } }
                            }
                        }
                        .padding(.horizontal, DS.Space.gutter)
                    }
                }
                .padding(.bottom, DS.Space.s14)
                .navigationTitle(shelfTitle(plan))
            }
        }
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// El calendario completo («Por día» · «Semana»): la vista de Próximos estrenos de siempre, abierta desde el encabezado del estante.
struct UpcomingScreen: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>

    var body: some View {
        ScrollView { UpcomingView(observer: observer).padding(.bottom, DS.Space.s14) }
            .background(Backdrop())
            .navigationTitle("Próximos estrenos").navigationBarTitleDisplayMode(.inline)
    }
}
