import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Para ti › Listas» (Para ti B, docs/producto/inicio-benchmark/para-ti/): la portada del mosaico, un círculo por cada
/// parte, «¿Qué vemos hoy?», el filtro Todo · Series · Películas y los grupos de estantes (cada uno dice de dónde viene).
struct ListsView: View {
    @Environment(\.titleName) var titleName
    var observer: ModelObserver<ParaTiModel>
    /// «Decide por mí», el sorteo (el dado de la barra; en un iPhone angosto, iOS lo pasa al «⋯» de la barra).
    var onDecide: () -> Void = {}
    /// «¿Qué vemos hoy?»: el mazo de Encuentra tu match perfecto.
    var onMatch: () -> Void = {}
    @Environment(AppEnvironment.self) private var env
    /// Premios, tus listas de Trakt, los años y Lo que ves.
    /// Uno para toda la app: cambiar entre mosaico y listas ya no lo vuelve a pedir todo (Mi lista, años, estudios).
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    /// «Lo más popular hoy» (el Top 10 de Trakt): el mismo catálogo de toda la app, que se pide al abrirla (RootView); aquí
    /// solo se lee, sin otra petición.
    @State private var catalog = ModelObserver(AppEnvironment.shared.catalog)
    /// El grupo que estás viendo (el índice de arriba lo marca).
    @State private var activeSection: CollectionSection = .forYou
    /// Para saltar a un grupo desde el índice: con la lista perezosa, `ScrollViewReader.scrollTo` no encontraba uno que aún
    /// no se armaba (el menú no bajaba a «Temporadas»); la posición del `ScrollView` sí lo encuentra.
    @State private var position = ScrollPosition()
    /// Arriba del todo: la barra no pone su desvanecido (el mosaico sigue detrás del título sin un corte).
    @State private var atTop = true
    /// Saltos elegidos en el índice (el toque háptico es de esos, no de cada sección que pasa al deslizar).
    @State private var jumps = 0
    /// Modo demostración (`-demo-collection`): la lista que se abre sola para las capturas.
    @State private var demoCollection: CollectionRoute?
    /// Lo de abajo (plataformas, colecciones, premios, años, tus listas) se arma cuando ya se ve lo de arriba, al deslizar o
    /// al saltar a una sección: armarlo todo de golpe con la primera pantalla ocupaba el hilo principal (y pedía sus
    /// estantes y pósters) justo cuando Para ti debía aparecer (Fernando, 31 oct 2026: tardaba ~5 s en verse).
    @State private var restReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// «Crear una lista»: el nombre que se escribe.
    @State private var naming = false
    @State private var newListName = ""
    private var model: ParaTiModel { observer.model }

    /// Lo general: todo lo que no es una lista tuya ni una plataforma.
    private var generalShelves: [ShelfPlan] {
        // Tus recomendaciones de Trakt viven en Inicio («Sugerencias para ti»): aquí no se repiten.
        model.visibleShelves.filter { $0.list.group != .platforms && listSource($0) == nil && $0.id != "recs" }
    }

    /// Si un estante es una lista tuya, de dónde: tu watchlist, tus series y tus listas son de Trakt; los catálogos de tus
    /// complementos, de cada complemento.
    private func listSource(_ plan: ShelfPlan) -> ListSource? {
        // Tus listas de Letterboxd van con las tuyas de Trakt, en «Tus listas».
        if ["watchlist", ForYou.favoritesList, "mine"].contains(plan.id) || plan.id.hasPrefix("list:") || plan.id.hasPrefix("lb:") { return .trakt }
        if plan.id.hasPrefix("addon:") { return .addon }
        return nil
    }

    /// Una tarjeta del grupo de listas: el nombre, su pila de pósters y adónde lleva.
    struct ListCardItem: Identifiable {
        let id: String, name: String, posters: [String], count: Int?
        /// Abre su lista completa.
        var shelf: ShelfRoute?
    }

    /// «Tuyo»: Mi lista, Favoritos, Tus series y luego tus listas de Trakt, en ese orden.
    private var traktLists: [ListCardItem] {
        let first = ["watchlist", ForYou.favoritesList, "mine"]
        return model.visibleShelves.filter { listSource($0) == .trakt }
            .sorted { (first.firstIndex(of: $0.id) ?? first.count) < (first.firstIndex(of: $1.id) ?? first.count) }
            .map(card)
    }

    /// Los catálogos de tus complementos. «Mi lista» ya no va aquí: vive en Inicio y en tu watchlist de Trakt.
    private var addonCards: [ListCardItem] {
        model.visibleShelves.filter { listSource($0) == .addon }.map(card)
    }

    private func card(_ plan: ShelfPlan) -> ListCardItem {
        let items = model.items(for: plan)
        let language = env.services.appSettings.uiLanguage
        let name: String = switch plan.id {
        case "watchlist": Strings.tr("Mi lista", language: language)
        case ForYou.favoritesList: Strings.tr("Favoritos", language: language)
        case "mine": Strings.tr("Tus series", language: language)
        default: plan.title.isEmpty ? plan.id : plan.title
        }
        return ListCardItem(id: plan.id, name: name, posters: items.prefix(DS.ParaTiB.matchFan).map(\.poster), count: items.isEmpty ? nil : items.count, shelf: ShelfRoute(id: plan.id))
    }

    var body: some View {
        ScrollViewReader { proxy in scroller(proxy).task { await demoScroll(proxy) } }
            .onAppear { Perf.mark("xtab.appear") }   // con `-perf`: de tocar Explorar a verla
            .alert("Nueva lista", isPresented: $naming) {   // ds-exception: pide un nombre: el campo de texto del sistema
                TextField("Nombre", text: $newListName)
                Button("Crear") { createList() }
                    .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancelar", role: .cancel) { newListName = "" }
            } message: { Text("Se crea en Trakt (privada). Agrégale títulos desde su ficha, con «Guardar en…».") }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        newListName = ""
        Task {
            if let problem = await model.createTraktList(named: name) { env.notify(problem, tone: .error) }
            else { env.notify("Lista creada en Trakt", detail: name, tone: .success) }
        }
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
            position.scrollTo(id: section, anchor: .top)
        }
        if let open = Demo.collection?.split(separator: ":"), open.count == 2 {
            try? await Task.sleep(for: .seconds(2))   // Demo: espera a que carguen las capturas
            demoCollection = CollectionRoute(kind: open[0] == "genre" ? .genre : .season, id: String(open[1]))
        }
        #endif
    }

    private func scroller(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // Perezoso (Fernando, 1 nov 2026: «Explorar cambia lento»): al volver a la pestaña solo se acomoda lo que se ve;
            // antes un `VStack` volvía a acomodar todos los grupos (plataformas, colecciones, años, listas) en cada cambio.
            // El índice de arriba sigue saltando a cualquiera (cada grupo tiene su `id`).
            LazyVStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                // Para ti B (docs/producto/inicio-benchmark/para-ti/): el mosaico como portada, un círculo por cada parte y
                // «¿Qué vemos hoy?». El destacado, «Porque viste» y los estrenos viven en Inicio.
                VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                    // Los del mosaico primero y luego los de los estantes, sin repetir: la lista solo crece mientras carga (antes
                    // pasaba de los estantes a 3 del mosaico y luego a 48, y el muro se revolvía dos veces al abrir).
                    let walls = Self.distinct((model.mosaic + generalShelves.flatMap { model.items(for: $0) }).map(\.poster))
                    if !walls.isEmpty { MosaicCover(posters: walls, memory: model.coverWall) { model.mode = .mosaic }.perfTag("paraTi.hero") }
                    // Sin los círculos de íconos (Fernando, 31 oct 2026): el menú de arriba a la derecha lleva a cada sección.
                    // Sin pósters (sin red, o sin TMDB ni Trakt) la tarjeta sigue y lo dice (F8: antes desaparecía mientras el dado y
                    // el mosaico seguían en la barra); adentro, «Sin conexión · Reintentar».
                    let fan = Array(walls.dropFirst(DS.ParaTiB.matchFan).prefix(DS.ParaTiB.matchFan))
                    if !fan.isEmpty || !model.showsFirstSkeleton { MatchTeaser(posters: fan, offline: !env.isOnline, onOpen: onMatch) }
                    // «Lo que se ve hoy» (antes «Ahora», que no decía qué era): su flama, qué trae, y el tipo con palabras debajo
                    // (los tres íconos solos no se entendían). Fernando, 30 oct 2026. Sus estantes son subsecciones: a 24 entre sí.
                    VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                    if !generalShelves.isEmpty || model.showsFirstSkeleton {
                        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                            DSChapterHead(label: CollectionSection.forYou.title, symbol: CollectionSection.forYou.symbol)
                            if model.hasKindSplit {
                                DSKindFilter(kind: Binding(get: { model.kind == KindFilter.all.rawValue ? "" : model.kind },
                                                           set: { new in Task { await model.setKind(new.isEmpty ? KindFilter.all.rawValue : new) } }))
                                    .padding(.horizontal, DS.Space.gutter)
                            }
                        }
                        .id("ahora")   // `-demo-shelf ahora` baja hasta aquí
                    }
                    if walls.isEmpty, generalShelves.isEmpty, model.showsFirstSkeleton { HeroSkeleton() }   // desde el primer cuadro, mientras llega
                    VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    ForEach(Array(generalShelves.enumerated()), id: \.element.id) { i, plan in
                        shelf(plan).entrance("shelf:" + plan.id, order: i).id(plan.id).perfTag("paraTi.shelf")   // entran escalonados
                        // «Lo más popular hoy», una franja más (BX, Fernando, 9 nov 2026): después de la segunda, no arriba.
                        if i == min(Self.popularAfter, generalShelves.count) - 1 { popularToday }
                    }
                    if generalShelves.isEmpty { popularToday }
                    // Lo nuevo en tus plataformas (TMDB): series con episodios recientes y películas recién llegadas.
                    if !model.newOnPlatforms.isEmpty {
                        // En panorámicas (otro formato: se reconoce sin leerla), con la plataforma en la esquina.
                        Shelf(title: Text("Nuevo en tus plataformas"), eyebrow: Text("Episodios y películas recién llegados")) {
                            ForEach(model.newOnPlatforms) { s in
                                TitleNavigationLink(route: s.route) {
                                    WideCard(art: s.wide, logo: s.logo, title: titleName(s.title, id: s.imdb, kind: s.kind), badge: Text(badgeKey(s.reason)),
                                             caption: Text(verbatim: titleName(s.title, id: s.imdb, kind: s.kind)), platform: s.platformName)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { SuggestionActions(suggestion: s) { dismissed in Task { await model.dismiss(dismissed) } } }
                            }
                        }
                        .id("new-on-platforms")   // `-demo-shelf new-on-platforms` baja hasta aquí
                    }
                    }
                    }
                    if model.needsSources { sourcesFallback }
                }
                .modifier(SectionSpy(section: .forYou, active: $activeSection))
                // Las colecciones (con su carácter: en carrusel y con peso), justo después de lo general.
                // Plataformas, Estudios, Premios y Por año, juntas y con el mismo aire entre ellas.
                // Cada colección es una sección: 40 entre rótulos (decisión 2, 31 oct 2026).
                if restReady { rest }
            }
            .scrollTargetLayout()   // los grupos son destinos de `position` (sin `scrollTargetBehavior`, no cambia cómo se desliza)
            .refreshOrbitHost()   // la luna de tirar para actualizar
            .padding(.top, DS.Layout.screenTop)   // el aire bajo el título (antes `ParaTiView` lo ponía afuera)
            .padding(.bottom, DS.Layout.screenBottom)   // aire bajo la última fila: la barra de pestañas no la tapa
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < DS.Size.barScrollHide } action: { _, top in
            atTop = top
            if !top { restReady = true }   // deslizaste: lo de abajo ya hace falta
        }
        .orbitalRefreshable { [model] in await model.refresh() }   // tirar para actualizar, con la luna de Orbital
        // Lo de arriba ya se ve (o ya no va a llegar): entonces lo de abajo. Al volver del mosaico, de una vez.
        .onChange(of: !generalShelves.isEmpty || (!model.isLoading && !model.lists.isEmpty), initial: true) { _, ready in
            if ready { restReady = true }
        }
        .scrollEdgeEffectHidden(atTop, for: .top)
        // Brincar a una sección: un menú en la barra (marca en cuál estás).
        .toolbar {
            // El dado de «Decide por mí» a la vista otra vez (Fernando, 1 nov 2026: escondido en el índice no se encontraba).
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onDecide) { Image(systemName: "dice") }
                    .accessibilityLabel(Text("Decide por mí")).accessibilityIdentifier("paraTi-decide")
            }
            // I10 · el mosaico, en la barra con los demás (antes, un círculo blanco suelto sobre el muro).
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.mode = .mosaic } label: { Image(systemName: "square.grid.3x3") }
                    .accessibilityLabel(Text("Pasear por el mosaico")).accessibilityIdentifier("paraTi-walk-mosaic")
            }
            ToolbarItem(placement: .topBarTrailing) { sectionMenu(proxy) }
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
        }

        .navigationDestination(for: PlatformRoute.self) { route in
            if let hub = model.platformHubs.first(where: { $0.brand == route.brand }) { PlatformRankingsView(observer: observer, hub: hub) }
        }
        .navigationDestination(for: CollectionRoute.self) { route in CollectionGridView(collections: collections, route: route) }
        .navigationDestination(item: $demoCollection) { route in CollectionGridView(collections: collections, route: route) }
        .task { await collections.model.loadMyList() }
        .navigationDestination(for: PopularRoute.self) { _ in PopularGridView(model: catalog.model) }
        .task { if catalog.model.popular.isEmpty, !catalog.model.isLoading { await catalog.model.load() } }   // casi siempre ya llegó
        .navigationDestination(for: ShelfRoute.self) { route in
            ListGridView(observer: observer, collections: collections, shelfID: route.id)
        }
    }

    /// Tras cuántos estantes de «Lo que se ve hoy» va «Lo más popular hoy».
    private static let popularAfter = 2

    /// «Lo más popular hoy» si ya llegó (sin él, la franja no se dibuja vacía).
    @ViewBuilder private var popularToday: some View {
        if !catalog.model.popular.isEmpty { PopularTodayShelf(items: catalog.model.popular).id("popular-today") }   // `-demo-shelf popular-today`
    }

    /// Sin repetir, en el mismo orden.
    private static func distinct(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// Plataformas, colecciones, premios, años, «Lo que ves» y tus listas: lo de abajo de la portada y lo general. Sin caja
    /// propia: cada grupo es hijo directo de la lista perezosa (el mismo aire entre ellos), para que el índice de arriba salte a
    /// uno que aún no se ha armado (dentro de una caja, `scrollTo` no lo encontraba y «Temporadas» no bajaba).
    @ViewBuilder private var rest: some View {
                    if !model.platformHubs.isEmpty { platforms.modifier(SectionSpy(section: .platforms, active: $activeSection)) }
                    if collections.model.tmdbReady {
                        studiosSection.modifier(SectionSpy(section: .studios, active: $activeSection))
                        seasonsSection.modifier(SectionSpy(section: .seasons, active: $activeSection))
                        genresSection.modifier(SectionSpy(section: .genres, active: $activeSection))
                    }
                    awards.modifier(SectionSpy(section: .awards, active: $activeSection))
                    // Colecciones (la repisa del canon), entre Premios y Años (Fernando, 31 oct 2026), con el mismo rótulo.
                    if collections.model.traktLinked {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSChapterHead(label: Text("Colecciones"), symbol: "books.vertical")
                            CollectionsCardLoader().padding(.horizontal, DS.Space.gutter)
                        }
                    }
                    if collections.model.traktLinked { yearsSection.modifier(SectionSpy(section: .years, active: $activeSection)) }
                    // La puerta de «Lo que ves», al final, justo antes de tus listas (Fernando, 31 oct 2026).
                    if collections.model.traktLinked {
                        WatchingCardLoader().accessibilityIdentifier("paraTi-your-year")
                            .padding(.horizontal, DS.Space.gutter)
                            .modifier(SectionSpy(section: .yourYear, active: $activeSection))
                    }
                    // Las listas: las tuyas de Trakt y las de tus complementos, con el mismo rótulo.
                    if !traktLists.isEmpty || collections.model.traktLinked {
                        listRows(label: CollectionSection.trakt.title, symbol: CollectionSection.trakt.symbol, cards: traktLists,
                                 create: collections.model.traktLinked ? { naming = true } : nil)
                            .modifier(SectionSpy(section: .trakt, active: $activeSection))
                    }
                    if !addonCards.isEmpty {
                        listRows(label: CollectionSection.addons.title, symbol: CollectionSection.addons.symbol, cards: addonCards)
                            .modifier(SectionSpy(section: .addons, active: $activeSection))
                    }
    }

    // MARK: tus plataformas
    /// Cada plataforma, una tarjeta con su top 3 en abanico; tocarla abre sus rankings.
    private var platforms: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSChapterHead(label: Text("Plataformas"), symbol: CollectionSection.platforms.symbol)
            CenteredCarousel(items: model.platformHubs, id: \.id, cardWidth: DS.PlatformFan.width) { hub in
                NavigationLink(value: PlatformRoute(brand: hub.brand)) {
                    PlatformFanCard(name: hub.name, logo: hub.logo, posters: model.cover(of: hub).map { Optional($0.poster) },
                                    tint: DS.PlatformTint.color(hub.brand))
                        .cardWeight(DS.PlatformTint.color(hub.brand))
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
            ForEach(CollectionSection.allCases.filter(isShown), id: \.self) { section in
                Button {
                    activeSection = section
                    jumps += 1
                    if restReady { withAnimation(DS.Motion.base(reduceMotion)) { position.scrollTo(id: section, anchor: .top) } }
                    else {
                        // Lo de abajo aún no estaba armado: primero se arma y en el siguiente cuadro se salta.
                        restReady = true
                        Task { @MainActor in withAnimation(DS.Motion.base(reduceMotion)) { position.scrollTo(id: section, anchor: .top) } }
                    }
                } label: {
                    // Cada sección con su ícono; la que ves, con la palomita (`DS.Symbol.current`) al lado.
                    Label { activeSection == section ? Text("\(section.title)  \(Image(systemName: DS.Symbol.current))") : section.title } icon: { Image(systemName: section.symbol) }
                }
            }
        } label: { Image(systemName: "list.bullet.indent") }
        .accessibilityLabel(Text("Ir a una sección"))
        .accessibilityIdentifier("paraTi-sections")
        .dsFeedback(.selection, trigger: jumps)   // solo al elegir una sección (no en cada una al deslizar)
    }

    private func isShown(_ section: CollectionSection) -> Bool {
        switch section {
        case .forYou: true
        case .trakt: !traktLists.isEmpty || collections.model.traktLinked
        case .addons: !addonCards.isEmpty
        case .platforms: !model.platformHubs.isEmpty
        case .awards: !collections.model.awards.isEmpty
        case .studios, .seasons, .genres: collections.model.tmdbReady
        case .years: collections.model.traktLinked
        case .yourYear: collections.model.traktLinked
        }
    }

    /// Premios: cada uno con su estatuilla al frente, sobre sus tres ganadores más recientes.
    @ViewBuilder private var awards: some View {
        // El mismo orden que la repisa de Colecciones (Óscar, Palma, Ariel…), para que las dos no se contradigan.
        let order = Canon.awardOrder
        let all = collections.model.awards.sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSChapterHead(label: Text("Premios"), symbol: CollectionSection.awards.symbol)
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
            DSChapterHead(label: Text("Estudios"), symbol: CollectionSection.studios.symbol)
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

    /// Temporadas: la de ahora (o la siguiente en llegar) en grande y, debajo, las próximas de la más cercana a la más lejana,
    /// cada una con sus tres títulos más vistos, su ícono y su nombre al pie y el halo de su color.
    private var seasonsSection: some View {
        let language = env.services.appSettings.uiLanguage
        let countdown = collections.model.seasonCountdown
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSChapterHead(label: Text("Temporadas"), symbol: CollectionSection.seasons.symbol)
            if let now = countdown.first {
                NavigationLink(value: CollectionRoute(kind: .season, id: now.season.slug)) {
                    SeasonFeature(name: Strings.tr(now.season.title, language: language), blurb: Strings.tr(now.season.blurb, language: language),
                                  days: now.days, posters: (collections.model.seasonItems[now.season.slug] ?? []).map(\.poster),
                                  tint: DS.Collections.season(now.season.slug))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.gutter)
                .accessibilityIdentifier("season-now")
                .task { await collections.model.loadSeason(now.season.slug) }
            }
            DSSectionHead(title: Text("Próximas temporadas")).padding(.horizontal, DS.Space.gutter)
                .padding(.top, DS.Space.s3)
            // Una línea de tiempo (Fernando, 31 oct 2026, decisión 7A): un punto por temporada con cuánto falta, la línea las une.
            CenteredCarousel(items: countdown.dropFirst().map { SeasonStop(season: $0.season, days: $0.days) }, id: \.season.slug,
                             cardWidth: DS.PlatformFan.width,
                             header: { AnyView(SeasonTimelineStop(days: $0.days)) }) { stop in
                let season = stop.season
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

    /// Una temporada de la línea de tiempo y cuántos días faltan.
    private struct SeasonStop { let season: TmdbSeason; let days: Int }

    /// Un grupo de listas en renglones que abren la lista completa: «Tuyo» (Mi lista, Favoritos, Tus series y tus listas de
    /// Trakt) y «De tus complementos».
    private func listRows(label: Text, symbol: String, cards: [ListCardItem], create: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSChapterHead(label: label, symbol: symbol)
            VStack(spacing: DS.Space.s2) {
                ForEach(cards) { c in
                    if let shelf = c.shelf {
                        NavigationLink(value: shelf) { ListRow(name: c.name, detail: listDetail(c), posters: c.posters) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("list-\(c.id)")
                    }
                }
                // Al final de tus listas: una nueva en Trakt.
                if let create {
                    Button(action: create) { Label("Crear una lista", systemImage: "plus") }
                        .dsSecondaryButton()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("list-create")
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    /// «Lo que dejaste pendiente · 34», «Lo que marcaste con el corazón · 21», «Las que estás viendo · 18» o «42 títulos».
    private func listDetail(_ c: ListCardItem) -> Text {
        let what: Text? = switch c.id {
        case "watchlist": Text("Lo que dejaste pendiente")
        case ForYou.favoritesList: Text("Lo que marcaste con el corazón")
        case "mine": Text("Las que estás viendo")
        default: c.id.hasPrefix("lb:") ? Text(verbatim: "Letterboxd") : nil
        }
        guard let count = c.count else { return what ?? Text(verbatim: "") }
        guard let what else { return Text("\(count) títulos") }
        return Text("\(what) · \(count)")
    }

    /// Lo mejor del género: el Top 10 del año de cada género (TMDB, por nota), con su ícono y su nombre al pie.
    private var genresSection: some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSChapterHead(label: Text("Géneros"), symbol: CollectionSection.genres.symbol)
            CenteredCarousel(items: collections.model.genres, id: \.slug, cardWidth: DS.PlatformFan.width) { genre in
                let name = Strings.tr(genre.title, language: language)
                NavigationLink(value: CollectionRoute(kind: .genre, id: genre.slug)) {
                    CollectionCard(title: Text(verbatim: name), detail: Text("Las mejor calificadas del año"), name: name,
                                   posters: (collections.model.genreCharts[genre.slug]?.items ?? []).prefix(3).map { Optional($0.poster) },
                                   tint: DS.Collections.genre(genre.slug), captioned: false) {
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
            DSChapterHead(label: Text("Años"), symbol: CollectionSection.years.symbol)
            CenteredCarousel(items: collections.model.years, id: \.self, cardWidth: DS.Collections.yearWidth) { year in
                NavigationLink(value: CollectionRoute(kind: .year, id: String(year))) {
                    YearCard(year: year, posters: collections.model.yearPosters[year] ?? [])
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
        // El porqué arriba del título (como una revista).
        return Shelf(title: shelfTitle(plan),
                     route: ShelfRoute(id: plan.id), loading: model.isLoading(shelf: plan) && items.isEmpty, source: shelfSource(plan), eyebrow: shelfMeta(plan)) {
            ForEach(items) { s in
                PlanPoster(suggestion: s, plan: plan, model: model, style: plan.style, badge: model.badges[s.imdb])
            }
        }
        // Los Top 10 (y los rankings de plataformas), con sus pósters pedidos en cuanto llega la lista.
        .task(id: items.first?.imdb) { if plan.style == .top10 || plan.style == .platform { ImagePipeline.shared.prefetchPosters(items.prefix(DS.Size.searchPrefetch).map(\.poster)) } }
    }

    /// Sin ninguna fuente tuya: lo que está en tendencia en Trakt y una invitación (un botón, no una tarjeta gris).
    @ViewBuilder private var sourcesFallback: some View {
        if !model.mosaic.isEmpty {
            Shelf(title: Text("En tendencia"), meta: Text("Lo más visto ahora en Trakt")) {
                ForEach(model.mosaic) { s in
                    ShelfPoster(suggestion: s, style: .plain, inList: false) { dismissed in Task { await model.dismiss(dismissed) } }
                }
            }
        }
        DSEmptyState(symbol: "link", title: Text("Conecta Trakt o tu Orbital"),
                     message: Text("Mi lista, tus recomendaciones y el Top 10 de tus plataformas aparecen aquí.")) {
            NavigationLink(value: SettingsRoute()) { Label("Abrir Ajustes", systemImage: "gearshape") }
        }
    }
}
