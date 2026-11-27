import SwiftUI
import OrbitalCore
import OrbitalModels

struct HomeView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @State var home: ModelObserver<HomeModel>
    @State var tvNow: ModelObserver<TVNowModel>
    @State var heroKindOpen = false   // HB1-B: la pastilla del tipo en la portada (Duo)
    @State private var inbox: ModelObserver<InboxModel>
    /// «Por lo que viste»: el mazo de lo último que viste y sus relacionadas.
    @State private var because = ModelObserver(BecauseModel(AppEnvironment.shared.services))
    /// Canales: tus series siempre al aire.
    @State private var channels = ModelObserver(ChannelsModel(AppEnvironment.shared.services))
    @State private var tint = ArtTint()
    @State private var openTitle: TitleRoute?
    /// Las sugerencias que marcaste «No me interesa» (se van ya; Trakt y tu Orbital lo saben al momento).
    @State private var dismissedPicks: Set<String> = []
    /// La tarjeta al frente de la portada (su lugar en la fila).
    @State private var heroSlot: Int?
    /// El Top 10 de Netflix: series (por omisión) o películas.
    @State private var topMovies = false
    /// La ruleta de «Un Simpson al azar».
    @State private var rollingSimpsons = false
    /// Sale hoy › el mes completo.
    @State private var showingCalendar = false
    /// El filtro avanzado (el cajón de la sesión de componentes), desde la franja de arriba.
    @Namespace private var simpsonsZoom
    @State private var continueSort: ListSort = .added
    @State private var continueKind = ""
    /// El alto de cada renglón de «Tu watchlist», que crece con el tamaño de letra.
    @ScaledMetric(relativeTo: .body) private var watchRow = DS.Editorial.watchlistRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openRemote) var openRemote
    @Environment(\.scenePhase) private var scenePhase

    /// Bajaste: el encabezado se encoge (las historias se achican en su lugar).
    @State private var collapsed = false
    /// Ya se vio una vez: al volver, la recarga espera a que termine el cambio de pestaña.
    @State private var appeared = false

    init() {
        _home = State(wrappedValue: ModelObserver(HomeModel(AppEnvironment.shared.services)))
        // El sondeo es de toda la app (arranca en RootView): aquí solo se ve.
        _tvNow = State(wrappedValue: ModelObserver(AppEnvironment.shared.tvNow))
        _inbox = State(wrappedValue: ModelObserver(AppEnvironment.shared.inbox))
    }

    /// Lo de arriba: «Termina de preparar Orbital», sin internet, lo que se ve en la TV y lo que la TV te mandó. En partes: el compilador de la CI
    /// (Xcode 26.3) no alcanzaba a revisar todo Inicio de una vez.
    @ViewBuilder private func topCards(_ model: HomeModel) -> some View {
        HomeLearnTop()   // «Termina de preparar Orbital» (las historias de «Aprende» viven solo en Ajustes desde el 18 nov)
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
                .transition(DS.Motion.appear(reduceMotion))
        }
        // Lo que la TV mandó con «Enviar al iPhone»: una tarjeta pequeña, bajo «Viendo en la TV».
        ForEach(inbox.model.fromTV) { item in
            FromTVCard(item: item,
                       onWatch: { inbox.model.watched(item); Task { await env.play(item) } },
                       onDownload: { Task { await inbox.model.downloadFromCard(item) } },
                       onDismiss: { inbox.model.dismiss(item) })
                .padding(.horizontal, DS.Space.gutter)
                .transition(DS.Motion.appear(reduceMotion))
        }
    }

    /// Las filas de abajo, escalonadas: lo que sale de tus series, sugerencias, «Porque viste», canales, Top 10 y Mi lista.
    @ViewBuilder private func lowerRows(_ model: HomeModel, kind: String?, picks: [Suggestion], pending: [Suggestion]) -> some View {
        // Lo que sale de tus series (solo series: con «Películas» en la barra, no se pinta). En el tablero va en el panel, bajo
        // «Seguir viendo» (Fernando, 22 nov 2026).
        if kind != "movie", !model.timeline.isEmpty, !board {
            ReleaseTimeline(airings: model.timeline, onOpen: { openTitle = $0 }, onCalendar: { showingCalendar = true })
                .entrance("home:timeline", order: 0)   // las filas de abajo entran escalonadas
        }
        // Tus recomendaciones de Trakt.
        if !picks.isEmpty {
            Rail(title: "Sugerencias para ti", route: HomeListRoute(id: "foryou"), eyebrow: Text("Recomendadas por Trakt"), quiet: true) {
                // Mantener el dedo abre el menú, como en Explorar (antes no había menú: al soltar se abría la ficha).
                ForEach(picks) { s in TitleLink(route: s.route).contextMenu { SuggestionActions(suggestion: s, onDismiss: dismissPick) } }
            }
            .entrance("home:picks", order: 1)
        }
        HomeBecause(model: because.model, kind: kind).entrance("home:because", order: 2)
        if kind != "movie" {   // solo series; la dona de «Un Simpson al azar» va en su encabezado (I9)
            HomeChannels(model: channels.model, simpsons: env.services.capabilities.personal ? { rollingSimpsons = true } : nil, simpsonsZoom: simpsonsZoom).entrance("home:channels", order: 3)
        }
        // El Top 10 de un servicio (Netflix, Disney+, HBO Max…), elegido con su pastilla: series o películas, cada una con su 1 al 10.
        if model.hasAnyTop { HomeTopTen(model: model, topMovies: $topMovies).entrance("home:top", order: 4) }
        if !pending.isEmpty { watchlist(model, items: pending).entrance("home:watchlist", order: 5) }
    }

    /// Abre con «Destacado» (lo que se está viendo esta semana, para ti); lo que dejaste a medias va justo debajo.
    private func spotlightPart(_ model: HomeModel) -> some View {
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

    /// La página de Inicio, fuera de `body` para que el compilador la revise a tiempo.
    private func page(_ model: HomeModel, kind: String?) -> some View {
        let fits: (String) -> Bool = { kind == nil || $0 == kind }
        let continuing = model.continueWatching.filter { fits($0.kind) }
        let picks = model.forYouPicks.filter { fits($0.kind) && !dismissedPicks.contains($0.imdb) }
        let pending = model.traktPending.filter { fits($0.kind) }
        // Perezosa: al volver a Inicio se acomoda solo lo que se ve, no la página entera (cada vuelta costaba 0.7 s en la Mac;
        // Fernando, 22 nov 2026: «le sigo picando y todavía se tarda»).
        return ShelfStack(lazy: Self.lazyPage, spacing: DS.Layout.betweenSections) {
            topCards(model)
            if board, !model.spotlight.isEmpty { boardTop(model, continuing: continuing, kind: kind) } else { cinema(model, continuing: continuing) }
            lowerRows(model, kind: kind, picks: picks, pending: pending)
            // Tus favoritos viven en Para ti › Tuyo (Fernando, 30 oct 2026): Inicio termina en Mi lista.
        }
        // El ancho es el de la columna (I2, `WindowMetrics.column`): si una fila pide más (letra grande, el SE), no empuja la página.
        // Ni `containerRelativeFrame` ni medir el ScrollView: con el control abierto los dos cuentan el panel (docs/ios-interfaz.md).
        .frame(width: WindowMetrics.column.width, alignment: .leading)
        .refreshOrbitHost(front: true)   // la luna de tirar para actualizar, delante de la portada (RF1)
        .padding(.top, DS.Space.s2)         // el destacado no se pega al saludo (el mismo aire que Para ti y Buscar)
        // La barra de pestañas de abajo ya deja su espacio: más aquí era aire muerto al final. Con las pestañas arriba (C1, Mac
        // e iPad ancho) no hay barra abajo y la última fila se pegaba a la orilla.
        .padding(.bottom, TopRow.tabsInLogoRow ? DS.Layout.screenBottom : DS.Space.s2)
        .animation(DS.Motion.enter(reduceMotion), value: tvNow.model.now != nil)
        .animation(DS.Motion.enter(reduceMotion), value: inbox.model.fromTV.map(\.id))
        .animation(DS.Motion.smooth(reduceMotion), value: board)   // al girar el iPad o abrir el control
    }

    /// «Cine»: la portada de orilla a orilla, «Seguir viendo» encimado en su borde y «Decide por mí» (iPhone, iPad parado, ventana angosta).
    @ViewBuilder private func cinema(_ model: HomeModel, continuing: [HomeItem]) -> some View {
            // Abre con «Destacado» (lo que se está viendo esta semana, para ti); lo que dejaste a medias va justo debajo, encimado
            // en su borde, como «A continuación» en la tele (RI2 en la Mac, 16 nov 2026).
            if !model.spotlight.isEmpty { spotlightPart(model) }
            if model.spotlight.isEmpty, model.continueWatching.isEmpty, model.isLoading {
                HeroSkeleton()   // la primera vez: el lugar ya reservado mientras llega
            }
            // El orden del Inicio nuevo (docs/producto/inicio-benchmark/): lo tuyo primero, luego lo que sale de tus series,
            // tus sugerencias, el Top 10 y Mi lista.
            if !continuing.isEmpty {
                continueRail(model, items: continuing).perfTag("home.rail")
                    // En oscuro, encimado en el borde de abajo de la portada (que se funde con el fondo): lo que tienes a
                    // medias se ve sin bajar. En claro la portada es una tarjeta y su título no se leería encima.
                    .padding(.top, model.spotlight.isEmpty ? 0 : (scheme == .dark ? -heroLift : DS.Layout.betweenSubsections - DS.Layout.betweenSections))   // en claro, 24 de la tarjeta (antes 0: se tocaban)
            } else if WindowMetrics.roomy, spotlightItems(model).count > 1 {
                // RI2: en la Mac, sin nada a medias, lo que sigue en la portada va en esa misma fila encimada (como la tele).
                upNextRail(model).padding(.top, scheme == .dark ? -heroLift : DS.Layout.betweenSubsections - DS.Layout.betweenSections)
            } else if !model.isLoading, model.spotlight.isEmpty, model.continueWatching.isEmpty, !model.offline {   // sin red, el aviso de arriba ya lo dice
                DSEmptyState(symbol: "play.rectangle.on.rectangle", title: Text("Todavía nada"), message: Text("Aquí aparece lo que vas viendo, en el iPhone y en Orbital."))
            }
            // «Decide por mí», la misma puerta de Explorar bajo «Seguir viendo» (DE2, 13 nov 2026). C6: con espacio, una tarjeta al
            // final de «Seguir viendo» (sola si no hay nada a medias).
            if !WindowMetrics.roomy || continuing.isEmpty { DecideHomeRow(compact: WindowMetrics.roomy) { openTitle = $0 }.frame(maxWidth: WindowMetrics.roomy ? DS.HomeBoard.decideWidth + 2 * DS.Space.gutter : nil, alignment: .leading).padding(.horizontal, WindowMetrics.roomy ? DS.Space.gutter : 0) }
    }

    /// MI2 · II1 (`HomeBoard`): la portada en dos tercios y, a su derecha, lo tuyo: lo que tienes a medias, lo nuevo de tus series y «Decide por mí».
    private func boardTop(_ model: HomeModel, continuing: [HomeItem], kind: String?) -> some View {
        HStack(alignment: .top, spacing: DS.HomeBoard.gap) {
            // Solo el ancho: el alto lo pone la portada (el del panel, `HomeBoard.heroAspect`) y los puntos van debajo. Con el
            // alto fijo, los puntos cabían adentro, el arte se encogía y quedaba con ~30 pt de hueco a cada lado: corrido de las
            // filas de abajo y más bajito que el panel (Fernando, 24 nov 2026: «los pósters están como descentrados»).
            spotlightPart(model).frame(width: HomeBoard.heroWidth)
            HomeBoardPanel(rows: { limit in boardRows(model, continuing: continuing, limit: limit) }, news: {
                if kind != "movie", !model.timeline.isEmpty { ReleaseTimeline(airings: model.timeline, onOpen: { openTitle = $0 }, onCalendar: { showingCalendar = true }, inset: 0) }
            }, decide: { DecideHomeRow(compact: true) { openTitle = $0 } })
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    /// Los renglones del panel: lo que tienes a medias (tocar sigue; mantener, el menú) o, sin nada, lo que sigue en la portada.
    @ViewBuilder private func boardRows(_ model: HomeModel, continuing: [HomeItem], limit: Int) -> some View {
        if continuing.isEmpty {
            DSSectionHead(title: Text("Lo que sigue"), eyebrow: Text("En la portada"))
            let items = spotlightItems(model)
            ForEach(items.indices.filter { $0 != (heroSlot ?? 0) }.prefix(limit), id: \.self) { i in
                Button { withAnimation(DS.Motion.smooth(reduceMotion)) { heroSlot = i } } label: {
                    BoardRow(title: titleName(items[i].title, id: items[i].imdb, kind: items[i].kind), art: items[i].wide, data: HomeHeroSlide.data(items[i], language: env.services.appSettings.uiLanguage), fallback: items[i].poster)
                }
                .buttonStyle(.plain).accessibilityHint(Text("Lo pasa al frente de la portada"))
            }
        } else {
            NavigationLink(value: HomeListRoute(id: "continue")) {
                DSSectionHead(title: Text("Seguir viendo"), count: continuing.count, chevron: true, eyebrow: Text("Lo que tienes a medias"))
            }
            .buttonStyle(.plain).accessibilityIdentifier("home-all-continue")
            ForEach(continuing.prefix(limit)) { item in
                Button { env.ui.playerSource = PlayerZoomID(metaID: item.metaID, slot: "continue"); Task { await env.play(item) } } label: {
                    BoardRow(title: titleName(item.title, id: item.metaID, kind: item.kind), art: item.background ?? item.poster, data: continueData(item), progress: item.progress, fallback: item.background == nil ? nil : item.poster)
                        .playerZoomSource(PlayerZoomID(metaID: item.metaID, slot: "continue"))
                }
                .buttonStyle(.plain)
                .contextMenu { continueMenu(model, item: item) }
            }
        }
    }

    /// Tablero (`HomeBoard`) o cine: la ventana acostada y ancha, sin letra de accesibilidad.
    private var board: Bool { HomeBoard.isOn(typeSize) }

    var body: some View {
        let _ = BodyCount.tick("home", why: Self._printChanges)   // V9: cuántas veces se pinta y por qué (`-perf-bodies`, `-perf-why`)
        let model = home.model
        ScrollView { page(model, kind: model.spotlightKind) }   // el tipo de la barra (Todo · Películas · Series) filtra toda la página
        // Un Bool (Equatable): el encabezado solo se vuelve a pintar al cruzar la línea, no en cada cuadro del desplazamiento.
        .scrollEdgeEffectStyle(.hard, for: .top)   // el encabezado propio (HE1-B) tapa lo que pasa por debajo, como la barra de antes
        // Con margen (se encoge pasando `collapseAt` y crece hasta volver bajo `expandAt`): al encogerse, el encabezado cambia de
        // alto y eso mueve un poco el desplazamiento; sin margen, encoger y crecer se alternaban sin fin y el iPhone cerraba la app
        // (Fernando, 4 nov: «cuando bajas y le picas X, truenan»).
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, scrolled in
            if !collapsed, scrolled > DS.HomeHeaderScroll.collapseAt { collapsed = true }
            else if collapsed, scrolled < DS.HomeHeaderScroll.expandAt { collapsed = false }
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazado (capturas de las filas de abajo)
        #endif
        // RF2 (25 nov 2026, «sigue quedándose un brinco cuando le das refresh en Inicio»): la luna espera solo a la página; el
        // tono del fondo y «Por lo que viste» llegan después de que la página regresó, no mientras regresa.
        .orbitalRefreshable {   // tirar para actualizar, con la luna de Orbital (también en Release: A2, 10 nov)
            await home.model.refresh()
            Task { @MainActor in
                try? await Task.sleep(for: DS.Motion.tabSettle)   // lo que dura el regreso
                await because.model.load()
                await tint.load(currentHero?.wide)
            }
        }
        .background(Backdrop(tint: tint.colors))
        // Sin título: arriba van el ícono y «Orbital» (el carácter de la app), también al bajar.
        .navigationTitle(Text(verbatim: "")).toolbarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $rollingSimpsons) { SimpsonsRoulette(tint: tint.colors).navigationTransition(.zoom(sourceID: "simpsons", in: simpsonsZoom)).environment(env).duoBars() }
        .onChange(of: env.ui.openSimpsons, initial: true) { _, wants in
            guard wants else { return }
            env.ui.openSimpsons = false
            rollingSimpsons = true
        }
        .appSheet(isPresented: $showingCalendar) {
            ReleaseCalendarView { route in showingCalendar = false; openTitle = route }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .task(priority: .utility) {
            #if DEBUG
            if Demo.isOn, Demo.open?.hasPrefix("simpsons") == true {   // `-demo-open simpsons`: la ruleta sola
                await env.simpsons.prefetch(); rollingSimpsons = true; return
            }
            if Demo.isOn, Demo.widget != nil {   // la galería de widgets: también «Un Simpson del día»
                await SimpsonsWidgetPublisher.publishIfNeeded(env.simpsons, seasons: env.services.appSettings.simpsonsSeasons)
            }
            #endif
            // La ficha de Los Simpson (~650 KB) fuera del arranque: primero Inicio y sus imágenes; si tocas la dona antes, la pide ella.
            try? await Task.sleep(for: .seconds(DS.Simpsons.prefetchDelay))
            await env.simpsons.prefetch()
            await SimpsonsWidgetPublisher.publishIfNeeded(env.simpsons, seasons: env.services.appSettings.simpsonsSeasons)   // el widget «Un Simpson del día»
        }
        // El encabezado propio de Inicio (HE1-B): el logo, la cápsula y los tipos (sin historias desde el 18 nov).
        .toolbar(Self.headerInBar ? .visible : .hidden, for: .navigationBar)
        .toolbar { if Self.headerInBar { barHeader } }
        .macTopShade()   // en la Mac, lo que sube no pasa crudo detrás del logo y las pestañas
        .safeAreaBar(edge: .top) { if !Self.headerInBar {
            HomeHeader(kind: Binding(get: { model.spotlightKind ?? "" }, set: { model.spotlightKind = $0.isEmpty ? nil : $0 }),
                       collapsed: collapsed,
                       showsRemote: showsRemote,
                       remote: { openRemote?() },
                       avatar: look.avatar)
        } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: HomeListRoute.self) { route in homeList(route) }
        .openingTitles(item: $openTitle)   // en el iPad y la Mac, en el panel de la derecha
        .task {
            // De vuelta a la pestaña: primero termina el salto de la barra (recargar a la par lo trababa) y luego se refresca.
            if appeared {
                try? await Task.sleep(for: DS.Motion.tabSettle)
                guard !Task.isCancelled else { return }
            }
            appeared = true
            await reload(ifStale: true)
        }   // volver de otra pestaña o de una ficha no lo vuelve a pedir todo
        .onTabHidden { hidden in if !hidden { Task { await reload(ifStale: true) } } }   // la baraja de la Mac no vuelve a correr `.task`
        .onChange(of: env.watchedSomething) { Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload(ifStale: true) } } }   // al volver a la app
    }

    /// «Mi lista» o «Tu watchlist» completas, en cuadrícula (desde el chevron de su encabezado).
    @ViewBuilder private func homeList(_ route: HomeListRoute) -> some View {
        if route.id == "continue" { allContinue(home.model) } else { titleGrid(route) }
    }

    /// Con orden y filtros (películas o series, género, ocultar lo visto), como toda lista abierta desde «Ver todo».
    private func titleGrid(_ route: HomeListRoute) -> some View {
        let items: [Suggestion] = route.id == "watchlist" ? home.model.traktPending : home.model.forYouPicks
        return ScrollView {
            SortableGrid(listID: "home:\(route.id)", items: items, collections: env.collections) { s, width in
                if let list = route.list {
                    TitleLink(route: s.route, width: width).contextMenu { listActions(s, in: list) }
                } else {
                    TitleLink(route: s.route, width: width)
                }
            }
                .padding(.bottom, DS.Layout.screenBottom)
        }
        .background(Backdrop(tint: tint.colors))
        .dsNavigationTitle(route.id == "watchlist" ? "Mi lista" : "Sugerencias para ti")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Lo tuyo y el tono del fondo (al abrir, al deslizar hacia abajo y al volver de ver algo). Lo pendiente por subir
    /// se sube solo y ya no se anuncia bajo el título («N cambios por subir»: no se quería ahí).
    private func reload(ifStale: Bool = false) async {
        // De vuelta de una ficha o de otra pestaña, con lo de hace menos de un minuto: nada que pedir (antes «Por lo que
        // viste» y el tono se volvían a pedir siempre y repintaban Inicio entera justo al regresar).
        if ifStale, !home.model.isStale() { return }
        async let related: Void = because.model.load()   // a la par (Trakt lo guarda: volver a pedirlo es barato)
        if ifStale { await home.model.refreshIfStale() } else { await home.model.refresh() }
        Perf.mark("home.done")
        await tint.load(currentHero?.wide)
        await related
    }

    /// Cuánto se encima «Seguir viendo» sobre la portada: solo en oscuro (en claro la portada es una tarjeta y no se leería).
    private var heroOverlap: CGFloat { scheme == .dark && !board ? DS.HomeHero.overlap : 0 }
    /// Cuánto sube la fila de abajo sobre la portada (en oscuro). Con puntero (Mac, iPad ancho) los puntos van en su renglón bajo
    /// la portada: subir lo mismo los tapaba con «Lo que tienes a medias» (27 nov 2026); ahí sube solo hasta quedar bajo ellos.
    private var heroLift: CGFloat { WindowMetrics.roomy ? DS.Layout.betweenSections - DS.Space.s2 : DS.Layout.betweenSections + heroOverlap }

    /// Al dejar picado un título de una de tus listas: ver, descargar, en la TV, marcar como vista y quitarlo de la lista.
    @ViewBuilder private func listActions(_ s: Suggestion, in list: SaveDestination) -> some View {
        let model = home.model
        SuggestionActions(suggestion: s, list: list, onWatched: { model.setShown($0.imdb, in: list, shown: false) }) { s in
            Task { await env.remove(s, from: list) { shown in model.setShown(s.imdb, in: list, shown: shown) } }
        }
    }

    /// «No me interesa» en una sugerencia: se quita ya y deja de sugerirse en el iPhone y en tu Orbital.
    private func dismissPick(_ s: Suggestion) {
        dismissedPicks.insert(s.imdb)
        let services = env.services
        Task {
            await services.forYou.dismiss(s.imdb)
            if services.orbital.isConfigured { await services.forYouRemote.dismiss(s.imdb) }
        }
    }

    private func route(_ item: HomeItem) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }

    /// Cómo se ve Inicio (carrusel, avatar), en vivo: al cambiarlo en Ajustes, Inicio se vuelve a pintar.
    var look: AppSettings {
        var settings = env.services.appSettings
        #if DEBUG
        if Demo.isOn {   // `-demo-avatar comet`: para ver cada avatar en las capturas
            if let v = Demo.value(after: "-demo-avatar") { settings.avatar = v }
        }
        #endif
        return settings
    }


    /// Cuántos de «Destacado» van en la portada.
    private func spotlightItems(_ model: HomeModel) -> [Suggestion] { Array(model.spotlightShown.prefix(HomeModel.heroCount)) }

    /// El que está al frente de la portada (el fondo toma su color).
    private var currentHero: Suggestion? {
        let items = spotlightItems(home.model)
        guard !items.isEmpty else { return nil }
        return items[min(heroSlot ?? 0, items.count - 1)]
    }

    /// Ancho entre alto de la portada: casi un póster en el iPhone, más baja en pantallas cortas y apaisada en ventana ancha.
    private var heroAspect: CGFloat { board ? HomeBoard.heroAspect : DS.HomeHero.current }

    /// La portada (docs/producto/inicio-benchmark/): el arte de borde a borde, detrás de la barra, que se desliza entre lo
    /// que todos están viendo. Cada título con su porqué en turquesa, su logo, sus datos y «Ver». Abajo, los puntos; encima de
    /// su borde entra «Seguir viendo». El fondo toma el color del que está al frente.
    private func spotlightCarousel(_ model: HomeModel) -> some View {
        let items = spotlightItems(model)
        let index = min(heroSlot ?? 0, max(0, items.count - 1))
        // Con puntero (Mac, iPad ancho) los puntos van en su renglón bajo la portada, con ‹ ›, y cada uno lleva a la suya:
        // encima de la portada, el clic se lo quedaba ella y abría la ficha (Fernando, 22 nov 2026: «el selector de
        // diferentes películas en la principal no funciona… los puntitos que vienen abajo»). En el iPhone se desliza con el
        // dedo y los puntos solo cuentan, encima.
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            heroScroller(items, index: index)
            if WindowMetrics.roomy {
                PageDots(count: items.count, index: index) { i in withAnimation(DS.Motion.smooth(reduceMotion)) { heroSlot = i } }
                    .padding(.leading, DS.Space.gutter * (scheme == .dark || board ? 1 : 2) - DS.Space.s2)   // la orilla del texto (la flecha trae su aire)
            }
        }
    }

    private func heroScroller(_ items: [Suggestion], index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {   // recorta: carrusel de página completa (lo de al lado no debe asomar) · sin flechas: página completa
            LazyHStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                    HomeHeroSlide(s: s, aspect: heroAspect, overlap: heroOverlap, tile: board) { openTitle = $0 }.containerRelativeFrame(.horizontal).id(i)   // ds-exception: mide el carrusel (ya del ancho de la página). Mantener y mover: se inclina
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $heroSlot)
        .clipShape(RoundedRectangle(cornerRadius: board ? DS.Radius.xxl : 0, style: .continuous))   // el tablero: la tarjeta al pasar de una a otra
        .overlay(alignment: .topTrailing) { heroKind }
        .overlay(alignment: .bottom) {
            if !WindowMetrics.roomy {
                PageDots(count: items.count, index: index)
                    .padding(.bottom, heroOverlap + DS.Space.s2)
                    .allowsHitTesting(false)   // tocar los puntos no abre la ficha
            }
        }
        // En oscuro el arte se funde con el fondo y sube detrás de la barra; en claro es una tarjeta (no pasa detrás).
        .ignoresSafeArea(edges: scheme == .dark && !board ? .top : [])
        // Cambió la lista (al volver de ver algo, al cambiar el tipo): te quedas en el que estabas si sigue; si no, el primero.
        .onChange(of: items.map(\.id)) { old, new in
            let current = heroSlot.flatMap { old.indices.contains($0) ? old[$0] : nil }
            heroSlot = current.flatMap { new.firstIndex(of: $0) } ?? 0
        }
        // Al cambiar el tamaño de la ventana el carrusel se quedaba a medio camino entre dos portadas (se asomaba el «Ver» de
        // la siguiente junto al panel, Mac, 22 nov 2026): ya quieta la ventana, vuelve a acomodarse en la que estabas.
        .task(id: WindowMetrics.column.width) {
            guard let slot = heroSlot, (try? await Task.sleep(for: DS.HomeHero.resizeSettle)) != nil else { return }
            heroSlot = nil
            await Task.yield()
            heroSlot = slot
        }
        .task(id: heroSlot) { await tint.load(currentHero?.wide) }   // se cancela si pasas a otro
        .dsFeedback(.selection, trigger: heroSlot) { old, _ in old != nil }
    }

    /// «Seguir viendo»: lo que dejaste a medias (o el siguiente episodio), en piezas anchas con su avance. Tocar una sigue
    /// donde ibas; mantenerla: la ficha, la TV o quitarla.
    private func continueRail(_ model: HomeModel, items: [HomeItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            NavigationLink(value: HomeListRoute(id: "continue")) {
                DSSectionHead(title: Text("Seguir viendo"), count: items.count, chevron: true, eyebrow: Text("Lo que tienes a medias"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            .accessibilityIdentifier("home-all-continue")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(items) { item in
                        Button {
                            env.ui.playerSource = PlayerZoomID(metaID: item.metaID, slot: "continue")
                            Task { await env.play(item) }
                        } label: {
                            StillCard(title: titleName(item.title, id: item.metaID, kind: item.kind), art: item.background ?? item.poster, data: continueData(item), progress: item.progress,
                                      fallback: item.background == nil ? nil : item.poster)
                                .playerZoomSource(PlayerZoomID(metaID: item.metaID, slot: "continue"))
                        }
                        .buttonStyle(.plain)
                        // Al dejarlo picado se levanta con la esquina de la tarjeta (no un rectángulo) y, al soltar, regresa
                        // sin que la orilla de la fila lo corte (`scrollClipDisabled` abajo).
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .contextMenu { continueMenu(model, item: item) }
                        // Lo que terminaste (o quitaste) se va encogiéndose y lo siguiente entra desde la derecha.
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                          removal: .scale(scale: DS.Motion.leaveScale).combined(with: .opacity)))
                    }
                    if WindowMetrics.roomy { DecideHomeRow(compact: true) { openTitle = $0 }.frame(width: DS.HomeBoard.decideWidth) }   // C6
                }
                .scrollTargetLayout()
                .animation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade, value: items.map(\.id))
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .rowEdge(.bleeds)
            .pagingArrows()   // C4: ‹ › con el puntero
            .edgeBump()
        }
    }

    /// Mantener una pieza de «Seguir viendo»: la ficha, la TV o quitarla.
    @ViewBuilder private func continueMenu(_ model: HomeModel, item: HomeItem) -> some View {
        Button("Ver la ficha", systemImage: "info.circle") { openTitle = route(item) }
        if env.services.orbital.isConfigured {
            Button("Ver en la TV", systemImage: "tv.and.mediabox") { Task { await env.playOnTV(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title) } }
        }
        Button("Quitar de Seguir viendo", systemImage: DS.Symbol.remove) { removeFromContinue(model, item) }
    }

    /// «Quitar de Seguir viendo» con «Deshacer»: Trakt y la biblioteca se enteran cuando el aviso ya se fue.
    private func removeFromContinue(_ model: HomeModel, _ item: HomeItem) {
        env.notify("Quitada de Seguir viendo", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { model.undoDismiss(item) }
        Task { await model.dismiss(item, undoWindow: DS.Timing.undoCommit) }
    }

    /// RI2 (Mac, sin nada a medias): los que siguen en la portada, en tarjetas anchas encimadas en su borde, como «A
    /// continuación» en la tele. Tocar uno lo pasa al frente (la ficha se abre desde la portada).
    private func upNextRail(_ model: HomeModel) -> some View {
        let items = spotlightItems(model)
        let current = min(heroSlot ?? 0, max(0, items.count - 1))
        let next = items.indices.filter { $0 != current }.sorted { ($0 - current + items.count) % items.count < ($1 - current + items.count) % items.count }
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSectionHead(title: Text("Lo que sigue"), eyebrow: Text("En la portada")).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(next, id: \.self) { i in
                        Button {
                            withAnimation(DS.Motion.smooth(reduceMotion)) { heroSlot = i }
                        } label: {
                            StillCard(title: titleName(items[i].title, id: items[i].imdb, kind: items[i].kind), art: items[i].wide, data: HomeHeroSlide.data(items[i], language: env.services.appSettings.uiLanguage), fallback: items[i].poster)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Lo pasa al frente de la portada"))
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .rowEdge(.bleeds)
            .pagingArrows()   // C4
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("home-up-next")
    }

    /// «Mi lista» (tu watchlist de Trakt, también sin Trakt en el teléfono): tarjetas con póster, datos y sinopsis en dos renglones que se deslizan juntos (cada renglón de Inicio
    /// con su forma: el destacado en carrusel, lo que sigues en panorámicas, lo pendiente en fichas y Mi lista en pósters).
    private func watchlist(_ model: HomeModel, items: [Suggestion]) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            NavigationLink(value: HomeListRoute(id: "watchlist")) {
                DSSectionHead(title: Text("Mi lista"), count: items.count, chevron: true, eyebrow: Text("Lo que dejaste pendiente"))
            }
            .buttonStyle(.plain).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                // Dos renglones (uno si son pocas), del alto que pida la letra; en el renglón, las primeras.
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(watchRow), spacing: DS.Space.s2), count: items.count < 3 ? 1 : 2), spacing: DS.Space.s2) {
                    ForEach(items.prefix(DS.Editorial.watchlistInRow)) { s in
                        let facts = [s.year.map(String.init), Vocabulary.genres(s.genres, language: language).first].compactMap { $0 }.joined(separator: " · ")
                        // La sinopsis de Trakt viene en inglés: en otro idioma, sin ella (salía en inglés en Inicio, 22 nov 2026).
                        TitleNavigationLink(route: s.route) {
                            WatchlistCard(title: titleName(s.title, id: s.imdb, kind: s.kind), poster: s.poster, facts: facts, overview: env.services.appSettings.titleLanguage == "en" ? s.overview : "").titleZoomSource(s.route)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { listActions(s, in: .myList) }
                    }
                }
                .scrollTargetLayout()
            }
            .rowEdge(.bleeds)   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .pagingArrows()   // C4
        }
    }

    /// «T2 E5 · quedan 20 min»; «Nuevo · T38 E5» si ibas al día y ya salió el episodio que sigue.
    private func continueData(_ item: HomeItem) -> [String] {
        let facts = progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes, language: env.language).components(separatedBy: " · ")
        // R3 y PT11 (4 nov 2026): lo que pediste a Real-Debrid y todavía baja: «Bajando en la nube · 42 % · T1 E2», como en
        // todos lados (nunca «Bajando · 42 %» suelto).
        let requests = env.services.debridRequests
        requests.track()
        if let request = requests.request(metaID: item.metaID, videoID: item.videoID), request.state.isActive {
            // El estado primero: si no cabe todo, `DataLine` suelta el episodio, no el avance.
            return [DebridRequestWords.title(request) { Strings.tr($0, language: env.services.appSettings.uiLanguage) }, facts.first].compactMap { $0 }
        }
        guard item.isNew == true else { return facts }
        return [Strings.tr("Nuevo", language: env.services.appSettings.uiLanguage)] + facts
    }

    /// «Seguir viendo» completo: todo (el carrusel solo trae los últimos), en piezas anchas con su avance.
    private func allContinue(_ model: HomeModel) -> some View {
        let kept = model.continueWatching.filter { continueKind.isEmpty || $0.kind == continueKind }
        let shown = continueSort == .title ? kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : kept
        return ScrollView {
            LazyVGrid(columns: DS.Poster.pairColumns(spacing: DS.Space.s2, wideMin: DS.Poster.stillWideMin), spacing: DS.Space.s4) {
                ForEach(shown) { item in
                    TitleNavigationLink(route: route(item)) {
                        StillCard(title: titleName(item.title, id: item.metaID, kind: item.kind), art: item.background ?? item.poster, data: continueData(item),
                                  progress: item.progress, width: nil, fallback: item.background == nil ? nil : item.poster)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Quitar de Seguir viendo", systemImage: DS.Symbol.remove) { removeFromContinue(model, item) } }
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Layout.screenBottom)
        }
        .background(Backdrop(tint: tint.colors))
        .dsNavigationTitle("Seguir viendo").navigationBarTitleDisplayMode(.inline)
        // Ordenar y filtrar, como toda lista abierta desde «Ver todo».
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ContinueSortMenu(sort: $continueSort, kind: $continueKind) }
        }
    }
}
