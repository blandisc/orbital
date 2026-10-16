#if DEBUG
import Foundation
import OrbitalCore

/// Modo demostración (solo en Debug, con el argumento `-demo`): una cuenta de Stremio falsa con biblioteca y un complemento
/// que da videos de prueba públicos. Cinemeta y los pósteres son los de verdad. Nada se guarda en el Keychain ni en disco:
/// sirve para recorrer la app en el simulador sin tu cuenta.
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static let addonURL = "https://demo.orbital.invalid/manifest.json"
    /// `-demo-no-tv`: sin Orbital conectada (para probar el QR: `xcrun simctl openurl booted "orbital-ios://pair?u=https%3A%2F%2Ftv.demo.invalid&t=demo"`).
    static var noTV: Bool { ProcessInfo.processInfo.arguments.contains("-demo-no-tv") }
    /// `-demo-tv-now`: la tarjeta «Viendo en la TV» con datos de mentira (para verla en el simulador).
    static var tvNow: Bool { ProcessInfo.processInfo.arguments.contains("-demo-tv-now") }

    /// `-demo-scrobble`: Trakt «conectado» con un último scrobble de mentira (para ver la fila de Ajustes › Trakt en el simulador).
    static var scrobble: Bool { ProcessInfo.processInfo.arguments.contains("-demo-scrobble") }

    /// Lo último que «se le contó a Trakt», para ver la fila de Ajustes sin ver nada antes.
    static func prefillScrobble(_ kv: KeyValueStore) {
        if scrobble { ScrobbleLog(kv: kv).recordSent(title: "The Office T2 · E5", action: .pause, at: Date().addingTimeInterval(-180)) }
    }

    private static func value(after flag: String) -> String? {
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
    /// `-demo-player panel|sources`: ya reproduciendo, abre el panel de audio y subtítulos o el de otra fuente.
    static var player: String? { value(after: "-demo-player") }
    /// `-demo-lang en`: idioma de la app.
    static var language: String? { value(after: "-demo-lang") }
    /// `-demo-search dune`: escribe eso en Buscar (pestaña Ver).
    static var search: String? { value(after: "-demo-search") }
    /// `-demo-open settings|sources|play`: lo que se abre encima de la ficha o de Inicio.
    static var open: String? { value(after: "-demo-open") }
    /// `-demo-gesture brightness|volume|seek|fastforward`: simula el gesto a medio camino (sin tocar la pantalla),
    /// para capturar su indicador en el simulador.
    static var gesture: String? { value(after: "-demo-gesture") }
    /// `-demo-console`: simula que tu Orbital de mentira sí contesta «Para ti» (con una lista de ejemplo con puesto),
    /// para ver el pie «Para ti de tu Orbital» y el número del Top 10 sin tener una consola real.
    static var console: Bool { ProcessInfo.processInfo.arguments.contains("-demo-console") }

    /// Secretos de arranque: sesión iniciada y el complemento de demostración.
    static func secrets() -> InMemorySecrets {
        let secrets = InMemorySecrets()
        if !ProcessInfo.processInfo.arguments.contains("-demo-signed-out") { secrets.set(SecretKey.stremioAuth, "DEMO") }
        if scrobble { secrets.set(SecretKey.traktTokens, #"{"access_token":"DEMO","expires_at":4102444800}"#) }   // sesión falsa: nada sale a Trakt
        if !noTV { secrets.set(SecretKey.orbitalToken, "demo") }      // una Orbital de mentira ya conectada («Ver en la TV»)
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

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let url = request.url
        if url.host == "api.strem.io" { return try await stremio(url.lastPathComponent, body: request.body.flatMap(JSON.parse)) }
        if url.host == "demo.orbital.invalid" { return addon(url.path) }
        if url.host == "api.trakt.tv" {   // con `-demo-scrobble` Trakt es de mentira: ni una petición sale a internet
            let user: JSON = url.path == "/users/settings" ? ["user": ["username": "demo"]] : [:]
            return HTTPResponse(status: url.path == "/users/settings" ? 200 : 404, data: user.serialized())
        }
        if url.host == "tv.demo.invalid", Demo.tvNow, url.path.hasPrefix("/api/companion/") {
            return lock.withLock { nowPlaying(path: url.path, body: request.body.flatMap(JSON.parse)) }
        }
        if url.host == "tv.demo.invalid" {
            // «Para ti» por el puerto público: sin `-demo-console`, tu Orbital de mentira no la contesta (404, como una
            // consola de una versión anterior) y el modelo cae solo a su lógica local — sin aviso, como siempre.
            if url.path.hasPrefix("/api/foryou") { return Demo.console ? foryouDemo(url) : HTTPResponse(status: 404, data: Data()) }
            return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        }
        return try await real.send(request)
    }

    /// Un overview de «Para ti» de mentira, con una lista de un chart (puesto incluido), para ver el pie «Para ti de tu
    /// Orbital» y el número del Top 10 sin tener una consola real (`-demo-console`).
    private func foryouDemo(_ url: URL) -> HTTPResponse {
        switch url.path {
        case "/api/foryou":
            let overview: JSON = [
                "lists": [["id": "chart:netflix", "title": "Top 10 Netflix", "icon": "trailer", "source": "TMDB",
                           "meta": "Lo más visto", "split": false, "brand": "netflix",
                           "logo": "https://images.metahub.space/logo/medium/tt1160419/img"]],
                "mosaic": [Self.chartItem],
            ]
            return HTTPResponse(status: 200, data: overview.serialized())
        case "/api/foryou/list": return HTTPResponse(status: 200, data: JSON.object(["items": [Self.chartItem]]).serialized())
        case "/api/foryou/details": return HTTPResponse(status: 200, data: JSON.object(["overview": "Sinopsis de prueba (modo demostración)."]).serialized())
        case "/api/foryou/dismiss": return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        default: return HTTPResponse(status: 404, data: Data())
        }
    }

    /// «Dune», puesto 1 de un chart de mentira: lo que manda `orbital/foryou.py` para un `video_item`, con `rank`.
    private static let chartItem: JSON = [
        "key": "video:tt1160419", "id": "cinemeta:movie:tt1160419", "source": "cinemeta", "kind": "movie", "meta_id": "tt1160419",
        "title": "Dune", "year": 2021, "why": "En Netflix", "detail": "N.º 1 esta semana", "rank": 1,
        "image": "https://images.metahub.space/poster/medium/tt1160419/img", "hero": "https://images.metahub.space/background/medium/tt1160419/img",
        "logo": "https://images.metahub.space/logo/medium/tt1160419/img", "overview": "", "video_id": "tt1160419", "action": "Ver",
    ]


    private static let nowPlayingDuration = 1_320.0

    /// `/api/companion/now` y `/api/companion/player`: una serie de mentira, viendo su episodio 5 de la temporada 2.
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
            default: break
            }
        }
        let playing: JSON = .object(["kind": .string("series"), "live": .bool(false), "meta_id": .string("tt0386676"),
                                     "video_id": .string("tt0386676:2:5"), "title": .string("The Office"),
                                     "episode_label": .string("T2 · E5"), "poster": .string("https://images.metahub.space/poster/medium/tt0386676/img"),
                                     "position": .double(nowPlayingPosition), "duration": .double(Self.nowPlayingDuration), "paused": .bool(nowPlayingPaused)])
        return HTTPResponse(status: 200, data: JSON.object(["playing": playing]).serialized())
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
        let streams: [JSON] = [
            // MKV con varias pistas de subtítulos SRT (archivo de prueba oficial de Matroska): lo abre AetherEngine por su vía propia.
            ["name": "[RD+] Demo\n1080p", "title": "Elephants.Dream.1080p.WEB-DL.MKV.Multi.Subs\n💾 2.4 GB 🇬🇧 🇪🇸 🇫🇷",
             "url": "https://raw.githubusercontent.com/ietf-wg-cellar/matroska-test-files/master/test_files/test5.mkv"],
            ["name": "[RD+] Demo\n1080p", "title": "Apple.BipBop.HLS.1080p.WEB-DL.Multi\n💾 2.1 GB 🇬🇧 🇪🇸",
             "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
             "behaviorHints": ["bingeGroup": "demo-1080p"]],
            ["name": "[RD+] Demo\n1080p", "title": "Big.Buck.Bunny.1080p.BluRay.x264\n💾 30.7 MB 🇬🇧",
             "url": "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"],
            ["name": "[RD+] Demo\n4K", "title": "Jellyfish.2160p.HDR.WEB-DL\n💾 14.8 GB 🇬🇧",
             "url": "https://test-videos.co.uk/vids/jellyfish/mp4/h264/1080/Jellyfish_1080_10s_20MB.mp4"],
        ]
        return HTTPResponse(status: 200, data: JSON.object(["streams": .array(streams)]).serialized())
    }
}
#endif
