import SwiftUI
import OrbitalCore
import OrbitalModels

/// Para ti › Listas: el feed de estantes (destacado, Series · Películas, un estante por lista) con sus secciones.

/// «Para ti › Listas»: el filtro Todo · Series · Películas, un destacado y los estantes (cada uno dice de dónde viene).
struct ListsView: View {
    var observer: ModelObserver<ParaTiModel>
    /// «Decide por mí» (en un iPhone angosto vive en el índice de arriba).
    var onDecide: () -> Void = {}
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openTitle: TitleRoute?
    /// Premios, tus listas de Trakt y «Por año».
    /// Uno para toda la app: cambiar entre mosaico y listas ya no lo vuelve a pedir todo (Mi lista, años, estudios).
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    /// El grupo que estás viendo (el índice de arriba lo marca).
    @State private var activeSection: CollectionSection = .forYou
    /// Saltos elegidos en el índice (el toque háptico es de esos, no de cada sección que pasa al deslizar).
    @State private var jumps = 0
    /// Modo demostración (`-demo-collection`): la lista que se abre sola para las capturas.
    @State private var demoCollection: CollectionRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var model: ParaTiModel { observer.model }

    /// Lo general: todo lo que no es una lista tuya ni una plataforma.
    private var generalShelves: [ShelfPlan] {
        // Tus recomendaciones de Trakt viven en Inicio («Sugerencias para ti»): aquí no se repiten.
        model.visibleShelves.filter { $0.list.group != .platforms && listSource($0) == nil && $0.id != "recs" }
    }

    /// Si un estante es una lista tuya, de dónde: tu watchlist, tus series y tus listas son de Trakt; los catálogos de tus
    /// complementos, de cada complemento.
    private func listSource(_ plan: ShelfPlan) -> ListSource? {
        if plan.id == "watchlist" || plan.id == "mine" || plan.id.hasPrefix("list:") { return .trakt }
        if plan.id.hasPrefix("addon:") { return .addon }
        return nil
    }

    /// Una tarjeta del grupo de listas: el nombre, su pila de pósters y adónde lleva.
    struct ListCardItem: Identifiable {
        let id: String, name: String, posters: [String], count: Int?
        /// Un estante abre su lista completa; una colección, la suya.
        var shelf: ShelfRoute?
        var collection: CollectionRoute?
    }

    private var traktLists: [ListCardItem] {
        model.visibleShelves.filter { listSource($0) == .trakt }.map(card)
    }

    /// Los catálogos de tus complementos. «Mi lista» ya no va aquí: vive en Inicio y en tu watchlist de Trakt.
    private var addonCards: [ListCardItem] {
        model.visibleShelves.filter { listSource($0) == .addon }.map(card)
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

    /// Modo demostración (`-demo-shelf id`): baja hasta ese estante al abrir, para las capturas. `-demo-section seasons|genres`
    /// baja hasta ese grupo de colecciones y `-demo-collection genre:accion` (o `season:halloween`) abre esa lista.
    private func demoScroll(_ proxy: ScrollViewProxy) async {
        #if DEBUG
        guard Demo.isOn else { return }
        if let id = Demo.shelf {
            try? await Task.sleep(for: .seconds(3))   // Demo: espera a que carguen las capturas
            proxy.scrollTo(id, anchor: .top)
        }
        if let name = Demo.section, let section = CollectionSection.allCases.first(where: { "\($0)" == name }) {
            try? await Task.sleep(for: .seconds(3))   // Demo: espera a que carguen las capturas
            proxy.scrollTo(section, anchor: .top)
        }
        if let open = Demo.collection?.split(separator: ":"), open.count == 2 {
            try? await Task.sleep(for: .seconds(2))   // Demo: espera a que carguen las capturas
            demoCollection = CollectionRoute(kind: open[0] == "genre" ? .genre : .season, id: String(open[1]))
        }
        #endif
    }

    private func scroller(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // Un `VStack` (no perezoso): son pocos grupos y así el índice puede saltar a cualquiera; lo pesado de adentro
            // (las tiras) sí es perezoso.
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                // Para ti B (docs/producto/inicio-benchmark/para-ti/): el mosaico como portada, un círculo por cada parte y
                // «¿Qué vemos hoy?». El destacado, «Porque viste» y los estrenos viven en Inicio.
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    let walls = (model.mosaic.isEmpty ? generalShelves.flatMap { model.items(for: $0) } : model.mosaic).map(\.poster)
                    if !walls.isEmpty { MosaicCover(posters: walls) { model.mode = .mosaic }.perfTag("paraTi.hero") }
                    SectionCircles(items: CollectionSection.allCases.filter(isShown).map { .init(id: $0, title: $0.title, symbol: $0.symbol) }) { section in
                        activeSection = section
                        jumps += 1
                        withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo(section, anchor: .top) }
                    }
                    DecideCard(posters: Array(walls.dropFirst(3).prefix(3)), onOpen: onDecide)
                    if model.hasKindSplit {
                        DSKindFilter(kind: Binding(get: { model.kind == KindFilter.all.rawValue ? "" : model.kind },
                                                   set: { new in Task { await model.setKind(new.isEmpty ? KindFilter.all.rawValue : new) } }), icons: true)
                            .frame(maxWidth: .infinity)
                    }
                    DSGroupTitle(title: Text("Ahora"), meta: Text("Lo que se está viendo"))
                    if walls.isEmpty, model.shelves.isEmpty, model.isLoading { FeedSkeleton() }   // la primera vez, mientras llega
                    ForEach(generalShelves) { plan in shelf(plan).id(plan.id).perfTag("paraTi.shelf") }
                    // Lo nuevo en tus plataformas (TMDB): series con episodios recientes y películas recién llegadas.
                    if !model.newOnPlatforms.isEmpty {
                        // En panorámicas (otro formato: se reconoce sin leerla), con la plataforma en la esquina.
                        Shelf(title: Text("Nuevo en tus plataformas"), eyebrow: Text("Episodios de estas semanas y películas recién llegadas")) {
                            ForEach(model.newOnPlatforms) { s in
                                TitleNavigationLink(route: s.route) {
                                    WideCard(art: s.wide, logo: s.logo, title: s.title, badge: Text(badgeKey(s.reason)),
                                             caption: Text(verbatim: s.title), platform: s.platformName)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { SuggestionActions(suggestion: s) { dismissed in Task { await model.dismiss(dismissed) } } }
                            }
                        }
                        .id("new-on-platforms")   // `-demo-shelf new-on-platforms` baja hasta aquí
                    }
                    if model.needsSources { sourcesFallback }
                }
                .modifier(SectionSpy(section: .forYou, active: $activeSection))
                // Las colecciones (con su carácter: en carrusel, con peso y reflejo), justo después de lo general.
                // Plataformas, Estudios, Premios y Por año, juntas y con el mismo aire entre ellas (el reflejo ya separa).
                VStack(alignment: .leading, spacing: DS.Collections.groupGap) {
                    if !model.platformHubs.isEmpty { platforms.modifier(SectionSpy(section: .platforms, active: $activeSection)) }
                    if collections.model.tmdbReady {
                        studiosSection.modifier(SectionSpy(section: .studios, active: $activeSection))
                        seasonsSection.modifier(SectionSpy(section: .seasons, active: $activeSection))
                        genresSection.modifier(SectionSpy(section: .genres, active: $activeSection))
                    }
                    awards.modifier(SectionSpy(section: .awards, active: $activeSection))
                    if collections.model.traktLinked { yearsSection.modifier(SectionSpy(section: .years, active: $activeSection)) }
                }
                // Al final, las listas: las de Trakt y las de tus complementos, aparte.
                if !traktLists.isEmpty { listGroup(title: "Listas de Trakt", source: .trakt, cards: traktLists).modifier(SectionSpy(section: .trakt, active: $activeSection)) }
                if !addonCards.isEmpty { listGroup(title: "De tus complementos", source: .addon, cards: addonCards).modifier(SectionSpy(section: .addons, active: $activeSection)) }
                // Lo que ves (reemplaza «Tu año», que vive adentro) y, debajo, Colecciones (la repisa del canon).
                if collections.model.traktLinked {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        DSSectionHead(title: Text("Lo que ves"), source: .trakt, eyebrow: Text("Lo que viste, contado"))
                        WatchingCardLoader().accessibilityIdentifier("paraTi-your-year")
                        CollectionsCardLoader()
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
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }

        .openingTitles(item: $openTitle)   // en el iPad y la Mac, en el panel de la derecha
        .navigationDestination(for: PlatformRoute.self) { route in
            if let hub = model.platformHubs.first(where: { $0.brand == route.brand }) { PlatformRankingsView(observer: observer, hub: hub) }
        }
        .navigationDestination(for: CollectionRoute.self) { route in CollectionGridView(collections: collections, route: route) }
        .navigationDestination(item: $demoCollection) { route in CollectionGridView(collections: collections, route: route) }
        .task { await collections.model.loadMyList() }
        .navigationDestination(for: ShelfRoute.self) { route in
            if route.id == "estrenos" { UpcomingScreen(observer: observer) } else { ListGridView(observer: observer, collections: collections, shelfID: route.id) }
        }
    }

    // MARK: tus plataformas
    /// Cada plataforma, una tarjeta con su top 3 en abanico; tocarla abre sus rankings.
    private var platforms: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSGroupTitle(title: Text("Plataformas"), meta: Text("Sus rankings de hoy"))
            CenteredCarousel(items: model.platformHubs, id: \.id, cardWidth: DS.PlatformFan.width, reflected: true) { hub in
                NavigationLink(value: PlatformRoute(brand: hub.brand)) {
                    PlatformFanCard(name: hub.name, logo: hub.logo, posters: model.cover(of: hub).map { Optional($0.poster) },
                                    tint: DS.PlatformTint.color(hub.brand))
                        .rowReflection(weight: DS.PlatformTint.color(hub.brand))
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
    /// Ir a una sección (el filtro Todo · Películas · Series va arriba de la lista, el mismo de toda la app).
    private func sectionMenu(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            if ParaTiView.narrow {
                Button("Decide por mí", systemImage: "dice", action: onDecide)
                Divider()
            }
            ForEach(CollectionSection.allCases.filter(isShown), id: \.self) { section in
                Button {
                    activeSection = section
                    jumps += 1
                    withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo(section, anchor: .top) }
                } label: {
                    // Cada sección con su ícono; la que ves, con ✓ al lado.
                    Label { activeSection == section ? Text("\(section.title)\(Text(verbatim: "  ✓"))") : section.title } icon: { Image(systemName: section.symbol) }
                }
            }
        } label: { Image(systemName: "list.bullet.indent") }
        .accessibilityLabel(Text("Ir a una sección"))
        .accessibilityIdentifier("paraTi-sections")
        .sensoryFeedback(.selection, trigger: jumps)   // solo al elegir una sección (no en cada una al deslizar)
    }

    private func isShown(_ section: CollectionSection) -> Bool {
        switch section {
        case .forYou: true
        case .trakt: !traktLists.isEmpty
        case .addons: !addonCards.isEmpty
        case .platforms: !model.platformHubs.isEmpty
        case .awards: !collections.model.awards.isEmpty
        case .studios, .seasons, .genres: collections.model.tmdbReady
        case .years: collections.model.traktLinked
        case .airings: false   // los estrenos viven en Inicio («Lo nuevo de lo tuyo»)
        case .yourYear: collections.model.traktLinked
        }
    }

    /// Un grupo de listas (de Trakt o de tus complementos): tarjetas de dos en dos que abren la lista completa.
    private func listGroup(title: LocalizedStringKey, source: ListSource, cards: [ListCardItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title).padding(.horizontal, DS.Space.gutter)
            LazyVGrid(columns: DS.Poster.pairColumns(spacing: DS.Space.s3, wideMin: DS.Poster.stillWideMin), spacing: DS.Space.s3) {
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
        // El mismo orden que la repisa de Colecciones (Óscar, Palma, Ariel…), para que las dos no se contradigan.
        let order = Canon.awardOrder
        let all = collections.model.awards.sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSGroupTitle(title: Text("Premios"), meta: Text("Los ganadores, del más reciente"))
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
            DSGroupTitle(title: Text("Estudios"), meta: Text("Lo más visto de cada uno"))
            CenteredCarousel(items: collections.model.studios.map { StudioItem(id: $0.id, name: $0.name) }, id: \.id, cardWidth: DS.PlatformFan.width, reflected: true) { studio in
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

    /// Temporadas: Halloween, Día de Muertos, Navidad, San Valentín y Verano (la de hoy primero), cada una con sus tres títulos
    /// más vistos, su ícono y su nombre al pie y el halo de su color.
    private var seasonsSection: some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSGroupTitle(title: Text("Temporadas"), meta: Text("La de ahora, primero"))
            CenteredCarousel(items: collections.model.seasons, id: \.slug, cardWidth: DS.PlatformFan.width, reflected: true) { season in
                let name = Strings.tr(season.title, language: language)
                NavigationLink(value: CollectionRoute(kind: .season, id: season.slug)) {
                    CollectionCard(title: Text(verbatim: name), detail: Text(verbatim: Strings.tr(season.blurb, language: language)), name: name,
                                   posters: (collections.model.seasonItems[season.slug] ?? []).prefix(3).map { Optional($0.poster) },
                                   tint: DS.Collections.season(season.slug), captioned: false) {
                        CollectionIconEmblem(slug: season.slug, name: name)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("season-\(season.slug)")
                .task { await collections.model.loadSeason(season.slug) }
            }
        }
    }

    /// Lo mejor del género: el Top 10 del año de cada género (TMDB, por nota), con su ícono y su nombre al pie.
    private var genresSection: some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSGroupTitle(title: Text("Géneros"), meta: Text("Las mejor calificadas del año"))
            CenteredCarousel(items: collections.model.genres, id: \.slug, cardWidth: DS.PlatformFan.width, reflected: true) { genre in
                let name = Strings.tr(genre.title, language: language)
                NavigationLink(value: CollectionRoute(kind: .genre, id: genre.slug)) {
                    CollectionCard(title: Text(verbatim: name), detail: Text("Las mejor calificadas del año"), name: name,
                                   posters: (collections.model.genreCharts[genre.slug]?.items ?? []).prefix(3).map { Optional($0.poster) },
                                   tint: DS.Collections.studio, captioned: false) {
                        CollectionIconEmblem(slug: genre.slug, name: name)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("genre-\(genre.slug)")
                .task { await collections.model.loadGenre(genre.slug) }
            }
        }
    }

    /// Por año: cada año con cuatro de sus películas (las premiadas, y si faltan, lo más popular).
    private var yearsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSGroupTitle(title: Text("Años"), meta: Text("Lo más popular de cada año"))
            CenteredCarousel(items: collections.model.years, id: \.self, cardWidth: DS.Collections.yearWidth, reflected: true) { year in
                NavigationLink(value: CollectionRoute(kind: .year, id: String(year))) {
                    YearCard(year: year, posters: collections.model.yearPosters[year] ?? []).rowReflection()
                }
                .buttonStyle(.plain)
                .task { await collections.model.loadYearPosters(year) }
            }
        }
    }

    // MARK: estantes
    /// De dónde viene una fila general: lo de Trakt (recomendadas, tendencias, populares), un complemento (sus catálogos), o
    /// tu Orbital. Lo popular de Cinemeta que todavía manda la consola va sin sello.
    private func shelfSource(_ plan: ShelfPlan) -> ListSource? {
        switch plan.id {
        case "recs", "trend", "popular", "mine", "watchlist": return .trakt
        case "cinemeta": return nil
        default:
            if plan.id.hasPrefix("list:") { return .trakt }
            if plan.id.hasPrefix("addon:") || plan.list.source == ForYouList.addonSource { return .addon }
            if plan.list.source == ListSource.criticsOrigin { return .critics }   // «Aprobadas por la crítica», de la consola
            return model.source == .console ? .orbital : nil
        }
    }

    private func shelf(_ plan: ShelfPlan) -> some View {
        let items = model.items(for: plan)
        // El porqué arriba del título (como una revista) y los pósters con su reflejo: los renglones con más carácter.
        return Shelf(title: shelfTitle(plan),
                     route: ShelfRoute(id: plan.id), loading: model.isLoading(shelf: plan) && items.isEmpty, source: shelfSource(plan), eyebrow: shelfMeta(plan),
                     reflected: plan.style != .top10) {   // el Top 10 no lleva reflejo: abajo van su ▲ ▼ y la cifra
            ForEach(items) { s in
                ShelfPoster(suggestion: s, style: plan.style, inList: plan.id != "watchlist" && model.watchlistKeys.contains(s.imdb), badge: model.badges[s.imdb]) { dismissed in Task { await model.dismiss(dismissed) } }   // en «Tu watchlist» todo está ahí: el marcador sobra
            }
        }
        // Los Top 10 (y los rankings de plataformas), con sus pósters pedidos en cuanto llega la lista.
        .task(id: items.first?.imdb) { if plan.style == .top10 || plan.style == .platform { ImagePipeline.shared.prefetchPosters(items.prefix(DS.Size.searchPrefetch).map(\.poster)) } }
    }

    /// Sin ninguna fuente tuya: lo que está en tendencia en Trakt y una invitación (un botón, no una tarjeta gris).
    @ViewBuilder private var sourcesFallback: some View {
        if !model.mosaic.isEmpty {
            Shelf(title: Text("En tendencia"), meta: Text("Lo que más se está viendo ahora"), source: .trakt) {
                ForEach(model.mosaic) { s in
                    ShelfPoster(suggestion: s, style: .plain, inList: false) { dismissed in Task { await model.dismiss(dismissed) } }
                }
            }
        }
        DSEmptyState(symbol: "link", title: Text("Conecta Trakt o tu Orbital"),
                     message: Text("Tu watchlist, tus recomendaciones y el Top 10 de tus plataformas aparecen aquí.")) {
            NavigationLink(value: SettingsRoute()) { Label("Abrir Ajustes", systemImage: "gearshape") }
        }
    }
}
