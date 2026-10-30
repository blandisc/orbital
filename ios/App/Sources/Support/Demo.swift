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
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    /// `-start-tab N` y `-start-mode lists|mosaic`: abren esa pestaña con tus datos de verdad (sin `-demo`), para revisar
    /// un iPhone físico desde la Mac (`devicectl … process launch`) y capturarlo. Solo Debug.
    static var startTab: Int? { value(after: "-start-tab").flatMap(Int.init) }
    static var startMode: String? { value(after: "-start-mode") }
    /// `-demo-no-idle`: el mosaico no se mueve solo (las pruebas de arrastre miden solo lo que hace el dedo).
    /// Lo guardado (Inicio, el mosaico, los colores) sobrevive entre aperturas, como en el iPhone de verdad (para medir).
    static var persist: Bool { ProcessInfo.processInfo.arguments.contains("-demo-persist") }
    static var noIdle: Bool { ProcessInfo.processInfo.arguments.contains("-demo-no-idle") }
    /// `-demo-free-tabs`: en demo se puede cambiar de pestaña (sin esto, la de `-demo-tab` vuelve siempre).
    static var freeTabs: Bool { ProcessInfo.processInfo.arguments.contains("-demo-free-tabs") }

    static let addonURL = "https://demo.orbital.invalid/manifest.json"
    /// `-demo-no-tv`: sin Orbital conectada (para probar el QR: `xcrun simctl openurl booted "orbital-ios://pair?u=https%3A%2F%2Ftv.demo.invalid&t=demo"`).
    /// `-demo-first-run`: la guía de la primera vez (sin Real-Debrid ni Trakt conectados).
    static var firstRun: Bool { ProcessInfo.processInfo.arguments.contains("-demo-first-run") }
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
        // El aviso al tocar «Ver» con tu Real-Debrid vencido (`TitleView+Acciones`), sin buscar fuentes de verdad.
        case "rd-vencido": env.notify(String(format: Strings.tr("Tu Real-Debrid venció hace %lld días", language: env.services.appSettings.uiLanguage), 2),
                                      tone: .warn, actionTitle: "Renovar") {}
        default: break
        }
    }

    static let handoffRequest = PlayRequest(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", originalTitle: "The Office",
                                            displayTitle: "La Oficina", episodeLabel: "T2 · E5")

    /// `-demo-scrobble`: Trakt «conectado» con un último scrobble de mentira (para ver la fila de Ajustes › Trakt en el simulador).
    static var searchSlow: Bool { ProcessInfo.processInfo.arguments.contains("-demo-search-slow") }
    static let slowLanes = ["torrentio", "comet", "mediafusion"]
    static var scrobble: Bool { ProcessInfo.processInfo.arguments.contains("-demo-scrobble") }
    /// `-demo-because`: Trakt de mentira con historial y relacionados, para ver «Porque viste» en Para ti.
    static var because: Bool { ProcessInfo.processInfo.arguments.contains("-demo-because") }
    /// `-demo-rate`: lo que terminaste hace poco y aún no calificas (Moonlight, Parásitos y una serie): la pastilla de calificar.
    static var rate: Bool { ProcessInfo.processInfo.arguments.contains("-demo-rate") }
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
    /// `-demo-section seasons`: en Para ti › Listas, baja hasta ese grupo de colecciones (el nombre del caso de `CollectionSection`).
    static var section: String? { value(after: "-demo-section") }
    /// `-demo-collection genre:accion` o `season:halloween`: en Para ti › Listas, abre esa lista (con `-demo-tmdb`).
    static var collection: String? { value(after: "-demo-collection") }
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
    static var offline: Bool { ProcessInfo.processInfo.arguments.contains("-demo-offline") }
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
    /// el diagnóstico dice ese tramo.
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
    static var console: Bool { ProcessInfo.processInfo.arguments.contains("-demo-console") }
    /// `-demo-tmdb`: TMDB de mentira (elenco, saga, tráiler, dónde verlo) para ver la ficha rica sin clave.
    static var tmdb: Bool { ProcessInfo.processInfo.arguments.contains("-demo-tmdb") }
    /// `-demo-mosaic-focus 3`: en «Para ti» › Mosaico, enfoca esa sugerencia (su índice en `model.mosaic`) al abrir.
    static var mosaicFocus: Int? { value(after: "-demo-mosaic-focus").flatMap(Int.init) }

    /// `-demo-mosaic-bench`: el mosaico se desplaza y cambia de foco solo (ver `MosaicBench`) e imprime los fotogramas.
    static var mosaicBench: Bool { ProcessInfo.processInfo.arguments.contains("-demo-mosaic-bench") }
    /// `-demo-trakt-builtin`: Trakt conectado con el Client ID incluido en la app (Ajustes sin Client ID).
    static var traktBuiltIn: Bool { ProcessInfo.processInfo.arguments.contains("-demo-trakt-builtin") }

    /// Secretos de arranque: sesión iniciada y el complemento de demostración.
    /// Cómo está tu Real-Debrid de mentira (`-demo-rd`): premium (143 días), soon (3 días), expired (hace 2 días), free, invalid
    /// o un número de días («14»).
    static var realDebrid: String? { value(after: "-demo-rd") }
    static let realDebridToken = String(repeating: "DEMO", count: 13)

    static func secrets() -> InMemorySecrets {
        let secrets = InMemorySecrets()
        if !ProcessInfo.processInfo.arguments.contains("-demo-signed-out") { secrets.set(SecretKey.stremioAuth, "DEMO") }
        if scrobble || airings || because || trakt || rate { secrets.set(SecretKey.traktTokens, #"{"access_token":"DEMO","refresh_token":"DEMO","expires_at":4102444800}"#) }   // sesión falsa (propia del iPhone): nada sale a Trakt
        if !noTV { secrets.set(SecretKey.orbitalToken, "demo") }      // una Orbital de mentira ya conectada («Ver en la TV»)
        if tmdb { secrets.set(SecretKey.tmdbKey, "DEMO") }            // TMDB de mentira: la ficha rica sin clave de verdad
        // `-demo-rd premium|soon|expired|free|invalid`: una clave de Real-Debrid de mentira (api.real-debrid.com la contesta la demo).
        if realDebrid != nil { secrets.set(AddonKeys.realDebridToken, Self.realDebridToken) }
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
