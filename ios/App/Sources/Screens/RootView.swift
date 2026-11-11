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
    /// Abrir ya «Versión» de este video (P2-B: «Probar otra versión» desde «Tus pedidos»).
    var versionsFor: String? = nil
}

struct RootView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// El reproductor y los avisos: solo la raíz se vuelve a pintar cuando cambian.
    private let ui = AppEnvironment.shared.ui
    @State private var session: ModelObserver<SessionModel>
    @State private var services: ModelObserver<Services>
    @Environment(\.scenePhase) private var scenePhase

    /// La entrada de la app: solo al arrancar en frío (cada arranque arma una raíz nueva). En modo demo, solo con
    /// `-demo-splash` (las capturas no la esperan).
    @State private var splashing: Bool
    /// El zoom tarjeta → reproductor.
    @Namespace private var playerZoom
    /// Si al volver a la app hay que pedir otra vez lo de la red (no al bajar el Centro de control ni cada pocos segundos).
    @State private var foreground = ForegroundRefresh()
    /// Ya se armó la raíz una vez en este arranque (la entrada no se repite).
    @MainActor private static var launched = false

    init() {
        let env = AppEnvironment.shared
        #if DEBUG
        let wanted = !Demo.isOn || Demo.has("-demo-splash")
        #else
        let wanted = true
        #endif
        // Solo la primera vez: SwiftUI vuelve a armar la raíz cuando cambia algo de la app (al emparejar tu Orbital con el QR,
        // el idioma…). Antes cada vez volvía a marcar `ui.splashing` y el logotipo de Inicio se quedaba escondido para
        // siempre (la entrada ya no corría para quitarlo).
        let splash = wanted && !Self.launched
        Self.launched = true
        _splashing = State(wrappedValue: splash)
        if splash { env.ui.splashing = true }
        _session = State(wrappedValue: ModelObserver(env.session))
        _services = State(wrappedValue: ModelObserver(env.services))
    }

    /// Desde dónde sigue en la TV: «desde 12:34», o «desde el principio» si apenas empezaba.
    /// Lo que sube la pastilla de calificar: encima de «Viendo en la TV» cuando ese accesorio va sobre la barra (iOS 26.1+, y
    /// no cuando la barra se minimiza y el accesorio se va a su lado).
    private func reminderLift() -> CGFloat {
        guard #available(iOS 26.1, *), let tv = env.tvNow else { return 0 }
        tv.track()
        return (tv.now != nil || tv.game != nil) && !ui.tvAccessoryInline ? DS.Toast.accessoryLift : 0
    }

    /// (Un `Text`, no un `String`: así sale en el idioma de la app y no en el del sistema.)
    static func handoffFrom(_ position: Double) -> Text {
        guard position >= DS.Toast.fromStartUnder else { return Text("desde el principio") }
        let time = Duration.seconds(position).formatted(.time(pattern: position >= 3600 ? .hourMinuteSecond : .minuteSecond))
        return Text("desde \(time)")
    }

    /// Las pestañas con lo que se abre a pantalla completa encima (reproductor, guía, historias) y sus preguntas. Aparte del
    /// cuerpo: de una sola pieza, el Swift de la CI (Xcode 26.3) no lo alcanzaba a revisar.
    @ViewBuilder private func presented() -> some View {
        // Se entra sin cuenta de Stremio: lo tuyo vive en el teléfono (y viaja por Trakt). Stremio se conecta en Ajustes, como respaldo.
        withPrompts(withCovers(MainTabs().onAppear { Perf.mark("app.tabs") }
        .environment(\.playerZoom, playerZoom)
        .background(DS.bg.ignoresSafeArea())
        .overlay { DownloadFlightLayer(flight: ui.downloadFlight).ignoresSafeArea() }
        .overlay { if splashing { LaunchSplash(target: ui.homeLogoFrame) { splashing = false; ui.splashing = false } } }))
    }

    /// Lo que se abre a pantalla completa: el reproductor, la guía y las historias (una pieza por cubierta: la CI los revisa
    /// por separado).
    private func withCovers<V: View>(_ content: V) -> some View {
        withStories(withGuide(withPlayer(content)))
    }

    /// El reproductor crece desde la tarjeta que se tocó y, al cerrar, se encoge de vuelta a ella (con su avance al día).
    private func withPlayer<V: View>(_ content: V) -> some View {
        @Bindable var env = env
        return content.fullScreenCover(item: $env.playing, onDismiss: { ui.playerSource = nil }, content: playerCover)
    }

    private func playerCover(_ request: PlayRequest) -> some View {
        PlayerScreen(request: request).playerZoom(from: ui.playerSource, in: playerZoom)
    }

    /// La guía de la primera vez (y la de Ajustes › Aprende Orbital › «Ver la guía otra vez»).
    private func withGuide<V: View>(_ content: V) -> some View {
        content.fullScreenCover(isPresented: showingGuide) { OnboardingView { ui.showingGuide = false } }
    }

    /// Una historia de «Aprende Orbital» (G3): desde los círculos de Inicio, Ajustes o «Ver la historia» de un aviso.
    private func withStories<V: View>(_ content: V) -> some View {
        content.fullScreenCover(item: openStory) { (route: StoryRoute) in storyDeck(route) }
    }

    private var showingGuide: Binding<Bool> { Binding(get: { ui.showingGuide }, set: { ui.showingGuide = $0 }) }
    private var openStory: Binding<StoryRoute?> { Binding(get: { ui.openStory.map(StoryRoute.init) }, set: { ui.openStory = $0?.id }) }

    /// Una historia de «Aprende Orbital».
    private func storyDeck(_ route: StoryRoute) -> some View {
        StoryDeck(stories: LearnModel(env.services).deck, start: route.id,
                  onSeen: { LearnModel(env.services).markSeen($0.id) },
                  onAction: { destination in
                      ui.openStory = nil
                      Task { try? await Task.sleep(for: DS.Motion.tabSettle); env.open(destination) }
                  },
                  close: { ui.openStory = nil })
    }

    /// El toque al empezar, cambiar la fecha y «¿Terminaste de verlo?».
    private func withPrompts(_ content: some View) -> some View {
        content
            .dsFeedback(.impact(flexibility: .soft), trigger: ui.playing?.id)   // empieza la función: un toque suave
            .sheet(item: Binding(get: { ui.redate }, set: { ui.redate = $0 })) { r in
                ViewingDatePicker(title: Text("¿Cuándo la viste?"), initial: r.at) { date in Task { await env.redate(r, to: date) } }
            }
            .alert("¿Terminaste de verlo?", isPresented: Binding(get: { env.askFinished != nil }, set: { if !$0 { env.askFinished = nil } })) {
                Button("Sí, marcar como visto") { if let r = env.askFinished { Task { await env.confirmFinished(r) } } }
                Button("No", role: .cancel) { env.askFinished = nil }
            } message: { Text("Infuse no dice cuánto dura, así que no sé si llegaste al final.") }
    }

    var body: some View {
        let _ = services.model   // cualquier cambio de los servicios (idioma, cuenta) vuelve a pintar la raíz
        presented()
        // Los avisos, siempre abajo (al alcance del pulgar, sobre la barra de pestañas) y del mismo tipo (`Toast`).
        // «Sigue en tu Orbital · Deshacer» gana: los demás esperan a que se vaya.
        .overlay(alignment: .bottom) {
            Group {
                if let h = ui.handoff {
                    // «Sigue en tu Orbital · Minions & Monstruos · desde 12:34»; si iba al principio, lo dice así (no «en 0:00»).
                    Toast(tone: .success, title: Text("Sigue en tu Orbital"), detail: Text("\(Text(verbatim: "\(titleName(h.request.displayTitle, id: h.request.metaID, kind: h.request.kind)) · "))\(Self.handoffFrom(h.position))"),
                          actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward", action: { Task { await env.undoHandoff() } },
                          symbol: "tv.and.mediabox", color: DS.brandMoon, seconds: DS.Timing.toastAction, dismiss: { env.handoff = nil })
                        .transition(DS.Motion.notice(reduceMotion))
                } else if !ui.coverShowsNotices {
                    BannerView()
                }
            }
            // A `DS.Toast.gap` de lo que tenga abajo: la barra, «Viendo en la TV» (antes lo tapaba justo al mandar algo a la
            // TV) o lo que la pantalla deje flotando (el pie del mosaico).
            .dsNoticePlacement(lift: reminderLift() + ui.noticeLift)
            .animation(DS.Motion.enter(reduceMotion), value: ui.noticeLift)
        }
        // Calificar lo que terminaste: la pastilla sobre la barra de pestañas (Fernando, 11 nov 2026: como estaba antes).
        .overlay(alignment: .bottom) { FloatingRatingReminder(lift: reminderLift()) }
        .animation(DS.Motion.enter(reduceMotion), value: ui.handoff)
        .animation(DS.Motion.enter(reduceMotion), value: env.notices.current)
        .task {
            #if DEBUG
            if Demo.isOn, let at = Demo.handoff { env.handoff = .init(request: Demo.handoffRequest, position: at) }
            if Demo.isOn { Demo.showNotice(env) }
            if Demo.isOn { ui.showingGuide = Demo.firstRun } else if OnboardingModel.shouldShow(env.services) { ui.showingGuide = true }
            // `-demo-story <id>`: una historia de «Aprende» abierta (capturas de sus escenas).
            if Demo.isOn, let story = Demo.value(after: "-demo-story") { ui.openStory = story }
            #else
            if OnboardingModel.shouldShow(env.services) { ui.showingGuide = true }
            #endif
            await env.services.syncLibrary()
            // Con tu Orbital conectada: lo nuevo de la consola (otra clave, Trakt recién conectado allá) llega solo.
            if env.services.orbital.isConfigured { _ = try? await env.services.connectOrbital() }
        }
        .task { env.tvNow.setActive(scenePhase == .active) }
        // Tus pedidos a Real-Debrid: mientras la app está abierta y algo baja, cada 20 s (R10); al volver, en cuanto se abre.
        .task(id: scenePhase == .active) { if scenePhase == .active { await env.services.debridRequests.follow(every: DS.Timing.debridPoll) } }
        // Las colecciones (una para toda la app): lo visto se vuelve a preguntar y otra cuenta no hereda nada.
        .onChange(of: env.watchedSomething) { env.collections.forgetWatched(); Task { await env.ratings.refresh(force: true) } }
        .onChange(of: env.services.generation) { env.collections.resetAccount() }
        .task(priority: .userInitiated) {
            // Buscar, adelantado y primero (antes que la fila de imágenes de Inicio): el color de su n.º 1 y los pósters del
            // Top 10 de la copia guardada; luego lo de hoy, y si cambió, otra vez.
            @MainActor func warm() async {
                await ArtTint().load(env.catalog.popular.first?.poster)
                let pixels = DS.Image.card * ImagePipeline.screenScale   // el mismo tamaño que pinta el póster
                let urls = env.catalog.popular.prefix(DS.Size.searchPrefetch).compactMap { $0.poster.flatMap(URL.init(string:)) }
                await withTaskGroup(of: Void.self) { group in
                    for url in urls { group.addTask { _ = await ImagePipeline.shared.image(url, maxPixel: pixels) } }
                }
            }
            let before = env.catalog.popular.first?.poster
            await warm()
            await env.catalog.load()
            if env.catalog.popular.first?.poster != before { await warm() }
        }
        .onChange(of: env.services.orbitalOn) { _, on in DebridRequestNotifier.registerCategory(language: env.services.appSettings.uiLanguage, tv: on) }
        .onChange(of: scenePhase) { _, phase in
            // «Viendo en la TV» y lo que la TV dejó para el iPhone se sondean mientras la app está activa; al irse a segundo
            // plano se le pide a iOS despertarla luego (mejor esfuerzo).
            env.tvNow.setActive(phase == .active)
            if phase == .background { foreground.wentToBackground() }
            if phase == .active {
                let decision = foreground.becameActive(at: Date())
                // V8 (10 nov 2026): antes salían 8 tareas a la vez al volver a la app, todas peleando con la pantalla que se
                // pinta. Ahora va primero lo que se ve (tu biblioteca y tus estrellas) y lo demás después, una cosa tras otra
                // y con prioridad baja.
                if decision == .refresh {
                    Task { await env.services.syncLibrary() }   // al abrir ya la pide el arranque (y si va una en camino, se une a ella)
                    env.ui.returnedToApp += 1   // la pantalla abierta (Explorar, una ficha) se pone al día
                }
                if decision != .skip { Task { await env.ratings.refresh() } }
                Task(priority: .utility) {
                    await env.services.refreshSharedDebrid()   // CX2-A, TEC-6: lo de iCloud puede llegar en cualquier momento
                    guard decision != .skip else { return }
                    await env.syncChoices()
                    await env.services.addonSync.refresh()   // S6: tu lista y la de tu TV (solo Ultra con TV)
                    await env.services.renewInviteIfNeeded()   // CX4-A, TEC-16: la invitación para tu iPad no se vence
                    await DebridReminderNotifier.refresh(env.services)
                    await ReleaseNotifier.check(origin: "al-abrir")
                    await AppearNotifier.check()   // R15: lo que nadie tenía, una vez al día
                }
            }
            #if DEBUG
            if phase == .active { DemoHTTPClient.postReleaseAlert(language: env.services.appSettings.uiLanguage) }
            #endif
            if phase == .background { InboxBackgroundTask.schedule(); ReleaseNotifier.schedule() }
            // Las descargas en cola se crean antes de irse (en segundo plano iOS las posterga): ver `Downloads.setBackgrounded`.
            if phase == .background || phase == .active {
                let background = phase == .background
                let id: UIBackgroundTaskIdentifier = background ? UIApplication.shared.beginBackgroundTask(withName: "orbital.downloads") : UIBackgroundTaskIdentifier.invalid
                Task {
                    // Primero el carril (lo que arranque la cola al irte ya nace en segundo plano), luego la cola.
                    await env.setDownloadsBackgrounded(background)
                    await env.services.downloads.setBackgrounded(background)
                    if id != UIBackgroundTaskIdentifier.invalid { UIApplication.shared.endBackgroundTask(id) }
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Abre el control de tu Orbital (el botón de la barra de Inicio); nil sin tu Orbital conectada.
    @Entry var openRemote: RemoteOpener? = nil
}

/// El botón del control: siempre igual a otro (como `TitlePanelOpener`), para que Inicio no se vuelva a pintar entera cada
/// vez que la raíz cambia de pestaña o regresa de una ficha.
/// V9: el valor del entorno es solo datos (`wide`); la acción vive en `AppUI.remoteButton` (fuera de Observation). Con el
/// cierre dentro, SwiftUI daba el entorno por cambiado en cada pasada de la raíz (cada sondeo de la TV) aunque `==` dijera
/// que era igual, y volvía a pintar Inicio entera (`-perf-why`: «_openRemote changed», 25 veces al abrir una ficha).
struct RemoteOpener: Equatable {
    /// Lo único que cambia lo que hace: si el control abre como panel o como hoja.
    let wide: Bool
    /// De qué ventana es (su acción, en `AppUI.remoteButtons`).
    let window: Int
    @MainActor func callAsFunction() { AppEnvironment.shared.ui.remoteButtons[window]?() }
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

/// La barra de pestañas nativa: en iOS 26 es de vidrio (Liquid Glass) y se encoge al deslizar.
struct MainTabs: View {
    @Environment(AppEnvironment.self) private var env
    private let ui = AppEnvironment.shared.ui   // la ficha o la pestaña que se pide abrir
    @State private var tvNow = ModelObserver(AppEnvironment.shared.tvNow)
    @State private var showRemote = false
    /// Esta ventana (V9: sus acciones del entorno viven en `AppUI`, ver `RemoteOpener`).
    @State private var window = AppEnvironment.shared.ui.newWindow()
    /// El acompañante del juego abierto en la consola.
    @State private var showGame = false
    /// La hoja del control estirada (el control completo) o corta.
    @State private var remoteLarge = false
    @State private var tab: Int
    /// Cuántas descargas siguen bajando o en pausa: el globito de la pestaña Descargas.
    @State private var pendingDownloads = 0
    /// RX1-A · lo que baja en la nube también cuenta en la pestaña Descargas (ahí vive).
    @State private var cloudPending = 0
    @State private var cloudWatch: ObservableModel.Subscription?
    @State private var finishedDownloads = 0
    @State private var paths: [NavigationPath] = Array(repeating: NavigationPath(), count: 4)
    /// Ventana ancha (iPad, Mac): las hojas son tarjetas sin alturas que estirar, así que el control abre completo.
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// La ficha abierta en el panel de la derecha (iPad, Mac): tocar una serie o película la abre ahí, sobre lo que veías.
    @State private var panelTitle: TitleRoute?
    /// El póster que vuela hacia el panel al abrir una ficha (`PosterFlight`).
    @State private var flight: PosterFlight?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Abrir el control (si hay TV configurada); aparte para que el compilador no se ahogue con el cuerpo. Como panel, el
    /// mismo botón lo cierra.
    private var openRemoteAction: RemoteOpener? {
        guard tvNow.model.isConfigured else { return nil }
        ui.remoteButtons[window] = {
            if remoteAsPanel && showRemote { showRemote = false; return }
            if remoteAsPanel { panelTitle = nil }   // un solo panel a la derecha: el control reemplaza a la ficha
            remoteLarge = tvNow.model.now == nil || sizeClass == .regular; showRemote = true
        }
        return RemoteOpener(wide: remoteAsPanel || sizeClass == .regular, window: window)
    }

    /// Ventana ancha (iPad horizontal, Mac): el control va en un panel fijo a la derecha y se navega a la vez. Angosta (iPad
    /// de pie, dos apps en pantalla): la tarjeta. En el iPhone el ancho nunca es regular: la hoja de siempre.
    private var remoteAsPanel: Bool { sizeClass == .regular && WindowMetrics.size.width >= DS.Remote.panelWindowWidth }

    /// La ficha como panel a la derecha: con ancho regular (iPad de pie o acostado, Mac). En el iPhone, a pantalla completa.
    /// Ya no: desde FE1 (4 nov 2026) la ficha del iPad y la Mac se abre a pantalla completa, como en el iPhone.
    private var titleAsPanel: Bool { false }

    /// ¿Hay algo en el panel de la derecha? (El control en ventana ancha o una ficha.)
    private var sidePanelShown: Binding<Bool> {
        Binding(get: { showRemote && remoteAsPanel },
                set: { if !$0 { showRemote = false; panelTitle = nil } })
    }

    /// El panel de la derecha: el control de la TV. La ficha ya no va aquí: flota a la izquierda, del tamaño del iPhone.
    @ViewBuilder private var sidePanel: some View {
        RemoteSheet(tvNow: tvNow, large: .constant(true), onContinueHere: { now in showRemote = false; openNowPlaying(now) },
                    close: { showRemote = false })
        .inspectorColumnWidth(min: DS.Remote.panelMin, ideal: DS.Remote.panelIdeal, max: DS.Remote.panelMax)
    }

    /// Abrir fichas en el panel (iPad, Mac); en el iPhone no existe y navegan a pantalla completa.
    private var titleOpener: TitlePanelOpener? {
        guard titleAsPanel else { return nil }
        ui.titlePanels[window] = { route, _ in
            showRemote = false
            panelTitle = route
        }
        return TitlePanelOpener(window: window)
    }

    /// Las cuatro pestañas, cada una con su pila de navegación.
    private func tabs(_ selection: Binding<Int>) -> some View {
        TabView(selection: selection) {
            Tab("Inicio", systemImage: "house", value: 0) { NavigationStack(path: $paths[0]) { HomeView() }.tint(DS.primary) }
            Tab("Explorar", image: OrbitalIcon.spark.asset, value: 1) {   // antes «Para ti» (Fernando, 31 oct 2026)
                NavigationStack(path: $paths[1]) {
                    // Colecciones (la repisa): la tarjeta de Para ti empuja `RepisaRoute`; un título abre su ficha en la misma pila.
                    ParaTiView()
                        .navigationDestination(for: RepisaRoute.self) { _ in RepisaView { paths[1].append($0) } }
                        .navigationDestination(for: RepisaCollectionRoute.self) { r in RepisaCollectionView(id: r.id) { paths[1].append($0) } }
                        .navigationDestination(for: WatchingRoute.self) { _ in WatchingView { paths[1].append($0) } }   // Lo que ves
                }.tint(DS.primary)
            }
            // Biblioteca: Descargas · Mi media · Guardado (Fernando, 3 nov 2026: BI2-A); antes «Descargas». Su ícono, una pila
            // de tarjetas (tu colección), del mismo trazo que la casa y la lupa; los libros parecían de lectura (4 nov, la 1774).
            Tab("Biblioteca", systemImage: "rectangle.stack", value: 3) { NavigationStack(path: $paths[3]) { DownloadsView() }.tint(DS.primary) }
                .badge(env.ui.seeingDownloads ? 0 : pendingDownloads + cloudPending)   // viéndola, sin marca
            // Buscar es la pestaña de búsqueda del sistema: va aparte, al final, y se abre con el campo listo.
            Tab("Buscar", systemImage: "magnifyingglass", value: 2, role: .search) { NavigationStack(path: $paths[2]) { BrowseView() }.tint(DS.primary) }
        }
    }

    /// Las pestañas con su barra, el panel de la derecha, los avisos y el accesorio «En la TV». En partes (`shell`, `wired`):
    /// el cuerpo de una sola pieza no lo alcanzaba a revisar el Swift de la CI (Xcode 26.3).
    private func shell(_ selection: Binding<Int>) -> some View {
        tabs(selection)
        // iPhone: la barra de abajo de siempre. iPad y Mac: la barra de arriba que se abre como barra lateral.
        .tabViewStyle(.sidebarAdaptable)
        // Como Apple (TV, Música): la barra arriba también acostado; la lateral, a un toque del botón de la barra (DK1, 4 nov 2026).
        .modifier(TabBarFirst())
        // El control como panel fijo a la derecha en ventana ancha (el inspector de SwiftUI); si la ventana se angosta con
        // el panel abierto, pasa solo a la tarjeta (`remoteAsPanel`).
        // y la ficha (iPad, Mac): tocar una serie o película la abre ahí, con el diseño del iPhone. Un solo panel: abrir uno
        // cierra el otro.
        .inspector(isPresented: sidePanelShown) { sidePanel }
        .environment(\.titlePanel, titleOpener)
        .posterFlight($flight, panelWidth: DS.Remote.panelIdeal)
        // La barra de pestañas siempre completa, en todas las pestañas: siempre ves Inicio, Explorar, Descargas y Buscar
        // (Fernando, 2 nov 2026: «la barra siempre debería estar completa, siempre deberíamos poder ver todo»).
        .tabBarMinimizeBehavior(.never)
        .onChange(of: tab) { _, t in if t == 2 { Perf.begin("stab"); Perf.mark("stab.tap") } }
        .task {
            let requests = env.services.debridRequests
            cloudPending = requests.active.count
            cloudWatch = requests.onChange { let count = requests.active.count; if count != cloudPending { cloudPending = count } }
        }
        .task {
            let downloads = env.services.downloads
            let all = await downloads.all
            pendingDownloads = all.filter { $0.state != .done }.count
            finishedDownloads = all.filter { $0.state == .done }.count   // lo que ya estaba descargado no vibra al abrir
            for await items in downloads.makeUpdates() {
                let count = items.filter { $0.state != .done }.count
                if count != pendingDownloads { pendingDownloads = count }
                let done = items.filter { $0.state == .done }.count
                if done != finishedDownloads { finishedDownloads = done }
            }
        }
        // Terminó una descarga: un toque de «listo» en la mano, estés en la pantalla que estés.
        .dsFeedback(.success, trigger: finishedDownloads) { (old: Int, new: Int) -> Bool in new > old }
        // El accesorio mientras la TV reproduce algo o corre un juego, en cualquier pantalla (antes se iba al entrar a una
        // ficha y parecía que a veces no salía). Sin nada en la TV, el control se abre con el botón junto al avatar.
        // Con el control abierto como panel (iPad acostado, Mac) la barrita se esconde: repetía lo que ya dice el panel
        // (revisión 2 del 11 nov).
        .bottomAccessory(isEnabled: (tvNow.model.now != nil || tvNow.model.game != nil) && !(showRemote && remoteAsPanel)) {
            // Un juego en la consola: su acompañante (como el control lo es de lo que suena).
            Group {
                if let game = tvNow.model.game {
                    GameAccessory(game: game) { showGame = true }
                } else if let now = tvNow.model.now {
                    TVAccessory(now: now, busy: tvNow.model.busy, toggle: { Task { await tvNow.model.control("toggle") } }, openRemote: { remoteLarge = sizeClass == .regular; showRemote = true },
                                yearOf: { kind, imdb in
                                    let meta = try? await env.services.cinemeta.meta(kind: kind, id: imdb)
                                    let found = (meta?["releaseInfo"]?.string ?? meta?["year"]?.string)?.trimmingCharacters(in: .whitespaces) ?? ""
                                    return found.isEmpty ? nil : found
                                })
                }
            }
            .modifier(AccessoryPlacementReport())   // si va encima de la barra o a su lado (la pastilla de calificar se acomoda)
        }
    }

    /// Lo que se le pasa a todas las pantallas y lo que abre el control o el juego de la TV.
    private func wired(_ selection: Binding<Int>) -> some View {
        shell(selection)
        .environment(\.openRemote, openRemoteAction)
        .environment(\.tallArt, TallArtLookup(env.services.tallArt))   // el póster sin texto en los marcos altos (ficha, «En tendencia»)
        // Si la TV deja de reproducir con la hoja abierta, la hoja se cierra (no se queda vacía).
        // (Estirado, el control completo sirve aunque no haya video: se queda.)
        .onChange(of: tvNow.model.now == nil) { _, stopped in if stopped, !remoteLarge { showRemote = false } }
        #if DEBUG
        .onChange(of: tvNow.model.now == nil) { _, stopped in   // `-demo-open remote` (corta) o `remote-full` (estirada)
            if !stopped, Demo.isOn, ["remote", "remote-full", "remote-pad", "voice-guide"].contains(Demo.open) { remoteLarge = Demo.open != "remote" || sizeClass == .regular; showRemote = true }
        }
        .task { if Demo.isOn, Demo.open == "remote-idle" { remoteLarge = true; showRemote = true } }   // el control sin nada en la TV
        #endif
        // Tocar el accesorio abre el control remoto completo (−10 · pausa · +10 · siguiente, salir, seguir aquí).
        .sheet(isPresented: $showGame) {
            if let game = tvNow.model.game {
                GameCompanionView(tvNow: tvNow, game: game).dsSheetContent(sides: false)   // su carrusel llega a las orillas
                    .fittedSheet().presentationDragIndicator(.visible)   // del alto de lo que tiene, como el control
            }
        }
        .onChange(of: tvNow.model.game == nil) { _, ended in if ended { showGame = false } }
        // Los avisos del juego, con la hoja abierta o no.
        .onChange(of: tvNow.model.game?.closesAt) { _, _ in CompanionAlerts.scheduleCloseWarning(env, game: tvNow.model.game) }
        .onChange(of: tvNow.model.console?.batteryPercent) { _, percent in
            if let game = tvNow.model.game { CompanionAlerts.warnBattery(env, game: game, percent: percent, plugged: tvNow.model.console?.plugged ?? true) }
        }
        #if DEBUG
        .onChange(of: tvNow.model.game?.id) { _, id in if id != nil, Demo.isOn, Demo.open == "game" { showGame = true } }   // `-demo-open game`
        #endif
        // Se cerró un juego en la consola: su resumen.
        .sheet(isPresented: Binding(get: { showRemote && !remoteAsPanel }, set: { if !$0 { showRemote = false } })) {
            RemoteSheet(tvNow: tvNow, large: $remoteLarge, onContinueHere: { now in showRemote = false; openNowPlaying(now) })
        }
    }

    var body: some View {
        // Tocar «Buscar» estando ya en Buscar abre el campo con el teclado (TabView avisa aunque la pestaña no cambie).
        let selection = Binding(get: { tab }, set: { new in
            if new == 2, tab == 2, paths[2].isEmpty { ui.focusSearch = true }
            tab = new
        })
        wired(selection)
        .tint(DS.accent)   // la pestaña elegida lleva el acento; dentro, los botones vuelven al papel
        .onAppear(perform: openDemoScreen)
        .onAppear(perform: openPendingTitle)
        .onChange(of: ui.pendingTitle) { openPendingTitle() }
        // Un aviso o «Tus pedidos» (RX1-A) abre la pestaña desde su principio: Descargas, no Ajustes encima.
        .onChange(of: ui.openTab) { _, new in if let new { tab = new; paths[new] = NavigationPath(); env.openTab = nil } }
        .onChange(of: ui.goBack) { _, back in
            guard back else { return }
            ui.goBack = false
            if !paths[tab].isEmpty { paths[tab].removeLast() }
        }
        // IOS-10: la invitación de tu iPhone sale al abrir Orbital en el iPad (una vez por invitación), no escondida en Ajustes.
        .task { if env.services.takeInviteToShow() { paths[tab].append(SettingsRoute()) } }
        .onChange(of: ui.openSettings) { _, open in
            guard open else { return }
            ui.openSettings = false
            paths[tab].append(SettingsRoute())
        }
        // Ajustes › Tus idiomas (N4-A): Ajustes encima y ella abre su página (y apaga la bandera).
        .onChange(of: ui.openLanguages) { _, open in if open { paths[tab].append(SettingsRoute()) } }
        // «Un Simpson al azar» del Centro de control: a Inicio, que abre la ruleta (y apaga la bandera).
        .onChange(of: ui.openSimpsons, initial: true) { _, wants in if wants { tab = 0 } }
        .onChange(of: ui.openRemote, initial: true) { _, wants in
            guard wants else { return }
            ui.openRemote = false
            guard env.services.capabilities.console else { return }   // la Mac no tiene control de la TV (ni manda a Ajustes a conectarla)
            // Sin tu Orbital conectada (el control del Centro de control abre la app igual): a Ajustes, donde se conecta.
            // Como panel, ⌘R (y el control del Centro de control) lo abre y lo cierra.
            if tvNow.model.isConfigured { if remoteAsPanel && showRemote { showRemote = false } else { panelTitle = nil; remoteLarge = true; showRemote = true } }
            else { paths[tab].append(SettingsRoute()) }
        }
        .task {
            forceDemoTab()   // una segunda vez: gana aunque la restauración de escena llegue después de aparecer
            #if DEBUG
            // `-demo-open control-simpsons`: como si tocaras «Un Simpson al azar» en el Centro de control (con `-demo-free-tabs`).
            if Demo.isOn, Demo.open == "control-simpsons" { try? await Task.sleep(for: .seconds(2)); OpenSimpsonsIntent.open?() }
            // `-demo-tab-cycle N -perf -demo-free-tabs`: de Inicio a Explorar N veces, midiendo cada cambio (ver `Perf.cycle`).
            if Demo.isOn, let n = Demo.value(after: "-demo-tab-cycle").flatMap(Int.init) {
                try? await Task.sleep(for: .seconds(10))   // Demo: que termine de arrancar
                for i in 1...max(1, n) {
                    tab = 0
                    try? await Task.sleep(for: .seconds(3))   // Demo: que Inicio se asiente
                    Perf.begin("xtab"); Perf.cycle("xtab", i); HitchMeter.measure("xtab", seconds: 2)
                    tab = Demo.value(after: "-demo-tab-cycle-to").flatMap(Int.init) ?? 1   // a otra pestaña, para comparar
                    try? await Task.sleep(for: .seconds(4))   // Demo: lo que tarda en asentarse Explorar
                }
                Perf.cycle("done", n)
            }
            #endif
        }
        #if DEBUG
        // iOS restaura la pestaña que viste la última vez (independiente de nuestro @State) y lo hace después de
        // aparecer y del `.task` de arriba: si en modo demo algo la cambia por detrás, se vuelve a pedir la tuya.
        .onChange(of: tab) { _, new in if Demo.isOn, !Demo.freeTabs, new != Demo.tab { tab = Demo.tab } }
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
        if titleAsPanel { panelTitle = route } else { paths[0].append(route) }   // iPad y Mac: flotando a la izquierda
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
        // `-demo-open settings-avatar` (la hoja del avatar) también vive en Ajustes.
        if Demo.open?.hasPrefix("settings") == true || Demo.open == "year" || Demo.open == "orbital-setup" { paths[tab].append(SettingsRoute()) }
        if Demo.open == "repisa" { tab = 1; paths[1].append(RepisaRoute()) }   // `-demo-open repisa`: Colecciones
        if Demo.open == "watching" { tab = 1; paths[1].append(WatchingRoute()) }   // `-demo-open watching`: Lo que ves
        let library = AppEnvironment.downloadsTab   // `-demo-open history` / `vistas`: Guardado › Historial o Vistas (capturas)
        if Demo.open == "history" { tab = library; paths[library].append(HistoryRoute()) }
        if Demo.open == "vistas" { tab = library; paths[library].append(SavedStateRoute(status: TitleStatus.watched.rawValue)) }
        if let id = Demo.repisa { tab = 1; paths[1].append(RepisaRoute()); paths[1].append(id) }   // `-demo-repisa oscar`: una colección
        if let title = Demo.title {
            let route = TitleRoute(kind: title.kind, metaID: title.id, title: "", poster: nil)
            if titleAsPanel { panelTitle = route } else { paths[tab].append(route) }
        }
        if let id = Demo.mediaTitle { paths[tab].append(MiMediaTitleRoute(id: id)) }
        if let id = Demo.playDownload { Task { await env.playDownloaded(metaID: String(id.split(separator: ":").first ?? ""), videoID: id) } }
        #endif
    }
}

/// Un aviso de la app (sin Infuse, sin fuentes, descargando…), abajo como todos: se va solo; tocarlo lo cierra.
struct BannerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ui = AppEnvironment.shared.ui

    var body: some View {
        if let banner = env.notices.current {
            let hasAction = banner.action != nil
            Toast(tone: banner.tone, title: Text(verbatim: banner.text), detail: banner.detail.map { Text(verbatim: $0) },
                  actionTitle: hasAction ? banner.actionTitle.map { LocalizedStringKey($0) } ?? "Ver" : nil, actionSymbol: banner.actionSymbol,
                  action: hasAction ? { env.runBannerAction(banner) } : nil,
                  second: banner.second.map { n in Toast.Second(title: banner.secondTitle ?? "", symbol: banner.secondSymbol ?? "arrow.uturn.backward") { env.notices.perform(n) } },
                  symbol: banner.symbol,
                  seconds: Toast.duration(banner.tone, hasAction: hasAction), dismiss: { env.dismissBanner(banner.serial) })
                .id(banner.serial)
                .transition(DS.Motion.notice(reduceMotion))
                .dsFeedback(bannerFeedback(banner), trigger: banner.serial)
        }
    }

    /// Un error o una advertencia vibran como aviso; lo demás, como logro. Aparte: en línea, el Swift de la CI no la resolvía a tiempo.
    private func bannerFeedback(_ banner: Notice) -> SensoryFeedback {
        banner.tone == .error || banner.tone == .warn ? .warning : .success
    }
}



/// La barra de pestañas arriba de entrada en el iPad (DK1); aparte, para que el cuerpo de la raíz compile a tiempo.
private struct TabBarFirst: ViewModifier {
    func body(content: Content) -> some View { content.defaultAdaptableTabBarPlacement(.tabBar) }
}
