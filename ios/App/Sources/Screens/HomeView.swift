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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openRemote) private var openRemote

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
                if !model.continueWatching.isEmpty {
                    heroCarousel(model)
                } else if !model.isLoading {
                    DSNotice(text: "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.").padding(.horizontal, DS.Space.gutter)
                }
                if model.continueWatching.count > Self.heroCount { alsoHad(model) }
                if !model.myList.isEmpty {
                    Rail(title: "Mi lista", count: model.myList.count, route: HomeListRoute(id: "mylist")) {
                        ForEach(model.myList) { item in
                            TitleLink(route: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster))
                        }
                    }
                }
                if !model.upcoming.isEmpty { upcoming(model) }
                if !model.traktPending.isEmpty {
                    // «Tu watchlist» (Trakt), con el nombre de la TV; dentro, todo está en tu watchlist: la etiqueta sobra.
                    Rail(title: "Tu watchlist", count: model.traktPending.count, route: HomeListRoute(id: "watchlist")) {
                        ForEach(model.traktPending) { s in TitleLink(route: s.route) }
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
        .navigationTitle(scrolledDown ? scrolledTitle : greeting).toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .subtitle(syncText)
        .toolbar {
            // Sin nada en la TV, el control de tu Orbital vive aquí (con algo reproduciéndose, en el accesorio de abajo).
            if let openRemote, tvNow.model.now == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openRemote) { Image(systemName: "av.remote") }
                        .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) { ProfileButton(avatar: look.avatar) }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: HomeListRoute.self) { route in homeList(route) }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: env.watchedSomething) { Task { await reload() } }
    }

    /// «Mi lista» o «Tu watchlist» completas, en cuadrícula (desde el chevron de su encabezado).
    private func homeList(_ route: HomeListRoute) -> some View {
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
    private func reload() async {
        await home.model.refresh()
        let work = env.services.pending.load()      // una sola lectura por actualización, no una por cada pintado
        pendingCount = work.progress.count + work.traktWatched.count
        await tint.load(currentHero.flatMap { $0.background ?? $0.poster })
    }

    /// «Hola, Fer» (el nombre de tu perfil; sin nombre, «Hola»): lo primero que se lee en Inicio.
    private var greeting: Text {
        let name = env.services.appSettings.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Text("Hola") : Text("Hola, \(name)")
    }

    /// El título con la barra encogida: lo más útil que haya.
    private var scrolledTitle: Text {
        if let now = tvNow.model.now { return Text("En la TV: \(now.live ? (now.channel ?? now.title) : now.title)") }
        if let airing = home.model.airingToday { return Text("Sale hoy: \(airing.series.title)") }
        let left = home.model.continueWatching.count
        if left > 1 { return Text("\(left) por terminar") }
        return Text("Inicio")
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

    /// Cuántos de «Seguir viendo» van en el carrusel del destacado; el resto, en «También tenías».
    private static let heroCount = 3

    /// El que está al frente del carrusel (el fondo toma su color).
    private var currentHero: HomeItem? {
        let items = Array(home.model.continueWatching.prefix(Self.heroCount))
        guard !items.isEmpty else { return nil }
        return items[(heroSlot ?? 0) % items.count]
    }

    /// «Seguir viendo»: tarjetas en carrusel (`DeckCard`) con las que siguen a los lados, más chicas y desenfocadas, en
    /// coverflow o abanico (Ajustes › Inicio); el fondo de la pantalla toma el color del que está al frente.
    private func heroCarousel(_ model: HomeModel) -> some View {
        let items = Array(model.continueWatching.prefix(Self.heroCount))
        let deck = DeckStyle(rawValue: look.homeDeck) ?? .coverflow
        // Una vuelta infinita: las mismas tarjetas repetidas muchas veces y se empieza a la mitad; al llegar a la última
        // sigue la primera (y hacia atrás igual). Con una sola, no hay vuelta.
        let copies = items.count > 1 ? DS.Deck.loopCopies : 1
        let middle = (copies / 2) * items.count
        return VStack(spacing: DS.Space.s3) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Deck.spacing) {
                    ForEach(0..<(copies * items.count), id: \.self) { slot in
                        hero(items[slot % items.count])
                            .containerRelativeFrame(.horizontal) { width, _ in width - 2 * DS.Deck.sideMargin }
                            .deckTransition(deck, reduceMotion: reduceMotion)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Deck.sideMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .scrollPosition(id: $heroSlot)
            .onAppear { if heroSlot == nil || (heroSlot ?? 0) >= copies * items.count { heroSlot = middle } }
            .onChange(of: items.map(\.id)) { heroSlot = middle }   // cambió lo que sigues viendo: de vuelta al primero
            PageDots(count: items.count, index: items.isEmpty ? 0 : (heroSlot ?? middle) % items.count)
        }
        .task(id: heroSlot) { await tint.load(currentHero.flatMap { $0.background ?? $0.poster }) }   // se cancela si pasas a otro
        .sensoryFeedback(.selection, trigger: heroSlot)
    }

    private func hero(_ item: HomeItem) -> some View {
        // La tarjeta abre la ficha con su propio toque; «Continuar» va aparte (un botón dentro de un NavigationLink puede
        // abrir la ficha en vez de reproducir).
        DeckCard(title: item.title, background: item.background ?? item.poster, logo: Artwork.logoURL(metaID: item.metaID),
                 eyebrow: item.nextUp ? Text("Sigue") : Text("Seguir viendo"), data: heroData(item), progress: item.progress,
                 minutesLeft: item.leftMinutes, timeStyle: TimeStyle(rawValue: look.homeTime) ?? .pill,
                 open: { openTitle = route(item) }) {
            if look.homeTime == TimeStyle.fill.rawValue {
                // El botón que se llena tiene ancho fijo: siempre cabe en un renglón con el de la TV.
                HStack(spacing: DS.Space.s3) { heroButtons(item) }
            } else {
                HeroActions { heroButtons(item) }   // con letra grande, uno debajo del otro
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openTitle = route(item) }
    }

    @ViewBuilder private func heroButtons(_ item: HomeItem) -> some View {
        continueButton(item)
        if env.services.orbital.isConfigured {
            DSIconButton(symbol: "tv", label: "Ver en la TV") {
                Task { await env.playOnTV(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title) }
            }
        }
    }

    /// «T2 · E5 · quedan 20 min · termina a las 23:21».
    private func heroData(_ item: HomeItem) -> [String] {
        let language = env.services.appSettings.uiLanguage
        var parts: [String] = []
        if let episode = item.episode { parts.append(Strings.episode(season: item.season, episode: episode, language: language)) }
        // «quedan N min» lo dice el indicador de la tarjeta (píldora, borde, botón u órbita); aquí, a qué hora terminas.
        if item.leftMinutes > 0 { parts.append(Strings.endsAt(minutesLeft: item.leftMinutes, now: env.services.now(), language: language)) }
        return parts
    }

    /// «Sale hoy» (A + una portada): lo de hoy en grande con su hora; lo demás, en panorámicas. Sin nada hoy, «Sale pronto».
    @ViewBuilder private func upcoming(_ model: HomeModel) -> some View {
        let today = model.airingToday
        let rest = model.upcoming.filter { $0.id != today?.id }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: today == nil ? Text("Sale pronto") : Text("Sale hoy")).padding(.horizontal, DS.Space.gutter)
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

    /// «También tenías»: lo demás de «Seguir viendo», en piezas anchas con su avance.
    private func alsoHad(_ model: HomeModel) -> some View {
        Rail(title: "También tenías", count: model.continueWatching.count - Self.heroCount) {
            ForEach(model.continueWatching.dropFirst(Self.heroCount)) { item in
                NavigationLink(value: route(item)) {
                    StillCard(title: item.title, art: item.background ?? item.poster,
                              data: progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes).components(separatedBy: " · "), progress: item.progress)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
            }
        }
    }

    private func continueButton(_ item: HomeItem) -> some View {
        // Como la TV: «Continuar» si ibas a medias; si toca el siguiente episodio, «Ver T3 E6». Con el color de su propio arte.
        let text = item.nextUp && item.episode != nil ? Text("Ver \(Strings.episode(season: item.season, episode: item.episode ?? 0, language: env.services.appSettings.uiLanguage))") : Text("Continuar")
        return Group {
            if look.homeTime == TimeStyle.fill.rawValue, let progress = item.progress {
                // Estilo «botón»: «Continuar» se llena con lo que llevas y dice cuánto falta.
                Button { Task { await env.play(item) } } label: { ProgressFillLabel(text: text, minutes: item.leftMinutes, fraction: progress) }
                    .buttonStyle(.plain)
            } else {
                WithArtColors(url: item.background ?? item.poster) { colors in
                    Button { Task { await env.play(item) } } label: {
                        Label { text } icon: { Image(systemName: "play.fill") }.lineLimit(1)
                    }
                    .dsArtButton(colors)
                }
            }
        }
    }
}
