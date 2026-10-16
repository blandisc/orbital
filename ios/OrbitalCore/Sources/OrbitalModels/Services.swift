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
    private let flushGate = FlushGate()
    public let stremio: StremioAPI

    public private(set) var registry: AddonRegistry { didSet { changed() } }
    public private(set) var finder: StreamFinder { didSet { changed() } }
    public private(set) var cinemeta: Cinemeta { didSet { changed() } }
    public private(set) var localizer: Localizer { didSet { changed() } }
    public private(set) var trakt: Trakt? { didSet { changed() } }
    public private(set) var forYou: ForYou { didSet { changed() } }
    /// «Para ti» de tu Orbital (la consola), cuando está conectada; `ParaTiModel` decide si la usa.
    public private(set) var forYouRemote: RemoteForYou { didSet { changed() } }
    public private(set) var watch: WatchService { didSet { changed() } }
    public private(set) var downloads: Downloads { didSet { changed() } }
    /// Cómo se escribe «T2 · E5» en el idioma de la app (la interfaz lo cambia; por omisión, en español).
    public var episodeLabel: @Sendable (Int, Int) -> String = { "T\($0) · E\($1)" }
    /// Cambia cuando se reconfiguran claves (para que las pantallas se actualicen).
    public private(set) var generation = 0 { didSet { changed() } }

    private let downloadTransport: DownloadTransport
    private let downloadsRoot: URL
    private let freeSpace: @Sendable () -> Int64
    private let clock: @Sendable () -> Date
    private let onDownloadsChange: @Sendable ([DownloadItem]) -> Void

    public init(http: HTTPClient, secrets: SecretsStore, kv: KeyValueStore, pending: PendingStore, downloadTransport: DownloadTransport,
                downloadsRoot: URL, savedDownloads: [DownloadItem] = [], freeSpace: @escaping @Sendable () -> Int64,
                clock: @escaping @Sendable () -> Date = { Date() }, onDownloadsChange: @escaping @Sendable ([DownloadItem]) -> Void = { _ in }) {
        self.http = http; self.secrets = secrets; self.kv = kv; self.pending = pending; self.downloadTransport = downloadTransport
        self.downloadsRoot = downloadsRoot; self.freeSpace = freeSpace; self.clock = clock; self.onDownloadsChange = onDownloadsChange
        let settings = SettingsStore(kv)
        self.settings = settings
        self.titlePrefs = TitlePreferences(kv)
        let stremio = StremioAPI(http: http)
        self.stremio = stremio
        let registry = AddonRegistry(http: http, account: stremio, auth: { secrets.get(SecretKey.stremioAuth) },
                                     own: { (secrets.get(SecretKey.ownAddons) ?? "").split(separator: "\n").map(String.init) }, clock: clock)
        let finder = StreamFinder(http: http, registry: registry, clock: clock)
        let cinemeta = Cinemeta(http: http, registry: registry, clock: clock)
        let tmdb = Tmdb(http: http, key: secrets.get(SecretKey.tmdbKey) ?? "", language: "es-MX")
        let localizer = Localizer(tmdb: tmdb, language: { settings.value.uiLanguage }, clock: clock)
        let trakt = Services.makeTrakt(http: http, secrets: secrets, settings: settings.value, clock: clock)
        self.registry = registry; self.finder = finder; self.cinemeta = cinemeta; self.localizer = localizer; self.trakt = trakt
        self.forYou = ForYou(trakt: trakt, tmdb: tmdb, region: { settings.value.region }, kv: kv, clock: clock)
        self.forYouRemote = RemoteForYou(remote: { OrbitalRemote(http: http, address: settings.value.orbitalAddress, token: secrets.get(SecretKey.orbitalToken) ?? "") }, clock: clock)
        self.watch = WatchService(stremio: stremio, authKey: { secrets.get(SecretKey.stremioAuth) }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: clock, gate: flushGate)
        self.downloads = Downloads(transport: downloadTransport, secrets: secrets, root: downloadsRoot, saved: savedDownloads, freeSpace: freeSpace,
                                   refresh: Services.refresher(finder: finder, settings: settings, titlePrefs: titlePrefs),
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
    static func refresher(finder: StreamFinder, settings: SettingsStore, titlePrefs: TitlePreferences) -> @Sendable (DownloadItem) async -> URL? {
        { item in
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
        if keys.region.count == 2 { settings.update { $0.region = keys.region } }
        reconfigure()
        // Trakt sin conectar en el iPhone (o con la sesión prestada de antes): la de la consola.
        if let session = keys.traktSession, let trakt, !trakt.linked || trakt.borrowed {
            trakt.adopt(session)
            if !got.contains("Trakt") { got.append("Trakt") }
            reconfigure()
        }
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
        localizer = Localizer(tmdb: tmdb, language: { settings.value.uiLanguage }, clock: clock)
        trakt = Services.makeTrakt(http: http, secrets: secrets, settings: s, clock: clock)
        forYou = ForYou(trakt: trakt, tmdb: tmdb, region: { settings.value.region }, kv: kv, clock: clock)
        watch = WatchService(stremio: stremio, authKey: { secrets.get(SecretKey.stremioAuth) }, cinemeta: cinemeta, trakt: trakt, pending: pending, clock: clock, gate: flushGate)
        generation += 1
    }

    /// Al cerrar sesión: lo pendiente y lo guardado de la cuenta anterior no se sube ni se muestra con la siguiente.
    public func clearAccountData() {
        pending.save(PendingWork())
        kv.set("home-cache", data: nil)
    }

    /// Los complementos o la cuenta cambiaron: se vuelve a preguntar todo.
    public func resetAccountCaches() async {
        await registry.invalidate()
        await forYou.clearCache()
        await forYouRemote.clearCache()
        generation += 1
    }
}
