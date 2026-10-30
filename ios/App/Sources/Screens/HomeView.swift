import SwiftUI
import OrbitalCore
import OrbitalModels

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var home: ModelObserver<HomeModel>
    @State private var tvNow: ModelObserver<TVNowModel>
    @State private var inbox: ModelObserver<InboxModel>
    /// «Por lo que viste»: el mazo de lo último que viste y sus relacionadas.
    @State private var because = ModelObserver(BecauseModel(AppEnvironment.shared.services))
    /// Canales: tus series siempre al aire.
    @State private var channels = ModelObserver(ChannelsModel(AppEnvironment.shared.services))
    @State private var tint = ArtTint()
    @State private var openTitle: TitleRoute?
    /// La tarjeta al frente de la portada (su lugar en la fila).
    @State private var heroSlot: Int?
    /// El Top 10 de Netflix: series (por omisión) o películas.
    @State private var topMovies = false
    /// La ruleta de «Un Simpson al azar».
    @State private var rollingSimpsons = false
    /// Sale hoy › el mes completo.
    @State private var showingCalendar = false
    /// El filtro avanzado (el cajón de la sesión de componentes), desde la franja de arriba.
    @State private var showingFilter = false
    @Namespace private var simpsonsZoom
    @State private var continueSort: ListSort = .added
    @State private var continueKind = ""
    /// El alto de cada renglón de «Tu watchlist», que crece con el tamaño de letra.
    @ScaledMetric(relativeTo: .body) private var watchRow = DS.Editorial.watchlistRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openRemote) private var openRemote
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _home = State(wrappedValue: ModelObserver(HomeModel(AppEnvironment.shared.services)))
        // El sondeo es de toda la app (arranca en RootView): aquí solo se ve.
        _tvNow = State(wrappedValue: ModelObserver(AppEnvironment.shared.tvNow))
        _inbox = State(wrappedValue: ModelObserver(AppEnvironment.shared.inbox))
    }

    var body: some View {
        let model = home.model
        // El tipo de la barra (Todo · Películas · Series) filtra toda la página, no solo la portada.
        let kind = model.spotlightKind
        let fits: (String) -> Bool = { kind == nil || $0 == kind }
        let continuing = model.continueWatching.filter { fits($0.kind) }
        let picks = model.forYouPicks.filter { fits($0.kind) }
        let pending = model.traktPending.filter { fits($0.kind) }
        let favorites = model.favorites.filter { fits($0.kind) }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                if model.offline {
                    // Sin internet: lo del teléfono sigue a la vista, y la salida es Descargas (más reintentar).
                    DegradedNotice(state: .offline) { Task { await model.refresh() } }
                        .padding(.horizontal, DS.Space.gutter)
                }
                // Con iOS 26.1 lo que suena en la TV vive en el accesorio de la barra de pestañas (y su control remoto en una hoja);
                // antes, en esta tarjeta.
                if !Self.hasTabAccessory, let now = tvNow.model.now {
                    NowPlayingCard(now: now, fetchedAt: tvNow.model.fetchedAt, busy: tvNow.model.busy,
                                  onAction: { action, delta in Task { await tvNow.model.control(action, delta: delta) } },
                                  onContinueHere: { openTitle = now.metaID.map { TitleRoute(kind: now.kind, metaID: $0, title: now.title, poster: now.poster) } })
                        .padding(.horizontal, DS.Space.gutter)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }
                // Lo que la TV mandó con «Enviar al iPhone»: una tarjeta pequeña, bajo «Viendo en la TV».
                ForEach(inbox.model.fromTV) { item in
                    FromTVCard(item: item,
                               onWatch: { inbox.model.watched(item); Task { await env.play(item) } },
                               onDownload: { Task { await inbox.model.downloadFromCard(item) } },
                               onDismiss: { inbox.model.dismiss(item) })
                        .padding(.horizontal, DS.Space.gutter)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }
                // Abre con «Destacado» (lo que se está viendo esta semana, para ti); lo que dejaste a medias va justo debajo.
                if !model.spotlight.isEmpty {
                    spotlightCarousel(model).perfTag("home.hero")
                        // Las primeras tarjetas: su fondo ligero se pide en cuanto se sabe cuáles son (no al pintarse). Los logos no:
                        // pesan ~350 KB y le quitaban red a la imagen grande.
                        .task(id: model.spotlight.first?.imdb) {
                            for case let preview? in model.spotlight.prefix(DS.Size.heroPrefetch).map({ Artwork.preview($0.wide) }) {
                                let pixels = CGFloat(preview.pixels)
                                if let url = URL(string: preview.url) { Task { _ = await ImagePipeline.shared.image(url, maxPixel: pixels, urgent: true) } }
                            }
                        }
                }
                if model.spotlight.isEmpty, model.continueWatching.isEmpty, model.isLoading {
                    FeedSkeleton()   // la primera vez: el lugar ya reservado mientras llega
                }
                // El orden del Inicio nuevo (docs/producto/inicio-benchmark/): lo tuyo primero, luego lo que sale de tus series,
                // tus sugerencias, el Top 10 y Mi lista.
                if !continuing.isEmpty {
                    continueRail(model, items: continuing).perfTag("home.rail")
                        // En oscuro, encimado en el borde de abajo de la portada (que se funde con el fondo): lo que tienes a
                        // medias se ve sin bajar. En claro la portada es una tarjeta y su título no se leería encima.
                        .padding(.top, model.spotlight.isEmpty ? 0 : -(DS.Editorial.sectionGap + heroOverlap))
                } else if !model.isLoading, model.spotlight.isEmpty, model.continueWatching.isEmpty, !model.offline {   // sin red, el aviso de arriba ya lo dice
                    DSEmptyState(symbol: "play.rectangle.on.rectangle", title: Text("Todavía nada"), message: Text("Aquí aparece lo que vas viendo, en el iPhone y en Orbital."))
                }
                // Lo que sale de tus series (solo series: con «Películas» en la barra, no se pinta).
                if kind != "movie", !model.timeline.isEmpty {
                    ReleaseTimeline(airings: model.timeline, onOpen: { openTitle = $0 }, onCalendar: { showingCalendar = true })
                }
                // Tus recomendaciones de Trakt.
                if !picks.isEmpty {
                    Rail(title: "Sugerencias para ti", route: HomeListRoute(id: "foryou"), eyebrow: Text("Recomendadas por Trakt con lo que ves"), source: .trakt, reflected: true) {
                        ForEach(picks) { s in TitleLink(route: s.route) }
                    }
                }
                HomeBecause(model: because.model, kind: kind)
                if kind != "movie" { HomeChannels(model: channels.model) }   // solo series
                // El Top 10 de un servicio (Netflix, Disney+, HBO Max…), elegido con su pastilla: series o películas, cada una con su 1 al 10.
                if model.hasAnyTop { topTen(model) }
                if !pending.isEmpty { watchlist(model, items: pending) }
                // Tus favoritos de Trakt (el corazón de la ficha): aquí hasta que Para ti tenga su grupo «Tuyo».
                if !favorites.isEmpty {
                    Rail(title: "Favoritos", count: favorites.count, route: HomeListRoute(id: "favorites"),
                         eyebrow: Text("Lo que marcaste con el corazón"), source: .trakt, reflected: true) {
                        ForEach(favorites) { s in TitleLink(route: s.route).contextMenu { favoriteActions(s) } }
                    }
                }
            }
            .padding(.top, DS.Space.s3)         // el destacado no se pega al saludo (el mismo aire que Para ti y Buscar)
            .padding(.bottom, DS.Space.s2)      // la barra de pestañas ya deja su espacio: más aquí era aire muerto al final
            .animation(DS.Motion.enter(reduceMotion), value: tvNow.model.now != nil)
            .animation(DS.Motion.enter(reduceMotion), value: inbox.model.fromTV.map(\.id))
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazado (capturas de las filas de abajo)
        #endif
        .background(Backdrop(tint: tint.colors))
        // Sin título: arriba van el ícono y «Orbital» (el carácter de la app), también al bajar.
        .navigationTitle(Text(verbatim: "")).toolbarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $rollingSimpsons) { SimpsonsRoulette(tint: tint.colors).navigationTransition(.zoom(sourceID: "simpsons", in: simpsonsZoom)) }
        .onChange(of: env.ui.openSimpsons, initial: true) { _, wants in
            guard wants else { return }
            env.ui.openSimpsons = false
            rollingSimpsons = true
        }
        .sheet(isPresented: $showingCalendar) {
            ReleaseCalendarView { route in showingCalendar = false; openTitle = route }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .task(priority: .utility) {
            #if DEBUG
            if Demo.isOn, Demo.open?.hasPrefix("simpsons") == true {   // `-demo-open simpsons`: la ruleta sola
                await env.simpsons.prefetch(); rollingSimpsons = true; return
            }
            #endif
            // La ficha de Los Simpson (~650 KB) fuera del arranque: primero Inicio y sus imágenes; si tocas la dona antes, la pide ella.
            try? await Task.sleep(for: .seconds(DS.Simpsons.prefetchDelay))
            await env.simpsons.prefetch()
        }
        // Todo · Películas · Series para toda la página y la puerta del filtro avanzado, bajo la barra.
        .safeAreaBar(edge: .top) {
            HomeKindBar(kind: Binding(get: { model.spotlightKind ?? "" }, set: { model.spotlightKind = $0.isEmpty ? nil : $0 }),
                        onFilters: { showingFilter = true })
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { AppMark() }
                .sharedBackgroundVisibility(.hidden)
            // Sin nada en la TV, el control de tu Orbital vive aquí (con algo reproduciéndose, en el accesorio de abajo).
            // Sin accesorio (iOS 26.0) el botón se queda siempre: era la única entrada al control con algo sonando.
            if let openRemote, tvNow.model.now == nil || !Self.hasTabAccessory {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openRemote) { Image(systemName: "av.remote") }
                        .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            // Un Simpson al azar (T5–T15): un toque, la ruleta, y empieza en el iPhone (las temporadas, en Ajustes).
            ToolbarItem(placement: .topBarTrailing) {
                Button { rollingSimpsons = true } label: { Image("Glyphs/donut").renderingMode(.original) }
                    .matchedTransitionSource(id: "simpsons", in: simpsonsZoom)   // la tele sale de la dona
                    .accessibilityLabel(Text("Un Simpson al azar"))
                    .accessibilityIdentifier("home-random-simpsons")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { ProfileButton(avatar: look.avatar) }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: HomeListRoute.self) { route in homeList(route) }
        .openingTitles(item: $openTitle)   // en el iPad y la Mac, en el panel de la derecha
        .advancedFilter(isPresented: $showingFilter) { openTitle = $0 }   // un resultado abre su ficha
        .task { await reload(ifStale: true) }   // volver de otra pestaña o de una ficha no lo vuelve a pedir todo
        .refreshable { await reload() }
        .onChange(of: env.watchedSomething) { Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload(ifStale: true) } } }   // al volver a la app
    }

    /// «Mi lista» o «Tu watchlist» completas, en cuadrícula (desde el chevron de su encabezado).
    @ViewBuilder private func homeList(_ route: HomeListRoute) -> some View {
        if route.id == "continue" { allContinue(home.model) } else { titleGrid(route) }
    }

    /// Con orden y filtros (películas o series, género, ocultar lo visto), como toda lista abierta desde «Ver todo».
    private func titleGrid(_ route: HomeListRoute) -> some View {
        let items: [Suggestion] = route.id == "watchlist" ? home.model.traktPending
            : route.id == "foryou" ? home.model.forYouPicks
            : home.model.favorites
        return ScrollView {
            SortableGrid(listID: "home:\(route.id)", items: items, collections: env.collections) { s, width in
                if let list = route.list {
                    TitleLink(route: s.route, width: width).contextMenu { listActions(s, in: list) }
                } else if route.id == "favorites" {
                    TitleLink(route: s.route, width: width).contextMenu { favoriteActions(s) }
                } else {
                    TitleLink(route: s.route, width: width)
                }
            }
                .padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop(tint: tint.colors))
        .navigationTitle(route.id == "watchlist" ? Text("Mi lista") : route.id == "foryou" ? Text("Sugerencias para ti") : Text("Favoritos"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Lo tuyo y el tono del fondo (al abrir, al deslizar hacia abajo y al volver de ver algo). Lo pendiente por subir
    /// se sube solo y ya no se anuncia bajo el título («N cambios por subir»: no se quería ahí).
    private func reload(ifStale: Bool = false) async {
        async let related: Void = because.model.load()   // a la par (Trakt lo guarda: volver a pedirlo es barato)
        if ifStale { await home.model.refreshIfStale() } else { await home.model.refresh() }
        Perf.mark("home.done")
        await tint.load(currentHero?.wide)
        await related
    }

    /// Cuánto se encima «Seguir viendo» sobre la portada: solo en oscuro (en claro la portada es una tarjeta y no se leería).
    private var heroOverlap: CGFloat { scheme == .dark ? DS.HomeHero.overlap : 0 }

    /// Al dejar picado un título de una de tus listas: ver, descargar, en la TV, marcar como vista y quitarlo de la lista.
    @ViewBuilder private func listActions(_ s: Suggestion, in list: SaveDestination) -> some View {
        let model = home.model
        SuggestionActions(suggestion: s, list: list, onWatched: { model.setShown($0.imdb, in: list, shown: false) }) { s in
            Task { await env.remove(s, from: list) { shown in model.setShown(s.imdb, in: list, shown: shown) } }
        }
    }

    /// Al dejar picado uno de tus favoritos: ver, guardar, descargar, en la TV y «Quitar de favoritos» (con «Deshacer»).
    @ViewBuilder private func favoriteActions(_ s: Suggestion) -> some View {
        SuggestionActions(suggestion: s, favorite: true) { s in Task { await env.removeFavorite(s) } }
    }

    private func route(_ item: HomeItem) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }

    /// Cómo se ve Inicio (carrusel, avatar), en vivo: al cambiarlo en Ajustes, Inicio se vuelve a pintar.
    private var look: AppSettings {
        var settings = env.services.appSettings
        #if DEBUG
        if Demo.isOn {   // `-demo-avatar comet`: para ver cada avatar en las capturas
            if let v = Demo.value(after: "-demo-avatar") { settings.avatar = v }
        }
        #endif
        return settings
    }

    private static var hasTabAccessory: Bool { if #available(iOS 26.1, *) { true } else { false } }

    /// Cuántos de «Destacado» van en la portada.

    private func spotlightItems(_ model: HomeModel) -> [Suggestion] { Array(model.spotlightShown.prefix(HomeModel.heroCount)) }

    /// El que está al frente de la portada (el fondo toma su color).
    private var currentHero: Suggestion? {
        let items = spotlightItems(home.model)
        guard !items.isEmpty else { return nil }
        return items[min(heroSlot ?? 0, items.count - 1)]
    }

    /// Ancho entre alto de la portada: casi un póster en el iPhone, más baja en pantallas cortas y apaisada en ventana ancha.
    private var heroAspect: CGFloat {
        let size = WindowMetrics.size
        if size.width >= DS.Size.compactWidth * 2 { return DS.HomeHero.aspectWide }
        return size.height < DS.HomeHero.shortScreen ? DS.HomeHero.aspectShort : DS.HomeHero.aspect
    }

    /// La portada (docs/producto/inicio-benchmark/): el arte de borde a borde, detrás de la barra, que se desliza entre lo
    /// que todos están viendo. Cada título con su porqué en turquesa, su logo, sus datos y «Ver». Abajo, los puntos; encima de
    /// su borde entra «Seguir viendo». El fondo toma el color del que está al frente.
    private func spotlightCarousel(_ model: HomeModel) -> some View {
        let items = spotlightItems(model)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                    hero(s).containerRelativeFrame(.horizontal).id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $heroSlot)
        .overlay(alignment: .bottom) {
            PageDots(count: items.count, index: min(heroSlot ?? 0, max(0, items.count - 1)))
                .padding(.bottom, heroOverlap + DS.Space.s3)
                .allowsHitTesting(false)   // tocar los puntos no abre la ficha
        }
        // En oscuro el arte se funde con el fondo y sube detrás de la barra; en claro es una tarjeta (no pasa detrás).
        .ignoresSafeArea(edges: scheme == .dark ? .top : [])
        // Cambió la lista (al volver de ver algo, al cambiar el tipo): te quedas en el que estabas si sigue; si no, el primero.
        .onChange(of: items.map(\.id)) { old, new in
            let current = heroSlot.flatMap { old.indices.contains($0) ? old[$0] : nil }
            heroSlot = current.flatMap { new.firstIndex(of: $0) } ?? 0
        }
        .task(id: heroSlot) { await tint.load(currentHero?.wide) }   // se cancela si pasas a otro
        .sensoryFeedback(.selection, trigger: heroSlot) { old, _ in old != nil }
    }

    private func hero(_ s: Suggestion) -> some View {
        // La portada abre la ficha con su propio toque; «Ver» va aparte (un botón dentro de un NavigationLink puede abrir la
        // ficha en vez de reproducir).
        BleedArt(url: s.wide, title: s.title, aspect: heroAspect, tall: TallArtKey(imdb: s.imdb, kind: s.kind)) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if let reason = reasonText(s.reason) { Eyebrow(text: reason, onArt: true, reason: true) }
                    TitleLogo(url: s.logo ?? Artwork.logoURL(metaID: s.imdb), title: s.title, size: .hero)
                    DataLine(parts: heroData(s), color: DS.onArtSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Ver ficha")) { openTitle = s.route }
                HeroActions { heroButtons(s) }
            }
            .padding(.bottom, heroOverlap + DS.Space.s6)   // los puntos y, en oscuro, lo que se encima
        }
        .contentShape(Rectangle())
        .onTapGesture { openTitle = s.route }
    }

    @ViewBuilder private func heroButtons(_ s: Suggestion) -> some View {
        WithArtColors(url: s.wide) { colors in
            Button {
                if s.kind == "series" { openTitle = s.route } else { Task { await env.play(s) } }
            } label: {
                Label { s.kind == "series" ? Text("Ver la serie") : Text("Ver") } icon: { Image(systemName: "play.fill") }.lineLimit(1)
            }
            .dsArtButton(colors)
        }
        if env.services.orbital.isConfigured {
            // Un toque lo explica («¿Ver en la TV?»), el segundo lo manda: solo el ícono no decía qué hacía.
            ConfirmIconButton(symbol: "tv", prompt: "¿Ver en la TV?", label: "Ver en la TV") {
                Task { await env.playOnTV(kind: s.kind, metaID: s.imdb, videoID: s.kind == "movie" ? s.imdb : nil, title: s.title) }
            }
        }
    }

    /// Por qué está en la portada, en turquesa arriba del título («En tendencia esta semana», «Para ti»…).
    private func reasonText(_ reason: SuggestionReason) -> Text? {
        switch reason {
        case .trending: Text("En tendencia esta semana")
        case .popular: Text("Lo más popular")
        case .recommended: Text("Para ti")
        default: Text("Destacado")
        }
    }

    /// «Película · 2024 · Drama».
    private func heroData(_ s: Suggestion) -> [String] {
        let language = env.services.appSettings.uiLanguage
        return [Strings.kind(s.kind, language: language), s.year.map(String.init), Vocabulary.genres(s.genres, language: language).first].compactMap { $0 }
    }

    /// «Seguir viendo»: lo que dejaste a medias (o el siguiente episodio), en piezas anchas con su avance. Tocar una sigue
    /// donde ibas; mantenerla: la ficha, la TV o quitarla.
    private func continueRail(_ model: HomeModel, items: [HomeItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            NavigationLink(value: HomeListRoute(id: "continue")) {
                DSSectionHead(title: Text("Seguir viendo"), count: items.count, chevron: true, eyebrow: Text("Lo que tienes a medias"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            .accessibilityIdentifier("home-all-continue")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(items) { item in
                        Button { Task { await env.play(item) } } label: {
                            StillCard(title: item.title, art: item.background ?? item.poster, data: continueData(item), progress: item.progress,
                                      fallback: item.background == nil ? nil : item.poster)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Ver la ficha", systemImage: "info.circle") { openTitle = route(item) }
                            if env.services.orbital.isConfigured {
                                Button("Ver en la TV", systemImage: "tv") { Task { await env.playOnTV(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title) } }
                            }
                            Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// «Mi lista» (tu watchlist de Trakt, también sin Trakt en el teléfono): tarjetas con póster, datos y sinopsis en dos renglones que se deslizan juntos (cada renglón de Inicio
    /// con su forma: el destacado en carrusel, lo que sigues en panorámicas, lo pendiente en fichas y Mi lista en pósters).
    private func watchlist(_ model: HomeModel, items: [Suggestion]) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            NavigationLink(value: HomeListRoute(id: "watchlist")) {
                DSSectionHead(title: Text("Mi lista"), count: items.count, chevron: true, eyebrow: Text("Lo que dejaste pendiente"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                // Dos renglones (uno si son pocas), del alto que pida la letra; en el renglón, las primeras.
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(watchRow), spacing: DS.Space.s3), count: items.count < 3 ? 1 : 2), spacing: DS.Space.s3) {
                    ForEach(items.prefix(DS.Editorial.watchlistInRow)) { s in
                        let facts = [s.year.map(String.init), Vocabulary.genres(s.genres, language: language).first].compactMap { $0 }.joined(separator: " · ")
                        TitleNavigationLink(route: s.route) {
                            WatchlistCard(title: s.title, poster: s.poster, facts: facts, overview: s.overview).titleZoomSource(s.route)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { listActions(s, in: .myList) }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// A qué pastilla se ancla la fila: la elegida contra el margen (donde se detiene al deslizar), o el principio si es de las
    /// primeras (se ve completa sin mover nada).
    private func pillAnchor(_ brand: String) -> String {
        let all = HomeModel.topServices.map(\.brand)
        return (all.firstIndex(of: brand) ?? 0) <= 1 ? all[0] : brand
    }

    private func topTen(_ model: HomeModel) -> some View {
        let service = model.topService
        let series = model.top(kind: "series"), films = model.top(kind: "movie")
        let pageKind = model.spotlightKind
        let movies = pageKind == "movie" ? true : pageKind == "series" ? false : (topMovies && !films.isEmpty || series.isEmpty)
        let items = movies ? films : series
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .sectionTitle) {
                DSSectionHead(title: Text("Top 10 en \(service.name)"),
                              eyebrow: service.weekly ? Text("Lo más visto en tu país esta semana") : Text("Lo más visto hoy · JustWatch"))
                    .lineLimit(1).minimumScaleFactor(DS.Size.titleShrink)
                Spacer(minLength: DS.Space.s2)
                // Siempre ocupa su lugar (oculto si el servicio solo tiene uno de los dos): al cambiar de servicio nada brinca.
                DSKindFilter(kind: Binding(get: { movies ? "movie" : "series" }, set: { topMovies = $0 == "movie" }), includeAll: false, compact: true)
                    .opacity(pageKind == nil && !series.isEmpty && !films.isEmpty ? 1 : 0).disabled(pageKind != nil || series.isEmpty || films.isEmpty)
            }
            .padding(.horizontal, DS.Space.gutter)
            // De qué servicio: una pastilla por cada uno, con su logo (la elegida, con su color). Ancladas: al deslizar se
            // detienen en el borde de una pastilla (nunca a la mitad) y la elegida siempre queda a la vista.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(HomeModel.topServices) { s in
                            PlatformPill(name: s.name, logo: s.logo, brand: s.brand, selected: s.brand == service.brand) {
                                Task { await model.selectTop(s.brand) }
                            }
                            .id(s.brand)
                            .accessibilityIdentifier("top-\(s.brand)")
                        }
                    }
                    .padding(.vertical, DS.PlatformFan.pillStroke)   // el borde de la elegida no se recorta
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                // Un riel: solo de lado. Antes la fila tenía unos puntos de más y se podía mover arriba y abajo.
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollTargetBehavior(.viewAligned)
                // Un riel fijo: tocar una pastilla no recorre la fila (antes saltaba para dejarla al borde). Solo al abrir, si la
                // guardada está lejos, se acerca.
                .onAppear { proxy.scrollTo(pillAnchor(service.brand), anchor: .leading) }
            }
            .sensoryFeedback(.selection, trigger: service.brand)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: DS.Space.s3) {
                    if items.isEmpty {
                        if model.loadingTop { ShelfSkeleton() }
                        else { Text("Hoy no hay ranking de este servicio.").recipe(.footnote).frame(width: DS.Size.cardMax, alignment: .leading) }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                        TitleNavigationLink(route: s.route) { RankedPosterCard(rank: s.rank ?? i + 1, title: s.title, poster: s.poster, movement: s.movement, isNew: s.isNew, tint: DS.PlatformTint.color(service.brand)).titleZoomSource(s.route) }
                            .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .id("\(service.brand)-\(movies)")   // al cambiar, desde el n.º 1
            .transition(.opacity)
        }
        .animation(DS.Motion.base(reduceMotion), value: service.brand)
        .task(id: items.first?.imdb) { ImagePipeline.shared.prefetchPosters(items.map(\.poster)) }
    }

    /// «T2 E5 · quedan 20 min»; «Nuevo · T38 E5» si ibas al día y ya salió el episodio que sigue.
    private func continueData(_ item: HomeItem) -> [String] {
        let facts = progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes, language: env.language).components(separatedBy: " · ")
        guard item.isNew == true else { return facts }
        return [Strings.tr("Nuevo", language: env.services.appSettings.uiLanguage)] + facts
    }

    /// «Seguir viendo» completo: todo (el carrusel solo trae los últimos), en piezas anchas con su avance.
    private func allContinue(_ model: HomeModel) -> some View {
        let kept = model.continueWatching.filter { continueKind.isEmpty || $0.kind == continueKind }
        let shown = continueSort == .title ? kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : kept
        return ScrollView {
            LazyVGrid(columns: DS.Poster.pairColumns(spacing: DS.Space.s3, wideMin: DS.Poster.stillWideMin), spacing: DS.Space.s4) {
                ForEach(shown) { item in
                    TitleNavigationLink(route: route(item)) {
                        StillCard(title: item.title, art: item.background ?? item.poster, data: continueData(item),
                                  progress: item.progress, width: nil, fallback: item.background == nil ? nil : item.poster)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop(tint: tint.colors))
        .navigationTitle(Text("Seguir viendo")).navigationBarTitleDisplayMode(.inline)
        // Ordenar y filtrar, como toda lista abierta desde «Ver todo».
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordenar", selection: $continueSort) {
                        Text("Lo último que viste").tag(ListSort.added)
                        Text("A–Z").tag(ListSort.title)
                    }
                    Picker("Mostrar", selection: $continueKind) {
                        Text("Todo").tag("")
                        Text("Películas").tag("movie")
                        Text("Series").tag("series")
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel(Text("Ordenar y filtrar"))
            }
        }
    }
}
