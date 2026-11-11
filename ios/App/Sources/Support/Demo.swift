import Foundation
import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

#if DEBUG

/// Modo demostración (solo en Debug, con el argumento `-demo`): una cuenta de Stremio falsa con biblioteca y un complemento
/// que da videos de prueba públicos. Cinemeta y los pósteres son los de verdad. Nada se guarda en el Keychain ni en disco:
/// sirve para recorrer la app en el simulador sin tu cuenta.
enum Demo {
    /// Los argumentos de arranque, leídos una sola vez (F10): las pantallas preguntan aquí (`has`, `value(after:)`), nunca a
    /// `ProcessInfo`. Solo existe en Debug; en Release la app no lee argumentos.
    static let arguments = ProcessInfo.processInfo.arguments
    static func has(_ flag: String) -> Bool { arguments.contains(flag) }

    static var isOn: Bool { has("-demo") }
    /// `-start-tab N` y `-start-mode lists|mosaic`: abren esa pestaña con tus datos de verdad (sin `-demo`), para revisar
    /// un iPhone físico desde la Mac (`devicectl … process launch`) y capturarlo. Solo Debug.
    static var startTab: Int? { value(after: "-start-tab").flatMap(Int.init) }
    static var startMode: String? { value(after: "-start-mode") }
    /// `-demo-no-idle`: el mosaico no se mueve solo (las pruebas de arrastre miden solo lo que hace el dedo).
    /// Lo guardado (Inicio, el mosaico, los colores) sobrevive entre aperturas, como en el iPhone de verdad (para medir).
    static var persist: Bool { has("-demo-persist") }
    static var noIdle: Bool { has("-demo-no-idle") }
    /// `-demo-free-tabs`: en demo se puede cambiar de pestaña (sin esto, la de `-demo-tab` vuelve siempre).
    static var freeTabs: Bool { has("-demo-free-tabs") }

    static let addonURL = "https://demo.orbital.invalid/manifest.json"
    /// `-demo-no-tv`: sin Orbital conectada (para probar el QR: `xcrun simctl openurl booted "orbital-ios://pair?u=https%3A%2F%2Ftv.demo.invalid&t=demo"`).
    /// `-demo-first-run`: la guía de la primera vez (sin Real-Debrid ni Trakt conectados).
    static var firstRun: Bool { has("-demo-first-run") }
    /// `-demo-coach`: como si ya hubieras hecho la guía, para que salgan los avisos sobre la pantalla (F3).
    static var coach: Bool { has("-demo-coach") }
    static var noTV: Bool { has("-demo-no-tv") }
    /// `-demo-tv-now`: la tarjeta «Viendo en la TV» con datos de mentira (para verla en el simulador).
    static var tvNow: Bool { has("-demo-tv-now") || horror }
    /// `-demo-tv-horror`: en la TV suena Insidious (con mapa de sustos de verdad) y la TV está en su reproductor.
    static var horror: Bool { has("-demo-tv-horror") }
    /// `-demo-volume-extra 150`: con el reproductor de la TV (`-demo-tv-horror`), el Extra en ese nivel (V4-A).
    static var volumeExtra: Int? { value(after: "-demo-volume-extra").flatMap(Int.init) }
    /// `-demo-game`: la consola de mentira tiene un juego abierto (modo acompañante).
    static var game: Bool { has("-demo-game") }

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
        case "bajando": env.notify("Bajando la recomendada", detail: "1080p · 2,4 GB", tone: .success, actionTitle: "Otra") {}
        case "trakt": env.notify("Tu sesión de Trakt se cerró", detail: "Sin ella no llegan tus recomendaciones", tone: .warn, actionTitle: "Conectar") {}
        case "cola":
            env.notify("Quitada de Mi lista", detail: "Oppenheimer", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {}
            env.notify("Todavía no está en la nube", detail: "Los estrenos suelen llegar unas horas después")
        case "perdido": env.notify("No cabe en el iPhone", detail: "Hacen falta 2400 MB y hay 1100 MB libres.", tone: .error, action: .downloads, actionTitle: "Descargas")
        case "neutral": env.notify("Todavía no está en la nube", detail: "Los estrenos suelen llegar unas horas después")
        // El aviso al tocar «Ver» con tu Real-Debrid vencido (`TitleView+Acciones`), sin buscar fuentes de verdad.
        case "rd-vencido":
            let cause = UnavailableCause.debridExpired
            env.notify(cause.title(), tone: .warn, actionTitle: UnavailableCause.label(.renew)) {}
        default: break
        }
    }

    static let handoffRequest = PlayRequest(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", originalTitle: "The Office",
                                            displayTitle: "La Oficina", episodeLabel: "T2 · E5")

    /// `-demo-scrobble`: Trakt «conectado» con un último scrobble de mentira (para ver la fila de Ajustes › Trakt en el simulador).
    static var searchSlow: Bool { has("-demo-search-slow") }
    static let slowLanes = ["torrentio", "comet", "mediafusion"]
    static var scrobble: Bool { has("-demo-scrobble") }
    /// `-demo-because`: Trakt de mentira con historial y relacionados, para ver «Porque viste» en Para ti.
    static var because: Bool { has("-demo-because") }
    /// `-demo-rate`: lo que terminaste hace poco y aún no calificas (Moonlight, Parásitos y una serie): la pastilla de calificar.
    static var rate: Bool { has("-demo-rate") }
    /// `-demo-trakt`: Trakt «conectado» con una watchlist y listas propias de mentira (unas recientes, otras viejas) que tardan
    /// ~1,5 s en llegar, como la red de verdad: para ver «Guardar en…» cargando y ya cargada. `-demo-open save` lo prende solo.
    static var trakt: Bool { has("-demo-trakt") || open == "save" }
    /// `-demo-vip`: tu Trakt de mentira es VIP (tu nota se guarda en Trakt; sin esto, en el iPhone). O3-B, G6.
    static var vip: Bool { has("-demo-vip") }
    /// `-demo-scroll 240`: la ficha abre ya desplazada esos puntos (para capturar el arte a medio recoger).
    static var scroll: Double? { value(after: "-demo-scroll").flatMap(Double.init) }
    /// `-demo-autoscroll`: la ficha baja sola y suave hasta ~600 pt, espera y regresa arriba (para grabar el arte en video).
    static var autoscroll: Bool { has("-demo-autoscroll") }
    /// `-demo-onedrive off|unlinked|linked`: OneDrive de mentira (Microsoft y la carpeta responden aquí; nada sale a tu cuenta).
    /// `linked` ya trae la carpeta «Películas» revisada: Dune Part Two (2024) y Severance T1 sale como fuente.
    static var oneDrive: String? { value(after: "-demo-onedrive") }
    /// `-demo-media`: Descargas abre en Mi media; `-demo-media-title movie:tt…` abre ese título.
    static var media: Bool { has("-demo-media") }
    /// `-demo-library downloads|media|saved`: la parte de Biblioteca con la que abre (sin esto, Guardado; con `-demo-media`,
    /// Mi media; con `-demo-downloads`, Descargas).
    static var libraryPart: String? { value(after: "-demo-library") }
    /// `-demo-saved-empty`: Mi lista de Trakt vacía (el vacío de Guardado, con «Explorar»).
    static var savedEmpty: Bool { has("-demo-saved-empty") }
    static var mediaTitle: String? { value(after: "-demo-media-title") }

    /// Lo último que «se le contó a Trakt», para ver la fila de Ajustes sin ver nada antes.
    static func prefillScrobble(_ kv: KeyValueStore) {
        if scrobble { ScrobbleLog(kv: kv).recordSent(title: "The Office T2 · E5", action: .pause, at: Date().addingTimeInterval(-180)) }
    }

    static func value(after flag: String) -> String? {
        let args = arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-demo-tab 2`: la pestaña con la que arranca (0 Inicio, 1 Explorar, 2 Buscar, 3 Biblioteca).
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
    static var playerPortrait: Bool { has("-demo-player-portrait") }
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
        ], upcoming: demoReleases(english: english))
    }

    /// «Lo nuevo de lo tuyo» de ejemplo, alrededor de hoy: ayer, hoy en la madrugada (ya salió), hoy a las 21:00, mañana y el viernes.
    private static func demoReleases(english: Bool) -> [WidgetSnapshot.UpcomingEpisode] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date())
        func at(_ days: Int, _ hour: Int) -> Date { today.addingTimeInterval(Double(days) * 86_400 + Double(hour) * 3_600) }
        func episode(_ id: String, _ title: String, _ season: Int, _ number: Int, _ days: Int, _ hour: Int) -> WidgetSnapshot.UpcomingEpisode {
            let aired = at(days, hour)
            return .init(title: title, episodeLabel: english ? "S\(season) E\(number)" : "T\(season) E\(number)", date: calendar.startOfDay(for: aired), metaID: id,
                         poster: "https://images.metahub.space/poster/medium/\(id)/img", aired: aired, atDawn: hour < 6)
        }
        return [episode("tt5875444", "Slow Horses", 5, 2, -1, 20), episode("tt9253284", "Andor", 2, 7, 0, 2), episode("tt14452776", "The Bear", 4, 3, 0, 21),
                episode("tt11280740", "Severance", 3, 1, 1, 20), episode("tt2788316", "Shōgun", 2, 4, 4, 21)]
    }

    /// `-demo-airings`: Trakt «conectado» con un calendario de mentira (Próximos estrenos) para ver el estante en Listas.
    static var airings: Bool { has("-demo-airings") }
    /// `-demo-shelf trend`: en Para ti › Listas, baja hasta ese estante al abrir (para capturarlo sin tocar la pantalla).
    static var shelf: String? { value(after: "-demo-shelf") }
    /// `-demo-mode lists`: en Para ti, abre en Listas (en vez de Mosaico).
    static var mode: String? { value(after: "-demo-mode") }
    /// `-demo-section seasons`: en Para ti › Listas, baja hasta ese grupo de colecciones (el nombre del caso de `CollectionSection`).
    static var section: String? { value(after: "-demo-section") }
    /// `-demo-zoom year|day`: el mapa de «Día por día» abre en el año o en un día (capturas).
    static var zoom: String? { value(after: "-demo-zoom") }
    /// `-demo-collection genre:accion` o `season:halloween`: en Para ti › Listas, abre esa lista (con `-demo-tmdb`).
    static var collection: String? { value(after: "-demo-collection") }
    /// `-demo-lang en`: idioma de la app.
    static var language: String? { value(after: "-demo-lang") }
    /// `-demo-downloads`: Descargas con una película, dos episodios y una a medias (para ver y deslizar los renglones).
    static var downloads: [DownloadItem] {
        guard has("-demo-downloads") else { return [] }
        func item(_ kind: String, _ meta: String, _ video: String, _ title: String, _ sub: String, _ state: DownloadState, _ release: String) -> DownloadItem {
            var d = DownloadItem(id: DownloadItem.makeID(metaID: meta, videoID: video), kind: kind, metaID: meta, videoID: video, title: title, originalTitle: title,
                                 subtitle: sub, poster: "https://images.metahub.space/poster/medium/\(meta)/img", addon: "Torrentio", release: release,
                                 sourceIndex: 0, expectedBytes: 2_400_000_000, relativePath: "\(meta)/\(video).mkv", createdAt: 0)
            d.state = state; d.writtenBytes = state == .done ? 2_400_000_000 : 900_000_000
            // Los subtítulos que de verdad estén junto al video (`-demo-play-download`), como los deja una descarga.
            let subs = demoDownloadsRoot.appendingPathComponent(meta).appendingPathComponent("subs")
            d.subtitleFiles = ((try? FileManager.default.contentsOfDirectory(atPath: subs.path)) ?? []).filter { $0.hasSuffix(".srt") }.sorted().map { "subs/\($0)" }
            // Y su índice (`subs/index.json`, como el que guarda una descarga de verdad en el índice de descargas).
            if let data = try? Data(contentsOf: subs.appendingPathComponent("index.json")),
               let saved = try? JSONDecoder().decode([SavedSubtitle].self, from: data) { d.savedSubtitles = saved }
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
    static var offline: Bool { has("-demo-offline") }
    /// `-demo-down trakt,addons,rd,tmdb,cinemeta,orbital`: con internet, pero esos servicios contestan 503 (caídos). Para probar
    /// el modo degradado (`docs/producto/modo-degradado.md`): cada pantalla debe decir quién falló, no «revisa tu conexión».
    static var down: Set<String> { Set((value(after: "-demo-down") ?? "").split(separator: ",").map(String.init)) }
    /// `-demo-play-download tt1160419`: al abrir, reproduce esa descarga (con `-demo-downloads`; el video se copia antes a
    /// `tmp/demo-downloads/<metaID>/<videoID>.mkv` del simulador, y sus subtítulos a `subs/` junto a él).
    static var playDownload: String? { value(after: "-demo-play-download") }
    /// `-demo-player-pick es`: ya en el reproductor, elige ese idioma de subtítulos como si lo tocaras.
    static var playerPick: String? { value(after: "-demo-player-pick") }

    /// `-demo-voice "pon dune"`: esa frase como pista del renglón de la voz; al tocarla se manda como si la hubieras dicho
    /// (para ver la respuesta, las varias o la guía en las pruebas de interfaz). Con `-demo-voice-fail tunnel|orbital|token|offline`, la orden no llega y
    /// el diagnóstico dice ese tramo; con `hang`, tu Orbital no contesta y la orden se queda esperando (para cancelarla).
    static var voice: String? { value(after: "-demo-voice") }
    static var voiceFail: String? { value(after: "-demo-voice-fail") }

    /// `-demo-search dune`: escribe eso en Buscar (pestaña Ver).
    static var search: String? { value(after: "-demo-search") }
    /// `-demo-open settings|sources|play`: lo que se abre encima de la ficha o de Inicio.
    static var open: String? { value(after: "-demo-open") }
    /// `-demo-repisa oscar`: abre Colecciones en esa colección (oscar, palm, criterion, top250…).
    static var repisa: String? { value(after: "-demo-repisa") }
    /// `-demo-gesture brightness|volume|seek|fastforward|fastforward-locked`: simula el gesto a medio camino
    /// (sin tocar la pantalla), para capturar su indicador en el simulador. `fastforward-locked` deja el ×2 fijo.
    static var gesture: String? { value(after: "-demo-gesture") }
    /// `-demo-console`: simula que tu Orbital de mentira sí contesta «Para ti» (con una lista de ejemplo con puesto),
    /// para ver el pie «Para ti de tu Orbital» y el número del Top 10 sin tener una consola real.
    /// `-demo-appearance light|dark`: fuerza el modo claro u oscuro (para las capturas de los dos).
    static var appearance: String? { value(after: "-demo-appearance") }
    static var console: Bool { has("-demo-console") }
    /// `-demo-tmdb`: TMDB de mentira (elenco, saga, tráiler, dónde verlo) para ver la ficha rica sin clave.
    static var tmdb: Bool { has("-demo-tmdb") }
    /// `-demo-mosaic-focus 3`: en «Para ti» › Mosaico, enfoca esa sugerencia (su índice en `model.mosaic`) al abrir.
    static var mosaicFocus: Int? { value(after: "-demo-mosaic-focus").flatMap(Int.init) }

    /// `-demo-mosaic-bench`: el mosaico se desplaza y cambia de foco solo (ver `MosaicBench`) e imprime los fotogramas.
    static var mosaicBench: Bool { has("-demo-mosaic-bench") }
    /// `-demo-trakt-builtin`: Trakt conectado con el Client ID incluido en la app (Ajustes sin Client ID).
    static var traktBuiltIn: Bool { has("-demo-trakt-builtin") }

    /// `-demo-rd-request queued|downloading|stalled|nopeers|blocked|toomany|ready|all`: tus pedidos a Real-Debrid de
    /// mentira (la libreta ya llena: The Office T1 E2 en ese estado; `all`, uno de cada uno) para ver la ficha, «Seguir
    /// viendo» y Ajustes › Tus pedidos en el simulador. Con `-demo-rd premium`. Nada sale a Real-Debrid.
    static var rdRequest: String? { value(after: "-demo-rd-request") }

    @MainActor static func seedRequests(_ services: Services) {
        // `offer`: nada pedido todavía, la versión latina «↓ Por pedir» (RX3-A, «Así funciona» con `-demo-debrid-intro`).
        guard let wanted = rdRequest, wanted != "offer" else { return }
        let book = services.debridRequests.requester.book
        let now = Date()
        func entry(_ hash: String, _ title: String, _ meta: String, _ video: String, _ season: Int?, _ episode: Int?, _ state: DebridRequest.State,
                   _ percent: Int, ago: TimeInterval, device: String = services.deviceName) -> DebridRequest {
            var r = DebridRequest(hash: String(repeating: hash, count: 40), rdID: "DEMO\(hash)", title: title, kind: season == nil ? "movie" : "series",
                                  metaID: meta, videoIDs: meta == "tt0386676" ? [video, "tt0386676:2:6", "tt0386676:1:1"] : [video], season: season, episode: episode, language: "es-419", device: device,
                                  createdAt: now.addingTimeInterval(-ago), rdStatus: state == .ready ? "downloaded" : "downloading", percent: percent,
                                  seeders: state == .noPeers ? 0 : 12, state: state)
            r.progressAt = now.addingTimeInterval(-(wanted == "stalled" ? 26 * 3600 : 60))
            return r
        }
        let office: (DebridRequest.State, Int) = switch wanted {
        case "queued": (.queued, 0)
        case "nopeers", "stalled": (.noPeers, 3)
        case "blocked": (.refused, 0)
        case "toomany": (.tooMany, 0)
        case "ready": (.ready, 100)
        default: (.downloading, 42)
        }
        // T2 E5 es donde vas en la biblioteca de mentira (la ficha y «Seguir viendo»); el pedido trae también T2 E6 (la tarjeta del
        // siguiente episodio). Antes era solo T2 E6 y la ficha decía «Pedir a la nube» en lugar de «Bajando… 42 %».
        book.put(entry("a", "The Office", "tt0386676", "tt0386676:2:5", 2, 5, office.0, office.1, ago: wanted == "stalled" ? 27 * 3600 : 360))
        if wanted == "all" {
            var tv = entry("b", "Nocturne", "tt1160419", "tt1160419", nil, nil, .queued, 0, ago: 1200, device: "TV")
            tv.account = "999"   // la TV con otra cuenta de Real-Debrid: se enseña, pero solo se abre su ficha (P2-B)
            book.put(tv)
            book.put(entry("c", "Severance", "tt11280740", "tt11280740:1:3", 1, 3, .noPeers, 3, ago: 90_000))
            book.put(entry("d", "Dune: Parte dos", "tt15239678", "tt15239678", nil, nil, .refused, 0, ago: 4000))
            book.put(entry("e", "Andor", "tt9253284", "tt9253284:2:7", 2, 7, .tooMany, 0, ago: 300))
            book.put(entry("f", "Interstellar", "tt0816692", "tt0816692", nil, nil, .ready, 100, ago: 7200))
        }
        services.debridRequests.reloadForDemo()
    }

    /// `-demo-rd revoked`: tu cuenta se confirmó ayer (Premium) y hoy Real-Debrid ya no acepta la clave (la cambiaste en
    /// real-debrid.com), para ver «Vuelve a conectar Real-Debrid» (P6-A). `-demo-rd-slow`: Real-Debrid tarda 3 s en contestar,
    /// para ver la página mientras revisa tu clave.
    @MainActor static func seedDebrid(_ services: Services) {
        guard realDebrid == "revoked" else { return }
        services.debrid.rememberForDemo(DebridStatus(service: "Real-Debrid", username: "demo", isPremium: true, expires: Date().addingTimeInterval(18 * 86_400),
                                                     checkedAt: Date(), userID: "1"))
    }
    static var rdSlow: Bool { has("-demo-rd-slow") }

    /// Lo que tienes a medias en la demo («Seguir viendo»: The Office, Breaking Bad e Interstellar). Antes lo traía la cuenta
    /// de mentira de Stremio al abrir; sin Stremio (E1) se siembra aquí, igual que quedaba. Con `-demo-signed-out`, nada.
    @MainActor static func seedLibrary(_ services: Services) {
        guard !has("-demo-signed-out") else { return }
        let now = Date().timeIntervalSince1970
        let rows: [(id: String, kind: String, name: String, video: String, at: Double, length: Double, hoursAgo: Double)] = [
            ("tt0386676", "series", "The Office", "tt0386676:2:5", 120, 1_320, 2),
            ("tt0903747", "series", "Breaking Bad", "tt0903747:1:3", 1_200, 2_820, 30),
            ("tt0816692", "movie", "Interstellar", "tt0816692", 3_000, 10_140, 50),
        ]
        services.library.batch { entries in
            for row in rows where entries[row.id] == nil {
                var entry = LibraryEntry(metaID: row.id, kind: row.kind, name: row.name, poster: "https://images.metahub.space/poster/medium/\(row.id)/img")
                entry.videoID = row.video; entry.position = row.at; entry.duration = row.length; entry.updatedAt = now - row.hoursAgo * 3600
                entries[row.id] = entry
            }
        }
    }

    /// Secretos de arranque: sesión iniciada y el complemento de demostración.
    /// Cómo está tu Real-Debrid de mentira (`-demo-rd`): premium (143 días), soon (3 días), expired (hace 2 días), free, invalid, unreachable
    /// o un número de días («14»).
    static var realDebrid: String? { value(after: "-demo-rd") }
    static let realDebridToken = String(repeating: "DEMO", count: 13)

    static func secrets() -> InMemorySecrets {
        let secrets = InMemorySecrets()
        // El complemento de demostración (videos de prueba), como uno que pegaste en Ajustes: antes llegaba con la cuenta de
        // mentira de Stremio y, sin ella (E1), el reproductor de la demo se quedaba sin versiones. Con `-demo-search-slow`, tres.
        if !has("-demo-signed-out") {
            let urls = searchSlow ? slowLanes.map { "https://demo.orbital.invalid/\($0)/manifest.json" } : [addonURL]
            secrets.set(SecretKey.ownAddons, urls.joined(separator: "\n"))
        }
        if scrobble || airings || because || trakt || rate { secrets.set(SecretKey.traktTokens, #"{"access_token":"DEMO","refresh_token":"DEMO","expires_at":4102444800}"#) }   // sesión falsa (propia del iPhone): nada sale a Trakt
        if !noTV { secrets.set(SecretKey.orbitalToken, "demo") }      // una Orbital de mentira ya conectada («Ver en la TV»)
        if tmdb || DemoViento.mode != nil { secrets.set(SecretKey.tmdbKey, "DEMO") }            // TMDB de mentira: la ficha rica sin clave de verdad
        // `-demo-rd premium|soon|expired|free|invalid`: una clave de Real-Debrid de mentira (api.real-debrid.com la contesta la demo).
        if realDebrid != nil || rdRequest != nil || DemoViento.mode != nil { secrets.set(AddonKeys.realDebridToken, Self.realDebridToken) }
        seedKeys(secrets)   // `-demo-keys`: la llave de este aparato (K1)
        seedCX(secrets)     // `-demo-cx`: CX1-B…CX8-A
        if oneDrive == "linked" { secrets.set(SecretKey.oneDriveTokens, #"{"access_token":"DEMO","refresh_token":"DEMO","expires_at":4102444800}"#) }
        return secrets
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
