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
    /// Lo que guardaste en Trakt y aún no llega (sin conexión, o con tu Orbital apagada): se manda en cuanto se pueda.
    public let traktOutbox: TraktOutbox
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
    public var introDB: IntroDB { IntroDB(http: http, recent: introDBRecent, store: kv) }
    private let introDBRecent = IntroDBRecent()
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
    /// Los títulos que Siri debe reconocer («Oye Siri, pon Los Simpson en Orbital»): cada uno con su nombre original (el que se
    /// le pide a la consola) y, si es otro, su nombre en español. `HomeModel` los pasa al terminar de actualizar Inicio.
    public var onSiriTitles: (@MainActor ([[String]]) -> Void)?
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

    /// Carpeta de lo que se guarda para enseñarlo al instante al abrir (stale-while-revalidate). nil = sin disco (pruebas).
    let cacheRoot: URL?
    /// El Client ID de Trakt incluido en la app (Info.plist › `OrbitalTraktClientID`, del ajuste de compilación
    /// `ORBITAL_TRAKT_CLIENT_ID`): el último recurso, después del de Ajustes y el de tu Orbital. Vacío: solo los otros dos.
    let builtInTraktClientID: String
    public nonisolated static var bundledTraktClientID: String {
        ((Bundle.main.object(forInfoDictionaryKey: "OrbitalTraktClientID") as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private let downloadTransport: DownloadTransport
    private let downloadsRoot: URL
    let freeSpace: @Sendable () -> Int64
    private let clock: @Sendable () -> Date
    /// Qué aparato es (iPhone o iPad): va en cada petición a tu Orbital.
    private let device: OrbitalRemote.Device?
    private let onDownloadsChange: @Sendable ([DownloadItem]) -> Void

    public init(http: HTTPClient, secrets: SecretsStore, kv: KeyValueStore, pending: PendingStore, downloadTransport: DownloadTransport,
                downloadsRoot: URL, savedDownloads: [DownloadItem] = [], freeSpace: @escaping @Sendable () -> Int64, cacheRoot: URL? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }, onDownloadsChange: @escaping @Sendable ([DownloadItem]) -> Void = { _ in },
                builtInTraktClientID: String = Services.bundledTraktClientID, device: OrbitalRemote.Device? = nil,
                allowsOrbital: Bool = true) {
        self.cacheRoot = cacheRoot
        self.allowsOrbital = allowsOrbital
        self.device = device
        self.builtInTraktClientID = builtInTraktClientID
        self.http = http; self.secrets = secrets; self.kv = kv; self.pending = pending; self.downloadTransport = downloadTransport
        self.downloadsRoot = downloadsRoot; self.freeSpace = freeSpace; self.clock = clock; self.onDownloadsChange = onDownloadsChange
        let scrobbleLog = ScrobbleLog(kv: kv)
        self.scrobbleLog = scrobbleLog
        let settings = SettingsStore(kv)
        // Al borrar la app se van los ajustes (UserDefaults) pero el Keychain se queda: la dirección de tu Orbital y la app de
        // Trakt se recuperan de ahí (antes, tras reinstalar, Trakt y «Para ti» no cargaban hasta volver a escanear el QR).
        if settings.value.orbitalAddress.isEmpty, let saved = secrets.get(SecretKey.orbitalAddress), !saved.isEmpty {
            settings.update { $0.orbitalAddress = saved }
        }
        if settings.value.traktClientID.isEmpty, let saved = secrets.get(SecretKey.traktClientID), !saved.isEmpty {
            settings.update { $0.traktClientID = saved }
        }
        self.settings = settings
        self.titlePrefs = TitlePreferences(kv)
        self.traktOutbox = TraktOutbox(kv)
        let stremio = StremioAPI(http: http)
        self.stremio = stremio
        let registry = AddonRegistry(http: http, account: stremio, auth: { secrets.get(SecretKey.stremioAuth) },
                                     own: { (secrets.get(SecretKey.ownAddons) ?? "").split(separator: "\n").map(String.init) },
                                     disk: cacheRoot?.appendingPathComponent("addons"), clock: clock)
        let cinemeta = Cinemeta(http: http, cached: http is URLSessionHTTPClient ? URLSessionHTTPClient.publicCache("cinemeta") : nil,
                                registry: registry,
                                disk: cacheRoot?.appendingPathComponent("cinemeta"),
                                clock: clock)
        let oneDrive = OneDrive(http: http, secrets: secrets, clientID: { settings.value.oneDriveClientID }, clock: clock)
        let oneDriveLibrary = OneDriveLibrary(drive: oneDrive, cinemeta: cinemeta, kv: kv, folder: { settings.value.oneDriveFolder }, clock: clock)
        let finder = StreamFinder(http: http, registry: registry, clock: clock)
        self.oneDrive = oneDrive; self.oneDriveLibrary = oneDriveLibrary
        let tmdb = Tmdb(http: http, key: secrets.get(SecretKey.tmdbKey) ?? "", language: "es-MX")
        let localizer = Localizer(tmdb: tmdb, language: { settings.value.uiLanguage }, clock: clock, store: kv)
        let trakt = Services.makeTrakt(http: http, secrets: secrets, settings: settings.value, builtIn: builtInTraktClientID, clock: clock)
        self.registry = registry; self.finder = finder; self.cinemeta = cinemeta; self.localizer = localizer; self.trakt = trakt; self.tmdb = tmdb
        self.forYou = ForYou(trakt: trakt, tmdb: tmdb, charts: Charts(http: http, tmdb: tmdb, cinemeta: cinemeta, kv: kv, region: { settings.value.region }, clock: clock),
                             addons: registry, http: http, region: { settings.value.region }, kv: kv, clock: clock)
        self.forYouRemote = RemoteForYou(remote: { OrbitalRemote(http: http, address: allowsOrbital ? settings.value.orbitalAddress : "",
                                                                 token: allowsOrbital ? secrets.get(SecretKey.orbitalToken) ?? "" : "", device: device) }, clock: clock)
        self.watch = WatchService(stremio: stremio, authKey: { secrets.get(SecretKey.stremioAuth) }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: clock, gate: flushGate, scrobbleLog: scrobbleLog)
        // El audio de lo que no lo dice: el idioma original (TMDB, si hay clave) y el país (Cinemeta); lo comprobado al verla.
        let origins = OriginBook(tmdb: { Tmdb(http: http, key: secrets.get(SecretKey.tmdbKey) ?? "") }, cinemeta: cinemeta)
        let prefs = titlePrefs
        Task { await finder.configure(origin: { kind, metaID in await origins.origin(kind: kind, metaID: metaID) },
                                      checked: { key in prefs.checkedAudio(key) }) }
        self.downloads = Downloads(transport: downloadTransport, secrets: secrets, root: downloadsRoot, saved: savedDownloads, freeSpace: freeSpace,
                                   refresh: Services.refresher(finder: finder, settings: settings, titlePrefs: titlePrefs, library: oneDriveLibrary),
                                   otherSource: Services.otherSource(finder: finder, settings: settings, titlePrefs: titlePrefs),
                                   subtitles: Services.subtitleFetcher(http: http, finder: finder, settings: settings, titlePrefs: titlePrefs),
                                   clock: clock, onChange: onDownloadsChange)
        super.init()
    }

    /// El Client ID, en orden: el de Ajustes (escrito a mano, o el que trajo tu Orbital si no había uno), el del Keychain
    /// (sobrevive a reinstalar) y, al final, el incluido en la app. Sin ninguno, no hay Trakt.
    static func traktClientID(settings: AppSettings, secrets: SecretsStore, builtIn: String) -> String {
        if !settings.traktClientID.isEmpty { return settings.traktClientID }
        if let saved = secrets.get(SecretKey.traktClientID), !saved.isEmpty { return saved }
        return builtIn
    }

    static func makeTrakt(http: HTTPClient, secrets: SecretsStore, settings: AppSettings, builtIn: String = "",
                          clock: @escaping @Sendable () -> Date) -> Trakt? {
        let id = traktClientID(settings: settings, secrets: secrets, builtIn: builtIn)
        guard !id.isEmpty else { return nil }
        // Las apps nuevas de Trakt (PKCE) no tienen secreto: el código y la renovación van sin él. Una antigua lo guarda en el Keychain.
        let secret = secrets.get(SecretKey.traktClientSecret) ?? ""
        let trakt = Trakt(http: http, secrets: secrets, clientID: id, clientSecret: secret, clock: clock)
        // La sesión que antes prestaba tu Orbital ya no se usa (cada dispositivo con la suya): se olvida aquí sin revocarla, y
        // Ajustes ofrece conectar Trakt en este iPhone.
        trakt.forgetBorrowedSession()
        return trakt
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

    /// La siguiente fuente para guardar (en el orden de siempre) que no sea una de las que ya no dieron el video.
    static func otherSource(finder: StreamFinder, settings: SettingsStore, titlePrefs: TitlePreferences) -> @Sendable (DownloadItem) async -> DownloadSource? {
        { item in
            guard item.addon != OneDriveLibrary.addonName else { return nil }   // tu archivo de OneDrive no tiene otra fuente
            let prefs = titlePrefs.languages(for: item.metaID, settings: settings.value).prefs
            guard let sources = try? await finder.find(kind: item.kind, videoID: item.videoID, prefs: prefs, purpose: .download, fresh: true) else { return nil }
            let skipped = Set(item.skippedReleases)
            guard let next = sources.first(where: { $0.playbackURL != nil && !skipped.contains($0.release.isEmpty ? "#\($0.index)" : $0.release) }),
                  let url = next.playbackURL else { return nil }
            return DownloadSource(url: url, addon: next.addon, release: next.release, sourceIndex: next.index, size: next.size > 0 ? Int64(next.size) : nil)
        }
    }

    /// Los subtítulos que se guardan con una descarga: TODOS los de español e inglés (y tus idiomas), hasta 50 por idioma,
    /// los que aún no tiene (ni por id ni por enlace), de 3 en 3. Para que en el avión haya varios que probar si uno sale
    /// desfasado. nil: sin red (se vuelve a intentar).
    static func subtitleFetcher(http: HTTPClient, finder: StreamFinder, settings: SettingsStore, titlePrefs: TitlePreferences) -> @Sendable (DownloadItem) async -> SubtitleFetch? {
        { item in
            let s = settings.value
            let languages = DownloadSubtitles.languages([titlePrefs.languages(for: item.metaID, settings: s).subtitles, s.subtitles, s.audio, s.uiLanguage])
            guard let found = await finder.subtitleSearch(kind: item.kind, videoID: item.videoID) else { return nil }
            let picks = DownloadSubtitles.pick(found, languages: languages, release: item.release, saved: item.allSavedSubtitles)
            return await DownloadSubtitles.fetchAll(picks) { url in
                guard let response = try? await http.send(HTTPRequest(url: url, timeout: 20)), response.status == 200 else { return nil }
                return response.data
            }
        }
    }

    /// Conecta tu Orbital (el QR de la TV o Ajustes) y trae de ella lo que falte aquí: la clave de TMDB, el Client ID de la
    /// aplicación de Trakt y el país. Es un atajo: sin consola el iPhone usa el Client ID incluido en la app (o el de Ajustes ›
    /// Avanzado). La sesión de Trakt NO se trae: el iPhone conecta la suya con un código. Devuelve qué se trajo («TMDB»,
    /// «Trakt»); lanza si no contesta.
    @discardableResult
    public func connectOrbital(address: String? = nil, token: String? = nil) async throws -> [String] {
        guard allowsOrbital else { return [] }   // la Mac no se empareja con tu Orbital (ni guarda la dirección)
        if let address { settings.update { $0.orbitalAddress = address }; secrets.set(SecretKey.orbitalAddress, address) }
        if let token { secrets.set(SecretKey.orbitalToken, token) }
        // Avisar ya (antes de preguntarle a la consola): el control y el sondeo aparecen aunque no se haya traído nada nuevo.
        // Antes solo se avisaba si cambiaban TMDB, Trakt o el país, y al volver a emparejar seguía «Sin conectar».
        if address != nil || token != nil { changed() }
        let remote = orbital
        try await remote.check()
        let keys = try await remote.keys()
        var got: [String] = []
        if !keys.tmdbKey.isEmpty, (secrets.get(SecretKey.tmdbKey) ?? "").isEmpty { secrets.set(SecretKey.tmdbKey, keys.tmdbKey); got.append("TMDB") }
        if !keys.traktClientID.isEmpty, settings.value.traktClientID.isEmpty { settings.update { $0.traktClientID = keys.traktClientID }; got.append("Trakt") }
        // El Client ID que de verdad se usa, también en el Keychain (sobrevive a reinstalar). Antes se guardaba el de la consola
        // aunque aquí hubieras pegado otro.
        if !settings.value.traktClientID.isEmpty { secrets.set(SecretKey.traktClientID, settings.value.traktClientID) }
        if !settings.value.orbitalAddress.isEmpty { secrets.set(SecretKey.orbitalAddress, settings.value.orbitalAddress) }
        let regionChanged = keys.region.count == 2 && keys.region != settings.value.region
        if regionChanged { settings.update { $0.region = keys.region } }
        // Solo se rearma si algo cambió: rearmar tira las cachés (traducciones, listas) y vuelve a pintar toda la app, y esto
        // corre en cada arranque.
        // La sesión prestada de antes se olvida aquí SIN revocarla (revocarla desconectaría la consola): Ajustes ofrece conectar
        // la tuya.
        let forgotBorrowed = trakt?.forgetBorrowedSession() ?? false
        if !got.isEmpty || regionChanged || forgotBorrowed { reconfigure() }
        return got
    }

    /// Tu Orbital de la TV («Ver en la TV»), con la dirección y el token de Ajustes. Sin `allowsOrbital` (la Mac) nunca queda
    /// configurado: ni control, ni «En la TV», ni lo que manda la TV, aunque el llavero traiga una dirección y un token.
    public var orbital: OrbitalRemote {
        guard allowsOrbital else { return OrbitalRemote(http: http, address: "", token: "", device: device) }
        return OrbitalRemote(http: http, address: settings.value.orbitalAddress, token: secrets.get(SecretKey.orbitalToken) ?? "", device: device)
    }

    /// ¿Este aparato habla con tu Orbital? No en la Mac (decisión de Fernando, 29 oct 2026): ahí la app es solo para ver.
    public let allowsOrbital: Bool

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
        trakt = Services.makeTrakt(http: http, secrets: secrets, settings: s, builtIn: builtInTraktClientID, clock: clock)
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

/// De dónde es cada título (idioma original y país), una vez por título: el audio de las versiones que no lo dicen.
actor OriginBook {
    private let tmdb: @Sendable () -> Tmdb
    private let cinemeta: Cinemeta
    private var known: [String: TitleOrigin] = [:]
    init(tmdb: @escaping @Sendable () -> Tmdb, cinemeta: Cinemeta) { self.tmdb = tmdb; self.cinemeta = cinemeta }

    func origin(kind: String, metaID: String) async -> TitleOrigin? {
        if let hit = known[metaID] { return hit }
        guard metaID.hasPrefix("tt") else { return nil }
        let client = tmdb()
        async let facts = client.configured ? (try? await client.original(imdb: metaID, kind: kind)) : nil
        async let meta = try? await cinemeta.meta(kind: kind, id: metaID)
        let info = await meta
        // El año solo en películas (una serie dura años: sus episodios no dicen el del estreno).
        let year = kind == "movie" ? (info?["year"]?.string ?? info?["releaseInfo"]?.string).flatMap { Int($0.prefix(4)) } : nil
        // Los nombres de TMDB y el de Cinemeta: una versión que no dice ninguno puede ser otro título (como la TV).
        let tmdb = await facts
        var titles = tmdb?.titles ?? []
        if let name = info?["name"]?.nonEmptyString, !titles.contains(name) { titles.append(name) }
        let found = TitleOrigin(language: tmdb?.language, country: info?["country"]?.nonEmptyString, year: year, titles: titles)
        if found.language != nil || found.country != nil { known[metaID] = found }
        return found
    }
}
