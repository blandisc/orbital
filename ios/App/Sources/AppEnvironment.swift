import SwiftUI
import UserNotifications
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
    /// Lo popular de Buscar: uno para toda la app, pedido al abrirla (Buscar ya lo encuentra listo, con su color).
    private(set) var catalog: CatalogModel!
    private(set) var inbox: InboxModel!
    private var servicesSubscription: ObservableModel.Subscription?
    let connectivity = Connectivity.shared
    private let liveActivity = DownloadLiveActivityController()

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
            AppDelegate.orientations = newValue == nil ? .portrait : .allButUpsideDown
            ui.playing = newValue
            if newValue == nil, old != nil { watchedSomething += 1 }
        }
    }
    /// Cambia cada vez que termina una reproducción (aquí o en Infuse): Inicio y la ficha se ponen al día.
    @Published private(set) var watchedSomething = 0
    /// Una ficha que pidió abrir un enlace (el widget): `MainTabs` la empuja en Inicio y la vacía.
    var pendingTitle: TitleRoute? { get { ui.pendingTitle } set { ui.pendingTitle = newValue } }
    /// Lo que se abrió en Infuse y está esperando a que vuelva (no se pinta).
    private var external: ExternalSession?
    /// Infuse volvió sin duración y no se sabe si terminaste: se pregunta.
    var askFinished: PlayRequest? { get { ui.askFinished } set { ui.askFinished = newValue } }
    /// Un aviso: lo que pasó («Descargando…») o lo que salió mal.
    var banner: Banner? { get { ui.banner } set { ui.banner = newValue } }
    /// Lo que acabas de pasar a la TV desde el reproductor: el aviso con «Deshacer» (regresa al iPhone en el mismo punto).
    var handoff: TVHandoff? { get { ui.handoff } set { ui.handoff = newValue } }
    struct TVHandoff: Equatable {
        var request: PlayRequest
        var position: Double
        static func == (a: TVHandoff, b: TVHandoff) -> Bool { a.request.id == b.request.id && a.position == b.position }
    }
    struct Banner: Equatable {
        var text: String; var tone: DSNotice.Tone; var action: BannerAction?
        /// Un segundo renglón («1080p · 2.4 GB») y el nombre del botón (por omisión, «Ver»).
        var detail: String? = nil
        var actionTitle: String? = nil
    }
    /// Lo que hace el botón de un aviso: ir a Descargas, o lo que pidió quien avisó (`perform`, con su número).
    enum BannerAction: Equatable { case downloads, perform(Int) }
    /// Lo que corre el botón de un aviso con `.perform` (solo el del aviso a la vista).
    private(set) var bannerPerform: (() -> Void)?
    private var bannerSerial = 0

    /// Un aviso con un botón propio: «Guardada en Mi lista · Cambiar», «Bajando la recomendada · Otra».
    func notify(_ text: String, detail: String? = nil, tone: DSNotice.Tone = .success, actionTitle: String, perform: @escaping () -> Void) {
        let language = services.appSettings.uiLanguage
        bannerSerial += 1
        bannerPerform = perform
        banner = Banner(text: Strings.message(text, language: language), tone: tone, action: .perform(bannerSerial),
                        detail: detail.map { Strings.message($0, language: language) }, actionTitle: Strings.tr(actionTitle, language: language))
    }
    /// Una pestaña que un aviso pide abrir («Ver» en «Descargando…»).
    var openTab: Int? { get { ui.openTab } set { ui.openTab = newValue } }
    static let downloadsTab = 3

    /// Las imágenes de tu Orbital (logos de canales, arte de juegos) se piden con su token.
    private func shareConsoleWithImages() {
        ImagePipeline.shared.setConsole(services.orbital.base, token: services.secrets.get(SecretKey.orbitalToken))
    }

    /// Un aviso: lo que arma la app en español se traduce aquí, una sola vez (el aviso ya se pinta tal cual).
    func notify(_ text: String, tone: DSNotice.Tone = .error, action: BannerAction? = nil) {
        banner = Banner(text: Strings.message(text, language: services.appSettings.uiLanguage), tone: tone, action: action)
    }
    /// Un texto armado en español por un modelo (error o aviso), listo para `Text`/`DSNotice` en el idioma de la app.
    func message(_ text: String) -> String { Strings.message(text, language: services.appSettings.uiLanguage) }
    /// Un aviso con datos: la clave («… %@») se traduce primero y luego se llena (`LocalizedStringKey` no encuentra un texto ya armado).
    func notify(format key: String, _ args: CVarArg..., tone: DSNotice.Tone = .error, action: BannerAction? = nil) {
        banner = Banner(text: String(format: Strings.tr(key, language: services.appSettings.uiLanguage), arguments: args), tone: tone, action: action)
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
        servicesSubscription = services.onChange { [weak self] in self?.objectWillChange.send(); self?.applyAppearance(); self?.shareConsoleWithImages() }
        shareConsoleWithImages()
        session = SessionModel(services)
        inbox = InboxModel(services)
        tvNow = TVNowModel(services)
        tvNow.inbox = inbox
        catalog = CatalogModel(services)
        inbox.onEvent = { [weak self] event in self?.announce(event) }
        Task { await services.downloads.start() }
        DownloadsModel.clearShared()   // los enlaces de «Compartir» de la vez pasada
        Task.detached(priority: .background) { AppEnvironment.pruneImported() }
        let settings = services.settings
        liveActivity.language = { settings.value.uiLanguage }
        Task { await liveActivity.follow(services.downloads) }
    }

    private static func makeServices(_ transport: BackgroundDownloadTransport) -> Services {
        #if DEBUG
        // Modo demostración: nada toca tu Keychain, tus ajustes ni tus descargas.
        if Demo.isOn {
            // `-demo-persist`: lo guardado sobrevive entre aperturas (como en tu iPhone), para medir abrir la app de nuevo.
            let kv: KeyValueStore = Demo.persist ? UserDefaultsKeyValueStore(prefix: "orbital-demo.") : InMemoryKeyValueStore()
            SettingsStore(kv).update {
                if let language = Demo.language { $0.uiLanguage = language }
                if !Demo.noTV { $0.orbitalAddress = "tv.demo.invalid" }
                if Demo.scrobble || Demo.airings || Demo.because { $0.traktClientID = "demo" }
                if let style = Demo.value(after: "-demo-because-style") { $0.becauseStyle = style }
                if let state = Demo.oneDrive, state != "off" { $0.oneDriveClientID = "demo" }
                if Demo.oneDrive == "linked" { $0.oneDriveFolder = "Películas" }
            }
            Demo.prefillScrobble(kv)
            let services = Services(http: DemoHTTPClient(), secrets: Demo.secrets(), kv: kv, pending: InMemoryPendingStore(),
                                    downloadTransport: transport, downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("demo-downloads"),
                                    savedDownloads: Demo.downloads, freeSpace: { DiskSpace.freeBytes() })
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
        case .downloading(let name): notify(format: "Descargando %@ (desde la TV)", name, tone: .success, action: .downloads)
        case .received(let name): notify(format: "Desde la TV: %@", name, tone: .info)
        case .downloadFailed(let name, let reason):
            switch reason {
            case .noSources: notify(format: "No encontré una fuente para descargar %@ (desde la TV)", name)
            case .notEnoughSpace: notify(format: "No hay espacio para descargar %@ (desde la TV)", name)
            case .other: notify(format: "No pude descargar %@ (desde la TV)", name)
            }
        case .played(let item):
            // El resumen de la sesión, en su hoja; un momento después, por si la hoja del juego se está cerrando (dos hojas en
            // el mismo cambio: la segunda no salía).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: DS.Timing.sheetHandoff)
                self.ui.played = item
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
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
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
        // Un video que te pasaron (AirDrop, Archivos, «Abrir con…»).
        if url.isFileURL { return await openFile(url) }
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

    /// Un video de fuera: se copia a la app (los de hace días se borran), se reconoce por el nombre del archivo (Cinemeta: nombre,
    /// año, temporada y episodio) y se reproduce. Reconocido, el reproductor le busca subtítulos en OpenSubtitles con la huella
    /// del archivo (los de esa copia exacta) y guarda tu avance en Stremio; sin reconocer, se ve igual, sin guardar nada.
    private func openFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        Self.pruneImported()
        let folder = Self.importedFolder
        let target = folder.appendingPathComponent(url.lastPathComponent)
        if target.standardizedFileURL != url.standardizedFileURL {
            try? FileManager.default.removeItem(at: target)
            do {
                // Lo que llega por AirDrop o «Abrir con…» queda en Documents/Inbox: se mueve (no se queda una segunda copia de gigas).
                if url.path.contains("/Inbox/") { try FileManager.default.moveItem(at: url, to: target) }
                else { try FileManager.default.copyItem(at: url, to: target) }
            } catch { notify("No pude abrir ese archivo."); return }
        }
        // Fuera del respaldo de iCloud (como las descargas) y con la fecha de hoy (de ella se cuentan los días para borrarlo).
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = target; try? mutable.setResourceValues(values)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
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

    /// Cuántos días se queda un video que te pasaron antes de borrarse solo.
    nonisolated static let importedDays: Double = 3
    nonisolated static var importedFolder: URL {
        let folder = AppFiles.support.appendingPathComponent("Importados", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Borra los videos que te pasaron hace más de `importedDays` (los de Documents/Inbox se mueven al abrirlos: no se quedan).
    nonisolated static func pruneImported() {
        let fm = FileManager.default
        let old = (try? fm.contentsOfDirectory(at: importedFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in old where ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < Date().addingTimeInterval(-importedDays * 86_400) {
            try? fm.removeItem(at: file)
        }
    }

    /// `orbital-ios://play?kind=&id=&video=` abre el reproductor en ese episodio (donde ibas); `orbital-ios://title?kind=&id=` abre la ficha.
    /// Sin episodio conocido, o si la ficha no carga, se cae a la ficha.
    private func open(_ link: WidgetLink) async {
        switch link {
        case .remote:
            ui.openRemote = true
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
    /// Un episodio de Los Simpson al azar, de la temporada 5 a la 15 (las buenas), aquí o en la TV.
    /// Un Simpson al azar (T5–T15): los episodios (para la ruleta) y el elegido. nil si Cinemeta no contesta.
    struct SimpsonsDraw: Equatable {
        var meta: JSON
        var name: String
        var reel: [(season: Int, episode: Episode)]
        var chosen: (season: Int, episode: Episode) { reel[reel.count - 1] }
        static func == (a: SimpsonsDraw, b: SimpsonsDraw) -> Bool { a.reel.map(\.episode.id) == b.reel.map(\.episode.id) }
    }

    /// Elige uno y arma la tira de la ruleta (otros al azar y, al final, el elegido).
    func drawSimpsons(reelLength: Int) async -> SimpsonsDraw? {
        let id = Self.simpsons
        guard let meta = try? await services.cinemeta.meta(kind: "series", id: id) else { notify("No pude traer los episodios de Los Simpson."); return nil }
        let pool = CinemetaParsing.seasons(meta).filter { Self.simpsonsSeasons.contains($0.season) }
            .flatMap { season in season.episodes.map { (season: season.season, episode: $0) } }
        guard pool.count > 1, let chosen = pool.randomElement() else { notify("No pude traer los episodios de Los Simpson."); return nil }
        let others = (0..<max(0, reelLength - 1)).compactMap { _ in pool.randomElement() }
        return SimpsonsDraw(meta: meta, name: meta["name"]?.string ?? "The Simpsons", reel: others + [chosen])
    }

    /// El elegido, en el iPhone y desde el principio.
    func playSimpsons(_ draw: SimpsonsDraw) {
        let (season, episode) = draw.chosen
        let label = Strings.episode(season: season, episode: episode.episode, language: services.appSettings.uiLanguage) + (episode.hasTitle ? " · \(episode.title)" : "")
        play(PlayRequest(kind: "series", metaID: Self.simpsons, videoID: episode.id, originalTitle: draw.name, displayTitle: draw.name, episodeLabel: label,
                         poster: String(format: ForYou.metahubPoster, Self.simpsons), meta: draw.meta, fromStart: true))
    }

    /// La imagen de un episodio (metahub).
    static func simpsonsStill(season: Int, episode: Int) -> String { "https://episodes.metahub.space/\(simpsons)/\(season)/\(episode)/w780.jpg" }

    static let simpsons = "tt0096697"
    static let simpsonsSeasons = 5...15

    func playOnTV(kind: String, metaID: String, videoID: String?, title: String) async {
        do {
            try await services.orbital.play(kind: kind, metaID: metaID, videoID: videoID, title: title)
            notify("Poniéndolo en la TV.", tone: .success)
        } catch { notify((error as? OrbitalRemote.Failure)?.description ?? "\(error)") }
    }

    /// Del reproductor del iPhone a tu Orbital, en el mismo punto: la TV sigue donde ibas y la app enseña el aviso.
    func handOffToTV(_ request: PlayRequest, position: Double) async {
        do {
            try await services.orbital.play(kind: request.kind, metaID: request.metaID, videoID: request.videoID, title: request.displayTitle)
            handoff = TVHandoff(request: request, position: position)
        } catch { notify((error as? OrbitalRemote.Failure)?.description ?? "\(error)") }
    }

    /// «Deshacer»: la TV se detiene y sigues en el iPhone donde ibas (el avance ya se guardó al cerrar).
    func undoHandoff() async {
        guard let h = handoff else { return }
        handoff = nil
        _ = try? await services.orbital.control(action: "stop")
        var request = h.request
        request.fromStart = false
        play(request)
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

    /// «Guardar» desde el menú de un póster: lo mismo que el círculo de la ficha (Mi lista, con un aviso que se deshace).
    func addToLibrary(_ s: Suggestion) async {
        do {
            try await services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: true)
            notify("Guardada en Mi lista", detail: "Stremio", actionTitle: "Deshacer") { [weak self] in
                Task { try? await self?.services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: false) }
            }
        } catch { notify(format: "No pude cambiar tu lista de Stremio: %@", message("\(error)")) }   // la causa, también traducida
    }

    /// «Descargar» desde Para ti (la fuente recomendada).
    func download(_ s: Suggestion) async {
        let outcome = await services.queueDownload(kind: s.kind, metaID: s.imdb, videoID: videoID(for: s), title: s.title, originalTitle: s.title, subtitle: "", poster: s.poster)
        switch outcome {
        case .queued:
            // Como el círculo de la ficha: qué se está bajando (calidad y tamaño) y a la mano, Descargas.
            let item = await services.downloads.item(DownloadItem.makeID(metaID: s.imdb, videoID: videoID(for: s)))
            let size = item?.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let detail = [item?.quality, size].compactMap { $0 }.joined(separator: " · ")
            banner = Banner(text: Strings.message("Bajando la recomendada", language: services.appSettings.uiLanguage), tone: .success, action: .downloads,
                            detail: detail.isEmpty ? nil : detail)
        case .noSources: notify("No hay fuentes de Real-Debrid para descargar.")
        case .notEnoughSpace(let text), .failed(let text): notify(text)
        case .already: notify("Ya está descargado.", tone: .info)
        }
    }

    /// «Ver» en la tarjeta «Desde la TV»: lo mismo, con lo que mandó la consola.
    func play(_ item: OrbitalRemote.InboxItem) async {
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.title,
                   episodeLabel: services.tvEpisodeLabel(item.season, item.episode, item.episodeLabel), poster: item.poster, at: item.position)
    }

    private func play(kind: String, metaID: String, videoID: String?, title: String, originalTitle: String, episodeLabel: String, poster: String?, at position: Double? = nil) async {
        guard let videoID, let meta = try? await services.cinemeta.meta(kind: kind, id: metaID) else { return notify("No pude abrir ese título.") }
        var request = PlayRequest(kind: kind, metaID: metaID, videoID: videoID, originalTitle: originalTitle, displayTitle: title,
                                  episodeLabel: episodeLabel, poster: poster, meta: meta)
        request.startPosition = position   // «Seguir en el iPhone»: el segundo exacto de la TV
        if services.appSettings.preferInfuse { await playExternal(request) } else { play(request) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Se registra antes de que termine de arrancar la app (lo exige iOS).
        ImagePipeline.shared.preconnect()   // lo primero: la conexión con las imágenes, mientras arranca lo demás
        InboxBackgroundTask.register()
        ReleaseNotifier.register()
        ReleaseNotifier.registerCategory(language: AppEnvironment.shared.services.appSettings.uiLanguage)
        // Los avisos de la app (tu tiempo de juego, la batería de la consola) se ven también con la app abierta.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Tocar un aviso o uno de sus botones («Ya está para ver»: Ver, Ver en la TV, Descargar).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            await ReleaseNotifier.handle(response)
            completionHandler()
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientations }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Puede llegar antes de que exista ninguna vista: se arma el entorno (que reconecta la sesión de descargas) y se guarda aquí.
        AppEnvironment.shared.transport.backgroundCompletion = completionHandler
    }
}

/// Lo que solo pinta la raíz de la app: el reproductor a pantalla completa, los avisos y lo que se pide abrir.
@MainActor
final class AppUI: ObservableObject {
    @Published var playing: PlayRequest?
    @Published var pendingTitle: TitleRoute?
    @Published var askFinished: PlayRequest?
    @Published var banner: AppEnvironment.Banner?
    @Published var handoff: AppEnvironment.TVHandoff?
    /// Se cerró un juego en la consola: su resumen (una hoja).
    @Published var played: OrbitalRemote.InboxItem?
    @Published var openTab: Int?
    /// El Centro de control pidió el control de tu Orbital.
    @Published var openRemote = false
}
