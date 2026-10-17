import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// Lo que la app necesita en todas partes: los servicios, quién reproduce y qué hacer cuando Infuse vuelve.
@MainActor
final class AppEnvironment: ObservableObject {
    let services: Services
    let transport: BackgroundDownloadTransport
    /// Una sola sesión para toda la app (la pantalla de Ajustes y la raíz ven el mismo estado al cerrar sesión).
    private(set) var session: SessionModel!
    /// «Viendo en la TV» y lo que la TV le deja al iPhone («Enviar» / «Descargar en el iPhone»): un solo sondeo para toda la app,
    /// no uno por pantalla (así una descarga mandada desde la TV arranca aunque estés en otra pestaña).
    private(set) var tvNow: TVNowModel!
    private(set) var inbox: InboxModel!
    private var servicesSubscription: ObservableModel.Subscription?
    let connectivity = Connectivity.shared
    private let liveActivity = DownloadLiveActivityController()

    /// Lo que se está reproduciendo con el reproductor propio (la vista del reproductor cubre toda la pantalla).
    /// El reproductor puede girar; el resto de la app es vertical. Se permite antes de presentarlo: la pantalla
    /// presentada toma las orientaciones permitidas al aparecer y no las vuelve a leer.
    @Published var playing: PlayRequest? {
        didSet {
            AppDelegate.orientations = playing == nil ? .portrait : .allButUpsideDown
            if playing == nil, oldValue != nil { watchedSomething += 1 }
        }
    }
    /// Cambia cada vez que termina una reproducción (aquí o en Infuse): Inicio y la ficha se ponen al día.
    @Published private(set) var watchedSomething = 0
    /// Una ficha que pidió abrir un enlace (el widget): `MainTabs` la empuja en Inicio y la vacía.
    @Published var pendingTitle: TitleRoute?
    /// Lo que se abrió en Infuse y está esperando a que vuelva.
    @Published private var external: ExternalSession?
    /// Infuse volvió sin duración y no se sabe si terminaste: se pregunta.
    @Published var askFinished: PlayRequest?
    /// Un aviso corto abajo: lo que pasó («Descargando…») o lo que salió mal.
    @Published var banner: Banner?
    struct Banner: Equatable { var text: String; var tone: DSNotice.Tone }

    /// Un aviso: lo que arma la app en español se traduce aquí, una sola vez (el aviso ya se pinta tal cual).
    func notify(_ text: String, tone: DSNotice.Tone = .error) { banner = Banner(text: Strings.message(text, language: services.appSettings.uiLanguage), tone: tone) }
    /// Un texto armado en español por un modelo (error o aviso), listo para `Text`/`DSNotice` en el idioma de la app.
    func message(_ text: String) -> String { Strings.message(text, language: services.appSettings.uiLanguage) }
    /// Un aviso con datos: la clave («… %@») se traduce primero y luego se llena (`LocalizedStringKey` no encuentra un texto ya armado).
    func notify(format key: String, _ args: CVarArg..., tone: DSNotice.Tone = .error) {
        banner = Banner(text: String(format: Strings.tr(key, language: services.appSettings.uiLanguage), arguments: args), tone: tone)
    }

    /// Un solo entorno para toda la app (las vistas lo comparten sin armar otro).
    static let shared = AppEnvironment()

    struct ExternalSession { var request: PlayRequest; var startedAt: Date; var startPosition: Double; var duration: Double }

    private init() {
        let transport = BackgroundDownloadTransport()
        self.transport = transport
        let services = Self.makeServices(transport)
        self.services = services
        let store = services.settings   // el almacén es seguro entre hilos: los cierres no tocan nada aislado al hilo principal
        transport.allowsCellular = { !store.value.wifiOnlyDownloads }
        services.episodeLabel = { Strings.episode(season: $0, episode: $1, language: store.value.uiLanguage) }
        services.tvEpisodeLabel = { Strings.tvEpisode(season: $0, episode: $1, label: $2, language: store.value.uiLanguage) }
        // El widget «Lo siguiente para ti»: sus textos en el idioma de la app y quién escribe su snapshot (al actualizar Inicio).
        services.widgetLabels = WidgetLabels(
            episode: { Strings.episode(season: $0, episode: $1, language: store.value.uiLanguage) },
            timeLeft: { Strings.timeLeft(minutes: $0, language: store.value.uiLanguage) },
            nextUp: { String(format: Strings.tr("Sigue: %@", language: store.value.uiLanguage), $0) })
        services.onWidgetSnapshot = { WidgetPublisher.publish($0) }
        #if DEBUG
        // Demostración: el widget enseña un snapshot de ejemplo (o vacío con `-demo-widget empty`); con `-demo-widget live`, el de verdad.
        if Demo.isOn, Demo.widget != "live" {
            services.onWidgetSnapshot = nil
            WidgetPublisher.publish(Demo.widget == "empty" ? .empty : Demo.widgetSnapshot)
        }
        #endif
        // Cambiar el idioma (o una clave) vuelve a pintar toda la app.
        servicesSubscription = services.onChange { [weak self] in self?.objectWillChange.send(); self?.applyAppearance() }
        session = SessionModel(services)
        inbox = InboxModel(services)
        tvNow = TVNowModel(services)
        tvNow.inbox = inbox
        inbox.onEvent = { [weak self] event in self?.announce(event) }
        Task { await services.downloads.start() }
        let settings = services.settings
        liveActivity.language = { settings.value.uiLanguage }
        Task { await liveActivity.follow(services.downloads) }
    }

    private static func makeServices(_ transport: BackgroundDownloadTransport) -> Services {
        #if DEBUG
        // Modo demostración: nada toca tu Keychain, tus ajustes ni tus descargas.
        if Demo.isOn {
            let kv = InMemoryKeyValueStore()
            SettingsStore(kv).update {
                if let language = Demo.language { $0.uiLanguage = language }
                if !Demo.noTV { $0.orbitalAddress = "tv.demo.invalid" }
                if Demo.scrobble || Demo.airings { $0.traktClientID = "demo" }
            }
            Demo.prefillScrobble(kv)
            let services = Services(http: DemoHTTPClient(), secrets: Demo.secrets(), kv: kv, pending: InMemoryPendingStore(),
                                    downloadTransport: transport, downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("demo-downloads"),
                                    freeSpace: { DiskSpace.freeBytes() })
            services.forYouFromConsole = Demo.console   // la ruta de la consola, para verla con la Orbital de mentira
            return services
        }
        #endif
        return Services(
            http: URLSessionHTTPClient(), secrets: KeychainSecrets(service: Bundle.main.bundleIdentifier ?? "com.example.orbital.ios"),
            kv: UserDefaultsKeyValueStore(), pending: FilePendingStore(url: AppFiles.pendingWork), downloadTransport: transport,
            downloadsRoot: AppFiles.downloadsRoot, savedDownloads: DownloadIndex.load(), freeSpace: { DiskSpace.freeBytes() },
            onDownloadsChange: { DownloadIndex.save($0) })
    }

    /// El aviso (con háptica, por el tono del aviso) de lo que pasó con lo que mandó la TV.
    private func announce(_ event: InboxModel.Event) {
        switch event {
        case .downloading(let name): notify(format: "Descargando %@ (desde la TV)", name, tone: .success)
        case .received(let name): notify(format: "Desde la TV: %@", name, tone: .info)
        case .downloadFailed(let name, let reason):
            switch reason {
            case .noSources: notify(format: "No encontré una fuente para descargar %@ (desde la TV)", name)
            case .notEnoughSpace: notify(format: "No hay espacio para descargar %@ (desde la TV)", name)
            case .other: notify(format: "No pude descargar %@ (desde la TV)", name)
            }
        }
    }

    /// En segundo plano (iOS lo permite cuando quiere): se mira lo que dejó la TV y se encolan las descargas, que siguen en la
    /// sesión de fondo. Lo seguro es abrir la app; esto es de mejor esfuerzo.
    func checkTVInbox() async {
        guard services.orbital.isConfigured, let snapshot = try? await services.orbital.snapshot() else { return }
        await inbox.process(snapshot.inbox)
    }

    var uiLocale: Locale { Locale(identifier: services.appSettings.uiLanguage) }
    /// Ajustes › Apariencia: nil sigue al iPhone.
    var colorScheme: ColorScheme? {
        #if DEBUG
        if let forced = Demo.appearance { return forced == "light" ? .light : .dark }
        #endif
        switch services.appSettings.appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    /// Pone el modo en todas las ventanas (la app, las hojas y el reproductor). `preferredColorScheme` no regresa a «Como el
    /// iPhone» después de forzar claro u oscuro y a veces no llega a las hojas abiertas: la ventana sí obedece siempre.
    func applyAppearance() {
        let style: UIUserInterfaceStyle = switch colorScheme { case .light: .light; case .dark: .dark; default: .unspecified }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style { window.overrideUserInterfaceStyle = style }
        }
    }

    // MARK: reproducir
    /// Reproduce con el motor propio o, si lo prefieres (o fallara), con Infuse.
    func play(_ request: PlayRequest) { playing = request }

    func playExternal(_ request: PlayRequest, source: Source? = nil) async {
        let position = request.fromStart ? 0 : await services.watch.resumePosition(metaID: request.metaID, videoID: request.videoID)
        let langs = services.titlePrefs.languages(for: request.metaID, settings: services.appSettings)
        var chosen = source
        if chosen == nil { chosen = try? await services.finder.best(kind: request.kind, videoID: request.videoID, prefs: langs.prefs) }
        guard let url = chosen?.playbackURL else { return notify("No hay fuentes de Real-Debrid para este título.") }
        let subtitle = await services.finder.subtitles(kind: request.kind, videoID: request.videoID, language: langs.subtitles.isEmpty ? services.appSettings.subtitles : langs.subtitles).first
        var season: Int?, episode: Int?
        let parts = request.videoID.split(separator: ":")
        if request.kind == "series", parts.count >= 3 { season = Int(parts[parts.count - 2]); episode = Int(parts[parts.count - 1]) }
        let filename = Infuse.filename(title: request.originalTitle, year: request.year, season: season, episode: episode, ext: DownloadFiles.fileExtension(for: url))
        guard let infuseURL = Infuse.playURL(.init(video: url, position: Int(position), subtitle: subtitle, filename: filename)) else { return }
        let runtime = request.meta.map { CinemetaParsing.runtimeSeconds(CinemetaParsing.describe($0).runtime) } ?? 0
        external = ExternalSession(request: request, startedAt: Date(), startPosition: position, duration: runtime)
        let opened = await UIApplication.shared.open(infuseURL)
        if !opened { external = nil; notify("No pude abrir Infuse. ¿Está instalado?") }
    }

    /// Infuse volvió (`orbital-ios://infuse-done?...`): se guarda dónde te quedaste. Infuse ya avisa a Trakt por su cuenta.
    func handle(url: URL) async {
        // El QR de «Conectar iPhone» en la TV: queda conectada sin escribir nada.
        if let pair = OrbitalRemote.pairing(url) { return await pairWithOrbital(address: pair.address, token: pair.token) }
        // El widget «Lo siguiente para ti»: reproducir donde ibas o abrir la ficha.
        if let link = WidgetLink.parse(url) { return await open(link) }
        guard let result = Infuse.parseCallback(url) else { return }
        defer { external = nil; watchedSomething += 1 }
        guard let session = external else { return }
        switch result {
        case .failed(_, let message, _):
            if let message { notify(format: "Infuse no pudo reproducirlo: %@", stripURLs(message)) } else { notify("Infuse no pudo reproducirlo.") }
        case .closed:
            guard let seconds = Infuse.seconds(from: result, knownDuration: session.duration) else { return }
            let r = session.request
            let watched = max(0, seconds - session.startPosition)
            let event = ProgressEvent(kind: r.kind, metaID: r.metaID, videoID: r.videoID, originalTitle: r.originalTitle, position: seconds, duration: session.duration,
                                      watched: min(watched, Date().timeIntervalSince(session.startedAt)), at: Date().timeIntervalSince1970)
            await services.watch.report(event, phase: .stopped(finished: session.duration > 0 && seconds >= session.duration * StremioLibrary.watchedAt), scrobbleToTrakt: false)
            // Infuse no dice la duración: si tampoco la sabemos, se pregunta si terminaste.
            if session.duration == 0, seconds > 60 { askFinished = r }
        }
    }

    /// `orbital-ios://play?kind=&id=&video=` abre el reproductor en ese episodio (donde ibas); `orbital-ios://title?kind=&id=` abre la ficha.
    /// Sin episodio conocido, o si la ficha no carga, se cae a la ficha.
    private func open(_ link: WidgetLink) async {
        switch link {
        case .title(let kind, let id):
            pendingTitle = TitleRoute(kind: kind, metaID: id, title: "", poster: nil)
        case .play(let kind, let id, let video):
            guard let video, let meta = try? await services.cinemeta.meta(kind: kind, id: id) else {
                pendingTitle = TitleRoute(kind: kind, metaID: id, title: "", poster: nil)
                return
            }
            let name = meta["name"]?.string ?? ""
            var label = ""
            let parts = video.split(separator: ":")
            if kind == "series", parts.count >= 3, let episode = Int(parts[parts.count - 1]) {
                label = Strings.episode(season: Int(parts[parts.count - 2]), episode: episode, language: services.appSettings.uiLanguage)
            }
            await play(kind: kind, metaID: id, videoID: video, title: name, originalTitle: name, episodeLabel: label, poster: meta["poster"]?.string)
        }
    }

    /// «Sí, lo terminé»: se marca como visto y Stremio apunta al siguiente.
    func confirmFinished(_ request: PlayRequest) async {
        let event = ProgressEvent(kind: request.kind, metaID: request.metaID, videoID: request.videoID, originalTitle: request.originalTitle,
                                  position: 1, duration: 1, watched: 0, at: Date().timeIntervalSince1970)
        await services.watch.report(event, phase: .stopped(finished: true), scrobbleToTrakt: false)
        askFinished = nil
    }

    func pairWithOrbital(address: String, token: String) async {
        do {
            let got = try await services.connectOrbital(address: address, token: token)
            let brought = got.joined(separator: services.appSettings.uiLanguage == "en" ? " and " : " y ")
            if got.isEmpty { notify("Conectado con tu Orbital.", tone: .success) } else { notify(format: "Conectado con tu Orbital: %@ ya están aquí.", brought, tone: .success) }
        } catch { notify((error as? OrbitalRemote.Failure)?.description ?? "\(error)") }
    }

    /// «Ver en la TV»: tu Orbital pone el título (la fuente recomendada, donde ibas; el avance vive en Stremio).
    func playOnTV(kind: String, metaID: String, videoID: String?, title: String) async {
        do {
            try await services.orbital.play(kind: kind, metaID: metaID, videoID: videoID, title: title)
            notify("Poniéndolo en la TV.", tone: .success)
        } catch { notify((error as? OrbitalRemote.Failure)?.description ?? "\(error)") }
    }

    /// Un título desde Inicio: reproduce directo donde ibas.
    func play(_ item: HomeItem) async {
        var label = ""
        if let episode = item.episode { label = Strings.episode(season: item.season, episode: episode, language: services.appSettings.uiLanguage) }
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.originalTitle, episodeLabel: label, poster: item.poster)
    }

    /// El video de una sugerencia: el episodio en curso, la película, o el primer episodio de una serie sin avance.
    func videoID(for s: Suggestion) -> String {
        if let next = s.next { return "\(s.imdb):\(next.season):\(next.episode)" }
        return s.kind == "movie" ? s.imdb : "\(s.imdb):1:1"
    }

    /// «Ver» desde Para ti: reproduce donde ibas (o desde el principio).
    func play(_ s: Suggestion) async {
        let label = s.next.map { Strings.episode(season: $0.season, episode: $0.episode, language: services.appSettings.uiLanguage) } ?? ""
        await play(kind: s.kind, metaID: s.imdb, videoID: videoID(for: s), title: s.title, originalTitle: s.title, episodeLabel: label, poster: s.poster)
    }

    /// «Mi lista» desde Para ti.
    func addToLibrary(_ s: Suggestion) async {
        do {
            try await services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: true)
            notify("Agregada a tu lista.", tone: .success)
        } catch { notify(format: "No pude cambiar tu lista de Stremio: %@", message("\(error)")) }   // la causa, también traducida
    }

    /// «Descargar» desde Para ti (la fuente recomendada).
    func download(_ s: Suggestion) async {
        let outcome = await services.queueDownload(kind: s.kind, metaID: s.imdb, videoID: videoID(for: s), title: s.title, originalTitle: s.title, subtitle: "", poster: s.poster)
        switch outcome {
        case .queued: notify("Descargando. Lo verás en Descargas.", tone: .success)
        case .noSources: notify("No hay fuentes de Real-Debrid para descargar.")
        case .notEnoughSpace(let text), .failed(let text): notify(text)
        case .already: notify("Ya está descargado.", tone: .info)
        }
    }

    /// «Ver» en la tarjeta «Desde la TV»: lo mismo, con lo que mandó la consola.
    func play(_ item: OrbitalRemote.InboxItem) async {
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.title, episodeLabel: services.tvEpisodeLabel(item.season, item.episode, item.episodeLabel), poster: item.poster)
    }

    private func play(kind: String, metaID: String, videoID: String?, title: String, originalTitle: String, episodeLabel: String, poster: String?) async {
        guard let videoID, let meta = try? await services.cinemeta.meta(kind: kind, id: metaID) else { return notify("No pude abrir ese título.") }
        let request = PlayRequest(kind: kind, metaID: metaID, videoID: videoID, originalTitle: originalTitle, displayTitle: title,
                                  episodeLabel: episodeLabel, poster: poster, meta: meta)
        if services.appSettings.preferInfuse { await playExternal(request) } else { play(request) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Se registra antes de que termine de arrancar la app (lo exige iOS).
        InboxBackgroundTask.register()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientations }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Puede llegar antes de que exista ninguna vista: se arma el entorno (que reconecta la sesión de descargas) y se guarda aquí.
        AppEnvironment.shared.transport.backgroundCompletion = completionHandler
    }
}
