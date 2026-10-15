import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes (desde el ícono de la esquina de Inicio).
struct SettingsRoute: Hashable {}

/// Un título al que se navega.
struct TitleRoute: Hashable {
    var kind: String
    var metaID: String
    var title: String
    var poster: String?
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var session: ModelObserver<SessionModel>
    @StateObject private var services: ModelObserver<Services>
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let env = AppEnvironment.shared
        _session = StateObject(wrappedValue: ModelObserver(env.session))
        _services = StateObject(wrappedValue: ModelObserver(env.services))
    }

    var body: some View {
        Group {
            switch session.model.state {
            case .signedIn: MainTabs()
            default: LoginView(session: session.model)
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .fullScreenCover(item: $env.playing) { request in PlayerScreen(request: request) }
        .alert("¿Terminaste de verlo?", isPresented: Binding(get: { env.askFinished != nil }, set: { if !$0 { env.askFinished = nil } })) {
            Button("Sí, marcar como visto") { if let r = env.askFinished { Task { await env.confirmFinished(r) } } }
            Button("No", role: .cancel) { env.askFinished = nil }
        } message: { Text("Infuse no dice cuánto dura, así que no sé si llegaste al final.") }
        .overlay(alignment: .bottom) { BannerView() }
        .task { _ = await env.services.watch.flushPending() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { _ = await env.services.watch.flushPending() } }
        }
    }
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

/// La barra de pestañas nativa: en iOS 26 es de vidrio (Liquid Glass) y se encoge al deslizar.
struct MainTabs: View {
    @State private var tab = 0
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: 4)

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "house", value: 0) { NavigationStack(path: $paths[0]) { HomeView() } }
            Tab("Para ti", systemImage: "sparkles", value: 1) { NavigationStack(path: $paths[1]) { ParaTiView() } }
            Tab("Ver", systemImage: "play.rectangle", value: 2) { NavigationStack(path: $paths[2]) { BrowseView() } }
            Tab("Descargas", systemImage: "arrow.down.circle", value: 3) { NavigationStack(path: $paths[3]) { DownloadsView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear(perform: openDemoScreen)
    }

    private func openDemoScreen() {
        #if DEBUG
        guard Demo.isOn else { return }
        tab = Demo.tab
        if Demo.open == "settings" { paths[tab].append(SettingsRoute()) }
        if let title = Demo.title { paths[tab].append(TitleRoute(kind: title.kind, metaID: title.id, title: "", poster: nil)) }
        #endif
    }
}

/// Un aviso corto abajo, sobre las pestañas (sin Infuse, sin fuentes, descargando…): desaparece solo; tocarlo lo cierra.
struct BannerView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        if let banner = env.banner {
            DSNotice(text: LocalizedStringKey(banner.text), tone: banner.tone)
                .padding(.horizontal, DS.Space.s4).padding(.bottom, DS.Space.s14 + DS.Space.s2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner) { try? await Task.sleep(nanoseconds: DS.Timing.banner); env.banner = nil }
                .onTapGesture { env.banner = nil }
                .sensoryFeedback(banner.tone == .error ? .error : .success, trigger: banner)
        }
    }
}
