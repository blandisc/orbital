import SwiftUI
import OrbitalCore
import OrbitalModels

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var home: ModelObserver<HomeModel>
    @StateObject private var tvNow: ModelObserver<TVNowModel>
    @StateObject private var inbox: ModelObserver<InboxModel>
    @StateObject private var tint = ArtTint()
    @State private var pendingCount = 0
    @State private var openTitle: TitleRoute?
    /// La tarjeta al frente del carrusel: su lugar en la vuelta infinita (`slot % cuántas`).
    @State private var heroSlot: Int?
    @State private var scrolledDown = false
    @State private var placingHero = false
    /// El Top 10 de Netflix: series (por omisión) o películas.
    @State private var topMovies = false
    /// La ruleta de «Un Simpson al azar».
    @State private var rollingSimpsons = false
    /// El alto de cada renglón de «Tu watchlist», que crece con el tamaño de letra.
    @ScaledMetric(relativeTo: .body) private var watchRow = DS.Editorial.watchlistRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openRemote) private var openRemote
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _home = StateObject(wrappedValue: ModelObserver(HomeModel(AppEnvironment.shared.services)))
        // El sondeo es de toda la app (arranca en RootView): aquí solo se ve.
        _tvNow = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.tvNow))
        _inbox = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.inbox))
    }

    var body: some View {
        let model = home.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                if model.offline { DSNotice(text: "Sin conexión: se ve lo último que guardé.", tone: .warn).padding(.horizontal, DS.Space.gutter) }
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
                if !model.spotlight.isEmpty { spotlightCarousel(model).perfTag("home.hero") }
                if !model.continueWatching.isEmpty {
                    continueRail(model).perfTag("home.rail")
                } else if !model.isLoading, model.spotlight.isEmpty {
                    DSNotice(text: "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.").padding(.horizontal, DS.Space.gutter)
                }
                // Primero lo pendiente (tu watchlist), luego lo que sale y al final lo que guardaste; cada renglón con su porqué
                // arriba, su sello de origen y su reflejo (el peso del carrusel de arriba).
                // Lo tuyo: tus recomendaciones (lo personal ya no va arriba, donde está lo de todos).
                if !model.forYouPicks.isEmpty {
                    Rail(title: "Para ti", route: nil, eyebrow: Text("Recomendadas con lo que ves"), source: .trakt) {
                        ForEach(model.forYouPicks) { s in TitleLink(route: s.route, reflected: true) }
                    }
                }
                // El Top 10 de un servicio (Netflix, Disney+, HBO Max…), elegido con su pastilla: series o películas, cada una con su 1 al 10.
                if model.hasAnyTop { topTen(model) }
                if !model.traktPending.isEmpty { watchlist(model) }
                if !model.upcoming.isEmpty { upcoming(model) }
                if !model.myList.isEmpty {
                    Rail(title: "Mi lista", count: model.myList.count, route: HomeListRoute(id: "mylist"),
                         eyebrow: Text("Lo que guardaste"), source: .stremio) {
                        ForEach(model.myList) { item in
                            TitleLink(route: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster), reflected: true)
                        }
                    }
                }
            }
            .padding(.top, DS.Space.s3)         // el destacado no se pega al saludo (el mismo aire que Para ti y Buscar)
            .padding(.bottom, DS.Space.s14)     // la última fila respira: la barra de pestañas no la tapa
            .animation(DS.Motion.enter(reduceMotion), value: tvNow.model.now != nil)
            .animation(DS.Motion.enter(reduceMotion), value: inbox.model.fromTV.map(\.id))
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > DS.Size.titleCollapse } action: { _, down in scrolledDown = down }
        .background(Backdrop(tint: tint.colors))
        // Arriba, el saludo; al bajar (la barra se encoge), algo útil en su lugar: lo que suena en la TV, lo que sale hoy o
        // cuántas tienes por terminar (y si no hay nada que decir, «Inicio»).
        // Arriba, el ícono y «Orbital» (el carácter de la app); al bajar, en medio, lo más útil que haya (lo que suena en la TV…).
        .navigationTitle(scrolledDown ? scrolledTitle : Text(verbatim: "")).toolbarTitleDisplayMode(.inline)
        .subtitle(syncText)
        .fullScreenCover(isPresented: $rollingSimpsons) { SimpsonsRoulette() }
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
            // Un Simpson al azar (T5–T15): un toque, la ruleta, y empieza en el iPhone.
            ToolbarItem(placement: .topBarTrailing) {
                Button { rollingSimpsons = true } label: { Image("Glyphs/donut").renderingMode(.original) }
                    .accessibilityLabel(Text("Un Simpson al azar"))
                    .accessibilityIdentifier("home-random-simpsons")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { ProfileButton(avatar: look.avatar) }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: HomeListRoute.self) { route in homeList(route) }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .task { await reload(ifStale: true) }   // volver de otra pestaña o de una ficha no lo vuelve a pedir todo
        .refreshable { await reload() }
        .onChange(of: env.watchedSomething) { Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload(ifStale: true) } } }   // al volver a la app
    }

    /// «Mi lista» o «Tu watchlist» completas, en cuadrícula (desde el chevron de su encabezado).
    @ViewBuilder private func homeList(_ route: HomeListRoute) -> some View {
        if route.id == "continue" { allContinue(home.model) } else { titleGrid(route) }
    }

    private func titleGrid(_ route: HomeListRoute) -> some View {
        let routes = route.id == "watchlist" ? home.model.traktPending.map(\.route) : home.model.myList.map(self.route)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(routes, id: \.metaID) { TitleLink(route: $0, width: DS.Poster.gridMinimum) }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop(tint: tint.colors))
        .navigationTitle(route.id == "watchlist" ? Text("Tu watchlist") : Text("Mi lista")).navigationBarTitleDisplayMode(.inline)
    }

    /// Lo de Stremio, lo pendiente por subir y el tono del fondo (al abrir, al deslizar hacia abajo y al volver de ver algo).
    private func reload(ifStale: Bool = false) async {
        if ifStale { await home.model.refreshIfStale() } else { await home.model.refresh() }
        let work = env.services.pending.load()      // una sola lectura por actualización, no una por cada pintado
        pendingCount = work.progress.count + work.traktWatched.count
        await tint.load(currentHero?.wide)
    }

    /// El título con la barra encogida: lo más útil que haya.
    private var scrolledTitle: Text {
        if let airing = home.model.airingToday { return Text("Sale hoy: \(airing.series.title)") }
        return Text(verbatim: "")   // sin nada que decir, solo el logotipo
    }

    /// Solo cuando hay algo que decir: «N cambios por subir» (lo que viste sin internet). Al día, nada (no hace falta decirlo).
    private var syncText: Text? {
        pendingCount > 0 ? Text("\(pendingCount) cambios por subir") : nil
    }

    private func route(_ item: HomeItem) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }

    /// Cómo se ve Inicio (carrusel, tiempo, avatar), en vivo: al cambiarlo en Ajustes, Inicio se vuelve a pintar.
    private var look: AppSettings {
        var settings = env.services.appSettings
        #if DEBUG
        if Demo.isOn {   // `-demo-deck fan`, `-demo-time arc`, `-demo-avatar comet`: para ver cada estilo en las capturas
            if let v = Demo.value(after: "-demo-deck") { settings.homeDeck = v }
            if let v = Demo.value(after: "-demo-time") { settings.homeTime = v }
            if let v = Demo.value(after: "-demo-avatar") { settings.avatar = v }
        }
        #endif
        return settings
    }

    private static var hasTabAccessory: Bool { if #available(iOS 26.1, *) { true } else { false } }

    /// Pone el carrusel en una tarjeta sin el toque háptico (no fue tu dedo).
    private func placeHero(_ slot: Int) {
        placingHero = true
        heroSlot = slot
        DispatchQueue.main.async { placingHero = false }
    }

    /// Cuántos de «Destacado» van en el carrusel.
    private static let heroCount = 10

    private func spotlightItems(_ model: HomeModel) -> [Suggestion] { Array(model.spotlightShown.prefix(Self.heroCount)) }

    /// El que está al frente del carrusel (el fondo toma su color).
    private var currentHero: Suggestion? {
        let items = spotlightItems(home.model)
        guard !items.isEmpty else { return nil }
        return items[(heroSlot ?? 0) % items.count]
    }

    /// «Destacado»: tarjetas en carrusel infinito (`DeckCard`) con las de los lados más chicas y desenfocadas, en coverflow o
    /// abanico (Ajustes › Inicio); arriba, el filtro de películas o series. El fondo toma el color del que está al frente.
    private func spotlightCarousel(_ model: HomeModel) -> some View {
        let items = spotlightItems(model)
        let deck = DeckStyle(rawValue: look.homeDeck) ?? .coverflow
        // Una vuelta infinita: las mismas tarjetas repetidas muchas veces y se empieza a la mitad; al llegar a la última
        // sigue la primera (y hacia atrás igual). Con una sola, no hay vuelta.
        let copies = items.count > 1 ? DS.Deck.loopCopies : 1
        let middle = (copies / 2) * items.count
        return VStack(spacing: DS.Space.s3) {
            HStack(alignment: .lastTextBaseline) {
                DSSectionHead(title: Text("En tendencia"), eyebrow: Text("Lo que todo el mundo está viendo"))
                Spacer(minLength: DS.Space.s2)
                kindFilter(model)
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Deck.spacing) {
                    ForEach(0..<(copies * items.count), id: \.self) { slot in
                        hero(items[slot % items.count])
                            .environment(\.solidButtons, true)   // la tarjeta se gira en 3D: sus botones sin vidrio (se deformaba)
                            .containerRelativeFrame(.horizontal)   // el ancho visible ya descuenta los márgenes: centrada, con las de los lados asomando
                            .deckTransition(deck, reduceMotion: reduceMotion)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Deck.sideMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .scrollPosition(id: $heroSlot, anchor: .center)   // centrada: las de los lados asoman igual
            .onAppear { if heroSlot == nil || (heroSlot ?? 0) >= copies * items.count { placeHero(middle) } }
            // Cambió la lista (al volver de ver algo, al refrescar): se queda en la que estabas si sigue; si no (o cambiaste el
            // filtro), la primera. Sin brincar al inicio cada vez.
            .onChange(of: items.map(\.id)) { old, new in
                let current = (heroSlot.map { old.isEmpty ? nil : old[$0 % old.count] }) ?? nil
                placeHero(middle + (current.flatMap { new.firstIndex(of: $0) } ?? 0))
            }
            PageDots(count: items.count, index: items.isEmpty ? 0 : (heroSlot ?? middle) % items.count)
                .frame(maxWidth: .infinity)
        }
        .task(id: heroSlot) { await tint.load(currentHero?.wide) }   // se cancela si pasas a otro
        // El toque solo al deslizar tú (no al acomodarla la app).
        .sensoryFeedback(.selection, trigger: heroSlot) { old, _ in old != nil && !placingHero }
    }

    /// Todo · Películas · Series: un botón chico (como el de Para ti), sin otro renglón.
    private func kindFilter(_ model: HomeModel) -> some View {
        Menu {
            Picker(selection: Binding(get: { model.spotlightKind ?? "" }, set: { model.spotlightKind = $0.isEmpty ? nil : $0 })) {
                Label("Todo", systemImage: "square.grid.2x2").tag("")
                Label("Películas", systemImage: "film").tag("movie")
                Label("Series", systemImage: "tv").tag("series")
            } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Text(model.spotlightKind == "movie" ? "Películas" : model.spotlightKind == "series" ? "Series" : "Todo")
                    .recipe(.footnote, color: DS.text).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
            .background(DS.fill, in: Capsule())
        }
        .accessibilityLabel(Text("Filtrar Destacado"))
        .accessibilityIdentifier("home-kind-filter")
    }

    private func hero(_ s: Suggestion) -> some View {
        // La tarjeta abre la ficha con su propio toque; «Ver» va aparte (un botón dentro de un NavigationLink puede abrir la
        // ficha en vez de reproducir).
        DeckCard(title: s.title, background: s.wide, logo: s.logo ?? Artwork.logoURL(metaID: s.imdb),
                 eyebrow: reasonText(s.reason), data: heroData(s), open: { openTitle = s.route }) {
            HeroActions { heroButtons(s) }   // con letra grande, uno debajo del otro
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

    /// Por qué está en el carrusel. Lo de tendencia no lleva nada: ya lo dice el título de la sección («En tendencia»).
    private func reasonText(_ reason: SuggestionReason) -> Text? {
        switch reason {
        case .trending: nil
        case .recommended: Text("Para ti")
        case .popular: Text("Popular")
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
    private func continueRail(_ model: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            NavigationLink(value: HomeListRoute(id: "continue")) {
                DSSectionHead(title: Text("Seguir viendo"), count: model.continueWatching.count, chevron: true, eyebrow: Text("Lo que tienes a medias"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            .accessibilityIdentifier("home-all-continue")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(model.continueWatching) { item in
                        Button { Task { await env.play(item) } } label: {
                            StillCard(title: item.title, art: item.background ?? item.poster, data: continueData(item), progress: item.progress)
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

    /// «Tu watchlist»: tarjetas con póster, datos y sinopsis en dos renglones que se deslizan juntos (cada renglón de Inicio
    /// con su forma: el destacado en carrusel, lo que sigues en panorámicas, lo pendiente en fichas y Mi lista en pósters).
    private func watchlist(_ model: HomeModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            NavigationLink(value: HomeListRoute(id: "watchlist")) {
                DSSectionHead(title: Text("Tu watchlist"), count: model.traktPending.count, chevron: true, source: .trakt, eyebrow: Text("Lo que dejaste pendiente"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                // Dos renglones (uno si son pocas), del alto que pida la letra; en el renglón, las primeras.
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(watchRow), spacing: DS.Space.s3), count: model.traktPending.count < 3 ? 1 : 2), spacing: DS.Space.s3) {
                    ForEach(model.traktPending.prefix(DS.Editorial.watchlistInRow)) { s in
                        let facts = [s.year.map(String.init), Vocabulary.genres(s.genres, language: language).first].compactMap { $0 }.joined(separator: " · ")
                        NavigationLink(value: s.route) {
                            WatchlistCard(title: s.title, poster: s.poster, facts: facts, overview: s.overview).titleZoomSource(s.route)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func topTen(_ model: HomeModel) -> some View {
        let service = model.topService
        let series = model.top(kind: "series"), films = model.top(kind: "movie")
        let movies = topMovies && !films.isEmpty || series.isEmpty
        let items = movies ? films : series
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .lastTextBaseline) {
                DSSectionHead(title: Text("Top 10 en \(service.name)"),
                              eyebrow: service.weekly ? Text("Lo más visto en tu país esta semana") : Text("Lo más visto hoy · JustWatch"))
                Spacer(minLength: DS.Space.s2)
                if !series.isEmpty, !films.isEmpty {
                    Picker(selection: $topMovies) { Text("Series").tag(false); Text("Películas").tag(true) } label: { EmptyView() }
                        .pickerStyle(.segmented).fixedSize()
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            // De qué servicio: una pastilla por cada uno, con su logo (la elegida, con su color).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(HomeModel.topServices) { s in
                        PlatformPill(name: s.name, logo: s.logo, brand: s.brand, selected: s.brand == service.brand) {
                            Task { await model.selectTop(s.brand) }
                        }
                        .accessibilityIdentifier("top-\(s.brand)")
                    }
                }
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .contentMargins(.vertical, DS.PlatformFan.pillStroke, for: .scrollContent)   // el borde de la elegida no se recorta
            .sensoryFeedback(.selection, trigger: service.brand)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: DS.Space.s3) {
                    if items.isEmpty {
                        if model.loadingTop { ShelfSkeleton() }
                        else { DSNotice(text: "Hoy no hay ranking de este servicio.").frame(width: DS.Size.cardMax) }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                        NavigationLink(value: s.route) { RankedPosterCard(rank: s.rank ?? i + 1, title: s.title, poster: s.poster, movement: s.movement, isNew: s.isNew, tint: DS.PlatformTint.color(service.brand)).titleZoomSource(s.route) }
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

    /// «T2 E5 · quedan 20 min».
    private func continueData(_ item: HomeItem) -> [String] {
        progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes).components(separatedBy: " · ")
    }

    /// «Sale hoy» (A + una portada): lo de hoy en grande con su hora; lo demás, en panorámicas. Sin nada hoy, «Sale pronto».
    @ViewBuilder private func upcoming(_ model: HomeModel) -> some View {
        let today = model.airingToday
        let rest = model.upcoming.filter { $0.id != today?.id }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: today == nil ? Text("Sale pronto") : Text("Sale hoy"), source: .trakt, eyebrow: Text("De las series que sigues"))
                .padding(.horizontal, DS.Space.gutter)
            if let today {
                NavigationLink(value: today.series.route) {
                    CoverCard(art: today.series.wide, logo: Artwork.logoURL(metaID: today.series.imdb), title: today.series.title,
                              why: airingWhen(today), detail: Text(verbatim: today.episodeLabel(env.services.episodeLabel)))
                }
                .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            }
            if !rest.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(rest) { a in
                            NavigationLink(value: a.series.route) {
                                WideCard(art: a.series.wide, logo: Artwork.logoURL(metaID: a.series.imdb), title: a.series.title, badge: airingWhen(a),
                                         caption: Text(verbatim: "\(a.series.title) · \(a.episodeLabel(env.services.episodeLabel))"))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    /// «Hoy · 21:00», «Mañana», «Viernes 24».
    private func airingWhen(_ a: Airing) -> Text {
        let locale = env.uiLocale
        if Calendar.current.isDateInToday(a.day) { return Text("Hoy") + Text(verbatim: " · ") + airingTime(a, locale: locale) }
        return dayName(a.day, locale: locale)
    }

    /// «Seguir viendo» completo: todo (el carrusel solo trae los últimos), en piezas anchas con su avance.
    private func allContinue(_ model: HomeModel) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s3), GridItem(.flexible())], spacing: DS.Space.s4) {
                ForEach(model.continueWatching) { item in
                    NavigationLink(value: route(item)) {
                        StillCard(title: item.title, art: item.background ?? item.poster,
                                  data: progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes).components(separatedBy: " · "),
                                  progress: item.progress, width: nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop(tint: tint.colors))
        .navigationTitle(Text("Seguir viendo")).navigationBarTitleDisplayMode(.inline)
    }
}
