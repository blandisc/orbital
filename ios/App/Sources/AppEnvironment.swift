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
    /// Lo que se abrió en Infuse y está esperando a que vuelva.
    @Published private var external: ExternalSession?
    /// Infuse volvió sin duración y no se sabe si terminaste: se pregunta.
    @Published var askFinished: PlayRequest?
    /// Un aviso corto abajo: lo que pasó («Descargando…») o lo que salió mal.
    @Published var banner: Banner?
    struct Banner: Equatable { var text: String; var tone: DSNotice.Tone }

    func notify(_ text: String, tone: DSNotice.Tone = .error) { banner = Banner(text: text, tone: tone) }

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
        // Cambiar el idioma (o una clave) vuelve a pintar toda la app.
        servicesSubscription = services.onChange { [weak self] in self?.objectWillChange.send() }
        session = SessionModel(services)
        Task { await services.downloads.start() }
        Task { await liveActivity.follow(services.downloads) }
    }

    private static func makeServices(_ transport: BackgroundDownloadTransport) -> Services {
        #if DEBUG
        // Modo demostración: nada toca tu Keychain, tus ajustes ni tus descargas.
        if Demo.isOn {
            let kv = InMemoryKeyValueStore()
            SettingsStore(kv).update { if let language = Demo.language { $0.uiLanguage = language }; if !Demo.noTV { $0.orbitalAddress = "tv.demo.invalid" } }
            return Services(http: DemoHTTPClient(), secrets: Demo.secrets(), kv: kv, pending: InMemoryPendingStore(),
                            downloadTransport: transport, downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("demo-downloads"),
                            freeSpace: { DiskSpace.freeBytes() })
        }
        #endif
        return Services(
            http: URLSessionHTTPClient(), secrets: KeychainSecrets(service: Bundle.main.bundleIdentifier ?? "com.example.orbital.ios"),
            kv: UserDefaultsKeyValueStore(), pending: FilePendingStore(url: AppFiles.pendingWork), downloadTransport: transport,
            downloadsRoot: AppFiles.downloadsRoot, savedDownloads: DownloadIndex.load(), freeSpace: { DiskSpace.freeBytes() },
            onDownloadsChange: { DownloadIndex.save($0) })
    }

    var uiLocale: Locale { Locale(identifier: services.appSettings.uiLanguage) }

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
        guard let result = Infuse.parseCallback(url) else { return }
        defer { external = nil; watchedSomething += 1 }
        guard let session = external else { return }
        switch result {
        case .failed(_, let message, _):
            notify(message.map { "Infuse no pudo reproducirlo: \(stripURLs($0))" } ?? "Infuse no pudo reproducirlo.")
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
            notify(got.isEmpty ? "Conectado con tu Orbital." : "Conectado con tu Orbital: \(brought) ya están aquí.", tone: .success)
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
        guard let videoID = item.videoID, let meta = try? await services.cinemeta.meta(kind: item.kind, id: item.metaID) else { return notify("No pude abrir ese título.") }
        var label = ""
        if let episode = item.episode { label = Strings.episode(season: item.season, episode: episode, language: services.appSettings.uiLanguage) }
        let request = PlayRequest(kind: item.kind, metaID: item.metaID, videoID: videoID, originalTitle: item.originalTitle, displayTitle: item.title,
                                  episodeLabel: label, poster: item.poster, meta: meta)
        if services.appSettings.preferInfuse { await playExternal(request) } else { play(request) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientations }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Puede llegar antes de que exista ninguna vista: se arma el entorno (que reconecta la sesión de descargas) y se guarda aquí.
        AppEnvironment.shared.transport.backgroundCompletion = completionHandler
    }
}
