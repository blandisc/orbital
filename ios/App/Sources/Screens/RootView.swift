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
        // Los avisos, siempre arriba y del mismo tipo (`Toast`): «Pasó a tu Orbital · Deshacer» gana sobre los demás.
        .overlay(alignment: .top) {
            if let h = env.handoff {
                Toast(symbol: "tv", color: DS.accent, title: Text("Pasó a tu Orbital"),
                      detail: Text("\(h.request.displayTitle) · sigue en \(Duration.seconds(h.position).formatted(.time(pattern: h.position >= 3600 ? .hourMinuteSecond : .minuteSecond)))"),
                      actionTitle: "Deshacer", action: { Task { await env.undoHandoff() } }, seconds: DS.Timing.handoff, dismiss: { env.handoff = nil })
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                BannerView()
            }
        }
        .animation(DS.Motion.base(false), value: env.handoff)
        .animation(DS.Motion.base(false), value: env.banner)
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

extension EnvironmentValues {
    /// Abre el control de tu Orbital (el botón de la barra de Inicio); nil sin tu Orbital conectada.
    @Entry var openRemote: (() -> Void)? = nil
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

/// La barra de pestañas nativa: en iOS 26 es de vidrio (Liquid Glass) y se encoge al deslizar.
struct MainTabs: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var tvNow = ModelObserver(AppEnvironment.shared.tvNow)
    @State private var showRemote = false
    /// La hoja del control estirada (el control completo) o corta.
    @State private var remoteLarge = false
    @State private var tab: Int
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: 4)

    init() {
        // En modo demo la pestaña pedida (`-demo-tab`) manda siempre, aunque iOS restaure la última que viste
        // (la restauración de escena no es nuestra ni se puede desactivar por vista: se vuelve a pedir en `.task`,
        // después de que la restauración ya aplicó lo suyo). Fuera de demo, la pestaña que recuerdes sigue igual.
        var initial = 0
        #if DEBUG
        if Demo.isOn { initial = Demo.tab } else if let start = Demo.startTab { initial = start }
        #endif
        _tab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "house", value: 0) { NavigationStack(path: $paths[0]) { HomeView() }.tint(DS.primary) }
            Tab("Para ti", image: OrbitalIcon.spark.asset, value: 1) { NavigationStack(path: $paths[1]) { ParaTiView() }.tint(DS.primary) }
            Tab("Descargas", systemImage: "arrow.down.circle", value: 3) { NavigationStack(path: $paths[3]) { DownloadsView() }.tint(DS.primary) }
            // Buscar es la pestaña de búsqueda del sistema: va aparte, al final, y se abre con el campo listo.
            Tab("Buscar", systemImage: "magnifyingglass", value: 2, role: .search) { NavigationStack(path: $paths[2]) { BrowseView() }.tint(DS.primary) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // El accesorio solo cuando hace falta: mientras la TV reproduce algo y en la pantalla de arriba de cada pestaña (en una
        // ficha o en Ajustes se va: no hay doble fila abajo). Sin nada en la TV, el control se abre con el botón junto al avatar.
        .bottomAccessory(isEnabled: tvNow.model.now != nil && paths[tab].isEmpty) {
            if let now = tvNow.model.now {
                TVAccessory(now: now, busy: tvNow.model.busy, toggle: { Task { await tvNow.model.control("toggle") } }, openRemote: { remoteLarge = false; showRemote = true })
            }
        }
        .environment(\.openRemote, tvNow.model.isConfigured ? { remoteLarge = tvNow.model.now == nil; showRemote = true } : nil)
        // Si la TV deja de reproducir con la hoja abierta, la hoja se cierra (no se queda vacía).
        // (Estirado, el control completo sirve aunque no haya video: se queda.)
        .onChange(of: tvNow.model.now == nil) { _, stopped in if stopped, !remoteLarge { showRemote = false } }
        #if DEBUG
        .onChange(of: tvNow.model.now == nil) { _, stopped in   // `-demo-open remote` (corta) o `remote-full` (estirada)
            if !stopped, Demo.isOn, ["remote", "remote-full", "voice-guide"].contains(Demo.open) { remoteLarge = Demo.open != "remote"; showRemote = true }
        }
        .task { if Demo.isOn, Demo.open == "remote-idle" { remoteLarge = true; showRemote = true } }   // el control sin nada en la TV
        #endif
        // Tocar el accesorio abre el control remoto completo (−10 · pausa · +10 · siguiente, salir, seguir aquí).
        .sheet(isPresented: $showRemote) {
            RemoteSheet(tvNow: tvNow, large: $remoteLarge, onContinueHere: { now in showRemote = false; openNowPlaying(now) })
        }
        .tint(DS.accent)   // la pestaña elegida lleva el acento; dentro, los botones vuelven al papel
        .onAppear(perform: openDemoScreen)
        .onAppear(perform: openPendingTitle)
        .onChange(of: env.pendingTitle) { openPendingTitle() }
        .onChange(of: env.openTab) { _, new in if let new { tab = new; env.openTab = nil } }
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
        if Demo.isOn { tab = Demo.tab } else if let start = Demo.startTab { tab = start }
        #endif
    }

    private func openDemoScreen() {
        #if DEBUG
        guard Demo.isOn else { return }
        tab = Demo.tab
        if Demo.open == "settings" || Demo.open == "year" { paths[tab].append(SettingsRoute()) }
        if let title = Demo.title { paths[tab].append(TitleRoute(kind: title.kind, metaID: title.id, title: "", poster: nil)) }
        #endif
    }
}

/// Un aviso de la app (sin Infuse, sin fuentes, descargando…), arriba como todos: se va solo; tocarlo lo cierra.
struct BannerView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        if let banner = env.banner {
            Toast(symbol: symbol(banner.tone), color: color(banner.tone), title: Text(verbatim: banner.text),
                  actionTitle: banner.action == nil ? nil : "Ver", action: banner.action.map { a in { run(a) } },
                  dismiss: { env.banner = nil })
                .id(banner.text)
                .transition(.move(edge: .top).combined(with: .opacity))
                .sensoryFeedback(banner.tone == .error ? .error : .success, trigger: banner)
        }
    }

    private func run(_ action: AppEnvironment.BannerAction) {
        switch action { case .downloads: env.openTab = AppEnvironment.downloadsTab }
    }

    private func symbol(_ tone: DSNotice.Tone) -> String {
        switch tone { case .info: "info"; case .success: "checkmark"; case .warn: "wifi.slash"; case .error: "exclamationmark" }
    }

    private func color(_ tone: DSNotice.Tone) -> Color {
        switch tone { case .info: DS.textMuted; case .success: DS.good; case .warn: DS.warning; case .error: DS.danger }
    }
}
