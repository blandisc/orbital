import Foundation
import OrbitalCore

/// Todo lo que la app necesita, armado en un solo lugar (la «raíz de composición»). Los modelos de vista
/// reciben esto y no saben de dónde salen la red, el Keychain ni las descargas.
@MainActor
public final class Services: ObservableModel {
    public let http: HTTPClient
    public let secrets: SecretsStore
    public let kv: KeyValueStore
    public let settings: SettingsStore
    public let titlePrefs: TitlePreferences
    public let pending: PendingStore
    /// Lo último que se le contó a Trakt (o el problema): vive aquí, no en `WatchService`, porque `reconfigure()` lo rearma.
    public let scrobbleLog: ScrobbleLog
    private let flushGate = FlushGate()
    public let stremio: StremioAPI

    public private(set) var registry: AddonRegistry { didSet { changed() } }
    public private(set) var finder: StreamFinder { didSet { changed() } }
    /// Tu OneDrive (la cuenta) y tu carpeta ya reconocida: sus videos salen como fuentes.
    public let oneDrive: OneDrive
    public let oneDriveLibrary: OneDriveLibrary
    public private(set) var cinemeta: Cinemeta { didSet { changed() } }
    public private(set) var localizer: Localizer { didSet { changed() } }
    /// IntroDB: dónde saltar la intro y el resumen (y cuándo empiezan los créditos).
    public var introDB: IntroDB { IntroDB(http: http) }
    public var jumpScares: JumpScares { JumpScares(http: http) }

    /// Los sustos de una película (id de IMDb), guardados la primera vez; nil si no hay mapa. El nombre en inglés y el año
    /// salen de Cinemeta (como los escribe el sitio); si no contesta, el que se da.
    public func scares(imdb: String, fallbackTitle: String) async -> [JumpScare]? {
        let key = "jumpscares.\(imdb)"
        if let data = kv.data(key), let saved = try? JSONDecoder().decode([JumpScare].self, from: data) { return saved.isEmpty ? nil : saved }
        let meta = try? await cinemeta.meta(kind: "movie", id: imdb)
        let title = meta?["name"]?.string ?? fallbackTitle
        let year = (meta?["year"]?.string ?? meta?["releaseInfo"]?.string).flatMap { Int($0.prefix(4)) }
        let found = await jumpScares.scares(title: title, year: year, imdb: imdb)
        if let found { kv.set(key, data: try? JSONEncoder().encode(found)) }
        return (found?.isEmpty ?? true) ? nil : found
    }
    /// TMDB directo (la ficha rica: elenco, saga, «Más como esto»…); sin clave, `configured` es false.
    public private(set) var tmdb: Tmdb { didSet { changed() } }
    public private(set) var trakt: Trakt? { didSet { changed() } }
    public private(set) var forYou: ForYou { didSet { changed() } }
    /// «Para ti» de tu Orbital (la consola), cuando está conectada; `ParaTiModel` decide si la usa.
    public private(set) var forYouRemote: RemoteForYou { didSet { changed() } }
    public private(set) var watch: WatchService { didSet { changed() } }
    public private(set) var downloads: Downloads { didSet { changed() } }
    /// «Para ti» de tu Orbital en vez de calcularlo en el iPhone. Apagado: el iPhone lo calcula él mismo (Trakt, el Top 10 de
    /// Netflix, las tendencias de JustWatch, TMDB) y no depende de que la consola conteste; la consola solo se entera de lo
    /// que marcas «No me interesa». Encendido solo en la demostración (`-demo-console`) y en las pruebas de esa ruta.
    public var forYouFromConsole = false
    /// Cómo se escribe «T2 · E5» en el idioma de la app (la interfaz lo cambia; por omisión, en español).
    public var episodeLabel: @Sendable (Int, Int) -> String = { "T\($0) · E\($1)" }
    /// El episodio de lo que manda la TV en el idioma de la app: con los números (temporada, episodio; 0 = especiales) si la
    /// consola los manda; si no (versión anterior), a partir de su etiqueta en español («T2 · E5»).
    public var tvEpisodeLabel: @Sendable (_ season: Int?, _ episode: Int?, _ label: String) -> String = { _, _, label in label }
    /// Los textos del widget «Lo siguiente para ti» en el idioma de la app (la interfaz los cambia; por omisión, español).
    public var widgetLabels: WidgetLabels = .spanish
    /// Quién publica el snapshot del widget (la app: baja y reduce las imágenes, lo escribe en el App Group y recarga el widget).
    /// `HomeModel` lo llama al terminar de actualizar Inicio.
    public var onWidgetSnapshot: (@MainActor (WidgetSnapshot) -> Void)?
    private var widgetContinue: [HomeItem] = []
    private var widgetAirings: [Airing] = []
    /// Arma y publica el snapshot del widget con lo último que se sabe de «Seguir viendo» (Inicio) y de «Próximos estrenos»
    /// (Inicio o Para ti): cada quien pasa solo lo suyo y se conserva lo otro.
    public func publishWidget(continueWatching: [HomeItem]? = nil, airings: [Airing]? = nil) {
        if let continueWatching { widgetContinue = continueWatching }
        if let airings { widgetAirings = airings }
        guard let publish = onWidgetSnapshot else { return }
        let upcoming = WidgetSnapshot.upcoming(from: widgetAirings, episode: episodeLabel)
        publish(WidgetSnapshot.make(continueWatching: widgetContinue, labels: widgetLabels, language: appSettings.uiLanguage,
                                    upcoming: upcoming.isEmpty ? nil : upcoming))
    }
    /// Cambia cuando se reconfiguran claves (para que las pantallas se actualicen).
    public private(set) var generation = 0 { didSet { changed() } }

    /// Un ajuste cambió (apariencia, idioma, cómo se ve Inicio…): quien escucha a los servicios (la app entera) se vuelve a
    /// pintar. Antes nadie se enteraba y el modo oscuro o el carrusel no cambiaban hasta reabrir la app.
    public func settingsDidChange() { changed() }

    private let downloadTransport: DownloadTransport
    private let downloadsRoot: URL
    let freeSpace: @Sendable () -> Int64
    private let clock: @Sendable () -> Date
    private let onDownloadsChange: @Sendable ([DownloadItem]) -> Void

    public init(http: HTTPClient, secrets: SecretsStore, kv: KeyValueStore, pending: PendingStore, downloadTransport: DownloadTransport,
                downloadsRoot: URL, savedDownloads: [DownloadItem] = [], freeSpace: @escaping @Sendable () -> Int64,
                clock: @escaping @Sendable () -> Date = { Date() }, onDownloadsChange: @escaping @Sendable ([DownloadItem]) -> Void = { _ in }) {
        self.http = http; self.secrets = secrets; self.kv = kv; self.pending = pending; self.downloadTransport = downloadTransport
        self.downloadsRoot = downloadsRoot; self.freeSpace = freeSpace; self.clock = clock; self.onDownloadsChange = onDownloadsChange
        let scrobbleLog = ScrobbleLog(kv: kv)
        self.scrobbleLog = scrobbleLog
        let settings = SettingsStore(kv)
        self.settings = settings
        self.titlePrefs = TitlePreferences(kv)
        let stremio = StremioAPI(http: http)
        self.stremio = stremio
        let registry = AddonRegistry(http: http, account: stremio, auth: { secrets.get(SecretKey.stremioAuth) },
                                     own: { (secrets.get(SecretKey.ownAddons) ?? "").split(separator: "\n").map(String.init) }, clock: clock)
        let cinemeta = Cinemeta(http: http, registry: registry, clock: clock)
        let oneDrive = OneDrive(http: http, secrets: secrets, clientID: { settings.value.oneDriveClientID }, clock: clock)
        let oneDriveLibrary = OneDriveLibrary(drive: oneDrive, cinemeta: cinemeta, kv: kv, folder: { settings.value.oneDriveFolder }, clock: clock)
        let finder = StreamFinder(http: http, registry: registry, clock: clock)
        self.oneDrive = oneDrive; self.oneDriveLibrary = oneDriveLibrary
        let tmdb = Tmdb(http: http, key: secrets.get(SecretKey.tmdbKey) ?? "", language: "es-MX")
        let localizer = Localizer(tmdb: tmdb, language: { settings.value.uiLanguage }, clock: clock, store: kv)
        let trakt = Services.makeTrakt(http: http, secrets: secrets, settings: settings.value, clock: clock)
        self.registry = registry; self.finder = finder; self.cinemeta = cinemeta; self.localizer = localizer; self.trakt = trakt; self.tmdb = tmdb
        self.forYou = ForYou(trakt: trakt, tmdb: tmdb, charts: Charts(http: http, tmdb: tmdb, cinemeta: cinemeta, kv: kv, region: { settings.value.region }, clock: clock),
                             addons: registry, http: http, region: { settings.value.region }, kv: kv, clock: clock)
        self.forYouRemote = RemoteForYou(remote: { OrbitalRemote(http: http, address: settings.value.orbitalAddress, token: secrets.get(SecretKey.orbitalToken) ?? "") }, clock: clock)
        self.watch = WatchService(stremio: stremio, authKey: { secrets.get(SecretKey.stremioAuth) }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: clock, gate: flushGate, scrobbleLog: scrobbleLog)
        self.downloads = Downloads(transport: downloadTransport, secrets: secrets, root: downloadsRoot, saved: savedDownloads, freeSpace: freeSpace,
                                   refresh: Services.refresher(finder: finder, settings: settings, titlePrefs: titlePrefs, library: oneDriveLibrary),
                                   subtitles: Services.subtitleFetcher(http: http, finder: finder, settings: settings, titlePrefs: titlePrefs),
                                   clock: clock, onChange: onDownloadsChange)
        super.init()
    }

    static func makeTrakt(http: HTTPClient, secrets: SecretsStore, settings: AppSettings, clock: @escaping @Sendable () -> Date) -> Trakt? {
        let id = settings.traktClientID.isEmpty ? (secrets.get(SecretKey.traktClientID) ?? "") : settings.traktClientID
        guard !id.isEmpty else { return nil }
        let secret = secrets.get(SecretKey.traktClientSecret) ?? ""     // el secreto nunca va en los ajustes normales
        // Si la sesión es la de tu Orbital, al caducar se le pide otra a la consola.
        let borrow: @Sendable () async -> BorrowedSession? = {
            let remote = OrbitalRemote(http: http, address: settings.orbitalAddress, token: secrets.get(SecretKey.orbitalToken) ?? "")
            return try? await remote.keys().traktSession
        }
        return Trakt(http: http, secrets: secrets, clientID: id, clientSecret: secret, clock: clock, borrow: borrow)
    }

    /// Un enlace nuevo de Real-Debrid para una descarga cuyo enlace caducó: el mismo complemento y la misma fuente.
    static func refresher(finder: StreamFinder, settings: SettingsStore, titlePrefs: TitlePreferences, library: OneDriveLibrary? = nil) -> @Sendable (DownloadItem) async -> URL? {
        { item in
            // De Mi media: un enlace nuevo del mismo archivo de tu OneDrive.
            if item.addon == OneDriveLibrary.addonName { return await library?.refreshURL(release: item.release) }
            let prefs = titlePrefs.languages(for: item.metaID, settings: settings.value).prefs
            guard let sources = try? await finder.find(kind: item.kind, videoID: item.videoID, prefs: prefs, purpose: .download, fresh: true) else { return nil }
            // El número de fuente sale del enlace: si el enlace cambió, el número también. Se busca la misma fuente por su nombre de
            // archivo y tamaño (y del mismo complemento); si no está, la mejor disponible.
            let same = sources.first { $0.index == item.sourceIndex }
                ?? sources.first { !item.release.isEmpty && $0.release == item.release && (item.expectedBytes == nil || Int64($0.size) == item.expectedBytes) && ($0.addon == item.addon || item.addon.isEmpty) }
                ?? sources.first { !item.release.isEmpty && $0.release == item.release }
            return (same ?? sources.first)?.playbackURL
        }
    }

    static func subtitleFetcher(http: HTTPClient, finder: StreamFinder, settings: SettingsStore, titlePrefs: TitlePreferences) -> @Sendable (DownloadItem) async -> [(name: String, data: Data)] {
        { item in
            let langs = titlePrefs.languages(for: item.metaID, settings: settings.value)
            var languages = [settings.value.audio]
            if !langs.subtitles.isEmpty { languages.append(langs.subtitles) }
            var out: [(name: String, data: Data)] = []
            for language in Set(languages) {
                for (i, url) in (await finder.subtitles(kind: item.kind, videoID: item.videoID, language: language)).prefix(1).enumerated() {
                    guard let response = try? await http.send(HTTPRequest(url: url, timeout: 20)), response.status == 200, !response.data.isEmpty else { continue }
                    out.append((name: "\(language)\(i == 0 ? "" : "-\(i)").srt", data: response.data))
                }
            }
            return out
        }
    }

    /// Conecta tu Orbital (el QR de la TV o Ajustes) y trae de ella lo que falte aquí: la clave de TMDB, la aplicación
    /// de Trakt, el país y la sesión de Trakt. Devuelve qué se trajo («TMDB», «Trakt»); lanza si no contesta.
    @discardableResult
    public func connectOrbital(address: String? = nil, token: String? = nil) async throws -> [String] {
        if let address { settings.update { $0.orbitalAddress = address } }
        if let token { secrets.set(SecretKey.orbitalToken, token) }
        let remote = orbital
        try await remote.check()
        let keys = try await remote.keys()
        var got: [String] = []
        if !keys.tmdbKey.isEmpty, (secrets.get(SecretKey.tmdbKey) ?? "").isEmpty { secrets.set(SecretKey.tmdbKey, keys.tmdbKey); got.append("TMDB") }
        if !keys.traktClientID.isEmpty, settings.value.traktClientID.isEmpty { settings.update { $0.traktClientID = keys.traktClientID }; got.append("Trakt") }
        let regionChanged = keys.region.count == 2 && keys.region != settings.value.region
        if regionChanged { settings.update { $0.region = keys.region } }
        // Solo se rearma si algo cambió: rearmar tira las cachés (traducciones, listas) y vuelve a pintar toda la app, y esto
        // corre en cada arranque.
        var needsReconfigure = !got.isEmpty || regionChanged
        if needsReconfigure { reconfigure(); needsReconfigure = false }
        // Trakt sin conectar en el iPhone (o con la sesión prestada de antes): la de la consola, si es otra.
        if let session = keys.traktSession, let trakt, !trakt.linked || (trakt.borrowed && trakt.accessToken != session.accessToken) {
            trakt.adopt(session)
            if !got.contains("Trakt") { got.append("Trakt") }
            needsReconfigure = true
        }
        if needsReconfigure { reconfigure() }
        return got
    }

    /// Tu Orbital de la TV («Ver en la TV»), con la dirección y el token de Ajustes.
    public var orbital: OrbitalRemote {
        OrbitalRemote(http: http, address: settings.value.orbitalAddress, token: secrets.get(SecretKey.orbitalToken) ?? "")
    }

    public func now() -> Date { clock() }
    public var authKey: String? { secrets.get(SecretKey.stremioAuth) }
    public var isSignedIn: Bool { authKey != nil }
    public var appSettings: AppSettings { settings.value }

    /// Tras cambiar una clave (TMDB, Trakt): se rearman las piezas que dependen de ellas.
    public func reconfigure() {
        let s = settings.value
        let tmdb = Tmdb(http: http, key: secrets.get(SecretKey.tmdbKey) ?? "", language: "es-MX")
        let settings = settings, secrets = secrets
        localizer = Localizer(tmdb: tmdb, language: { settings.value.uiLanguage }, clock: clock, store: kv)
        self.tmdb = tmdb
        trakt = Services.makeTrakt(http: http, secrets: secrets, settings: s, clock: clock)
        let charts = Charts(http: http, tmdb: tmdb, cinemeta: cinemeta, kv: kv, region: { settings.value.region }, clock: clock)
        forYou = ForYou(trakt: trakt, tmdb: tmdb, charts: charts, addons: registry, http: http, region: { settings.value.region }, kv: kv, clock: clock)
        watch = WatchService(stremio: stremio, authKey: { secrets.get(SecretKey.stremioAuth) }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: clock, gate: flushGate, scrobbleLog: scrobbleLog)
        generation += 1
    }

    /// Al cerrar sesión: lo pendiente y lo guardado de la cuenta anterior no se sube ni se muestra con la siguiente.
    public func clearAccountData() {
        pending.save(PendingWork())
        scrobbleLog.clear()
        kv.set("home-cache", data: nil)
        kv.set("recent-searches", data: nil)   // lo que buscaste no pasa a la siguiente cuenta
    }

    /// Los complementos o la cuenta cambiaron: se vuelve a preguntar todo.
    public func resetAccountCaches() async {
        await registry.invalidate()
        await forYou.clearCache()
        await forYouRemote.clearCache()
        generation += 1
    }
}
