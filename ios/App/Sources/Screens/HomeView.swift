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
                    hero(first).padding(.horizontal, DS.Space.gutter)
                } else if !model.isLoading {
                    DSNotice(text: "Aquí aparece lo que vas viendo, en el iPhone y en Orbital.").padding(.horizontal, DS.Space.gutter)
                }
                if model.continueWatching.count > 1 {
                    Rail(title: "Seguir viendo") {
                        ForEach(model.continueWatching.dropFirst()) { item in
                            TitleLink(route: TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster), progress: item.progress)
                                .contextMenu { Button("Quitar de Seguir viendo", systemImage: "xmark.circle") { Task { await model.dismiss(item) } } }
                        }
                    }
                }
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
            .padding(.bottom, DS.Space.s8)
            .animation(DS.Motion.enter(reduceMotion), value: tvNow.model.now != nil)
            .animation(DS.Motion.enter(reduceMotion), value: inbox.model.fromTV.map(\.id))
        }
        .background(TintedBackground(tint: tint.color))
        .navigationTitle("Orbital").navigationBarTitleDisplayMode(.large)
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
        await tint.load(home.model.continueWatching.first?.poster)
    }

    /// «Stremio al día» o «N cambios por subir» (si no hubo internet).
    private var syncText: Text {
        pendingCount > 0 ? Text("\(pendingCount) cambios por subir") : Text("Stremio al día")
    }

    private func hero(_ item: HomeItem) -> some View {
        let detail = [episodeText(season: item.season, episode: item.episode)].filter { !$0.isEmpty }.joined(separator: " · ")
        // La tarjeta abre la ficha con su propio toque; «Continuar» va aparte (un botón dentro de un NavigationLink puede
        // abrir la ficha en vez de reproducir).
        return HeroCard(title: item.title, detail: detail, background: item.background ?? item.poster, badge: item.nextUp ? "Sigue" : "Seguir viendo", progress: item.progress) {
            // Botón y tiempo en un renglón; si la letra no cabe, uno debajo del otro (nunca «Conti-nuar»).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) { continueButton(item); timeLeft(item) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { continueButton(item); timeLeft(item) }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
        .onTapGesture { openTitle = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }
        .accessibilityAction(named: Text("Ver ficha")) { openTitle = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster) }
    }

    private func continueButton(_ item: HomeItem) -> some View {
        Button { Task { await env.play(item) } } label: { Label("Continuar", systemImage: "play.fill").lineLimit(1) }.dsPrimaryButton()
    }

    @ViewBuilder private func timeLeft(_ item: HomeItem) -> some View {
        if item.leftMinutes > 0 { Text(timeLeftText(minutes: item.leftMinutes)).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1) }
    }
}
