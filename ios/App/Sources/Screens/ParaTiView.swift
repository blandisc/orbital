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
    /// «Decide por mí» abierto.
    @State private var deciding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init() { _model = StateObject(wrappedValue: ModelObserver(ParaTiModel(AppEnvironment.shared.services))) }

    var body: some View {
        let m = model.model
        VStack(spacing: DS.Space.s2) {
            if m.isGeneric, m.mode == .mosaic, !m.mosaic.isEmpty {
                Text("Lo más popular en Stremio. Conecta Trakt en Ajustes y el mosaico se arma con lo tuyo.")
                    .font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.gutter)
            }
            if let error = m.error, m.mosaic.isEmpty, m.lists.isEmpty { DSNotice(verbatim: env.message(error)).padding(.horizontal, DS.Space.gutter) }
            switch m.mode {
            case .mosaic:
                Mosaic(items: m.mosaic, watchlistKeys: m.watchlistKeys, demoFocus: demoFocusImdb, onDismiss: { s in Task { await m.dismiss(s) } },
                       onFocusChange: { new in
                           // Sin nada elegido (al abrir, o al pasar de largo) no hay pie; elegir una lo muestra.
                           focused = new
                           if let new { focusedArt = new.wide }
                       }, onOpen: { openTitle = $0.route })
                // La pieza elegida, contada sobre el pie del mosaico (flota: el mosaico no cambia de alto al elegir o soltar).
                .overlay(alignment: .bottom) {
                    if DS.Mosaic.uniform, let item = focused {
                        // Como la TV: el motivo tal cual, y una serie sugerida abre su ficha («Ver la serie»), no un episodio al azar.
                        MosaicCaption(reason: Text(badgeKey(item.reason)), title: item.title, logo: item.logo,
                                      data: (factStrings(item).first ?? "").components(separatedBy: " · "), accent: tint.colors, isSeries: item.kind == "series",
                                      open: { openTitle = item.route },
                                      watch: { if item.kind == "series" { openTitle = item.route } else { Task { await env.play(item) } } }) {
                            SuggestionActions(suggestion: item, includeWatch: false) { s in Task { await m.dismiss(s) } }
                        }
                        .padding(DS.Space.s4)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                        .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(item.imdb)
                    }
                }
            case .lists: ListsView(observer: model)
            }
        }
        .padding(.top, DS.Space.s3)   // el mismo aire bajo el título que Inicio
        .background(Backdrop(tint: m.mode == .mosaic ? tint.colors : nil))
        .task(id: m.mode == .mosaic ? focusedArt : nil) { await tint.load(m.mode == .mosaic ? focusedArt : nil) }
        .navigationTitle("Para ti").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones
        .toolbar {
            // «Decide por mí»: una sola propuesta, por tiempo y ánimo.
            ToolbarItem(placement: .topBarTrailing) {
                Button { deciding = true } label: { Image(systemName: "dice") }.accessibilityLabel(Text("Decide por mí"))
            }
            // Un solo selector en la pantalla (Todo · Series · Películas, en Listas): mosaico ↔ listas es este botón.
            ToolbarItem(placement: .topBarTrailing) {
                Button { m.mode = m.mode == .mosaic ? .lists : .mosaic } label: {
                    Image(systemName: m.mode == .mosaic ? "list.bullet.rectangle" : "square.grid.2x2")
                }
                .accessibilityLabel(m.mode == .mosaic ? Text("Ver las listas") : Text("Ver el mosaico"))
                .accessibilityIdentifier("paraTi-mode")
                .sensoryFeedback(.selection, trigger: m.mode)
            }
            // «Actualizar»: en Listas, deslizando hacia abajo; el mosaico no se desliza, así que ahí es un botón.
            if m.mode == .mosaic {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(m.isLoading).accessibilityLabel(Text("Actualizar"))
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .task {
            #if DEBUG
            if Demo.isOn, Demo.open == "lists" || Demo.mode == "lists" { m.mode = .lists }
            if Demo.isOn, Demo.mode == "mosaic" { m.mode = .mosaic }
            if Demo.isOn, Demo.open == "decide" { Task { try? await Task.sleep(for: .seconds(4)); deciding = true } }   // cuando ya cargó lo que se sugiere
            if let start = Demo.startMode { m.mode = start == "lists" ? .lists : .mosaic }
            #endif
            await m.load()
        }
        .refreshable { await m.refresh() }
        .sheet(isPresented: $deciding) {
            DecideView(pool: (m.because?.items ?? []) + m.mosaic + m.visibleShelves.flatMap { m.items(for: $0) }, sources: decideSources(m)) { openTitle = $0 }
        }
        .animation(DS.Motion.base(reduceMotion), value: m.mode)
        .animation(DS.Motion.base(reduceMotion), value: focused?.imdb)
    }

    /// «¿Qué vemos?» › De dónde: «Porque viste», lo nuevo en tus plataformas y cada estante que se ve (con su nombre).
    private func decideSources(_ m: ParaTiModel) -> [DecideModel.Source] {
        let language = env.services.appSettings.uiLanguage
        var out: [DecideModel.Source] = []
        if let because = m.because { out.append(.init(id: "because", name: String(format: Strings.tr("Porque viste %@", language: language), because.seed.title), items: because.items)) }
        if !m.newOnPlatforms.isEmpty { out.append(.init(id: "new", name: Strings.tr("Nuevo en tus plataformas", language: language), items: m.newOnPlatforms)) }
        for plan in m.visibleShelves {
            let name: String = switch plan.id {
            case "watchlist": Strings.tr("Tu watchlist", language: language)
            case "mine": Strings.tr("Tus series", language: language)
            case "recs": Strings.tr("Recomendadas", language: language)
            case "trend": Strings.tr("En tendencia", language: language)
            case "popular": Strings.tr("Lo más popular", language: language)
            default: plan.title.isEmpty ? plan.id : plan.title
            }
            out.append(.init(id: plan.id, name: name, items: m.items(for: plan)))
        }
        return out
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
        Button("Guardar", systemImage: "plus") { Task { await env.addToLibrary(suggestion) } }
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
    /// El porqué en el póster («Sale el viernes», «N.º 3 en Netflix»), si lo hay.
    var badge: PosterBadge? = nil
    /// El ancho del póster (más chico dentro de «Porque viste»).
    var width: CGFloat = DS.Poster.railWidth
    /// El reflejo del póster debajo (no en el Top 10: abajo va su ▲ ▼ y la cifra).
    var reflected = false
    let onDismiss: (Suggestion) -> Void
    @State private var taps = 0

    var body: some View {
        Group {
            if style == .top10, let rank = suggestion.rank {
                NavigationLink(value: suggestion.route) { RankedPosterCard(rank: rank, title: suggestion.title, poster: suggestion.poster, movement: suggestion.movement, isNew: suggestion.isNew).titleZoomSource(suggestion.route) }.buttonStyle(.plain)
            } else {
                TitleLink(route: suggestion.route, badge: badge.map(badgeText), bookmarked: inList, rank: style == .platform ? suggestion.rank : nil, width: width,
                          detail: yearAndKind(year: suggestion.year.map(String.init) ?? "", kind: suggestion.kind), reflected: reflected)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { taps += 1 })
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
        .contextMenu { SuggestionActions(suggestion: suggestion, onDismiss: onDismiss) }
    }
}

/// «Sale hoy», «Sale mañana», «Sale el viernes» o «N.º 3 en Netflix».
@MainActor func badgeText(_ badge: PosterBadge) -> LocalizedStringKey {
    switch badge {
    case .rank(let n, let platform): return "N.º \(n) en \(platform)"
    case .airs(let day):
        if Calendar.current.isDateInToday(day) { return "Sale hoy" }
        if Calendar.current.isDateInTomorrow(day) { return "Sale mañana" }
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(AppEnvironment.shared.uiLocale))
        return "Sale el \(weekday)"
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
    let brand = plan.list.brand.flatMap { brand in Tmdb.platforms.first { $0.brand == brand }?.name } ?? plan.list.brand
    // Sin marca no se puede nombrar («Top 10 en »): se deja el título de la TV.
    if plan.id.hasPrefix("chart:") { return brand.map { Text("Top 10 en \($0)") } }
    if plan.id.hasPrefix("jw:") { return brand.map { Text("Tendencias en \($0)") } }
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


/// El filtro de «Para ti › Listas»: todo, solo series o solo películas.
enum KindFilter: String, CaseIterable, Identifiable {
    case all, series, movie
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self { case .all: "Todo"; case .series: "Series"; case .movie: "Películas" }
    }
}

/// «Para ti › Listas»: el filtro Todo · Series · Películas, un destacado y los estantes (cada uno dice de dónde viene).
struct ListsView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openTitle: TitleRoute?
    /// Los colores del arte del destacado: su «Ver» toma el color claro, como en la TV.
    @StateObject private var featuredTint = ArtTint()
    /// La posición del carrusel del destacado (vuelta infinita: la tarjeta es la posición módulo cuántas hay).
    @State private var featuredSlot: Int?
    /// Premios, tus listas de Trakt y «Por año».
    /// Uno para toda la app: cambiar entre mosaico y listas ya no lo vuelve a pedir todo (Mi lista, años, estudios).
    @StateObject private var collections = ModelObserver(Self.sharedCollections)
    @MainActor static let sharedCollections = CollectionsModel(AppEnvironment.shared.services)
    /// El grupo que estás viendo (el índice de arriba lo marca).
    @State private var activeSection: CollectionSection = .forYou
    /// Saltos elegidos en el índice (el toque háptico es de esos, no de cada sección que pasa al deslizar).
    @State private var jumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var model: ParaTiModel { observer.model }

    /// Lo general: todo lo que no es una lista tuya ni una plataforma.
    private var generalShelves: [ShelfPlan] { model.visibleShelves.filter { $0.list.group != .platforms && listSource($0) == nil } }

    /// Si un estante es una lista tuya, de dónde: tu watchlist, tus series y tus listas son de Trakt; los catálogos de tus
    /// complementos, de Stremio.
    private func listSource(_ plan: ShelfPlan) -> ListSource? {
        if plan.id == "watchlist" || plan.id == "mine" || plan.id.hasPrefix("list:") { return .trakt }
        if plan.id.hasPrefix("addon:") { return .stremio }
        return nil
    }

    /// Una tarjeta del grupo de listas: el nombre, su pila de pósters y adónde lleva.
    struct ListCardItem: Identifiable {
        let id: String, name: String, posters: [String], count: Int?
        /// Un estante abre su lista completa; Mi lista de Stremio, su colección.
        var shelf: ShelfRoute?
        var collection: CollectionRoute?
    }

    private var traktLists: [ListCardItem] {
        model.visibleShelves.filter { listSource($0) == .trakt }.map(card)
    }

    private var stremioCards: [ListCardItem] {
        var cards: [ListCardItem] = []
        let mine = collections.model.myList
        if !mine.isEmpty {
            cards.append(ListCardItem(id: "mylist", name: Strings.tr("Mi lista", language: env.services.appSettings.uiLanguage),
                                      posters: mine.prefix(2).map(\.poster), count: mine.count, collection: CollectionRoute(kind: .myList, id: "mylist")))
        }
        return cards + model.visibleShelves.filter { listSource($0) == .stremio }.map(card)
    }

    private func card(_ plan: ShelfPlan) -> ListCardItem {
        let items = model.items(for: plan)
        let language = env.services.appSettings.uiLanguage
        let name: String = switch plan.id {
        case "watchlist": Strings.tr("Tu watchlist", language: language)
        case "mine": Strings.tr("Tus series", language: language)
        default: plan.title.isEmpty ? plan.id : plan.title
        }
        return ListCardItem(id: plan.id, name: name, posters: items.prefix(2).map(\.poster), count: items.isEmpty ? nil : items.count, shelf: ShelfRoute(id: plan.id))
    }

    var body: some View {
        ScrollViewReader { proxy in scroller(proxy).task { await demoScroll(proxy) } }
    }

    /// Modo demostración (`-demo-shelf id`): baja hasta ese estante al abrir, para las capturas.
    private func demoScroll(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard Demo.isOn, let id = Demo.shelf else { return }
        try? await Task.sleep(for: .seconds(3))
        proxy.scrollTo(id, anchor: .top)
        #endif
    }

    private func scroller(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // Un `VStack` (no perezoso): son pocos grupos y así el índice puede saltar a cualquiera; lo pesado de adentro
            // (las tiras) sí es perezoso.
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                // Para ti: lo general (el destacado, «Porque viste», las sugerencias), cada fila con su sello.
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    let slides = model.featuredSlides
                    if !slides.isEmpty { featuredCarousel(slides).perfTag("paraTi.hero") }
                    if let because = model.because { becauseCard(because) }
                    ForEach(generalShelves) { plan in shelf(plan).id(plan.id).perfTag("paraTi.shelf") }
                    // Lo nuevo en tus plataformas (TMDB): series con episodios recientes y películas recién llegadas.
                    if !model.newOnPlatforms.isEmpty {
                        // En panorámicas (otro formato: se reconoce sin leerla), con la plataforma en la esquina.
                        Shelf(title: Text("Nuevo en tus plataformas"), eyebrow: Text("Episodios de estas semanas y películas recién llegadas")) {
                            ForEach(model.newOnPlatforms) { s in
                                NavigationLink(value: s.route) {
                                    WideCard(art: s.wide, logo: s.logo, title: s.title, badge: Text(badgeKey(s.reason)),
                                             caption: Text(verbatim: s.title))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { SuggestionActions(suggestion: s) { dismissed in Task { await model.dismiss(dismissed) } } }
                            }
                        }
                    }
                    if model.needsSources { sourcesFallback }
                }
                .modifier(SectionSpy(section: .forYou, active: $activeSection))
                // Las colecciones (con su carácter: en carrusel, con peso y reflejo), justo después de lo general.
                // Plataformas, Estudios, Premios y Por año, juntas y con el mismo aire entre ellas (el reflejo ya separa).
                VStack(alignment: .leading, spacing: DS.Collections.groupGap) {
                    if !model.platformHubs.isEmpty { platforms.reflectionTail().modifier(SectionSpy(section: .platforms, active: $activeSection)) }
                    if collections.model.tmdbReady { studiosSection.reflectionTail().modifier(SectionSpy(section: .studios, active: $activeSection)) }
                    awards.modifier(SectionSpy(section: .awards, active: $activeSection))
                    if collections.model.traktLinked { yearsSection.reflectionTail().modifier(SectionSpy(section: .years, active: $activeSection)) }
                }
                if !model.airings.isEmpty {   // vacío → no se pinta (el calendario completo ya existe: `UpcomingView`)
                    Shelf(title: Text("Próximos estrenos"), meta: Text("Lo que sale de las series que sigues"), route: ShelfRoute(id: "estrenos"), source: .trakt) {
                        ForEach(model.airings.prefix(12)) { AiringCard(airing: $0) }
                    }
                    .modifier(SectionSpy(section: .airings, active: $activeSection))
                }
                // Al final, las listas: las de Trakt y las de Stremio, aparte.
                if !traktLists.isEmpty { listGroup(title: "Listas de Trakt", source: .trakt, cards: traktLists).modifier(SectionSpy(section: .trakt, active: $activeSection)) }
                if !stremioCards.isEmpty { listGroup(title: "Listas de Stremio", source: .stremio, cards: stremioCards).modifier(SectionSpy(section: .stremio, active: $activeSection)) }
                // Tu año (lo que viste, día por día): aquí a la vista, no escondido en tu perfil.
                if collections.model.traktLinked {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        DSSectionHead(title: Text("Tu año"), source: .trakt, eyebrow: Text("Lo que viste, día por día"))
                        NavigationLink { YearView() } label: {
                            HStack(spacing: DS.Space.s3) {
                                Image(systemName: "square.grid.3x3.fill").font(DS.TextRecipe.title.font).foregroundStyle(DS.accent)
                                    .frame(width: DS.Collections.yearIcon, height: DS.Collections.yearIcon)
                                    .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                VStack(alignment: .leading, spacing: DS.Space.s1) {
                                    Text("Tu año en Orbital").recipe(.cardTitle)
                                    Text("Horas, tus días más intensos, lo que más viste y tu mapa de calor").recipe(.footnote).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(DS.textMuted)
                            }
                            .padding(DS.Space.s3)
                            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("paraTi-your-year")
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .modifier(SectionSpy(section: .yourYear, active: $activeSection))
                }
            }
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s14)   // aire bajo la última fila: la barra de pestañas no la tapa
        }
        // Brincar a una sección: un menú en la barra (marca en cuál estás).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { sectionMenu(proxy) }
        }

        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .navigationDestination(for: PlatformRoute.self) { route in
            if let hub = model.platformHubs.first(where: { $0.brand == route.brand }) { PlatformRankingsView(observer: observer, hub: hub) }
        }
        .navigationDestination(for: CollectionRoute.self) { route in CollectionGridView(collections: collections, route: route) }
        .task { await collections.model.loadMyList() }
        .navigationDestination(for: ShelfRoute.self) { route in
            if route.id == "estrenos" { UpcomingScreen(observer: observer) } else { ListGridView(observer: observer, collections: collections, shelfID: route.id) }
        }
    }

    // MARK: tus plataformas
    /// Cada plataforma, una tarjeta con su top 3 en abanico; tocarla abre sus rankings.
    private var platforms: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Tus plataformas", meta: Text("Sus rankings de hoy")).padding(.horizontal, DS.Space.gutter)
            CenteredCarousel(items: model.platformHubs, id: \.id, cardWidth: DS.PlatformFan.width) { hub in
                NavigationLink(value: PlatformRoute(brand: hub.brand)) {
                    PlatformFanCard(name: hub.name, logo: hub.logo, posters: model.cover(of: hub).map { Optional($0.poster) },
                                    tint: DS.PlatformTint.color(hub.brand))
                        .reflected(weight: DS.PlatformTint.color(hub.brand))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("platform-\(hub.brand)")
            }
        }
    }

    // MARK: colecciones
    /// Un estudio para la tira (con su id para `ForEach`).
    struct StudioItem { let id: Int; let name: String }

    /// El índice de arriba: salta a cada grupo.
    /// Un solo menú en la barra para Listas: qué mostrar (Todo · Series · Películas) e ir a una sección. Antes eran dos botones
    /// y, con los demás, el título «Para ti» se cortaba.
    private func sectionMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            if model.hasKindSplit {
                Picker(selection: Binding(get: { KindFilter(rawValue: model.kind) ?? .all }, set: { new in Task { await model.setKind(new.rawValue) } })) {
                    ForEach(KindFilter.allCases) { Text($0.label).tag($0) }
                } label: { Text("Mostrar") }
                .pickerStyle(.inline)
                Divider()
            }
            ForEach(CollectionSection.allCases.filter(isShown), id: \.self) { section in
                Button {
                    activeSection = section
                    jumps += 1
                    withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo(section, anchor: .top) }
                } label: {
                    // Cada sección con su ícono; la que ves, con ✓ al lado.
                    Label { activeSection == section ? section.title + Text(verbatim: "  ✓") : section.title } icon: { Image(systemName: section.symbol) }
                }
            }
        } label: { Image(systemName: model.kind == KindFilter.all.rawValue ? "list.bullet.indent" : "line.3.horizontal.decrease.circle.fill") }
        .accessibilityLabel(Text("Ir a una sección"))
        .accessibilityIdentifier("paraTi-sections")
        .sensoryFeedback(.selection, trigger: jumps)   // solo al elegir una sección (no en cada una al deslizar)
    }

    private func isShown(_ section: CollectionSection) -> Bool {
        switch section {
        case .forYou: true
        case .trakt: !traktLists.isEmpty
        case .stremio: !stremioCards.isEmpty
        case .platforms: !model.platformHubs.isEmpty
        case .awards: !collections.model.awards.isEmpty
        case .studios: collections.model.tmdbReady
        case .years: collections.model.traktLinked
        case .airings: !model.airings.isEmpty
        case .yourYear: collections.model.traktLinked
        }
    }

    /// «Porque viste X»: una tarjeta propia (no una fila más) con lo que viste y lo relacionado.
    private func becauseCard(_ because: (seed: TraktEntry, items: [Suggestion])) -> some View {
        let fromHistory = model.becauseSeeds.map { BecauseSeed(id: $0.imdb, title: $0.title, poster: String(format: ForYou.metahubPoster, $0.imdb)) }
        let seeds = fromHistory.contains { $0.id == because.seed.imdb } ? fromHistory
            : [BecauseSeed(id: because.seed.imdb, title: because.seed.title, poster: String(format: ForYou.metahubPoster, because.seed.imdb))] + fromHistory
        return BecauseCard(style: BecauseStyle(rawValue: env.services.appSettings.becauseStyle) ?? .posters,
                           seeds: seeds, selected: because.seed.imdb,
                           choose: { id in if let seed = model.becauseSeeds.first(where: { $0.imdb == id }) { Task { await model.chooseBecause(seed) } } }) {
            ForEach(because.items) { s in
                ShelfPoster(suggestion: s, style: .plain, inList: model.watchlistKeys.contains(s.imdb), badge: model.badges[s.imdb], width: DS.Collections.relatedPoster) { dismissed in Task { await model.dismiss(dismissed) } }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// Un grupo de listas (de Trakt o de Stremio): tarjetas de dos en dos que abren la lista completa.
    private func listGroup(title: LocalizedStringKey, source: ListSource, cards: [ListCardItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title).padding(.horizontal, DS.Space.gutter)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible())], spacing: DS.Space.s3) {
                ForEach(cards) { c in
                    Group {
                        if let shelf = c.shelf { NavigationLink(value: shelf) { ListCard(name: c.name, source: source, posters: c.posters, count: c.count) } }
                        else if let collection = c.collection { NavigationLink(value: collection) { ListCard(name: c.name, source: source, posters: c.posters, count: c.count) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("list-\(c.id)")
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    /// Premios: cada uno con su estatuilla al frente, sobre sus tres ganadores más recientes.
    @ViewBuilder private var awards: some View {
        let all = collections.model.awards
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSectionHead(title: "Premios", meta: Text("Los ganadores, del más reciente")).padding(.horizontal, DS.Space.gutter)
                CenteredCarousel(items: all, id: \.id, cardWidth: DS.PlatformFan.width) { award in
                    NavigationLink(value: CollectionRoute(kind: .award, id: award.id)) { AwardCard(award: award) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("award-\(award.id)")
                }
            }
        }
    }

    /// Estudios: A24, Pixar, Ghibli… cada uno con sus tres películas más vistas y su nombre al frente.
    private var studiosSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Estudios", meta: Text("Lo más visto de cada uno")).padding(.horizontal, DS.Space.gutter)
            CenteredCarousel(items: collections.model.studios.map { StudioItem(id: $0.id, name: $0.name) }, id: \.id, cardWidth: DS.PlatformFan.width) { studio in
                NavigationLink(value: CollectionRoute(kind: .studio, id: String(studio.id))) {
                    CollectionCard(title: Text(verbatim: studio.name), detail: Text("Lo más visto"), name: studio.name,
                                   posters: (collections.model.studioItems[studio.id] ?? []).prefix(3).map { Optional($0.poster) }, tint: DS.Collections.studio, captioned: false) {
                        StudioEmblem(name: studio.name, logo: collections.model.studioLogos[studio.id])
                    }
                }
                .buttonStyle(.plain)
                .task { await collections.model.loadStudio(studio.id) }
            }
        }
    }

    /// Por año: cada año con cuatro de sus películas (las premiadas, y si faltan, lo más popular).
    private var yearsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "Por año", meta: Text("Lo más popular de cada año")).padding(.horizontal, DS.Space.gutter)
            CenteredCarousel(items: collections.model.years, id: \.self, cardWidth: DS.Collections.yearWidth) { year in
                NavigationLink(value: CollectionRoute(kind: .year, id: String(year))) {
                    YearCard(year: year, posters: collections.model.yearPosters[year] ?? []).reflected()
                }
                .buttonStyle(.plain)
                .task { await collections.model.loadYearPosters(year) }
            }
        }
    }

    // MARK: estantes
    /// De dónde viene una fila general: lo de Trakt (recomendadas, tendencias, populares), lo de Stremio (catálogos), o tu Orbital.
    private func shelfSource(_ plan: ShelfPlan) -> ListSource? {
        switch plan.id {
        case "recs", "trend", "popular", "mine", "watchlist": return .trakt
        case "cinemeta": return .stremio
        default:
            if plan.id.hasPrefix("list:") { return .trakt }
            if plan.id.hasPrefix("addon:") { return .stremio }
            return model.source == .console ? .orbital : nil
        }
    }

    private func shelf(_ plan: ShelfPlan) -> some View {
        let items = model.items(for: plan)
        // El porqué arriba del título (como una revista) y los pósters con su reflejo: los renglones con más carácter.
        return Shelf(title: shelfTitle(plan),
                     route: ShelfRoute(id: plan.id), loading: model.isLoading(shelf: plan) && items.isEmpty, source: shelfSource(plan), eyebrow: shelfMeta(plan)) {
            ForEach(items) { s in
                ShelfPoster(suggestion: s, style: plan.style, inList: plan.id != "watchlist" && model.watchlistKeys.contains(s.imdb), badge: model.badges[s.imdb], reflected: true) { dismissed in Task { await model.dismiss(dismissed) } }   // en «Tu watchlist» todo está ahí: el marcador sobra
            }
        }
        .reflectionTail()
        // Los Top 10 (y los rankings de plataformas), con sus pósters pedidos en cuanto llega la lista.
        .task(id: items.first?.imdb) { if plan.style == .top10 || plan.style == .platform { ImagePipeline.shared.prefetchPosters(items.prefix(DS.Size.searchPrefetch).map(\.poster)) } }
    }

    /// Sin ninguna fuente tuya: lo más popular de Stremio y una invitación (un botón, no una tarjeta gris).
    @ViewBuilder private var sourcesFallback: some View {
        if !model.mosaic.isEmpty {
            Shelf(title: Text("Lo más popular en Stremio"), meta: Text("Sin Trakt ni Orbital, esto es lo que ve todo el mundo")) {
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
    /// Varias de la misma lista del destacado, para pasar con el dedo (como «Seguir viendo» en Inicio), con sus puntos.
    private func featuredCarousel(_ slides: [ParaTiModel.Featured]) -> some View {
        // Una vuelta infinita, como el carrusel de Inicio: las mismas tarjetas repetidas y se empieza a la mitad.
        let copies = slides.count > 1 ? DS.Deck.loopCopies : 1
        let middle = (copies / 2) * slides.count
        let index = (featuredSlot ?? middle) % slides.count
        let current = slides[index]
        return VStack(spacing: DS.Space.s3) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<(copies * slides.count), id: \.self) { slot in featuredTile(slides[slot % slides.count]).containerRelativeFrame(.horizontal) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $featuredSlot)
            .onAppear { if featuredSlot == nil || (featuredSlot ?? 0) >= copies * slides.count { featuredSlot = middle } }
            if slides.count > 1 { PageDots(count: slides.count, index: index) }
        }
        .task(id: current.item.wide) { await featuredTint.load(current.item.wide) }   // «Ver» toma el color del que está al frente
        .sensoryFeedback(.selection, trigger: featuredSlot)
        .onChange(of: slides.map(\.item.id)) { featuredSlot = middle }   // «Actualizar» o Series ↔ Películas: de vuelta al primero
    }

    private func featuredTile(_ featured: ParaTiModel.Featured) -> some View {
        let s = featured.item
        let route = s.route
        return HeroCard(title: s.title, background: s.wide, logo: s.logo, eyebrow: Text(reasonKey(featured.reason)), accentEyebrow: true,
                        data: (factStrings(s).first ?? "").components(separatedBy: " · "), open: { openTitle = route }) {
            HeroActions { watchButton(s); moreMenu(s) }   // con letra grande, uno debajo del otro
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
        .onTapGesture { openTitle = route }
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
    @ObservedObject var collections: ModelObserver<CollectionsModel>
    let shelfID: String
    private var model: ParaTiModel { observer.model }

    private func poster(_ s: Suggestion, _ plan: ShelfPlan) -> some View {
        ShelfPoster(suggestion: s, style: plan.style == .top10 ? .platform : plan.style, inList: plan.id != "watchlist" && model.watchlistKeys.contains(s.imdb)) { dismissed in Task { await model.dismiss(dismissed) } }
    }

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
                    let items = model.items(for: plan)
                    if items.isEmpty && !model.isLoading(shelf: plan) {
                        DSNotice(text: "Nada por aquí por ahora.").padding(.horizontal, DS.Space.gutter)
                    } else if plan.style == .top10 {
                        // Un ranking se lee en su orden: sin ordenar ni filtrar.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                            ForEach(items) { s in poster(s, plan) }
                        }
                        .padding(.horizontal, DS.Space.gutter)
                    } else {
                        SortableGrid(listID: plan.id, items: items, watched: { await collections.model.watchedIDs() },
                             imdbRatings: { items in await collections.model.imdbRatings(items.map { ($0.kind, $0.imdb) }) }) { s in poster(s, plan) }
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


/// A dónde lleva una tarjeta de «Tus plataformas».
struct PlatformRoute: Hashable { var brand: String }

/// Los rankings de una plataforma: su logo con su brillo arriba y, por ranking (Top 10 de Netflix, tendencia de JustWatch;
/// series y películas), los pósters con su número grande en el color de la plataforma. Tocar uno abre su ficha.
struct PlatformRankingsView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    let hub: PlatformHub
    private var model: ParaTiModel { observer.model }
    /// «Series» o «Películas» (pestañas grandes) y cuál de sus listas (pestañas de texto con el subrayado de la marca).
    @State private var kind: String?
    @State private var source: PlatformRanking.Source?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kinds: [String] { ["series", "movie"].filter { k in hub.rankings.contains { $0.kind == k } } }
    private var currentKind: String { kind ?? kinds.first ?? "series" }
    private var sources: [PlatformRanking.Source] {
        var seen = Set<String>()
        return hub.rankings.filter { $0.kind == currentKind }.map(\.source).filter { seen.insert($0.rawValue).inserted }
    }
    private var current: PlatformRanking? {
        let wanted = source.flatMap { s in sources.contains(s) ? s : nil } ?? sources.first
        return hub.rankings.first { $0.kind == currentKind && $0.source == wanted }
    }

    var body: some View {
        let tint = DS.PlatformTint.color(hub.brand)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                HStack(spacing: DS.Space.s4) {
                    PlatformLogoTile(url: hub.logo, name: hub.name, size: DS.PlatformFan.headerLogo, radius: DS.Radius.lg, tint: tint,
                                     glow: DS.PlatformFan.headerGlow)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        if let current { rankingSource(current).recipe(.footnote, color: DS.textMuted) }
                        Text(verbatim: hub.name).recipe(.title)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                // Pestañas grandes: la elegida brilla, la otra se apaga.
                if kinds.count > 1 {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
                        ForEach(kinds, id: \.self) { k in
                            Button { withAnimation(DS.Motion.base(reduceMotion)) { kind = k } } label: {
                                (k == "movie" ? Text("Películas") : Text("Series")).recipe(.title, color: k == currentKind ? DS.text : DS.textFaint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(k == currentKind ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .sensoryFeedback(.selection, trigger: currentKind)
                }
                // Sus listas, como pestañas de texto con el subrayado en el color de la plataforma.
                if sources.count > 1, let current {
                    HStack(spacing: DS.Space.s5) {
                        ForEach(sources, id: \.rawValue) { src in
                            Button { withAnimation(DS.Motion.base(reduceMotion)) { source = src } } label: {
                                VStack(spacing: DS.Space.s2) {
                                    sourceName(src).recipe(.secondary, color: src == current.source ? DS.text : DS.textMuted).fontWeight(.semibold)
                                    Capsule().fill(src == current.source ? tint : .clear).frame(height: DS.PlatformFan.tabUnderline)
                                }
                                .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(src == current.source ? .isSelected : [])
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
                if let current { grid(current, tint: tint) }
            }
            .padding(.vertical, DS.Space.s4)
            .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(Text(verbatim: hub.name)).navigationBarTitleDisplayMode(.inline)
        .task { await model.loadRankings(hub) }
    }

    /// La lista en cuadrícula de dos, con el número grande en el color de la plataforma y su brillo (como hoy).
    @ViewBuilder private func grid(_ ranking: PlatformRanking, tint: Color) -> some View {
        let items = model.items(for: ranking)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible(), spacing: DS.Space.s3)], spacing: DS.Space.s5) {
            if items.isEmpty && model.isLoading(ranking: ranking) { ShelfSkeleton() }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, s in
                NavigationLink(value: s.route) {
                    RankedPosterCard(rank: s.rank ?? index + 1, title: s.title, poster: s.poster, movement: s.movement, isNew: s.isNew, tint: tint)
                        .titleZoomSource(s.route)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .id(ranking.id)
        .transition(.opacity)
    }

    private func sourceName(_ source: PlatformRanking.Source) -> Text {
        switch source { case .netflixTop10: Text("Top 10"); case .justWatch: Text("Tendencia"); case .popular: Text("Lo más popular") }
    }

    private func rankingSource(_ ranking: PlatformRanking) -> Text {
        switch ranking.source {
        case .netflixTop10: Text("Netflix · esta semana")
        case .justWatch: Text("JustWatch · hoy")
        case .popular: Text("TMDB")
        }
    }
}
