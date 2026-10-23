#if DEBUG
import Foundation
import SwiftUI
import OrbitalCore
import OrbitalModels

/// Modo demostración (solo en Debug, con el argumento `-demo`): una cuenta de Stremio falsa con biblioteca y un complemento
/// que da videos de prueba públicos. Cinemeta y los pósteres son los de verdad. Nada se guarda en el Keychain ni en disco:
/// sirve para recorrer la app en el simulador sin tu cuenta.
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    /// `-start-tab N` y `-start-mode lists|mosaic`: abren esa pestaña con tus datos de verdad (sin `-demo`), para revisar
    /// un iPhone físico desde la Mac (`devicectl … process launch`) y capturarlo. Solo Debug.
    static var startTab: Int? { value(after: "-start-tab").flatMap(Int.init) }
    static var startMode: String? { value(after: "-start-mode") }
    /// `-demo-no-idle`: el mosaico no se mueve solo (las pruebas de arrastre miden solo lo que hace el dedo).
    /// Lo guardado (Inicio, el mosaico, los colores) sobrevive entre aperturas, como en el iPhone de verdad (para medir).
    static var persist: Bool { ProcessInfo.processInfo.arguments.contains("-demo-persist") }
    static var noIdle: Bool { ProcessInfo.processInfo.arguments.contains("-demo-no-idle") }

    static let addonURL = "https://demo.orbital.invalid/manifest.json"
    /// `-demo-no-tv`: sin Orbital conectada (para probar el QR: `xcrun simctl openurl booted "orbital-ios://pair?u=https%3A%2F%2Ftv.demo.invalid&t=demo"`).
    static var noTV: Bool { ProcessInfo.processInfo.arguments.contains("-demo-no-tv") }
    /// `-demo-tv-now`: la tarjeta «Viendo en la TV» con datos de mentira (para verla en el simulador).
    static var tvNow: Bool { ProcessInfo.processInfo.arguments.contains("-demo-tv-now") || horror }
    /// `-demo-tv-horror`: en la TV suena Insidious (con mapa de sustos de verdad) y la TV está en su reproductor.
    static var horror: Bool { ProcessInfo.processInfo.arguments.contains("-demo-tv-horror") }
    /// `-demo-game`: la consola de mentira tiene un juego abierto (modo acompañante).
    static var game: Bool { ProcessInfo.processInfo.arguments.contains("-demo-game") }

    /// `-demo-inbox download|open`: tu Orbital de mentira dejó algo para el iPhone («Descargar en el iPhone» o «Enviar al iPhone»):
    /// con `download` se ve la descarga de prueba y el aviso; con `open`, la tarjeta «Desde la TV» en Inicio.
    static var inbox: String? { value(after: "-demo-inbox") }

    /// `-demo-handoff <segundos>`: el aviso «Sigue en tu Orbital» al abrir, como si acabaras de pasar algo a la TV en ese punto.
    /// El nombre de la descarga de prueba de `-diag-download`.
    static let diagTitle = "Prueba de descarga"
    static var handoff: Double? { value(after: "-demo-handoff").flatMap(Double.init) }
    /// `-demo-notice ya|bajando|trakt|cola|perdido`: un aviso de ejemplo al abrir (para verlos en el simulador).
    static var notice: String? { value(after: "-demo-notice") }

    @MainActor static func showNotice(_ env: AppEnvironment) {
        switch notice {
        case "ya": env.notify("Ya está descargada", detail: "En el iPhone, para ver sin conexión", tone: .info, actionTitle: "Ver", actionSymbol: "play.fill") {}
        case "bajando": env.notify("Bajando la recomendada", detail: "1080p · 2.4 GB", tone: .success, actionTitle: "Otra") {}
        case "trakt": env.notify("Tu sesión de Trakt se cerró", detail: "Sin ella no llegan tus recomendaciones", tone: .warn, actionTitle: "Conectar") {}
        case "cola":
            env.notify("Quitada de Mi lista", detail: "Oppenheimer", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {}
            env.notify("Real-Debrid aún no lo tiene", detail: "Los estrenos suelen llegar unas horas después")
        case "perdido": env.notify("No cabe en el iPhone", detail: "Hacen falta 2400 MB y hay 1100 MB libres.", tone: .error, action: .downloads, actionTitle: "Descargas")
        case "neutral": env.notify("Real-Debrid aún no lo tiene", detail: "Los estrenos suelen llegar unas horas después")
        default: break
        }
    }

    static let handoffRequest = PlayRequest(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", originalTitle: "The Office",
                                            displayTitle: "La Oficina", episodeLabel: "T2 · E5")

    /// `-demo-scrobble`: Trakt «conectado» con un último scrobble de mentira (para ver la fila de Ajustes › Trakt en el simulador).
    static var scrobble: Bool { ProcessInfo.processInfo.arguments.contains("-demo-scrobble") }
    /// `-demo-because`: Trakt de mentira con historial y relacionados, para ver «Porque viste» en Para ti.
    static var because: Bool { ProcessInfo.processInfo.arguments.contains("-demo-because") }
    /// `-demo-trakt`: Trakt «conectado» con una watchlist y listas propias de mentira (unas recientes, otras viejas) que tardan
    /// ~1,5 s en llegar, como la red de verdad: para ver «Guardar en…» cargando y ya cargada. `-demo-open save` lo prende solo.
    static var trakt: Bool { ProcessInfo.processInfo.arguments.contains("-demo-trakt") || open == "save" }
    /// `-demo-scroll 240`: la ficha abre ya desplazada esos puntos (para capturar el arte a medio recoger).
    static var scroll: Double? { value(after: "-demo-scroll").flatMap(Double.init) }
    /// `-demo-autoscroll`: la ficha baja sola y suave hasta ~600 pt, espera y regresa arriba (para grabar el arte en video).
    static var autoscroll: Bool { ProcessInfo.processInfo.arguments.contains("-demo-autoscroll") }
    /// `-demo-onedrive off|unlinked|linked`: OneDrive de mentira (Microsoft y la carpeta responden aquí; nada sale a tu cuenta).
    /// `linked` ya trae la carpeta «Películas» revisada: Dune Part Two (2024) y Severance T1 sale como fuente.
    static var oneDrive: String? { value(after: "-demo-onedrive") }
    /// `-demo-media`: Descargas abre en Mi media; `-demo-media-title movie:tt…` abre ese título.
    static var media: Bool { ProcessInfo.processInfo.arguments.contains("-demo-media") }
    static var mediaTitle: String? { value(after: "-demo-media-title") }

    /// Lo último que «se le contó a Trakt», para ver la fila de Ajustes sin ver nada antes.
    static func prefillScrobble(_ kv: KeyValueStore) {
        if scrobble { ScrobbleLog(kv: kv).recordSent(title: "The Office T2 · E5", action: .pause, at: Date().addingTimeInterval(-180)) }
    }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-demo-tab 2`: la pestaña con la que arranca (0 Inicio, 1 Para ti, 2 Ver, 3 Descargas).
    static var tab: Int { value(after: "-demo-tab").flatMap(Int.init) ?? 0 }
    /// `-demo-title series:tt0386676`: abre esa ficha en la pestaña de arranque.
    static var title: (kind: String, id: String)? {
        guard let parts = value(after: "-demo-title")?.split(separator: ":"), parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
    /// `-demo-player dock|subtitles|audio|version|close`: ya reproduciendo, abre «Audio y subtítulos» (con Subtítulos o Audio
    /// abierto) o «Versión»; `close` cierra el reproductor.
    static var player: String? { value(after: "-demo-player") }
    /// `-demo-player-state skip-intro|error|upnext|locked`: ya reproduciendo, pone «Saltar intro», el error, la tarjeta de
    /// «Siguiente episodio» o el bloqueo (estados que el simulador no alcanza solo). `-demo-player-portrait`: abre en vertical.
    static var playerState: String? { value(after: "-demo-player-state") }
    static var playerPortrait: Bool { ProcessInfo.processInfo.arguments.contains("-demo-player-portrait") }
    /// `-demo-widget sample|empty|live`: lo que enseña el widget «Lo siguiente para ti» (por omisión un snapshot de ejemplo; `empty`,
    /// sin nada pendiente; `live`, el que arma Inicio con la biblioteca de demostración).
    static var widget: String? { value(after: "-demo-widget") }

    /// El snapshot de ejemplo del widget: una serie a medias, el siguiente episodio de otra y una película.
    static var widgetSnapshot: WidgetSnapshot {
        func poster(_ id: String) -> String { "https://images.metahub.space/poster/medium/\(id)/img" }
        func wide(_ id: String) -> String { "https://images.metahub.space/background/medium/\(id)/img" }
        let english = language == "en"
        return WidgetSnapshot(language: english ? "en" : "es", items: [
            .init(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:6", title: english ? "The Office" : "La Oficina", episodeLabel: english ? "S2 · E6" : "T2 · E6",
                  status: english ? "20 min left" : "quedan 20 min", progress: 0.55, poster: poster("tt0386676"), wide: wide("tt0386676"), logo: Artwork.logoURL(metaID: "tt0386676")),
            .init(kind: "series", metaID: "tt0903747", videoID: "tt0903747:2:1", title: "Breaking Bad", status: english ? "Next up: S2 · E1" : "Sigue: T2 · E1", poster: poster("tt0903747"), wide: wide("tt0903747"), logo: Artwork.logoURL(metaID: "tt0903747")),
            .init(kind: "movie", metaID: "tt0816692", videoID: "tt0816692", title: "Interstellar", status: english ? "1 h 12 min left" : "quedan 1 h 12 min", progress: 0.3, poster: poster("tt0816692"), wide: wide("tt0816692"), logo: Artwork.logoURL(metaID: "tt0816692")),
        ])
    }

    /// `-demo-airings`: Trakt «conectado» con un calendario de mentira (Próximos estrenos) para ver el estante en Listas.
    static var airings: Bool { ProcessInfo.processInfo.arguments.contains("-demo-airings") }
    /// `-demo-shelf trend`: en Para ti › Listas, baja hasta ese estante al abrir (para capturarlo sin tocar la pantalla).
    static var shelf: String? { value(after: "-demo-shelf") }
    /// `-demo-mode lists`: en Para ti, abre en Listas (en vez de Mosaico).
    static var mode: String? { value(after: "-demo-mode") }
    /// `-demo-lang en`: idioma de la app.
    static var language: String? { value(after: "-demo-lang") }
    /// `-demo-downloads`: Descargas con una película, dos episodios y una a medias (para ver y deslizar los renglones).
    static var downloads: [DownloadItem] {
        guard ProcessInfo.processInfo.arguments.contains("-demo-downloads") else { return [] }
        func item(_ kind: String, _ meta: String, _ video: String, _ title: String, _ sub: String, _ state: DownloadState, _ release: String) -> DownloadItem {
            var d = DownloadItem(id: DownloadItem.makeID(metaID: meta, videoID: video), kind: kind, metaID: meta, videoID: video, title: title, originalTitle: title,
                                 subtitle: sub, poster: "https://images.metahub.space/poster/medium/\(meta)/img", addon: "Torrentio", release: release,
                                 sourceIndex: 0, expectedBytes: 2_400_000_000, relativePath: "\(meta)/\(video).mkv", createdAt: 0)
            d.state = state; d.writtenBytes = state == .done ? 2_400_000_000 : 900_000_000
            // Los subtítulos que de verdad estén junto al video (`-demo-play-download`), como los deja una descarga.
            let subs = demoDownloadsRoot.appendingPathComponent(meta).appendingPathComponent("subs")
            d.subtitleFiles = ((try? FileManager.default.contentsOfDirectory(atPath: subs.path)) ?? []).sorted().map { "subs/\($0)" }
            return d
        }
        return [item("movie", "tt1160419", "tt1160419", "Dune", "", .done, "Dune.2021.1080p.WEB-DL"),
                item("movie", "tt15239678", "tt15239678", "Dune: Parte dos", "", .paused, "Dune.Part.Two.2160p.WEB-DL"),
                item("series", "tt0386676", "tt0386676:2:5", "The Office", "T2 · E5", .done, "The.Office.S02E05.720p"),
                item("series", "tt0386676", "tt0386676:2:6", "The Office", "T2 · E6", .done, "The.Office.S02E06.720p")]
    }

    /// La carpeta de descargas del modo demostración.
    static var demoDownloadsRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("demo-downloads") }
    /// `-demo-offline`: como en modo avión: toda petición falla con «sin conexión» (las de mentira también).
    static var offline: Bool { ProcessInfo.processInfo.arguments.contains("-demo-offline") }
    /// `-demo-play-download tt1160419`: al abrir, reproduce esa descarga (con `-demo-downloads`; el video se copia antes a
    /// `tmp/demo-downloads/<metaID>/<videoID>.mkv` del simulador, y sus subtítulos a `subs/` junto a él).
    static var playDownload: String? { value(after: "-demo-play-download") }
    /// `-demo-player-pick es`: ya en el reproductor, elige ese idioma de subtítulos como si lo tocaras.
    static var playerPick: String? { value(after: "-demo-player-pick") }

    /// `-demo-search dune`: escribe eso en Buscar (pestaña Ver).
    static var search: String? { value(after: "-demo-search") }
    /// `-demo-open settings|sources|play`: lo que se abre encima de la ficha o de Inicio.
    static var open: String? { value(after: "-demo-open") }
    /// `-demo-gesture brightness|volume|seek|fastforward`: simula el gesto a medio camino (sin tocar la pantalla),
    /// para capturar su indicador en el simulador.
    static var gesture: String? { value(after: "-demo-gesture") }
    /// `-demo-console`: simula que tu Orbital de mentira sí contesta «Para ti» (con una lista de ejemplo con puesto),
    /// para ver el pie «Para ti de tu Orbital» y el número del Top 10 sin tener una consola real.
    /// `-demo-appearance light|dark`: fuerza el modo claro u oscuro (para las capturas de los dos).
    static var appearance: String? { value(after: "-demo-appearance") }
    static var console: Bool { ProcessInfo.processInfo.arguments.contains("-demo-console") }
    /// `-demo-tmdb`: TMDB de mentira (elenco, saga, tráiler, dónde verlo) para ver la ficha rica sin clave.
    static var tmdb: Bool { ProcessInfo.processInfo.arguments.contains("-demo-tmdb") }
    /// `-demo-mosaic-focus 3`: en «Para ti» › Mosaico, enfoca esa sugerencia (su índice en `model.mosaic`) al abrir.
    static var mosaicFocus: Int? { value(after: "-demo-mosaic-focus").flatMap(Int.init) }

    /// `-demo-mosaic-bench`: el mosaico se desplaza y cambia de foco solo (ver `MosaicBench`) e imprime los fotogramas.
    static var mosaicBench: Bool { ProcessInfo.processInfo.arguments.contains("-demo-mosaic-bench") }

    /// Secretos de arranque: sesión iniciada y el complemento de demostración.
    static func secrets() -> InMemorySecrets {
        let secrets = InMemorySecrets()
        if !ProcessInfo.processInfo.arguments.contains("-demo-signed-out") { secrets.set(SecretKey.stremioAuth, "DEMO") }
        if scrobble || airings || because || trakt { secrets.set(SecretKey.traktTokens, #"{"access_token":"DEMO","expires_at":4102444800}"#) }   // sesión falsa: nada sale a Trakt
        if !noTV { secrets.set(SecretKey.orbitalToken, "demo") }      // una Orbital de mentira ya conectada («Ver en la TV»)
        if tmdb { secrets.set(SecretKey.tmdbKey, "DEMO") }            // TMDB de mentira: la ficha rica sin clave de verdad
        if oneDrive == "linked" { secrets.set(SecretKey.oneDriveTokens, #"{"access_token":"DEMO","refresh_token":"DEMO","expires_at":4102444800}"#) }
        return secrets
    }
}

/// Responde como Stremio y como un complemento; lo demás (Cinemeta, imágenes, TMDB) va a la red de verdad.
final class DemoHTTPClient: HTTPClient, @unchecked Sendable {
    private let real = URLSessionHTTPClient()
    private let lock = NSLock()
    private var library: [String: JSON]

    init() {
        let now = Date().timeIntervalSince1970
        func iso(_ hoursAgo: Double) -> JSON { .string(StremioLibrary.iso(now - hoursAgo * 3600)) }
        func poster(_ id: String) -> JSON { .string("https://images.metahub.space/poster/medium/\(id)/img") }
        let items: [JSON] = [
            ["_id": "tt0386676", "name": "The Office", "type": "series", "poster": poster("tt0386676"), "removed": false, "temp": false,
             "state": ["video_id": "tt0386676:2:5", "timeOffset": 120_000, "duration": 1_320_000, "lastWatched": iso(2)]],
            ["_id": "tt0903747", "name": "Breaking Bad", "type": "series", "poster": poster("tt0903747"), "removed": false, "temp": false,
             "state": ["video_id": "tt0903747:1:3", "timeOffset": 1_200_000, "duration": 2_820_000, "lastWatched": iso(30)]],
            ["_id": "tt0816692", "name": "Interstellar", "type": "movie", "poster": poster("tt0816692"), "removed": true, "temp": true,
             "state": ["video_id": "tt0816692", "timeOffset": 3_000_000, "duration": 10_140_000, "lastWatched": iso(50)]],
            ["_id": "tt1160419", "name": "Dune", "type": "movie", "poster": poster("tt1160419"), "removed": false, "temp": false, "state": [:]],
            ["_id": "tt11280740", "name": "Severance", "type": "series", "poster": poster("tt11280740"), "removed": false, "temp": false, "state": [:]],
            ["_id": "tt15239678", "name": "Dune: Part Two", "type": "movie", "poster": poster("tt15239678"), "removed": false, "temp": false, "state": [:]],
        ]
        library = Dictionary(uniqueKeysWithValues: items.map { ($0["_id"]!.string!, $0) })
    }

    /// Avance de mentira de «Viendo en la TV», que sigue corriendo mientras no esté en pausa (como la consola de verdad).
    private var nowPlayingPosition = 420.0
    private var nowPlayingTicked = Date()
    private var nowPlayingPaused = false
    private var inboxAcked = false
    private var demoVolume = 40, demoMuted = false

    /// `-net-latency`: las respuestas de mentira tardan 80–150 ms, como un servidor de verdad.
    private static let netLatency = ProcessInfo.processInfo.arguments.contains("-net-latency")

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let start = Perf.now()
        if Demo.offline { throw URLError(.notConnectedToInternet) }
        do {
            let response: HTTPResponse
            if let fake = try await fake(request) {
                if Self.netLatency { try? await Task.sleep(for: .milliseconds(Int.random(in: 80...150))) }
                response = fake
            } else {
                response = try await real.send(request)
            }
            Perf.net(kind: "api", url: request.url, method: request.method, start: start, end: Perf.now(), bytes: response.data.count, status: response.status)
            return response
        } catch {
            Perf.net(kind: "api", url: request.url, method: request.method, start: start, end: Perf.now(), bytes: 0, status: -1)
            throw error
        }
    }

    /// La respuesta de mentira, o nada si la petición va a la red de verdad.
    private func fake(_ request: HTTPRequest) async throws -> HTTPResponse? {
        let url = request.url
        if url.host == "api.strem.io" { return try await stremio(url.lastPathComponent, body: request.body.flatMap(JSON.parse)) }
        if url.host == "demo.orbital.invalid" { return addon(url.path) }
        // OpenSubtitles de mentira: varias versiones por idioma (con copia, descargas, y unas SDH/forzadas que se esconden).
        if url.host == "opensubtitles-v3.strem.io" { return HTTPResponse(status: 200, data: Self.subtitlesDemo.serialized()) }
        if url.host == "api.trakt.tv", url.path.hasPrefix("/calendars/my/shows") { return calendarDemo() }
        if url.host == "api.trakt.tv", Demo.because, let found = Self.becauseDemo(url.path) {
            // Los relacionados tardan lo que tarda Trakt de verdad (para medir qué tan fluido se siente cambiar de título).
            if url.path.hasSuffix("/related") { try? await Task.sleep(nanoseconds: 1_200_000_000) }   // ds-exception: demora de red simulada (solo modo demo)
            return HTTPResponse(status: 200, data: found.serialized())
        }
        if url.host == "api.trakt.tv", Demo.trakt, let found = await traktDemo(request) { return found }
        // La calificación de la comunidad de Trakt (la ficha la enseña con su logo junto a IMDb y TMDB).
        if url.host == "api.trakt.tv", url.path.hasSuffix("/ratings") { return HTTPResponse(status: 200, data: JSON.object(["rating": .double(8.4), "votes": 52_310]).serialized()) }
        if url.host == "api.trakt.tv" {   // con `-demo-scrobble` Trakt es de mentira: ni una petición sale a internet
            let user: JSON = url.path == "/users/settings" ? ["user": ["username": "demo"]] : [:]
            return HTTPResponse(status: url.path == "/users/settings" ? 200 : 404, data: user.serialized())
        }
        if url.host == "api.themoviedb.org", Demo.tmdb { return tmdbDemo(url) }
        if Demo.oneDrive != nil, url.host == "login.microsoftonline.com" || url.host == "graph.microsoft.com" { return Self.oneDriveDemo(url) }
        if url.host == "tv.demo.invalid", Demo.tvNow || Demo.inbox != nil || Demo.game, url.path.hasPrefix("/api/companion/") {
            return lock.withLock { nowPlaying(path: url.path, body: request.body.flatMap(JSON.parse)) }
        }
        if url.host == "tv.demo.invalid" {
            // «Para ti» por el puerto público: sin `-demo-console`, tu Orbital de mentira no la contesta (404, como una
            // consola de una versión anterior) y el modelo cae solo a su lógica local — sin aviso, como siempre.
            if url.path.hasPrefix("/api/foryou") { return Demo.console ? foryouDemo(url) : HTTPResponse(status: 404, data: Data()) }
            return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        }
        return nil
    }

    /// `-demo-release-alert`: pide permiso y manda el aviso de ejemplo unos segundos después (para verlo con la app cerrada).
    @MainActor static func postReleaseAlert(language: String) {
        guard Demo.isOn, ProcessInfo.processInfo.arguments.contains("-demo-release-alert") else { return }
        Task {
            guard await ReleaseNotifier.requestPermission() else { return }
            try? await Task.sleep(for: .seconds(4))
            await ReleaseNotifier.post([releaseAlert], language: language)
        }
    }

    /// Un aviso «Ya está para ver» de ejemplo (`-demo-release-alert`).
    static let releaseAlert = ReleaseAlerts.Alert(id: "tt14452776:4:2", metaID: "tt14452776", show: "The Bear", season: 4, episode: 2, episodeTitle: "Bolognese",
                                                  poster: "https://images.metahub.space/poster/medium/tt14452776/img",
                                                  art: "https://images.metahub.space/background/medium/tt14452776/img", quality: "1080p", instant: true, minutes: 34)

    /// «Porque viste» de mentira: lo último que viste (cinco series) y lo que Trakt relaciona con cada una.
    static let becauseShows: [(String, String, [(String, String)])] = [
        ("tt0472954", "It's Always Sunny in Philadelphia", [("tt0367279", "Arrested Development"), ("tt0290988", "Trailer Park Boys"), ("tt1759761", "Veep"), ("tt0387764", "Peep Show")]),
        ("tt0386676", "The Office", [("tt1266020", "Parks and Recreation"), ("tt2467372", "Brooklyn Nine-Nine"), ("tt4477976", "Superstore"), ("tt3526078", "Schitt's Creek")]),
        ("tt14452776", "The Bear", [("tt15677150", "Shrinking"), ("tt11815682", "Hacks"), ("tt14403178", "Beef"), ("tt5687612", "Fleabag")]),
        ("tt11280740", "Severance", [("tt14688458", "Silo"), ("tt2085059", "Black Mirror"), ("tt5753856", "Dark"), ("tt0475784", "Westworld")]),
        ("tt0903747", "Breaking Bad", [("tt3032476", "Better Call Saul"), ("tt5071412", "Ozark"), ("tt2707408", "Narcos"), ("tt0306414", "The Wire")]),
    ]

    static func becauseDemo(_ path: String) -> JSON? {
        func show(_ id: String, _ title: String) -> JSON { ["title": .string(title), "year": 2020, "ids": ["imdb": .string(id), "trakt": 1]] }
        if path == "/sync/history" {
            // Vistas hace 2, 5, 9, 16 y 30 días (para «la viste hace…»).
            let days = [2, 5, 9, 16, 30]
            return .array(becauseShows.enumerated().map { i, s in
                let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(days[i % days.count]) * 86_400))
                return ["type": "episode", "show": show(s.0, s.1), "watched_at": .string(at)]
            })
        }
        if path.hasPrefix("/shows/"), path.hasSuffix("/related"), let found = becauseShows.first(where: { path.contains($0.0) }) {
            return .array(found.2.map { show($0.0, $0.1) })
        }
        return nil
    }

    /// TMDB de mentira (`-demo-tmdb`): cualquier título es el 1; su ficha trae reparto (con caras de metahub), tráiler, saga,
    /// recomendaciones y dónde verlo; una persona trae su biografía y su trabajo.
    private func tmdbDemo(_ url: URL) -> HTTPResponse {
        let path = url.path.replacingOccurrences(of: "/3", with: "")
        let body: JSON
        if path.hasPrefix("/find/") {
            // Los de `demoSpanish` tienen su propio id (300+): su nombre en español, sin sinopsis de México (sale la de España).
            let id = Self.demoSpanish.firstIndex { $0.0 == url.lastPathComponent }.map { 300 + $0 } ?? 1
            body = ["movie_results": [["id": .int(id)]], "tv_results": [["id": .int(id)]]]
        } else if path.hasSuffix("/translations"), let id = Int(url.deletingLastPathComponent().lastPathComponent), id >= 300, Self.demoSpanish.indices.contains(id - 300) {
            body = ["translations": [["iso_639_1": "es", "iso_3166_1": "ES", "data": ["title": .string(Self.demoSpanish[id - 300].1), "name": .string(Self.demoSpanish[id - 300].1),
                                                                                      "overview": "Sinopsis de demostración en español de España."]]]]
        } else if let id = Int(url.lastPathComponent), id >= 300, Self.demoSpanish.indices.contains(id - 300) {
            body = ["id": .int(id), "title": .string(Self.demoSpanish[id - 300].1), "name": .string(Self.demoSpanish[id - 300].1), "overview": ""]
        } else if path.hasPrefix("/person/") {
            body = ["id": 1, "name": "Steve Carell", "birthday": "1962-08-16", "place_of_birth": "Concord, Massachusetts",
                    "biography": "Actor, comediante y productor estadounidense. Conocido por Michael Scott en The Office, y por Foxcatcher, Little Miss Sunshine y The Big Short.",
                    "combined_credits": ["cast": [["id": 2, "media_type": "tv", "name": "The Office", "poster_path": "/o.jpg", "popularity": 90, "character": "Michael Scott"],
                                                  ["id": 3, "media_type": "movie", "title": "Foxcatcher", "poster_path": "/f.jpg", "popularity": 40, "character": "John du Pont"]]]]
        } else if path.hasPrefix("/watch/providers/") {
            body = ["results": [["provider_id": 8, "provider_name": "Netflix"], ["provider_id": 337, "provider_name": "Disney Plus"], ["provider_id": 1899, "provider_name": "HBO Max"]]]
        } else if path.hasPrefix("/discover/") {
            // Colecciones › Estudios y «Nuevo en tus plataformas»: ids 100+ que la ficha de abajo vuelve títulos reales.
            let offset = abs(url.query?.hashValue ?? 0) % Self.demoIMDb.count
            body = ["results": .array((0..<8).map { ["id": .int(100 + (offset + $0) % Self.demoIMDb.count)] })]
        } else if let id = Int(url.lastPathComponent), id >= 100, Self.demoIMDb.indices.contains(id - 100) {
            let pick = Self.demoIMDb[id - 100]
            body = ["id": .int(id), "title": .string(pick.1), "name": .string(pick.1), "imdb_id": .string(pick.0), "release_date": "2024-03-01", "first_air_date": "2024-03-01"]
        } else if path.hasPrefix("/collection/") {
            body = ["name": "Dune: colección", "parts": [["id": 5, "title": "Dune", "release_date": "2021-09-15", "poster_path": "/d1.jpg"],
                                                        ["id": 6, "title": "Dune: Part Two", "release_date": "2024-02-27", "poster_path": "/d2.jpg"]]]
        } else {
            body = ["id": 1, "vote_average": .double(8.6), "vote_count": 4000, "belongs_to_collection": ["id": 9],
                    "networks": [["name": "NBC"]], "created_by": [["id": 7, "name": "Greg Daniels"]],
                    "credits": ["cast": [["id": 1, "name": "Steve Carell", "character": "Michael Scott"], ["id": 2, "name": "Rainn Wilson", "character": "Dwight Schrute"],
                                         ["id": 3, "name": "John Krasinski", "character": "Jim Halpert"], ["id": 4, "name": "Jenna Fischer", "character": "Pam Beesly"]], "crew": []],
                    "content_ratings": ["results": [["iso_3166_1": "MX", "rating": "B"]]],
                    "release_dates": ["results": [["iso_3166_1": "MX", "release_dates": [["certification": "B12"]]]]],
                    "videos": ["results": [["site": "YouTube", "key": "LHOtME2DL4g", "type": "Trailer", "name": "Tráiler"],
                                           ["site": "YouTube", "key": "gO8N3L_aERg", "type": "Featurette", "name": "Así se hizo"]]],
                    "recommendations": ["results": [["id": 8, "name": "Parks and Recreation", "first_air_date": "2009-04-09", "poster_path": "/p.jpg"],
                                                    ["id": 10, "name": "Brooklyn Nine-Nine", "first_air_date": "2013-09-17", "poster_path": "/b.jpg"]]],
                    "watch/providers": ["results": ["MX": ["flatrate": [["provider_name": "Prime Video"], ["provider_name": "Netflix"]]]]]]
        }
        return HTTPResponse(status: 200, data: body.serialized())
    }

    /// Nombres en español para el TMDB de mentira (Mi media y la ficha los enseñan traducidos).
    static let demoSpanish: [(String, String)] = [("tt15239678", "Dune: Parte dos"), ("tt11280740", "Separación")]

    /// Títulos reales para el TMDB de mentira (sus pósters salen de metahub).
    static let demoIMDb: [(String, String)] = [
        ("tt11280740", "Severance"), ("tt15239678", "Dune: Part Two"), ("tt6710474", "Everything Everywhere All at Once"), ("tt14452776", "The Bear"),
        ("tt5788792", "Moonlight"), ("tt13623632", "Alien: Romulus"), ("tt8111088", "The Mandalorian"), ("tt2560140", "Attack on Titan"),
        ("tt0386676", "The Office"), ("tt7660850", "Succession"), ("tt10986410", "Ted Lasso"), ("tt5180504", "The Witcher"),
    ]

    /// Un overview de «Para ti» de mentira con varios estantes (Lo tuyo, Top 10 de Netflix con puesto, una plataforma, tendencias y el
    /// catálogo de un complemento), para ver el feed de Listas completo sin una consola real (`-demo-console`).
    private func foryouDemo(_ url: URL) -> HTTPResponse {
        switch url.path {
        case "/api/foryou":
            func list(_ id: String, _ title: String, _ source: String, _ meta: String, split: Bool, brand: String? = nil, logo: String? = nil) -> JSON {
                var row: [String: JSON] = ["id": .string(id), "title": .string(title), "icon": "list", "source": .string(source), "meta": .string(meta), "split": .bool(split)]
                if let brand { row["brand"] = .string(brand) }
                if let logo { row["logo"] = .string(logo) }
                return .object(row)
            }
            let logo = { (id: String) in "https://images.metahub.space/logo/medium/\(id)/img" }
            let overview: JSON = [
                "lists": [list("watchlist", "Tu watchlist", "Trakt", "Lo que dejaste pendiente", split: false),
                          list("mine", "Tus series", "Trakt", "Las que estás viendo", split: false),
                          list("chart:netflix", "Top 10 en Netflix", "Netflix", "Esta semana en México", split: true, brand: "netflix", logo: logo("tt1160419")),
                          list("jw:disney", "Tendencias en Disney+", "JustWatch", "Tendencia en JustWatch · México", split: true, brand: "disney", logo: logo("tt4154796")),
                          list("trend", "En tendencia", "Trakt", "Lo más visto esta semana", split: true),
                          list("addon:cat", "Clásicos", "Stremio", "De Cinemeta", split: false),
                          list("addon:empty", "Un catálogo vacío", "Stremio", "De nadie", split: false)],
                "mosaic": [Self.demoRow("tt1160419", "Dune", 2021, "movie", rank: 1, why: "En Netflix")],
            ]
            return HTTPResponse(status: 200, data: overview.serialized())
        case "/api/foryou/list":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value ?? ""
            return HTTPResponse(status: 200, data: JSON.object(["items": .array(Self.demoItems(id))]).serialized())
        case "/api/foryou/details": return HTTPResponse(status: 200, data: JSON.object(["overview": "Sinopsis de prueba (modo demostración)."]).serialized())
        case "/api/foryou/dismiss": return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        default: return HTTPResponse(status: 404, data: Data())
        }
    }

    /// El calendario de Trakt de mentira: tres series que salen hoy, mañana y en tres días.
    private func calendarDemo() -> HTTPResponse {
        func row(_ imdb: String, _ title: String, days: Double, hour: Double, season: Int, episode: Int, network: String) -> JSON {
            let when = Calendar.current.startOfDay(for: Date()).addingTimeInterval(days * 86_400 + hour * 3600)
            return ["first_aired": .string(StremioLibrary.iso(when.timeIntervalSince1970)),
                    "episode": ["season": .int(season), "number": .int(episode), "title": "Episodio de prueba"],
                    "show": ["title": .string(title), "year": 2022, "network": .string(network), "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        let rows: JSON = .array([row("tt14452776", "The Bear", days: 0, hour: 20, season: 3, episode: 4, network: "FX"),
                                 row("tt11280740", "Severance", days: 1, hour: 21, season: 2, episode: 7, network: "Apple TV+"),
                                 row("tt0903747", "Breaking Bad", days: 3, hour: 19, season: 1, episode: 4, network: "AMC"),
                                 // Para el calendario del mes: dos el mismo día, tres otro día y unos que ya salieron.
                                 row("tt8649186", "Only Murders in the Building", days: 0, hour: 21, season: 5, episode: 8, network: "Hulu"),
                                 row("tt5753856", "Dark", days: 6, hour: 9, season: 1, episode: 2, network: "Netflix"),
                                 row("tt2085059", "Black Mirror", days: 6, hour: 10, season: 7, episode: 1, network: "Netflix"),
                                 row("tt11280740", "Severance", days: 6, hour: 21, season: 2, episode: 8, network: "Apple TV+"),
                                 row("tt14452776", "The Bear", days: -7, hour: 20, season: 3, episode: 3, network: "FX"),
                                 row("tt11280740", "Severance", days: -6, hour: 21, season: 2, episode: 6, network: "Apple TV+")])
        return HTTPResponse(status: 200, data: rows.serialized())
    }

    /// Tus listas de Trakt de mentira (`-demo-trakt`): nombre, cuándo se crearon y cuándo cambiaron (horas atrás) y qué tienen.
    /// Trakt las manda en el orden en que las acomodaste (aquí, de la más vieja a la más nueva): la app decide cuál va arriba.
    private struct DemoTraktList { var id: Int; var name: String; var created: Double; var updated: Double; var items: Set<String> }
    private var traktLists: [DemoTraktList] = [
        .init(id: 101, name: "Documentales", created: 9000, updated: 8000, items: ["tt7366338"]),
        .init(id: 102, name: "Clásicos pendientes", created: 6000, updated: 4000, items: ["tt0068646", "tt0111161"]),
        .init(id: 103, name: "Para ver con Ana", created: 2000, updated: 900, items: ["tt0386676", "tt0108778"]),
        .init(id: 104, name: "Terror de octubre", created: 400, updated: 30, items: ["tt1591095"]),
        .init(id: 105, name: "Fin de semana", created: 48, updated: 2, items: ["tt15239678"]),
    ]
    private var traktWatchlist: [(imdb: String, title: String, kind: String, hoursAgo: Double)] = [
        ("tt11280740", "Severance", "show", 5), ("tt15239678", "Dune: Part Two", "movie", 30), ("tt0903747", "Breaking Bad", "show", 200),
    ]
    private var nextTraktList = 106

    /// Trakt de mentira para «Guardar en…»: la watchlist, tus listas (tardan ~1,5 s, como la red) y lo que escribes en ellas.
    private func traktDemo(_ request: HTTPRequest) async -> HTTPResponse? {
        let path = request.url.path, post = request.method == "POST"
        let body = request.body.flatMap(JSON.parse)
        func iso(_ hoursAgo: Double) -> JSON { .string(StremioLibrary.iso(Date().timeIntervalSince1970 - hoursAgo * 3600)) }
        func imdbs(_ body: JSON?) -> [String] { ((body?["movies"]?.array ?? []) + (body?["shows"]?.array ?? [])).compactMap { $0["ids"]?["imdb"]?.string } }
        func json(_ value: JSON, status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        if path == "/users/me/lists", !post {
            try? await Task.sleep(for: .milliseconds(1500))   // ds-exception: demora de red simulada (solo modo demo), para ver «Guardar en…» cargando
            return lock.withLock {
                json(.array(traktLists.map { l in
                    ["name": .string(l.name), "ids": ["trakt": .int(l.id), "slug": .string(l.name.lowercased())], "privacy": "private",
                     "item_count": .int(l.items.count), "created_at": iso(l.created), "updated_at": iso(l.updated)]
                }))
            }
        }
        if path == "/users/me/lists", post {
            return lock.withLock {
                let name = body?["name"]?.string ?? "Lista"
                traktLists.append(.init(id: nextTraktList, name: name, created: 0, updated: 0, items: []))
                defer { nextTraktList += 1 }
                return json(["name": .string(name), "ids": ["trakt": .int(nextTraktList)], "created_at": iso(0), "updated_at": iso(0)], status: 201)
            }
        }
        let parts = path.split(separator: "/").map(String.init)   // users · me · lists · {id} · items [· remove]
        if parts.count >= 5, parts[2] == "lists", parts[4] == "items", let id = Int(parts[3]) {
            return lock.withLock {
                guard let i = traktLists.firstIndex(where: { $0.id == id }) else { return json([:], status: 404) }
                if post {
                    let ids = imdbs(body)
                    if parts.count == 6 { traktLists[i].items.subtract(ids) } else { traktLists[i].items.formUnion(ids) }
                    traktLists[i].updated = 0
                    return json(["added": [:]], status: 201)
                }
                return json(.array(traktLists[i].items.sorted().map { ["type": "movie", "movie": ["ids": ["imdb": .string($0)]]] }))
            }
        }
        if path.hasPrefix("/sync/watchlist") {
            return lock.withLock {
                if post {
                    let ids = imdbs(body)
                    if path.hasSuffix("/remove") { traktWatchlist.removeAll { ids.contains($0.imdb) } }
                    else { for id in ids where !traktWatchlist.contains(where: { $0.imdb == id }) { traktWatchlist.insert((id, id, body?["shows"] != nil ? "show" : "movie", 0), at: 0) } }
                    return json(["added": [:]], status: 201)
                }
                return json(.array(traktWatchlist.map { w in
                    ["listed_at": iso(w.hoursAgo), "type": .string(w.kind),
                     w.kind: ["title": .string(w.title), "year": 2022, "ids": ["imdb": .string(w.imdb), "trakt": 1]]]
                }))
            }
        }
        return nil
    }

    /// Lo que manda `orbital/foryou.py` para un `video_item`, con `rank` si es de un chart.
    private static func demoRow(_ imdb: String, _ title: String, _ year: Int, _ kind: String, rank: Int? = nil, why: String) -> JSON {
        var row: [String: JSON] = [
            "key": .string("video:\(imdb)"), "id": .string("cinemeta:\(kind):\(imdb)"), "source": "cinemeta", "kind": .string(kind), "meta_id": .string(imdb),
            "title": .string(title), "year": .int(year), "why": .string(why),
            "image": .string("https://images.metahub.space/poster/medium/\(imdb)/img"), "hero": .string("https://images.metahub.space/background/medium/\(imdb)/img"),
            "logo": .string("https://images.metahub.space/logo/medium/\(imdb)/img"), "overview": "", "video_id": .string(imdb), "action": "Ver",
        ]
        if let rank {
            row["rank"] = .int(rank)
            // El Top 10 real de la TV trae cuánto se movió y si es nuevo: unos suben, otros bajan, uno entra.
            let moves = [2, 0, -1, 3, -2, 0, 1, -3, 0, 4]
            row["movement"] = .int(moves[(rank - 1) % moves.count])
            row["new"] = .bool(rank == 4)
        }
        return .object(row)
    }

    private static func demoItems(_ list: String) -> [JSON] {
        let top: [(String, String, Int, String)] = [("tt1160419", "Dune", 2021, "movie"), ("tt11280740", "Severance", 2022, "series"), ("tt0903747", "Breaking Bad", 2008, "series"),
                                                    ("tt0816692", "Interstellar", 2014, "movie"), ("tt15239678", "Dune: Part Two", 2024, "movie"), ("tt0386676", "The Office", 2005, "series"),
                                                    ("tt0944947", "Game of Thrones", 2011, "series"), ("tt7366338", "Chernobyl", 2019, "series"), ("tt0108778", "Friends", 1994, "series"),
                                                    ("tt1375666", "Inception", 2010, "movie")]
        switch list {
        case "chart:netflix": return top.enumerated().map { demoRow($1.0, $1.1, $1.2, $1.3, rank: $0 + 1, why: "N.º \($0 + 1) en Netflix") }
        case "watchlist", "mine": return [top[1], top[0], top[4], top[2]].map { demoRow($0.0, $0.1, $0.2, $0.3, why: "En tu watchlist") }
        case "jw:disney":
            return [("tt4154796", "Avengers: Endgame", 2019, "movie"), ("tt2250912", "Spider-Man: Homecoming", 2017, "movie"), ("tt3896198", "Guardianes de la Galaxia 2", 2017, "movie"),
                    ("tt2527338", "Star Wars: El ascenso de Skywalker", 2019, "movie"), ("tt0076759", "Star Wars", 1977, "movie"), ("tt1630029", "Avatar: El camino del agua", 2022, "movie")]
                .enumerated().map { demoRow($1.0, $1.1, $1.2, $1.3, rank: $0 + 1, why: "En Disney+") }
        case "trend":
            return [("tt0137523", "El club de la pelea", 1999, "movie"), ("tt0111161", "Cadena perpetua", 1994, "movie"), ("tt0133093", "Matrix", 1999, "movie"),
                    ("tt0110912", "Tiempos violentos", 1994, "movie"), ("tt0068646", "El padrino", 1972, "movie")].map { demoRow($0.0, $0.1, $0.2, $0.3, why: "En tendencia") }
        case "addon:cat":
            return [("tt0099685", "Buenos muchachos", 1990, "movie"), ("tt0114369", "Seven", 1995, "movie"), ("tt0109830", "Forrest Gump", 1994, "movie"),
                    ("tt0120737", "El señor de los anillos", 2001, "movie")].map { demoRow($0.0, $0.1, $0.2, $0.3, why: "Popular") }
        default: return []
        }
    }

    private static let nowPlayingDuration = 1_320.0

    /// `/api/companion/now` y `/api/companion/player`: una serie de mentira, viendo su episodio 5 de la temporada 2.
    private var demoGamePaused = false, demoGameOpen = true, demoPowerMode = "balanced"

    private func nowPlaying(path: String, body: JSON?) -> HTTPResponse {
        let now = Date()
        if !nowPlayingPaused { nowPlayingPosition = min(Self.nowPlayingDuration, nowPlayingPosition + now.timeIntervalSince(nowPlayingTicked)) }
        nowPlayingTicked = now
        if path == "/api/companion/player", let action = body?["action"]?.string {
            switch action {
            case "pause": nowPlayingPaused = true
            case "play": nowPlayingPaused = false
            case "toggle": nowPlayingPaused.toggle()
            case "skip": nowPlayingPosition = min(Self.nowPlayingDuration, max(0, nowPlayingPosition + Double(body?["delta"]?.intValue ?? 0)))
            case "volume": demoVolume = max(0, min(100, demoVolume + Int(body?["delta"]?.doubleValue ?? 0))); demoMuted = false
            case "mute": demoMuted.toggle()
            default: break
            }
        }
        // El control completo: la TV de mentira acepta las teclas y el texto (no hay interfaz que mover).
        if path == "/api/companion/input" || path == "/api/companion/text" {
            return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        }
        if path == "/api/companion/inbox/ack" {
            inboxAcked = true
            return HTTPResponse(status: 200, data: JSON.object(["removed": .int(1)]).serialized())
        }
        // La bandeja de mentira: lo que «dejó» la TV, hasta que la app avisa que ya lo atendió.
        var inbox: [JSON] = []
        if Demo.inbox == "played", !inboxAcked {   // `-demo-inbox played`: se cerró un juego (el resumen de la sesión)
            inbox = [.object(["id": "demo-played", "action": "played", "meta_id": "steam:1245620", "video_id": "1", "title": "Elden Ring",
                              "seconds": .int(4380), "total_seconds": .int(312_000), "crashed": false, "low_memory": true, "captures": .int(3),
                              "at": .double(Date().timeIntervalSince1970)])]
        } else if let action = Demo.inbox, !inboxAcked {
            let open = action == "open"
            inbox = [.object(["id": "demo-inbox", "kind": .string(open ? "movie" : "series"), "meta_id": .string(open ? "tt1160419" : "tt0386676"),
                              "video_id": .string(open ? "tt1160419" : "tt0386676:2:5"), "title": .string(open ? "Dune" : "The Office"),
                              "episode_label": .string(open ? "" : "T2 · E5"),
                              "poster": .string("https://images.metahub.space/poster/medium/\(open ? "tt1160419" : "tt0386676")/img"),
                              "action": .string(open ? "open" : "download"), "at": .double(Date().timeIntervalSince1970)])]
        }
        // El modo acompañante de mentira: Elden Ring abierto, la consola con su batería, controles y memoria.
        if Demo.game {
            if path == "/api/companion/game", let action = body?["action"]?.string {
                switch action { case "home": demoGamePaused = true; case "resume": demoGamePaused = false; case "close": demoGameOpen = false; default: break }
            }
            if path == "/api/companion/console" {
                if let mode = body?["power_mode"]?.string { demoPowerMode = mode }
                let state: JSON = ["battery": ["percent": 58, "plugged": false, "minutes_left": 130], "power_mode": .string(demoPowerMode), "brightness": 70,
                                   "wifi": ["ssid": "Casa 5G", "signal": 82],
                                   "controllers": [["kind": "legion", "battery": "full"], ["kind": "xbox", "battery": "low"]],
                                   "memory": ["free_gb": .double(6.1), "apps": [["name": "Chrome", "gb": .double(2.3), "closable": true], ["name": "Discord", "gb": .double(0.8), "closable": true]]]]
                return HTTPResponse(status: 200, data: state.serialized())
            }
            let game: JSON = demoGameOpen ? .object(["id": "steam:1245620", "title": "Elden Ring", "system": "steam",
                                                     "art": ["cover": "https://cdn.cloudflare.steamstatic.com/steam/apps/1245620/library_600x900.jpg",
                                                             "hero": "https://cdn.cloudflare.steamstatic.com/steam/apps/1245620/library_hero.jpg",
                                                             "logo": "https://cdn.cloudflare.steamstatic.com/steam/apps/1245620/logo.png"],
                                                     "started": .double(Date().timeIntervalSince1970 - 72 * 60), "paused": .bool(demoGamePaused), "closes_at": .null]) : .null
            if path == "/api/companion/game" { return HTTPResponse(status: 200, data: JSON.object(["game": game]).serialized()) }
            return HTTPResponse(status: 200, data: JSON.object(["playing": .null, "inbox": .array(inbox), "game": game]).serialized())
        }
        guard Demo.tvNow else {
            return HTTPResponse(status: 200, data: JSON.object(["playing": .null, "inbox": .array(inbox)]).serialized())
        }
        if Demo.horror {
            let movie: JSON = .object(["kind": .string("movie"), "live": .bool(false), "meta_id": .string("tt1591095"), "video_id": .string("tt1591095"),
                                       "title": .string("Insidious"), "poster": .string("https://images.metahub.space/poster/medium/tt1591095/img"),
                                       "position": .double(1300 + nowPlayingPosition), "duration": .double(6180), "paused": .bool(nowPlayingPaused),
                                       "tracks": ["audio": [["id": "1", "label": "Inglés 5.1", "selected": true], ["id": "2", "label": "Español", "selected": false]],
                                                  "subtitles": [["id": "0", "label": "Sin subtítulos", "selected": false], ["id": "3", "label": "Español", "selected": true]]]])
            let playerUI: JSON = ["screen": "player", "text_field": false, "section": "Películas y series", "legend": ["select": "Pausa", "alt": "Audio y subtítulos", "options": "Versión", "back": "Salir"],
                                  "volume": ["level": .int(demoVolume), "muted": .bool(demoMuted)]]
            return HTTPResponse(status: 200, data: JSON.object(["playing": movie, "inbox": .array(inbox), "ui": playerUI]).serialized())
        }
        let playing: JSON = .object(["kind": .string("series"), "live": .bool(false), "meta_id": .string("tt0386676"),
                                     "video_id": .string("tt0386676:2:5"), "title": .string("The Office"),
                                     "episode_label": .string("T2 · E5"), "poster": .string("https://images.metahub.space/poster/medium/tt0386676/img"),
                                     "position": .double(nowPlayingPosition), "duration": .double(Self.nowPlayingDuration), "paused": .bool(nowPlayingPaused)])
        // La pantalla de la TV de mentira: en su ficha, con la leyenda del pie (como la manda la consola de verdad).
        let ui: JSON = ["screen": "title", "text_field": false, "section": "Películas y series",
                        "legend": ["select": "Reproducir", "back": "Atrás", "alt": "Mi lista", "options": "Más", "menu": "Menú", "search": "Buscar",
                                   "page": "De 5 en 5", "section": "Secciones"],
                        "volume": ["level": .int(demoVolume), "muted": .bool(demoMuted)]]
        return HTTPResponse(status: 200, data: JSON.object(["playing": playing, "inbox": .array(inbox), "ui": ui]).serialized())
    }

    private func ok(_ result: JSON) -> HTTPResponse { HTTPResponse(status: 200, data: JSON.object(["result": result]).serialized()) }

    private func stremio(_ method: String, body: JSON?) async throws -> HTTPResponse {
        try? await Task.sleep(nanoseconds: 300_000_000)     // ds-exception: demora de red simulada (solo modo demo), no es una espera de la interfaz
        switch method {
        case "login":
            if body?["password"]?.string == "error" { return HTTPResponse(status: 200, data: JSON.object(["error": ["message": "Contraseña incorrecta"]]).serialized()) }
            return ok(["authKey": "DEMO", "user": ["email": body?["email"] ?? "demo@orbital"]])
        case "datastoreGet":
            let ids = (body?["ids"]?.array ?? []).compactMap(\.string)
            return ok(.array(lock.withLock { ids.isEmpty ? Array(library.values) : ids.compactMap { library[$0] } }))
        case "datastorePut":
            lock.withLock { for change in body?["changes"]?.array ?? [] { if let id = change["_id"]?.string { library[id] = change } } }
            return ok(["success": true])
        case "addonCollectionGet":
            return ok(["addons": [["transportUrl": .string(Demo.addonURL), "manifest": Self.manifest]]])
        default:
            return ok(.null)
        }
    }

    static var subtitlesDemo: JSON {
        let rows: [(String, String, Int, Bool, Bool)] = [
            ("eng", "Elephants.Dream.1080p.WEB-DL.DDP5.1.H264-NTb", 4210, false, false), ("eng", "Elephants.Dream.720p.BluRay.x264-SPARKS", 18_400, false, false),
            ("eng", "Elephants.Dream.1080p.WEB-DL.H264-NTb.SDH", 3100, true, false), ("eng", "Elephants.Dream.HDTV.x264-LOL", 950, false, false),
            ("spa", "Elephants.Dream.1080p.WEB-DL.H264-NTb", 1290, false, false), ("spa", "Elephants.Dream.DVDRip.XviD-FXG", 3400, false, false),
            ("spa", "Elephants.Dream.Forzados", 220, false, true), ("fre", "Elephants.Dream.1080p.BluRay-AMIABLE", 610, false, false),
            ("ger", "Elephants.Dream.WEBRip-GER", 120, false, false), ("por", "Elephants.Dream.1080p.WEB-DL-NTb", 480, false, false),
        ]
        return ["subtitles": .array(rows.enumerated().map { i, r in
            ["id": .string("\(i)"), "url": .string("https://demo.orbital.invalid/sub/\(i).srt"), "lang": .string(r.0), "release": .string(r.1),
             "downloads": .int(r.2), "hearing_impaired": .bool(r.3), "foreign_parts_only": .bool(r.4)]
        })]
    }

    static let manifest: JSON = ["id": "orbital.demo", "name": "Demo (videos de prueba)", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]

    private func addon(_ path: String) -> HTTPResponse {
        if path.hasSuffix("manifest.json") { return HTTPResponse(status: 200, data: Self.manifest.serialized()) }
        guard path.hasPrefix("/stream/") else { return HTTPResponse(status: 404, data: Data()) }
        // Como Torrentio con Real-Debrid: título con resolución, tamaño e idioma. Videos públicos de prueba.
        // `-demo-slow`: una «película» de 1 GB (un archivo de prueba de velocidad) para ver la descarga y su actividad en vivo.
        if ProcessInfo.processInfo.arguments.contains("-demo-slow") {
            return HTTPResponse(status: 200, data: JSON.object(["streams": [["name": "[RD+] Demo\n1080p", "title": "Archivo.Grande.1080p.WEB-DL.mkv\n💾 125 MB 🇪🇸",
                                                                             "url": "https://proof.ovh.net/files/1Gb.dat"]]]).serialized())
        }
        // `-demo-versions`: las versiones reales de Intensa-Mente 2 (nombres de Torrentio, octubre de 2026), con videos de prueba,
        // para ver «Elegir versión» con latino, castellano, el original y los demás.
        if ProcessInfo.processInfo.arguments.contains("-demo-versions") {
            // Un video largo (el de prueba de Apple): con uno de 10 s el reproductor se cerraba antes de poder verlo.
            // `-demo-video <url>`: otro video (p. ej. un MKV largo servido desde la Mac, para probar la vuelta de segundo plano).
            let video = Demo.value(after: "-demo-video") ?? "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
            let rows: [(String, String, String, String)] = [
                ("[RD+] Torrentio\n4k DV | HDR", "Inside.Out.2.2024.2160p.WEB-DL.DV.HDR10.PLUS.ENG.LATINO.DDP5.1.Atmos.H265-BEN.THE.MEN", "17.72 GB", "TorrentGalaxy\n🇬🇧 🇲🇽"),
                ("[RD+] Torrentio\n1080p", "IntensaMente.2.2024.1080p-Dual-Lat", "2.93 GB", "Cinecalidad\n🇲🇽"),
                ("[RD+] Torrentio\n1080p", "IntensaMente 2 (2024) 1080p WEBDL LAT - ZeiZ", "12.32 GB", "Cinecalidad\n🇲🇽"),
                ("[RD+] Torrentio\n1080p", "Inside.Out.2.2024.1080p.WEB-DL.ENG.LATINO.DDP5.1.Atmos.H264-BEN.THE.MEN", "7.5 GB", "TorrentGalaxy\n🇬🇧 🇪🇸 🇲🇽"),
                ("[RD+] Torrentio\n4k DV | HDR", "Inside.Out.2.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX[TGx]", "16.65 GB", "TorrentGalaxy"),
                ("[RD+] Torrentio\n1080p", "Inside Out 2 2024 1080p BluRay", "1.78 GB", "YTS"),
                ("[RD download] Torrentio\n720p", "Inside Out 2 2024 720p BluRay", "886.99 MB", "YTS"),
                ("[RD+] Torrentio\n1080p", "Del reves 2 (Inside Out 2) (2024) [Bluray 1080p][Esp]", "6.73 GB", "Wolfmax4k\n🇪🇸"),
                ("[RD download] Torrentio\n720p", "Del reves 2 (Inside Out 2) (2024) [Bluray 720p][Esp]", "4.73 GB", "Wolfmax4k\n🇪🇸"),
                ("[RD download] Torrentio\n4k HDR", "Inside Out 2 2024 Bluray 2160p AV1 HDR10 EN/FR/ES OPUS 7.1-UH [UserHEVC]", "6.43 GB", "1337x\n🇬🇧 🇪🇸 🇫🇷"),
                ("[RD+] Torrentio\n1080p", "Izvrnuto.obrnuto.2.(2024).1080p.x265.4Mbps.2CH.224.crtani.film.hrvatski", "3.03 GB", "1337x\n🇭🇷"),
                ("[RD+] Torrentio\nTeleSync", "Inside Out 2 (Intensa-mente 2) (2024) ts-hq lat.mp4", "1.94 GB", "Cinecalidad\n🇲🇽"),
            ]
            let streams = rows.enumerated().map { i, r -> JSON in
                let parts = r.3.components(separatedBy: "\n")
                return ["name": .string(r.0), "title": .string("\(r.1)\n👤 \(40 - i) 💾 \(r.2) ⚙️ \(parts[0])\n\(parts.count > 1 ? parts[1] : "")"), "url": .string(video + "?v=\(i)")]
            }
            return HTTPResponse(status: 200, data: JSON.object(["streams": .array(streams)]).serialized())
        }
        let streams: [JSON] = [
            // MKV con varias pistas de subtítulos SRT (archivo de prueba oficial de Matroska): lo abre AetherEngine por su vía propia.
            ["name": "[RD+] Demo\n1080p", "title": "Elephants.Dream.1080p.WEB-DL.MKV.Multi.Subs\n💾 2.4 GB 🇬🇧 🇪🇸 🇫🇷",
             "url": "https://raw.githubusercontent.com/ietf-wg-cellar/matroska-test-files/master/test_files/test5.mkv"],
            ["name": "[RD+] Demo\n1080p", "title": "Apple.BipBop.HLS.1080p.WEB-DL.Multi\n💾 2.1 GB 🇬🇧 🇪🇸",
             "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
             "behaviorHints": ["bingeGroup": "demo-1080p"]],
            ["name": "[RD+] Demo\n1080p", "title": "Big.Buck.Bunny.1080p.BluRay.x264\n💾 30.7 MB 🇬🇧",
             "url": "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"],
            ["name": "[RD+] Demo\n4K", "title": "Jellyfish.2160p.DV.HDR.WEB-DL.DDP5.1.Atmos\n💾 14.8 GB 🇬🇧",
             "url": "https://test-videos.co.uk/vids/jellyfish/mp4/h264/1080/Jellyfish_1080_10s_20MB.mp4"],
        ]
        return HTTPResponse(status: 200, data: JSON.object(["streams": .array(streams)]).serialized())
    }

    /// «Tu año» con un historial inventado (siempre el mismo): unas noches de serie, unas de película, rachas.
    static var demoYear: YearInReview {
        let cal = Calendar.current, now = Date()
        let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        let days = cal.dateComponents([.day], from: start, to: now).day ?? 0
        let shows = [("tt0903747", "Breaking Bad"), ("tt5180504", "The Witcher"), ("tt11280740", "Severance")]
        let movies = [("tt15239678", "Dune: Part Two", ["science-fiction", "adventure"]), ("tt6710474", "Everything Everywhere All at Once", ["science-fiction", "comedy"]),
                      ("tt1160419", "Dune", ["science-fiction", "drama"])]
        var plays: [TraktPlay] = []
        for d in 0...max(days, 0) {
            let seed = (d * 7919) % 23
            guard let day = cal.date(byAdding: .day, value: d, to: start), seed < 13 else { continue }
            if seed % 3 != 0 {
                let show = shows[(d / 9) % shows.count]
                for e in 0..<(1 + seed % 3) { plays.append(TraktPlay(at: day.addingTimeInterval(Double(e) * 3600), kind: "series", imdb: show.0, title: show.1, minutes: 50, genres: ["drama"],
                                                                         season: 1 + d / 60, episode: 1 + (d + e) % 10, episodeTitle: "Episodio \(1 + (d + e) % 10)")) }
            }
            if seed % 4 == 0 {
                let movie = movies[(d / 5) % movies.count]
                plays.append(TraktPlay(at: day.addingTimeInterval(7200), kind: "movie", imdb: movie.0, title: movie.1, minutes: 140, genres: movie.2))
            }
        }
        return YearInReview.make(plays, year: cal.component(.year, from: now), calendar: cal)
    }
}
extension Demo {
    static var yearInReview: YearInReview { DemoHTTPClient.demoYear }
}

/// `-demo-scroll N`: la pantalla abre ya desplazada N puntos (cuando ya cargó), para capturar a medio camino lo que cambia
/// al desplazar (el arte de la ficha). `-demo-autoscroll`: baja sola y suave hasta ~600 pt (~4 s), espera 1 s y regresa
/// arriba (~3 s), para grabarlo con `xcrun simctl io … recordVideo`. Sin los argumentos no toca el desplazamiento.
struct DemoScroll: ViewModifier {
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        if Demo.autoscroll {
            content.scrollPosition($position).task {
                try? await Task.sleep(for: .seconds(2))   // ds-exception: espera a que la ficha cargue (solo modo demo)
                await glide(from: 0, to: 600, seconds: 4)
                try? await Task.sleep(for: .seconds(1))   // ds-exception: quieta abajo antes de regresar (solo modo demo)
                await glide(from: 600, to: 0, seconds: 3)
            }
        } else if let y = Demo.scroll {
            content.scrollPosition($position).task {
                try? await Task.sleep(for: .seconds(2))   // ds-exception: espera a que la ficha cargue (solo modo demo)
                position.scrollTo(y: y)
            }
        } else {
            content
        }
    }

    /// Un recorrido suave cuadro a cuadro (~60 por segundo, curva smoothstep): `withAnimation` + `scrollTo` no respeta la
    /// duración, y para grabar hace falta que dure lo que dice.
    @MainActor private func glide(from: Double, to: Double, seconds: Double) async {
        let frames = max(1, Int(seconds * 60))
        let start = Date()
        for i in 1...frames {
            let t = HeroCollapse.smoothstep(0, 1, Double(i) / Double(frames))
            position.scrollTo(y: from + (to - from) * t)            // Al ritmo del reloj, no del sueño: si un cuadro se atrasa, el recorrido no se alarga.
            let next = start.addingTimeInterval(seconds * Double(i) / Double(frames))
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
    }
}
#endif

#if DEBUG
extension DemoHTTPClient {
    /// Microsoft y OneDrive de mentira: un código que se acepta al primer intento y una carpeta con dos títulos.
    static func oneDriveDemo(_ url: URL) -> HTTPResponse {
        func ok(_ json: JSON) -> HTTPResponse { HTTPResponse(status: 200, data: json.serialized()) }
        let path = url.path.removingPercentEncoding ?? url.path
        if path.hasSuffix("/devicecode") {
            return ok(["device_code": "demo", "user_code": "ORB-7421", "verification_uri": "https://www.microsoft.com/link", "interval": 2, "expires_in": 900])
        }
        if path.hasSuffix("/token") { return ok(["access_token": "DEMO", "refresh_token": "DEMO", "expires_in": 3600]) }
        if path.hasSuffix("/root/children") {
            return ok(["value": [["id": "f1", "name": "Documentos", "folder": ["childCount": 12]], ["id": "f2", "name": "Fotos", "folder": ["childCount": 840]],
                                 ["id": "f3", "name": "Películas", "folder": ["childCount": 2]]]])
        }
        if path.hasSuffix("Películas:/children") {
            return ok(["value": [["id": "s1", "name": "Severance", "folder": ["childCount": 2]],
                                 ["id": "m1", "name": "Dune Part Two (2024) 2160p HDR Atmos.mkv", "size": 41_200_000_000, "file": [:], "createdDateTime": "2026-10-16T20:00:00Z"],
                                 ["id": "m2", "name": "Dune Part Two (2024) 1080p WEB-DL 5.1.mkv", "size": 8_400_000_000, "file": [:], "createdDateTime": "2026-10-16T20:05:00Z"],
                                 ["id": "m3", "name": "The.Matrix.1999.1080p.BluRay.x264.mkv", "size": 9_800_000_000, "file": [:], "createdDateTime": "2026-08-02T10:00:00Z"],
                                 ["id": "m4", "name": "Vacaciones en la playa 2019.mp4", "size": 1_200_000_000, "file": [:], "createdDateTime": "2026-07-01T10:00:00Z"]]])
        }
        if path.hasSuffix("Películas/Severance:/children") {
            return ok(["value": [["id": "e1", "name": "Severance.S01E01.1080p.WEB-DL.mkv", "size": 2_100_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"],
                                 ["id": "e2", "name": "Severance.S01E02.1080p.WEB-DL.mkv", "size": 2_000_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"],
                                 ["id": "e4", "name": "Severance.S01E04.2160p.mkv", "size": 6_800_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"]]])
        }
        if path.contains(":/children") { return ok(["value": []]) }
        if path.contains("/me/drive/items/") {
            // Un video público de muestra: se reproduce de verdad sin tocar ninguna cuenta.
            return ok(["@microsoft.graph.downloadUrl": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"])
        }
        return HTTPResponse(status: 404, data: Data())
    }
}
#endif
