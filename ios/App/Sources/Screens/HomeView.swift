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
    @State private var heroID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        _home = StateObject(wrappedValue: ModelObserver(HomeModel(AppEnvironment.shared.services)))
        // El sondeo es de toda la app (arranca en RootView): aquí solo se ve.
        _tvNow = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.tvNow))
        _inbox = StateObject(wrappedValue: ModelObserver(AppEnvironment.shared.inbox))
    }

    var body: some View {
        let model = home.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if model.offline { DSNotice(text: "Sin conexión: se ve lo último que guardé.", tone: .warn).padding(.horizontal, DS.Space.gutter) }
                if let now = tvNow.model.now {
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
                    Rail(title: "Mi lista") {
                        ForEach(model.myList) { item in
                            TitleLink(route: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster))
                        }
                    }
                }
                if !model.traktPending.isEmpty {
                    Rail(title: "Pendientes en Trakt") {
                        ForEach(model.traktPending) { s in TitleLink(route: s.route, badge: "En tu lista") }
                    }
                }
            }
            .padding(.bottom, DS.Space.s14)     // la última fila respira: la barra de pestañas no la tapa
            .animation(DS.Motion.enter(reduceMotion), value: tvNow.model.now != nil)
            .animation(DS.Motion.enter(reduceMotion), value: inbox.model.fromTV.map(\.id))
        }
        .background(Backdrop(tint: tint.color))
        .navigationTitle(greeting).navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(syncText)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: SettingsRoute()) { Image(systemName: "person.crop.circle") }.accessibilityLabel(Text("Ajustes")) } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(item: $openTitle) { TitleView(route: $0) }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: env.watchedSomething) { Task { await reload() } }
    }

    /// Lo de Stremio, lo pendiente por subir y el tono del fondo (al abrir, al deslizar hacia abajo y al volver de ver algo).
    private func reload() async {
        await home.model.refresh()
        let work = env.services.pending.load()      // una sola lectura por actualización, no una por cada pintado
        pendingCount = work.progress.count + work.traktWatched.count
        await tint.load(currentHero.flatMap { $0.background ?? $0.poster })
    }

    /// «Buenos días / Buenas tardes / Buenas noches», como en la consola: lo primero que se lee en Inicio.
    private var greeting: LocalizedStringKey {
        switch Vocabulary.greeting(hour: Calendar.current.component(.hour, from: Date())) {
        case .morning: "Buenos días"
        case .afternoon: "Buenas tardes"
        case .evening: "Buenas noches"
        }
    }

    /// «Stremio al día» o «N cambios por subir» (si no hubo internet).
    private var syncText: Text {
        pendingCount > 0 ? Text("\(pendingCount) cambios por subir") : Text("Stremio al día")
    }

    private func route(_ item: HomeItem) -> TitleRoute { TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }

    /// Cuántos de «Seguir viendo» van en el carrusel del destacado; el resto, en «También tenías».
    private static let heroCount = 3

    /// El que está al frente del carrusel (el fondo toma su color).
    private var currentHero: HomeItem? {
        let items = home.model.continueWatching.prefix(Self.heroCount)
        return items.first { $0.id == heroID } ?? items.first
    }

    /// «Seguir viendo»: un carrusel de destacados a sangre que se detiene en cada uno, con sus puntos; el fondo de la
    /// pantalla toma el color del que está al frente.
    private func heroCarousel(_ model: HomeModel) -> some View {
        let items = Array(model.continueWatching.prefix(Self.heroCount))
        return VStack(spacing: DS.Space.s3) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in hero(item).containerRelativeFrame(.horizontal) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $heroID)
            PageDots(count: items.count, index: items.firstIndex { $0.id == (heroID ?? items.first?.id) } ?? 0)
        }
        .onChange(of: heroID) { Task { await tint.load(currentHero.flatMap { $0.background ?? $0.poster }) } }
        .sensoryFeedback(.selection, trigger: heroID)
    }

    private func hero(_ item: HomeItem) -> some View {
        // La tarjeta abre la ficha con su propio toque; «Continuar» va aparte (un botón dentro de un NavigationLink puede
        // abrir la ficha en vez de reproducir).
        HeroCard(title: item.title, background: item.background ?? item.poster, logo: Artwork.logoURL(metaID: item.metaID),
                 eyebrow: item.nextUp ? Text("Sigue") : Text("Seguir viendo"), data: heroData(item), progress: item.progress) {
            HStack(spacing: DS.Space.s3) {
                continueButton(item)
                if env.services.orbital.isConfigured {
                    DSIconButton(symbol: "tv", label: "Ver en la TV") {
                        Task { await env.playOnTV(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openTitle = route(item) }
        .accessibilityAction(named: Text("Ver ficha")) { openTitle = route(item) }
    }

    /// «T2 · E5 · quedan 20 min · terminas a las 23:21».
    private func heroData(_ item: HomeItem) -> [String] {
        let language = env.services.appSettings.uiLanguage
        var parts: [String] = []
        if let episode = item.episode { parts.append(Strings.episode(season: item.season, episode: episode, language: language)) }
        if item.leftMinutes > 0 {
            parts.append(Strings.timeLeft(minutes: item.leftMinutes, language: language))
            parts.append(Strings.endsAt(minutesLeft: item.leftMinutes, now: env.services.now(), language: language))
        }
        return parts
    }

    /// «También tenías»: lo demás de «Seguir viendo», en piezas anchas con su avance.
    private func alsoHad(_ model: HomeModel) -> some View {
        Rail(title: "También tenías") {
            ForEach(model.continueWatching.dropFirst(Self.heroCount)) { item in
                NavigationLink(value: route(item)) {
                    StillCard(title: item.title, art: item.background ?? item.poster,
                              data: [progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes)], progress: item.progress)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
            }
        }
    }

    private func continueButton(_ item: HomeItem) -> some View {
        Button { Task { await env.play(item) } } label: { Label("Continuar", systemImage: "play.fill").lineLimit(1) }.dsPrimaryButton()
    }
}
