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
                if let first = model.continueWatching.first {
                    hero(first)
                } else if !model.isLoading {
                    DSNotice(text: "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.").padding(.horizontal, DS.Space.gutter)
                }
                if model.continueWatching.count > 1 { alsoHad(model) }
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
        .navigationDestination(for: TitleRoute.self) { TitleView(route: $0) }
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
        await tint.load(home.model.continueWatching.first.flatMap { $0.background ?? $0.poster })
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

    private func hero(_ item: HomeItem) -> some View {
        let detail = progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes)
        // La tarjeta abre la ficha con su propio toque; «Continuar» va aparte (un botón dentro de un NavigationLink puede
        // abrir la ficha en vez de reproducir).
        return HeroCard(title: item.title, detail: detail, background: item.background ?? item.poster, logo: Artwork.logoURL(metaID: item.metaID),
                        badge: item.nextUp ? "Sigue" : "Seguir viendo", progress: item.progress) {
            continueButton(item)
        }
        .contentShape(Rectangle())
        .onTapGesture { openTitle = route(item) }
        .accessibilityAction(named: Text("Ver ficha")) { openTitle = route(item) }
    }

    /// «También tenías»: lo demás de «Seguir viendo», en renglones (miniatura ancha, nombre y dato) como en la consola.
    private func alsoHad(_ model: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: "También tenías")
            ForEach(model.continueWatching.dropFirst()) { item in
                NavigationLink(value: route(item)) {
                    RowTile(title: item.title, thumb: item.background ?? item.poster,
                            detail: progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes), progress: item.progress)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private func continueButton(_ item: HomeItem) -> some View {
        Button { Task { await env.play(item) } } label: { Label("Continuar", systemImage: "play.fill").lineLimit(1) }.dsPrimaryButton()
    }
}
