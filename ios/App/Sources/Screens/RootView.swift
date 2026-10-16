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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: env.playing?.id)   // empieza la función: un toque suave
        .alert("¿Terminaste de verlo?", isPresented: Binding(get: { env.askFinished != nil }, set: { if !$0 { env.askFinished = nil } })) {
            Button("Sí, marcar como visto") { if let r = env.askFinished { Task { await env.confirmFinished(r) } } }
            Button("No", role: .cancel) { env.askFinished = nil }
        } message: { Text("Infuse no dice cuánto dura, así que no sé si llegaste al final.") }
        .overlay(alignment: .bottom) { BannerView() }
        .task {
            _ = await env.services.watch.flushPending()
            // Con tu Orbital conectada: lo nuevo de la consola (otra clave, Trakt recién conectado allá) llega solo.
            if env.services.orbital.isConfigured { _ = try? await env.services.connectOrbital() }
        }
        .task { env.tvNow.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            // «Viendo en la TV» y lo que la TV dejó para el iPhone se sondean mientras la app está activa; al irse a segundo
            // plano se le pide a iOS despertarla luego (mejor esfuerzo).
            env.tvNow.setActive(phase == .active)
            if phase == .active { Task { _ = await env.services.watch.flushPending() } }
            if phase == .background { InboxBackgroundTask.schedule() }
        }
    }
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

/// La barra de pestañas nativa: en iOS 26 es de vidrio (Liquid Glass) y se encoge al deslizar.
struct MainTabs: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var tvNow = ModelObserver(AppEnvironment.shared.tvNow)
    @State private var tab: Int
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: 4)

    init() {
        // En modo demo la pestaña pedida (`-demo-tab`) manda siempre, aunque iOS restaure la última que viste
        // (la restauración de escena no es nuestra ni se puede desactivar por vista: se vuelve a pedir en `.task`,
        // después de que la restauración ya aplicó lo suyo). Fuera de demo, la pestaña que recuerdes sigue igual.
        var initial = 0
        #if DEBUG
        if Demo.isOn { initial = Demo.tab }
        #endif
        _tab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "house", value: 0) { NavigationStack(path: $paths[0]) { HomeView() }.tint(DS.primary) }
            Tab("Para ti", systemImage: "sparkles", value: 1) { NavigationStack(path: $paths[1]) { ParaTiView() }.tint(DS.primary) }
            Tab("Descargas", systemImage: "arrow.down.circle", value: 3) { NavigationStack(path: $paths[3]) { DownloadsView() }.tint(DS.primary) }
            // Buscar es la pestaña de búsqueda del sistema: va aparte, al final, y se abre con el campo listo.
            Tab("Buscar", systemImage: "magnifyingglass", value: 2, role: .search) { NavigationStack(path: $paths[2]) { BrowseView() }.tint(DS.primary) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .bottomAccessory(isEnabled: tvNow.model.now != nil) {
            if let now = tvNow.model.now {
                TVAccessory(now: now, busy: tvNow.model.busy) { Task { await tvNow.model.control("toggle") } }
                    .contentShape(Rectangle())
                    .onTapGesture { openNowPlaying(now) }
            }
        }
        .tint(DS.accent)   // la pestaña elegida lleva el acento; dentro, los botones vuelven al papel
        .onAppear(perform: openDemoScreen)
        .onAppear(perform: openPendingTitle)
        .onChange(of: env.pendingTitle) { openPendingTitle() }
        .task { forceDemoTab() }   // una segunda vez: gana aunque la restauración de escena llegue después de aparecer
        #if DEBUG
        // iOS restaura la pestaña que viste la última vez (independiente de nuestro @State) y lo hace después de
        // aparecer y del `.task` de arriba: si en modo demo algo la cambia por detrás, se vuelve a pedir la tuya.
        .onChange(of: tab) { _, new in if Demo.isOn, new != Demo.tab { tab = Demo.tab } }
        #endif
    }

    /// Tocar el accesorio «En la TV» abre la ficha de lo que suena (en Inicio).
    private func openNowPlaying(_ now: OrbitalRemote.NowPlaying) {
        guard let metaID = now.metaID else { return }
        tab = 0
        paths[0].append(TitleRoute(kind: now.kind, metaID: metaID, title: now.title, poster: now.poster))
    }

    /// Una ficha pedida por un enlace (`orbital-ios://title`): se abre en Inicio, encima de lo que hubiera.
    private func openPendingTitle() {
        guard let route = env.pendingTitle else { return }
        env.pendingTitle = nil
        tab = 0
        paths[0].append(route)
    }

    /// Solo la pestaña (repetible: no abre nada encima dos veces).
    private func forceDemoTab() {
        #if DEBUG
        if Demo.isOn { tab = Demo.tab }
        #endif
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
                // Flota sobre la pantalla: vidrio de verdad, o el texto se mezcla con lo de abajo.
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                .padding(.horizontal, DS.Space.s4).padding(.bottom, DS.Space.s14 + DS.Space.s2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner) { try? await Task.sleep(nanoseconds: DS.Timing.banner); env.banner = nil }
                .onTapGesture { env.banner = nil }
                .sensoryFeedback(banner.tone == .error ? .error : .success, trigger: banner)
        }
    }
}
