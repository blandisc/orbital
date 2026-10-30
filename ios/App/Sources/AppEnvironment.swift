import SwiftUI
import UserNotifications
import UIKit
import WidgetKit
import OrbitalCore
import OrbitalModels

/// Lo que la app necesita en todas partes: los servicios, quién reproduce y qué hacer cuando Infuse vuelve.
@MainActor
@Observable
final class AppEnvironment {
    /// Cambiar el idioma (o una clave) vuelve a pintar toda la app: quien lee `services` mientras se pinta sigue sus cambios.
    var services: Services { core.track(); return core }
    private let core: Services
    let transport: BackgroundDownloadTransport
    /// Mantiene la app viva en segundo plano mientras baja algo que pediste (iOS 26, `BGContinuedProcessingTask`).
    let downloadContinuation = DownloadContinuation()
    /// Una sola sesión para toda la app (la pantalla de Ajustes y la raíz ven el mismo estado al cerrar sesión).
    @ObservationIgnored private(set) var session: SessionModel!
    /// «Viendo en la TV» y lo que la TV le deja al iPhone («Enviar» / «Descargar en el iPhone»): un solo sondeo para toda la app,
    /// no uno por pantalla (así una descarga mandada desde la TV arranca aunque estés en otra pestaña).
    @ObservationIgnored private(set) var tvNow: TVNowModel!
    /// Lo popular de Buscar: uno para toda la app, pedido al abrirla (Buscar ya lo encuentra listo, con su color).
    @ObservationIgnored private(set) var catalog: CatalogModel!
    @ObservationIgnored private(set) var inbox: InboxModel!
    /// Conectar OneDrive: uno para toda la app (si sales de Ajustes mientras escribes el código, al volver sigue esperando).
    @ObservationIgnored lazy var oneDriveSetup = OneDriveModel(services)
    /// Premios, tus listas de Trakt y «Por año»: uno para toda la app (cambiar entre mosaico y listas no lo vuelve a pedir todo).
    @ObservationIgnored lazy var collections = CollectionsModel(services)
    /// Lo que ves y el Wrapped: uno para toda la app (el historial se trae una vez y se cuenta por periodo).
    @ObservationIgnored lazy var watching: WatchingModel = {
        let model = WatchingModel(services)
        #if DEBUG
        if Demo.isOn { model.preload(Demo.yearInReview.plays.values.flatMap { $0 }) }   // el mismo historial inventado de «Tu año»
        #endif
        return model
    }()
    /// Colecciones (la repisa): una para toda la app, con lo visto de `collections` (el mismo caché).
    @ObservationIgnored lazy var repisa = RepisaModel(services, watched: { [unowned self] in await self.collections.watchedIDs() })
    /// El filtro avanzado: uno para toda la app (lo que elegiste se queda al volver a abrir el cajón).
    @ObservationIgnored lazy var advancedFilter = AdvancedFilterModel(services)
    /// Tus calificaciones y el recordatorio de calificar (como en Trakt): uno para toda la app (la ficha y la pastilla ven lo mismo).
    @ObservationIgnored lazy var ratings = RatingsModel(services)
    /// Ver, guardar, quitar, favoritos y marcar como vista desde un póster: la lógica en `TitleActions` (OrbitalModels, con pruebas).
    @ObservationIgnored lazy var titles = TitleActions(services)
    /// «Un Simpson al azar»: la lógica vive en `SimpsonsModel` (OrbitalModels, con pruebas); aquí se le enchufan las imágenes y el aviso.
    @ObservationIgnored lazy var simpsons: SimpsonsModel = {
        let model = SimpsonsModel(services, reelLength: DS.Simpsons.reelLength)
        model.warmImages = { await ImagePipeline.shared.warmPosters($0) }
        model.onError = { [weak self] text, detail in self?.notify(text, detail: detail) }
        return model
    }()
    @ObservationIgnored private var servicesSubscription: ObservableModel.Subscription?
    let connectivity = Connectivity.shared
    private let liveActivity = DownloadLiveActivityController()
    @ObservationIgnored private var traktObserver: NSObjectProtocol?
    /// La actividad en vivo de las descargas: en segundo plano su barra avanza sola con lo estimado.
    func setDownloadsBackgrounded(_ value: Bool) async {
        // Con la app a la vista, las descargas por pedazos van por el carril rápido; al irte, pasan a segundo plano, salvo que
        // la tarea continua de iOS siga viva (entonces siguen igual de rápido).
        await transport.setForeground(!value || downloadContinuation.isRunning)
        await liveActivity.setBackgrounded(value)
    }

    /// El estado que solo pinta la raíz (el reproductor, los avisos, la pestaña que se pide abrir) vive aparte, en `ui`:
    /// así un aviso o el reproductor que se abre no vuelven a pintar Inicio, Para ti y la ficha (que observan `env`).
    let ui = AppUI()

    /// Lo que se está reproduciendo con el reproductor propio (la vista del reproductor cubre toda la pantalla).
    /// El reproductor puede girar; el resto de la app es vertical. Se permite antes de presentarlo: la pantalla
    /// presentada toma las orientaciones permitidas al aparecer y no las vuelve a leer.
    var playing: PlayRequest? {
        get { ui.playing }
        set {
            let old = ui.playing
            Orientation.mask = newValue == nil ? .portrait : .allButUpsideDown
            ui.playing = newValue
            if newValue == nil, old != nil { watchedSomething += 1 }
        }
    }
    /// Cambia cada vez que termina una reproducción (aquí o en Infuse): Inicio y la ficha se ponen al día.
    var watchedSomething = 0
    /// Una ficha que pidió abrir un enlace (el widget): `MainTabs` la empuja en Inicio y la vacía.
    var pendingTitle: TitleRoute? { get { ui.pendingTitle } set { ui.pendingTitle = newValue } }
    /// Lo que se abrió en Infuse y está esperando a que vuelva (no se pinta).
    @ObservationIgnored var external: ExternalSession?
    /// Infuse volvió sin duración y no se sabe si terminaste: se pregunta.
    var askFinished: PlayRequest? { get { ui.askFinished } set { ui.askFinished = newValue } }
    /// Los avisos de la app («Descargando…», lo que salió mal): la cola vive en `NoticeCenter` (OrbitalModels, con pruebas);
    /// aquí solo se traducen y se mandan. La raíz pinta `notices.current`.
    let notices = NoticeCenter(queueLimit: DS.Toast.queueLimit)
    typealias Banner = Notice
    typealias BannerAction = NoticeAction
    /// Lo que acabas de pasar a la TV desde el reproductor: el aviso con «Deshacer» (regresa al iPhone en el mismo punto).
    var handoff: TVHandoff? { get { ui.handoff } set { ui.handoff = newValue } }
    struct TVHandoff: Equatable {
        var request: PlayRequest
        var position: Double
        static func == (a: TVHandoff, b: TVHandoff) -> Bool { a.request.id == b.request.id && a.position == b.position }
    }

    /// Un aviso con un botón propio: «Guardada en Mi lista · Cambiar», «Bajando la recomendada · Otra».
    func notify(_ text: String, detail: String? = nil, tone: NoticeTone = .success, actionTitle: String, actionSymbol: String? = nil,
                perform: @escaping () -> Void) {
        let language = services.appSettings.uiLanguage
        let serial = notices.register(perform)
        notices.show(Notice(text: Strings.message(text, language: language), tone: tone, action: .perform(serial),
                            detail: detail.map { Strings.message($0, language: language) }, actionTitle: Strings.tr(actionTitle, language: language),
                            actionSymbol: actionSymbol))
    }

    /// Se fue (se acabó su tiempo, lo tocaste o lo deslizaste): sale el siguiente que esperaba.
    func dismissBanner(_ serial: Int) { notices.dismiss(serial) }

    /// Su salida: ir a Descargas o lo que pidió quien avisó.
    func runBannerAction(_ banner: Banner) {
        switch banner.action {
        case .downloads: openTab = Self.downloadsTab
        case .perform(let n): notices.perform(n)
        case nil: break
        }
    }

    /// Una pestaña que un aviso pide abrir («Ver» en «Descargando…»).
    var openTab: Int? { get { ui.openTab } set { ui.openTab = newValue } }
    static let downloadsTab = 3

    /// Las imágenes de tu Orbital (logos de canales, arte de juegos) se piden con su token.
    private func shareConsoleWithImages() {
        ImagePipeline.shared.setConsole(services.orbital.base, token: services.secrets.get(SecretKey.orbitalToken))
    }

    /// Un aviso: lo que arma la app en español se traduce aquí, una sola vez (el aviso ya se pinta tal cual).
    /// Neutral si nadie dice otra cosa: el ámbar es para lo que te necesita y el rojo, para cuando algo se perdió.
    func notify(_ text: String, detail: String? = nil, tone: NoticeTone = .info, action: BannerAction? = nil, actionTitle: String? = nil) {
        let language = services.appSettings.uiLanguage
        notices.show(Notice(text: Strings.message(text, language: language), tone: tone, action: action,
                            detail: detail.map { Strings.message($0, language: language) }, actionTitle: actionTitle.map { Strings.tr($0, language: language) }))
    }
    /// Un texto armado en español por un modelo (error o aviso), listo para `Text`/`DSNotice` en el idioma de la app.
    func message(_ text: String) -> String { Strings.message(text, language: services.appSettings.uiLanguage) }
    /// Un aviso con datos: la clave («… %@») se traduce primero y luego se llena (`LocalizedStringKey` no encuentra un texto ya armado).
    func notify(format key: String, _ args: CVarArg..., detail: String? = nil, tone: NoticeTone = .info, action: BannerAction? = nil) {
        let language = services.appSettings.uiLanguage
        notices.show(Notice(text: String(format: Strings.tr(key, language: language), arguments: args), tone: tone, action: action,
                            detail: detail.map { Strings.message($0, language: language) }))
    }

    /// Lo que bajaste de ese video, sin red (si ya no está, a Descargas).
    func playDownloaded(metaID: String, videoID: String) async {
        guard let item = await services.downloads.item(DownloadItem.makeID(metaID: metaID, videoID: videoID)), item.state == .done else {
            openTab = Self.downloadsTab; return
        }
        play(await DownloadsModel(services, freeSpace: { DiskSpace.freeBytes() }).playRequest(item))
    }

    /// Lo que pasó al pedir una descarga, dicho igual en toda la app (la ficha, Para ti, Mi media y lo que manda la TV).
    /// `.queued` lo dice quien la pidió (cada uno a su manera: el anillo, «Bajando la recomendada»).
    func report(_ outcome: TitleModel.DownloadOutcome, downloaded video: (metaID: String, videoID: String)? = nil) {
        switch outcome {
        case .queued: break
        case .noSources: notify("No hay una versión para bajar", detail: "Real-Debrid no tiene un archivo de este título")
        case .notEnoughSpace(let text): notify("No cabe en el iPhone", detail: text, tone: .warn, action: .downloads, actionTitle: "Descargas")
        case .already:
            if let video {
                notify("Ya está descargada", detail: "En el iPhone, para ver sin conexión", tone: .info, actionTitle: "Ver", actionSymbol: "play.fill") { [weak self] in
                    Task { await self?.playDownloaded(metaID: video.metaID, videoID: video.videoID) }
                }
            }
            else { notify("Ya está descargada", detail: "En el iPhone, para ver sin conexión", action: .downloads, actionTitle: "Descargas") }
        case .failed(let text): notify("No pude preparar la descarga", detail: text, tone: .warn)
        }
    }

    /// Un solo entorno para toda la app (las vistas lo comparten sin armar otro).
    static let shared = AppEnvironment()

    struct ExternalSession { var request: PlayRequest; var startedAt: Date; var startPosition: Double; var duration: Double }

    private init() {
        let transport = BackgroundDownloadTransport()
        self.transport = transport
        let services = AppComposition.makeServices(transport)
        self.core = services
        let store = services.settings   // el almacén es seguro entre hilos: los cierres no tocan nada aislado al hilo principal
        transport.allowsCellular = { !store.value.wifiOnlyDownloads }
        services.episodeLabel = { Strings.episode(season: $0, episode: $1, language: store.value.uiLanguage) }
        services.tvEpisodeLabel = { Strings.tvEpisode(season: $0, episode: $1, label: $2, language: store.value.uiLanguage) }
        // El widget «Lo siguiente para ti»: sus textos en el idioma de la app y quién escribe su snapshot (al actualizar Inicio).
        services.widgetLabels = WidgetLabels(
            episode: { Strings.episode(season: $0, episode: $1, language: store.value.uiLanguage) },
            timeLeft: { Strings.timeLeft(minutes: $0, language: store.value.uiLanguage) },
            nextUp: { String(format: Strings.tr("Sigue: %@", language: store.value.uiLanguage), $0) })
        // Los mismos títulos le enseñan a Siri los nombres de «Seguir viendo» («Oye Siri, pon The Office en Orbital»).
        services.onWidgetSnapshot = { WidgetPublisher.publish($0) }
        services.onSiriTitles = { SiriTitles.save($0) }
        #if DEBUG
        // Demostración: el widget enseña un snapshot de ejemplo (o vacío con `-demo-widget empty`); con `-demo-widget live`, el de verdad.
        if Demo.isOn, Demo.widget != "live" {
            services.onWidgetSnapshot = nil
            WidgetPublisher.publish(Demo.widget == "empty" ? .empty : Demo.widgetSnapshot)
        }
        #endif
        // Cambiar el idioma (o una clave) vuelve a pintar toda la app (por Observation, ver `services`); aquí, la apariencia y las imágenes.
        servicesSubscription = services.onChange { [weak self] in self?.applyAppearance(); self?.shareConsoleWithImages() }
        shareConsoleWithImages()
        session = SessionModel(services)
        inbox = InboxModel(services)
        tvNow = TVNowModel(services)
        tvNow.inbox = inbox
        catalog = CatalogModel(services)
        inbox.onEvent = { [weak self] event in self?.announce(event) }
        // Trakt cerró la sesión: se avisa una vez, con un botón a Ajustes (antes se desconectaba en silencio).
        traktObserver = NotificationCenter.default.addObserver(forName: Trakt.sessionLost, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notify("Tu sesión de Trakt se cerró", detail: "Sin ella no llegan tus recomendaciones", tone: .warn,
                             actionTitle: "Conectar") { self?.ui.openSettings = true }
            }
        }
        Task { await services.downloads.start() }
        #if DEBUG
        // `-diag-download <imdb>`: con tu cuenta de verdad (no la demostración), baja esa película con la fuente recomendada, para
        // medir en el iPhone qué pasa al salir de la app (ver `DownloadTimeline`). `-diag-cleanup <imdb>` la borra.
        if let imdb = Demo.value(after: "-diag-download") {
            Task {
                try? FileManager.default.removeItem(at: DownloadTimeline.file)
                // El camino de siempre de «Descargar» (la fuente recomendada; si no da el video, la cola prueba otra).
                _ = await services.queueDownload(kind: "movie", metaID: imdb, videoID: imdb, title: Demo.diagTitle, originalTitle: Demo.diagTitle,
                                                           subtitle: "", poster: nil)
            }
        }
        if let imdb = Demo.value(after: "-diag-cleanup") {
            Task { for item in await services.downloads.all where item.metaID == imdb { await services.downloads.remove(item.id) } }
        }
        // `-demo-real-download <url>`: una descarga de verdad (con el transporte real, por pedazos) para medir el motor.
        if Demo.isOn, let raw = Demo.value(after: "-demo-real-download"), let url = URL(string: raw) {
            Task {
                let item = DownloadItem(id: "tt0000001|tt0000001", kind: "movie", metaID: "tt0000001", videoID: "tt0000001", title: "Prueba de velocidad",
                                        originalTitle: "Prueba", subtitle: "", poster: nil, addon: "Demo", sourceIndex: 0, expectedBytes: nil,
                                        relativePath: DownloadFiles.relativePath(metaID: "tt0000001", videoID: "tt0000001", ext: "bin"),
                                        createdAt: Date().timeIntervalSince1970)
                try? await services.downloads.enqueue(item, url: url)
            }
        }
        #endif
        DownloadsModel.clearShared()   // los enlaces de «Compartir» de la vez pasada
        Task.detached(priority: .background) { ImportedVideos.prune() }
        let settings = services.settings
        liveActivity.language = { settings.value.uiLanguage }
        Task { await liveActivity.follow(services.downloads) }
        // Una descarga que se detiene con la app cerrada se avisa (antes la actividad solo desaparecía).
        // La tarea continua de iOS: que sigan a toda velocidad aunque salgas de la app.
        let lanes = self.transport
        downloadContinuation.language = { settings.value.uiLanguage }
        let liveActivity = liveActivity
        downloadContinuation.onStarted = {
            await lanes.setForeground(true)
            await liveActivity.setSuppressed(true)   // una sola actividad: la de iOS mientras dura la tarea
        }
        downloadContinuation.onEnded = { await liveActivity.setSuppressed(false) }
        services.titlePrefs.onPendingChoice = { [weak self] in Task { @MainActor in self?.scheduleChoiceSync() } }
        downloadContinuation.onExpired = { if UIApplication.shared.applicationState != .active { await lanes.setForeground(false) } }
        Task {
            for await items in services.downloads.makeUpdates() {
                DownloadFailureNotifier.observe(items, language: settings.value.uiLanguage)
                downloadContinuation.update(items)
                DownloadTimeline.record(items, fastLane: lanes.isFastLane, continued: downloadContinuation.isRunning)
            }
        }
    }


    /// El aviso (con háptica, por el tono del aviso) de lo que pasó con lo que mandó la TV.
    private func announce(_ event: InboxModel.Event) {
        switch event {
        case .downloading(let name): notify(format: "La TV te mandó «%@»", name, detail: "Bajando en el iPhone", tone: .success, action: .downloads)
        case .received(let name): notify(format: "La TV te mandó «%@»", name)
        case .downloadFailed(let name, let reason):
            switch reason {
            case .noSources: notify(format: "No pude bajar «%@»", name, detail: "Real-Debrid no tiene un archivo de este título")
            case .notEnoughSpace: notify(format: "«%@» no cabe en el iPhone", name, detail: "Libera espacio en Descargas", tone: .warn, action: .downloads)
            case .other: notify(format: "No pude bajar «%@»", name, detail: "Lo mandó la TV: intenta desde su ficha")
            }
        case .played:
            break   // Se cerró un juego en la consola: sin resumen ni aviso (se sentía como un regaño por el tiempo jugado).
        }
    }

    /// En segundo plano (iOS lo permite cuando quiere): se mira lo que dejó la TV y se encolan las descargas, que siguen en la
    /// sesión de fondo. Lo seguro es abrir la app; esto es de mejor esfuerzo.
    /// El audio, la variante y los subtítulos de cada título valen en la TV y aquí: se manda lo que cambió y se trae lo de
    /// la TV (al abrir la app y unos segundos después de elegir algo). Sin tu Orbital, nada se pierde: espera.
    func syncChoices() async {
        guard services.orbital.isConfigured else { return }
        await services.titlePrefs.syncChoices(with: services.orbital)
    }

    @ObservationIgnored private var choiceSync: Task<Void, Never>?
    func scheduleChoiceSync() {
        choiceSync?.cancel()
        choiceSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))   // varias elecciones seguidas (audio y subtítulos) van juntas
            guard !Task.isCancelled else { return }
            await self?.syncChoices()
        }
    }

    func checkTVInbox() async {
        guard services.orbital.isConfigured, let snapshot = try? await services.orbital.snapshot() else { return }
        await inbox.process(snapshot.inbox)
    }

    var uiLocale: Locale { Locale(identifier: services.appSettings.uiLanguage) }
    /// El idioma de la interfaz («es» o «en»), para los textos que se arman en código.
    var language: String { services.appSettings.uiLanguage }
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
        do {
            for window in AppWindows.all where window.overrideUserInterfaceStyle != style {
                // Con un fundido (como Ajustes): de golpe, toda la app se redibujaba en un cuadro y se sentía trabado.
                UIView.transition(with: window, duration: DesignTokens.Motion.slow, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }

    // MARK: reproducir
    /// Reproduce con el motor propio o, si lo prefieres (o fallara), con Infuse.
    func play(_ request: PlayRequest) { playing = request }

    /// Un enlace que llega a la app: un archivo de video, el QR de la TV, el widget o la vuelta de Infuse.
    func handle(url: URL) async {
        // Un video que te pasaron (AirDrop, Archivos, «Abrir con…»).
        if url.isFileURL { return await openFile(url) }
        // El QR de «Conectar iPhone» en la TV: queda conectada sin escribir nada.
        if let pair = OrbitalRemote.pairing(url) { return await pairWithOrbital(address: pair.address, token: pair.token) }
        // El widget «Lo siguiente para ti»: reproducir donde ibas o abrir la ficha.
        if let link = WidgetLink.parse(url) { return await open(link) }
        guard let result = Infuse.parseCallback(url) else { return }
        await infuseReturned(result)
    }

    /// Un video de fuera: se copia a la app (los de hace días se borran), se reconoce por el nombre del archivo (Cinemeta: nombre,
    /// año, temporada y episodio) y se reproduce. Reconocido, el reproductor le busca subtítulos en OpenSubtitles con la huella
    /// del archivo (los de esa copia exacta) y guarda tu avance en el teléfono y en Trakt; sin reconocer, se ve igual, sin guardar nada.
    private func openFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let target: URL
        do { target = try ImportedVideos.store(url) } catch { notify("No pude abrir ese archivo", tone: .warn); return }
        let parsed = ReleaseName.parse(url.lastPathComponent)
        let kind = parsed.isSeries ? "series" : "movie"
        let found = ((try? await services.cinemeta.searchAll(parsed.title)) ?? []).filter { $0.kind == kind }
        // Con año, el de ese año; sin año, solo si el nombre es exactamente el mismo («Vacaciones.mov» no es la película «Vacation»).
        func plain(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber } }
        let match = parsed.year != nil
            ? found.first { r in r.year.hasPrefix(String(parsed.year ?? 0)) }
            : found.first { plain($0.title) == plain(parsed.title) }
        var request: PlayRequest
        if let match {
            let video = parsed.isSeries ? "\(match.metaID):\(parsed.season ?? 1):\(parsed.episode ?? 1)" : match.metaID
            request = PlayRequest(kind: kind, metaID: match.metaID, videoID: video, originalTitle: match.title, displayTitle: match.title,
                                  episodeLabel: parsed.isSeries ? Strings.episode(season: parsed.season, episode: parsed.episode ?? 1, language: services.appSettings.uiLanguage) : "",
                                  poster: match.poster, year: match.year, localFile: target)
        } else {
            request = PlayRequest(kind: "movie", metaID: "file:\(target.lastPathComponent)", videoID: "file:\(target.lastPathComponent)",
                                  originalTitle: parsed.title, displayTitle: parsed.title, localFile: target)
        }
        request.fromStart = match == nil
        play(request)
    }

    /// `orbital-ios://play?kind=&id=&video=` abre el reproductor en ese episodio (donde ibas); `orbital-ios://title?kind=&id=` abre la ficha.
    /// Sin episodio conocido, o si la ficha no carga, se cae a la ficha.
    private func open(_ link: WidgetLink) async {
        switch link {
        case .remote:
            ui.openRemote = true
        case .downloads:
            openTab = Self.downloadsTab
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
}

