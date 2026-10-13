import SwiftUI
import OrbitalCore
import OrbitalModels

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
        .overlay(alignment: .top) { BannerView() }
        .task { _ = await env.services.watch.flushPending() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { _ = await env.services.watch.flushPending() } }
        }
    }
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

/// La barra de pestañas nativa: en iOS 26 es de vidrio (Liquid Glass) y se encoge al deslizar.
struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Inicio", systemImage: "house") { NavigationStack { HomeView() } }
            Tab("Para ti", systemImage: "sparkles") { NavigationStack { ParaTiView() } }
            Tab("Ver", systemImage: "play.rectangle") { NavigationStack { BrowseView() } }
            Tab("Descargas", systemImage: "arrow.down.circle") { NavigationStack { DownloadsView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Un aviso corto arriba (sin Infuse, sin fuentes…): desaparece solo.
struct BannerView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        if let text = env.banner {
            DSNotice(text: LocalizedStringKey(text), tone: .warn)
                .padding(DS.Space.s4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: text) { try? await Task.sleep(nanoseconds: DS.Timing.banner); env.banner = nil }
                .onTapGesture { env.banner = nil }
        }
    }
}
