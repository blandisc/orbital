import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Guarda el motor y el modelo juntos (el motor se arma una sola vez por reproducción). Vive en un `@State`, que evalúa su
/// valor inicial en cada `init` de la vista: por eso el motor y el modelo se arman la primera vez que se piden, no al crearlo.
@MainActor
final class PlayerHolder {
    var parts: (engine: VideoPlayerEngine, model: PlayerModel)?

    var engine: VideoPlayerEngine { built.engine }
    /// La vista que lee el modelo mientras se pinta se vuelve a pintar con cada cambio suyo (Observation).
    var model: PlayerModel { let model = built.model; model.track(); return model }

    var built: (engine: VideoPlayerEngine, model: PlayerModel) {
        if let parts { return parts }
        let made = Self.make()
        parts = made
        return made
    }

    static func make() -> (engine: VideoPlayerEngine, model: PlayerModel) {
        let services = AppEnvironment.shared.services
        let engine = PlayerEngines.make()
        let library = services.oneDriveLibrary
        let model = PlayerModel(engine: engine, finder: services.finder, watch: services.watch, titlePrefs: services.titlePrefs, settings: services.settings,
                            onCellular: { Connectivity.shared.isCellular }, episodeLabel: services.episodeLabel,
                            localEpisode: { metaID, videoID in
                                // El siguiente episodio ya descargado (para seguir viendo sin conexión).
                                guard let item = await services.downloads.item(DownloadItem.makeID(metaID: metaID, videoID: videoID)), item.state == .done else { return nil }
                                let file = await services.downloads.fileURL(item)
                                return LocalEpisode(file: file, subtitles: item.subtitleFiles.map { file.deletingLastPathComponent().appendingPathComponent($0) },
                                                    saved: item.allSavedSubtitles)
                            },
                            skipSegments: { videoID in await services.introDB.segments(videoID: videoID) },   // saltar intro y resumen (IntroDB, como Infuse)
                            scareMap: { imdb, title in await services.scares(imdb: imdb, fallbackTitle: title) })   // el mapa de sustos
        model.subtitlePicks = SubtitlePicks(services.kv)   // «Este va bien»: el subtítulo que elegiste para la serie
        model.subtitleOffsets = SubtitleOffsets(services.kv)   // la sincronía de cada versión (antes no se conectaba y se perdía)
        model.ownSource = { videoID, preferred in await library.source(videoID, purpose: .watch, preferring: preferred) }   // Mi media: tu copia primero
        // Episodios descargados que se encadenan solos: cada uno visto se atiende al pasar al siguiente (borrar / bajar el que sigue).
        model.onFinishedLocal = { finished in
            Task {
                guard let item = await services.downloads.item(DownloadItem.makeID(metaID: finished.metaID, videoID: finished.videoID)) else { return }
                await DownloadsModel(services, freeSpace: { DiskSpace.freeBytes() }).afterWatching(item)
            }
        }
        return (engine, model)
    }
}

/// El reproductor a pantalla completa, con gestos: un toque muestra los controles, doble toque a los lados salta ±10 s.
struct PlayerScreen: View {
    let request: PlayRequest
    @Environment(AppEnvironment.self) var env
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Con VoiceOver los controles no se esconden solos (si no, no queda nada que tocar).
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOver
    @State var holder = PlayerHolder()
    @State var controlsVisible = true
    /// Cuándo fue el último toque de un dedo y el último de dos (para que uno de dos dedos no mueva también los controles).
    @State var singleTapAt = Date.distantPast
    @State var twoFingerTapAt = Date.distantPast
    /// «Bloquear» (como Netflix): sin controles y la pantalla no responde a toques ni deslizamientos (para no pausar o adelantar
    /// sin querer). Un toque enseña la cápsula de arriba con «Desbloquear».
    @State var locked = false
    /// La cápsula de «Pantalla bloqueada» (arriba). `showsUnlock`: tras un toque, con el botón. `collapsed`: ya es el
    /// círculo del candado. `risen`: sube y se desvanece. `generation` descarta un cierre si llegó otro aviso.
    @State var lockNoticeVisible = false
    @State var lockNoticeShowsUnlock = false
    @State var lockNoticeCollapsed = false
    @State var lockNoticeRisen = false
    @State var lockNoticeGeneration = 0
    @State var unlockHide: Task<Void, Never>?
    @State var hideTask: Task<Void, Never>?
    /// El «⋯» de la barra horizontal abierto: mientras está, los controles no se esconden (si no, se cerraba solo).
    @State var moreOpen = false
    /// «Descargar» desde el reproductor: si este video (película o episodio) ya está en Descargas (o se está bajando).
    @State var inDownloads = false
    @Environment(\.verticalSizeClass) var verticalSize
    @State var scrubbing: Double?
    /// A dónde se pidió ir y el video todavía no llega.
    @State var pendingSeek: Double?
    @AppStorage("scare-warnings") var scareWarnings = true
    @State var finished = false
    @State var pip = PictureInPicture()
    @State var nowPlaying = NowPlaying()
    /// En vertical, a qué altura va el video (lo mueves arrastrándolo; se recuerda) y su valor mientras arrastras.
    @AppStorage(PlayerScreen.portraitCenterKey) var portraitCenter = Double(DS.PlayerPanel.portraitCenter)
    @State var portraitDrag: Double?
    @State var portraitAtDragStart: Double = 0
    /// «Modo iPod» (vertical): "" apagado, "white" o "black". Se queda para la próxima.
    @AppStorage("player-ipod") var ipodFace = ""
    /// Girando la rueda del iPod: a dónde vas (se va al soltar) y cuándo fue la última muesca (rápido = de a minuto).
    @State var wheelTarget: Double?
    /// De vuelta de segundo plano: el cuadro donde ibas, a la vista mientras el motor rearma el video (antes, negro y a esperar).
    @State var frozenFrame: UIImage?
    @State var frozenTask: Task<Void, Never>?
    /// Si la app está al frente. Un `@State` y no `scenePhase`: dentro de una tarea, `scenePhase` es una copia del momento
    /// en que empezó (se quedaba en «segundo plano» para siempre y el cuadro guardado no se quitaba).
    @State var appActive = true
    @State var lastNotch: Date?
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    /// El zoom de cada sentido: el de horizontal se recuerda (Ajustes); el de vertical arranca siempre en el cuadro completo. Antes
    /// era uno solo y al volver de horizontal con «Llenar» el video quedaba en vertical a pantalla completa, recortado.
    @State var landscapeZoom: VideoZoom = .fit
    @State var portraitZoom: VideoZoom = .fit
    /// Cuándo cambió el sentido: un pellizco que termina justo después (los pulgares al girar) no cuenta.
    @State var rotatedAt = Date.distantPast
    @State var pinchStartedAt: Date?
    @State var zoomBeforePinch: (zoom: VideoZoom, at: Date)?
    #if DEBUG
    @State var lastPinch = 0.0
    #endif
    var zoom: VideoZoom { landscape ? landscapeZoom : portraitZoom }
    @State var zoomToast: VideoZoom?
    /// «Subtítulos desactivados» o «Español · 1 de 4», un momento, al apagar o prender con el botón.
    @State var subtitleToast: String?
    /// Lo que pasó al pedir «Descargar» (el mismo aviso que en el resto de la app, arriba: abajo están los controles).
    @State var notice: PlayerNotice?
    /// Avisos que llegaron con la cápsula del candado en pantalla. Salen, en orden, cuando esa cápsula se va.
    @State var heldNotices = HeldNotices<QueuedNotice>()
    @State var heldDrain: Task<Void, Never>?
    @State var heldDrainGeneration = 0
    struct PlayerNotice: Equatable {
        var title: String, detail: String?, tone: DSNotice.Tone
        var showsDownloads = false
        /// «Cambiar a latino»: otra versión que sí trae tu idioma (su índice), en el mismo segundo.
        var switchTo: Int? = nil
        var switchTitle: String? = nil
        let id = UUID()
    }
    /// Lo que espera turno. Subtítulos y zoom se quedan con el último; los demás, todos, en orden.
    enum QueuedNotice {
        case player(PlayerNotice)
        case subtitle(String)
        case zoom(VideoZoom)
    }
    enum QueuedNoticeKey: Hashable { case subtitle, zoom }
    /// Subtítulos rápidos (el panel chico sobre el video) y su lista de idiomas.
    @State var subtitleDock = false
    /// La hoja «Audio y subtítulos» tiene dos páginas: lo de siempre y «Versión» (por idioma o todas las fuentes).
    enum DockPage { case media, version, episodes }
    @State var dockPage: DockPage = .media
    /// Las temporadas de la serie que suena, para «Episodios» (se leen al abrirlo: son cientos de episodios).
    @State var episodeSeasons: [Season] = []
    /// Viendo un archivo descargado, los episodios que también están bajados (los demás no se pueden poner).
    @State var playableEpisodes: Set<String>?
    @State var dockOpens: SubtitleDock.Section? = .subtitles
    @State var versionShowsAll = false
    /// Una versión que Real-Debrid aún no tiene: se pregunta antes de abrirla (puede tardar o no abrir).
    @State var slowPick: Int?
    /// Lo que mide la hoja (para que en vertical ocupe lo suyo y, si no cabe, se recorra).
    @State var dockLanguages = false
    /// «Todas las versiones» desde el panel chico: media hoja (el video sigue a la vista arriba).
    @State var dockVersions = false
    /// «Sincronizar con una línea»: las frases congeladas (nil: no está abierto), la que tocaste y el ajuste que quedó.
    @State var syncLines: [SubtitleLine]?
    @State var syncPicked: Double?
    @State var syncResult: Double?
    @State var zoomToastTask: Task<Void, Never>?
    /// Cuántas veces se ha visto «Arrastra para mover» junto a la agarradera (se deja de decir después de unas pocas).
    @AppStorage("player-move-hint-seen") var moveHintSeen = 0
    /// En esta función se dice (se decide al abrir, para que no aparezca y desaparezca a media película).
    /// En vertical, este arrastre mueve el video (empezó en la agarradera o fuera del video); si no, es brillo o volumen.
    @State var movingVideo = false

    // MARK: gestos como Infuse (brillo, volumen, buscar arrastrando, 2×)
    @State var dragAxis: GestureAxis = .undecided
    @GestureState var dragging = false
    @State var verticalKind: VerticalGesture?
    @State var brightnessAtDragStart: Double = 1
    @State var volumeAtDragStart: Double = 0
    @State var originalBrightness: Double = 1
    @State var requestedVolume: Float?
    @State var indicator: (kind: VerticalGesture, symbol: String, value: Double)?
    /// Aparte de `indicator` (que se actualiza en cada punto del arrastre, sin animar) para que solo la entrada
    /// y la salida se animen; moverlo de golpe en cada cuadro se vería tembloroso.
    @State var indicatorVisible = false
    @State var indicatorHideTask: Task<Void, Never>?
    @State var seekPositionAtDragStart: Double?
    @State var seekPreview: Double?
    @State var isFastForwarding = false
    /// ×2 fijo: deslizaste hacia abajo hasta que vibró; sigue al soltar y un toque en la píldora lo quita.
    @State var fastForwardLocked = false
    /// El dedo sigue puesto después de la pulsación larga (el ×2 dura lo que dure el dedo, como TikTok).
    @State var fastForwardHolding = false
    /// El ×2 se quedó con este toque (aunque ya hayas deslizado hacia arriba para quitarlo): el arrastre del video no lo roba.
    @State var fastForwardOwnsTouch = false
    /// Cómo estaba al empezar a mantener: si ya iba fijo, el aviso dice deslizar hacia arriba para quitarlo.
    @State var fastForwardLockedAtStart = false
    @State var fastForwardToggledThisHold = false
    /// Dónde empezó el toque (el ×2 es del lado derecho, como YouTube; hacia abajo se mide desde aquí).
    @State var touchStartX: CGFloat?
    @State var touchStartY: CGFloat?
    /// El ícono que aparece un momento al centro tras un doble toque (pausa, ±10 s).
    @State var flashSymbol: String?
    /// Dobles toques en una orilla: cuántos segundos llevan sumados y de qué lado (la burbuja va de ese lado).
    @State var skipChain: (forward: Bool, seconds: Int, at: Date)?
    @State var skipChainTask: Task<Void, Never>?
    @State var skipHaptic = 0
    @State var skipEdgeHaptic = 0
    /// ×2: lo que lleva el anillo al deslizar hacia abajo, antes de quedarse fijo.
    @State var fastForwardProgress: Double = 0
    @State var flashTask: Task<Void, Never>?
    /// Lo que mide la tarjeta de «Siguiente episodio» (para subir los subtítulos sobre ella).
    @State var upNextHeight: CGFloat = 0
    @State var rateBeforeFastForward: Float = 1

    /// Lo que suena ahora: cambia al pasar solo al siguiente episodio (el `request` es solo con el que se abrió).
    var current: PlayRequest { holder.model.request ?? request }
    @State var ambientURL: URL?
    @State var knownAspect: Double?
    @State var aspectTitle: String?
    /// El alto que pide «Audio y subtítulos» en vertical (para subir el video lo justo y que quepa sin desplazarse).
    @State var dockNeed: CGFloat = 0
    /// Lo que enseña el botón grande (la carga o el play/pausa): una sola regla, probada en `PlayerPresentationTests`.
    @State var presentation = PlayerPresentation()
    @State var controlsHiddenAt = Date.distantPast

    var body: some View {
        let model = holder.model
        ZStack {
            if let face = ipod { Rectangle().fill(face.body).ignoresSafeArea() } else { DS.video.ignoresSafeArea() }
            // El fondo ambiente aparece (con un desvanecido) cuando el video ya suena: mientras carga, todo negro (antes la franja
            // de arriba cambiaba de color a media carga).
            Group { if !landscape && !fillsPortrait && ipod == nil && model.hasPlayed { ambientLayer } }
                .animation(DS.Motion.base(reduceMotion), value: model.hasPlayed)
            GeometryReader { geo in
                let rect = videoRect(in: geo.size)
                ZStack {
                    if ipod != nil { DS.video }   // la pantalla del iPod: negro detrás del video
                    holder.engine.surface
                    if let frozenFrame { frozenCover(frozenFrame).transition(.opacity) }
                    if dragAxis != .horizontal && !fillsPortrait {
                        // Mientras buscas arrastrando, el subtítulo se quita: la burbuja ya dice el tiempo y no hay con qué encimarlo.
                        // Sube con los controles solo en horizontal (en vertical los controles van fuera del video: si subía,
                        // quedaba a media imagen).
                        holder.engine.subtitleOverlay(lifted: controlsVisible && landscape, speedPill: speedPillVisible && landscape, look: SubtitleLook(settings: env.services.appSettings), delay: model.subtitleDelay)
                            // Con la tarjeta de «Siguiente episodio» (abajo a la derecha, en horizontal) la línea sube sobre ella.
                            .offset(y: landscape && model.upNext != nil && !locked && !subtitleDock ? -(upNextHeight + DS.Space.s6) : 0)
                            .transition(.opacity)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                // Al arrastrarlo se levanta: un poco más chico, con esquinas y sombra (como al mover algo en iOS).
                .clipShape(RoundedRectangle(cornerRadius: movingVideo ? DS.PlayerPanel.liftRadius : 0, style: .continuous))
                .scaleEffect(movingVideo ? DS.PlayerPanel.liftScale : 1)
                .shadow(color: movingVideo ? DS.scrimStrong : .clear, radius: DS.PlayerPanel.liftShadow)
                .offset(x: rect.minX, y: rect.minY)
                // «Recortar» en vertical: los subtítulos con el tamaño de siempre (el de un cuadro a lo ancho), abajo; con los
                // controles a la vista suben sobre ellos.
                .overlay(alignment: .bottom) {
                    if fillsPortrait && dragAxis != .horizontal {
                        // Con los controles, ya van por encima de ellos; si además está la píldora, un poco más. Sin controles
                        // y con la píldora al pie, suben lo bastante para no taparla.
                        let aboveControls = controlsVisible ? geo.size.height * DS.PlayerPanel.portraitFillControlsShare : DS.Space.s6
                        let abovePill = speedPillVisible ? (controlsVisible ? DS.Space.s10 : DS.Subtitle.liftWithSpeedPill) : 0
                        holder.engine.subtitleOverlay(lifted: false, speedPill: false, look: SubtitleLook(settings: env.services.appSettings), delay: model.subtitleDelay)
                            .frame(width: geo.size.width, height: geo.size.width / DS.Poster.stillAspect)
                            .padding(.bottom, aboveControls + abovePill)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea(edges: landscape ? .all : [])   // en vertical el video respeta la isla y el indicador de inicio
            if locked { lockLayer } else { gestureLayer(model) }
            SystemVolumeControl(volume: $requestedVolume)
                .frame(width: DS.Gesture.indicatorBarWidth, height: DS.Gesture.indicatorBarWidth)
                .allowsHitTesting(false).accessibilityHidden(true)
            // Cargando o reconectando: al centro del video, no de la pantalla (en vertical los controles van bajo el video
            // y el aviso se les encimaba). El error sí va al centro de la pantalla (trae botones y necesita espacio).
            if case .failed = model.phase { statusOverlays(model) } else {
                GeometryReader { geo in
                    let rect = videoRect(in: geo.size)
                    // Todo lo que carga (la búsqueda de versiones y la ruedita) con su centro en el del video, siempre el mismo punto:
                    // antes la búsqueda iba al centro de la pantalla y en vertical la ruedita que seguía brincaba hacia arriba.
                    // Con los controles a la vista la carga va en su botón grande (mismo punto): aquí no se repite.
                    if !(transportShown(model)) { statusOverlays(model).position(x: rect.midX, y: rect.midY) }
                }
                .ignoresSafeArea(edges: landscape ? .all : [])
                .allowsHitTesting(false)
            }
            gestureOverlays
            // En los dos sentidos los controles se esconden solos si no haces nada (un toque los trae); bloqueado, no salen.
            // Abriendo, la barra de arriba (✕ para salir) siempre se ve: antes un toque la escondía y no había cómo cancelar.
            let controlsShown = (controlsVisible || model.phase == .preparing) && !locked && !failed(model) && !subtitleDock && ipod == nil
            // Los controles y ±10/botón grande en UN solo bloque con una sola transición: antes eran dos y, si el giro o el
            // ocultamiento caían a la vez, podía quedar el ±10 flotando sin las barras.
            if controlsShown {
                ZStack {
                    controls(model)
                    // ±10 y el botón grande, siempre al centro del video (en vertical también, encima de la imagen): el mismo punto
                    // donde está la imagen del episodio al abrir y donde se ve la carga.
                    if model.phase != .preparing {
                        GeometryReader { geo in
                            let rect = videoRect(in: geo.size)
                            transport(model).position(x: rect.midX, y: rect.midY)
                        }
                        .ignoresSafeArea(edges: landscape ? .all : [])
                    }
                }
                .transition(.opacity)
            }
            // Encima de los controles: en horizontal sobre la barra; en vertical, al pie (o sobre la barra si «Recortar»).
            if speedPillVisible { speedPill.transition(.opacity) }
            // El iPod no se esconde (es el aparato): con la pantalla bloqueada se ve pero no se toca.
            if let face = ipod, !failed(model) { ipodChrome(model, face: face).transition(.opacity) }
            if (controlsShown || (ipod != nil && !locked)) && moreOpen { moreLayer(model) }
            if subtitleDock && !locked { subtitleDockLayer(model).transition(.move(edge: .bottom).combined(with: .opacity)) }
            // «Saltar intro» no depende de los controles (se esconden a los pocos segundos y con ellos se iba el botón):
            // con los controles escondidos queda solo, abajo a la derecha, como en Netflix o Infuse. Con los controles a la
            // vista (en pausa, o con la ventana de PiP afuera) ya va dentro de ellos: antes salía dos veces.
            // En vertical va justo debajo del video, a la derecha (donde sale con los controles); antes quedaba al pie de la
            // pantalla, lejos de la imagen. Con un error a la vista, no.
            else if !controlsShown && !locked && ipod == nil && !failed(model) && model.skipIntroTo != nil {
                if landscape {
                    VStack { Spacer(); HStack { Spacer(); skipIntro(model) } }.padding(DS.Space.s6).transition(.opacity)
                } else {
                    GeometryReader { geo in
                        HStack { Spacer(); skipIntro(model) }
                            .padding(.horizontal, DS.Space.gutter)
                            .offset(y: videoRect(in: geo.size).maxY + DS.Space.s4)
                    }
                    .transition(.opacity)
                }
            }
            // Bloqueado no se ve (ni se toca): si llega a cero, pasa solo al siguiente. En vertical va entre el video y la barra
            // (dentro de los controles, o sola si están escondidos); en horizontal, abajo a la derecha sobre la barra.
            // Con el panel de subtítulos abierto, tampoco: se encimaba sobre él (sale al cerrarlo, si aún falta).
            if let up = model.upNext, !locked, !subtitleDock {
                if landscape {
                    VStack { Spacer(); HStack { Spacer(); upNextCard(model, up).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { upNextHeight = $0 } } }
                        .padding(.horizontal, DS.Space.s6)
                        .padding(.bottom, controlsVisible ? DS.Space.s6 + DS.Size.touchTarget * 2 : DS.Space.s6)
                } else if ipod != nil {
                    // En el iPod, sobre lo de abajo de la pantalla (el nombre y el avance), como un aviso del aparato.
                    GeometryReader { geo in
                        let screen = IPodLayout(in: geo.size, aspect: portraitAspect).screen
                        upNextCard(model, up).padding(.horizontal, DS.Space.gutter)
                            .frame(width: geo.size.width, height: screen.maxY - DS.Space.s2, alignment: .bottom)
                    }
                } else if !controlsVisible {
                    GeometryReader { geo in
                        upNextCard(model, up).padding(.horizontal, DS.Space.gutter)
                            .frame(width: geo.size.width)
                            .offset(y: videoRect(in: geo.size).maxY + DS.Space.s4)
                    }
                }
            }
        }
        .onArt()   // sobre el video siempre se ve como en la sala oscura, aunque la app esté en modo claro
        // Los arrastres verticales (brillo, volumen) que empiezan cerca del borde no abren el Centro de control ni el de
        // notificaciones: iOS pide un segundo deslizamiento, como en cualquier reproductor.
        .defersSystemGestures(on: .vertical)
        // VoiceOver: frotar con dos dedos cierra; el doble toque con dos dedos pausa o sigue (los gestos de siempre de iOS).
        .accessibilityAction(.escape) { Task { await close() } }
        .accessibilityAction(.magicTap) { userTogglePlay(holder.model) }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(DS.Motion.base(reduceMotion), value: controlsVisible)
        .animation(DS.Motion.base(reduceMotion), value: dragAxis)
        .animation(DS.Motion.base(reduceMotion), value: ipodFace)
        .onAppear { Perf.mark("player.shown") }
        .onChange(of: model.snapshot.state) { if model.snapshot.state == .playing { Perf.mark("player.firstFrame") } }
        .task {
            // Abre como tienes el teléfono (Los Simpson, siempre vertical); boca arriba o sin saberlo, horizontal.
            #if DEBUG
            let startPortrait = request.startPortrait || Demo.playerPortrait
            #else
            let startPortrait = request.startPortrait
            #endif
            if startPortrait { rotate(allowed: .allButUpsideDown, to: .portrait) } else { rotate(allowed: .allButUpsideDown, to: Self.openingOrientation) }
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            // Después, girar el teléfono gira el video como el resto de iOS: UIKit gira solo dentro de `allButUpsideDown`
            // y respeta el candado de rotación del teléfono (con el candado puesto, el video se queda como está).
            // La sesión de video, siempre (la voz del control la deja en otro modo y con el volumen bajado).
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.isIdleTimerDisabled = true
            originalBrightness = Double(UIScreen.main.brightness)
            // `begin` va aparte: el plazo de arranque (45 s) tiene que seguir corriendo mientras carga.
            let engine = holder.engine
            landscapeZoom = VideoZoom(stored: env.services.appSettings.videoZoom)
            #if DEBUG
            if Demo.isOn, let raw = Demo.value(after: "-demo-zoom") { landscapeZoom = VideoZoom(stored: raw); portraitZoom = VideoZoom(stored: raw) }   // `-demo-zoom fill`: para capturas
            if Demo.isOn, let face = Demo.value(after: "-demo-ipod") { ipodFace = face == "off" ? "" : face }   // `-demo-ipod black`
            #endif
            pip.onActiveChange = { engine.setPictureInPictureActive($0) }
            nowPlaying.start(model: model)
            Task {
                await model.begin(request); scheduleHide()
                #if DEBUG
                if Demo.isOn, let open = Demo.player {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
                    // `-demo-player dock|subtitles|audio|version|subtitle-versions`: la hoja «Audio y subtítulos» (con ese renglón abierto) o «Versión».
                    switch open {
                    case "dock", "subtitles": openDock(.subtitles)
                    case "audio": openDock(.audio)
                    case "version": openDock(nil, version: true)
                    case "subtitle-versions": openDock(.subtitles); dockVersions = true   // todas las versiones del idioma puesto
                    case "episodes": openEpisodes(model)   // `-demo-player episodes`: la lista de episodios
                    case "near-end": await model.seek(to: model.snapshot.duration * 0.92); hideTask?.cancel(); controlsVisible = true   // con «Siguiente» a la vista
                    case "close": await close()
                    default: break
                    }
                }
                // `-demo-player-pick es`: como tocar ese idioma en «Subtítulos» (para capturarlo sin tocar la pantalla).
                if Demo.isOn, let code = Demo.playerPick {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 4)
                    await pickSubtitleLanguage(code, model)
                }
                if Demo.isOn, let state = Demo.playerState {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 4)
                    if state == "locked" { lock() } else { model.demoState(state) }
                }
                if Demo.isOn, let gesture = Demo.gesture {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 4)
                    simulateGesture(gesture, model: model)
                }
                #endif
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: DS.Timing.tick)
                await model.tick()
                if let aspect = engine.videoAspect, aspect != knownAspect { knownAspect = aspect }   // para cuando el motor la olvide
                pip.update(engine.pictureInPicture)
                nowPlaying.update(title: current.displayTitle, subtitle: current.episodeLabel, poster: current.poster, snapshot: model.snapshot)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.appDidEnterBackground() } }
            // De vuelta: el motor soltó el video en segundo plano; se rearma (o se pide otra vez) en vez de quedarse en negro.
            if phase == .background { model.appDidEnterBackgroundFully(); captureFrozenFrame() }
            appActive = phase == .active
            if phase == .active {
                // Si el video siguió vivo (volviste rápido, o seguía sonando), no hace falta el cuadro guardado.
                if holder.engine.showsVideo { frozenTask?.cancel(); frozenFrame = nil }
                Task { await model.appDidBecomeActive() }
            }
        }
        .onChange(of: model.phase) { _, phase in if phase == .closed { finish() } }
        // El cuadro guardado se queda hasta que el video de verdad vuelve a la pantalla (o algo falla y sale el error).
        .task(id: frozenFrame != nil) {
            while frozenFrame != nil, !Task.isCancelled {
                if failed(holder.model) { frozenFrame = nil; break }
                if appActive, holder.engine.showsVideo, holder.model.snapshot.state != .loading {
                    withAnimation(DS.Motion.base(reduceMotion)) { frozenFrame = nil }
                    break
                }
                try? await Task.sleep(nanoseconds: DS.Timing.frozenFramePoll)
            }
        }
        // «Arrastra para mover» junto a la agarradera solo las primeras funciones.
        // Las primeras veces, el video da un brinquito (hacia abajo y de regreso) en cuanto aparece la agarradera: enseña que se
        // mueve sin decirlo con texto.
        .task {
            guard moveHintSeen < DS.PlayerPanel.moveHintTimes, !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 3)
            guard !landscape, ipod == nil, !fillsPortrait, controlsVisible else { return }
            moveHintSeen += 1
            withAnimation(DS.Motion.spring(reduceMotion)) { portraitDrag = portraitCenter + DS.PlayerPanel.moveNudge }
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 8)
            withAnimation(DS.Motion.spring(reduceMotion)) { portraitDrag = nil }
        }

        // Esta versión no trae tu idioma (o no el latino) y otra sí: se ofrece cambiar sin perder el punto.
        .onChange(of: model.notice) { _, value in
            let ui0 = env.services.appSettings.uiLanguage
            if value == .switchFailedBack {
                return show(PlayerNotice(title: Strings.tr("Esa versión no abrió", language: ui0), detail: Strings.tr("Volviste a la que veías, en el mismo punto.", language: ui0), tone: .warn))
            }
            // Una versión falló y se prueba otra: se dice (antes cambiaba a escondidas y solo se veía la carga más tiempo).
            if case .triedAnotherSource(let attempt)? = value {
                return show(PlayerNotice(title: String(format: Strings.tr("Probando otra versión (%lld)…", language: ui0), attempt),
                                         detail: Strings.tr("La anterior no respondió. Sigue en el mismo punto.", language: ui0), tone: .info))
            }
            if value == .notReadyOnRealDebrid {
                return show(PlayerNotice(title: Strings.tr("Real-Debrid aún no la tiene", language: ui0), detail: Strings.tr("Mandó su aviso de «descargando». Puede tardar; prueba más tarde u otra versión.", language: ui0), tone: .warn))
            }
            guard case .otherVersionHasYourLanguage(let want, let have, let index)? = value else { return }
            let ui = env.services.appSettings.uiLanguage, tr = { (k: String) in Strings.tr(k, language: ui) }
            // Corto, para que quepa con su botón: «No trae latino · Sus pistas: inglés y castellano · Cambiar».
            let wanted = want == "es" ? VersionLanguageRow.spanish(ui) : Streams.versionLanguageName(want, in: ui)
            let tracks = have.map { VersionLanguageRow.inline(Streams.versionLanguageName($0, in: ui), ui) }.joined(separator: tr(" y "))
            show(PlayerNotice(title: String(format: tr("No trae %@"), VersionLanguageRow.inline(wanted, ui)),
                              detail: String(format: tr("Sus pistas: %@"), tracks), tone: .warn,
                              switchTo: index, switchTitle: tr("Cambiar")))
        }
        // El video ya llegó (o pasó un momento): el pulgar vuelve a seguir el avance real.
        .onChange(of: model.snapshot.position) { _, position in
            if let target = pendingSeek, abs(position - target) < DS.Gesture.seekArrived { pendingSeek = nil }
        }
        .task(id: current.videoID) {
            // Otro episodio de la misma serie: la proporción se conserva hasta que el motor mida la nueva (antes se borraba y un 4:3
            // brincaba a 16:9 un momento). Otro título: se olvida.
            if aspectTitle != current.metaID { knownAspect = nil; aspectTitle = current.metaID }
            // ×2 fijo no pasa al siguiente episodio: cada episodio empieza a velocidad normal.
            if isFastForwarding { endFastForward(holder.model, force: true) }
            await loadAmbient(); await loadLocalizedEpisodes()
        }
        .onChange(of: PlayerPresentation.loadKind(model), initial: true) { _, kind in
            presentation.update(kind, playing: model.snapshot.state == .playing, videoID: current.videoID)
        }
        .onChange(of: model.snapshot.state == .playing) { presentation.engineChanged { holder.model.snapshot.state == .playing } }
        // Al girar, cada sentido con su zoom; y otra vez cuando termina la animación del giro (el motor del iPhone a veces se
        // quedaba con el «Llenar» de horizontal y la imagen seguía agrandada en vertical).
        // El motor recibe el zoom desde un solo lugar: cada vez que cambia el de este sentido (al girar, al pellizcar, desde el «⋯»).
        .onChange(of: zoom, initial: true) { holder.engine.setZoom(zoom) }
        .onChange(of: landscape) {
            PlayerModel.note("giro a \(landscape ? "horizontal" : "vertical") (zoom vertical era \(portraitZoom.rawValue))")
            rotatedAt = Date()
            // Vertical vuelve siempre al cuadro completo al girar: si algo puso «Recortar» sin querer (un pellizco al sujetar el
            // teléfono), el giro lo deshace.
            portraitZoom = .fit
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: DS.Timing.rotationSettle)
                holder.engine.setZoom(zoom)
            }
        }
        .task(id: pendingSeek) { if pendingSeek != nil { try? await Task.sleep(nanoseconds: DS.Timing.seekPatience); pendingSeek = nil } }
        .onChange(of: moreOpen) { _, open in if !open, controlsVisible, !locked { scheduleHide() } }   // cerrado el «⋯», vuelve a contar
        .onChange(of: voiceOver) { _, on in if on { controlsVisible = true } }   // con VoiceOver, los controles no se esconden
        // Una versión que Real-Debrid aún no tiene: la verdad antes de abrirla (puede tardar u horas; si manda su aviso, se vuelve).
        .confirmationDialog(Text("Real-Debrid aún no tiene esta versión"), isPresented: Binding(get: { slowPick != nil }, set: { if !$0 { slowPick = nil } }), titleVisibility: .visible) {
            Button("Abrirla de todos modos") {
                if let index = slowPick { withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media }; Task { await model.switchSource(to: index) } }
                slowPick = nil
            }
            Button("Mejor no", role: .cancel) { slowPick = nil }
        } message: { Text("Empieza a bajarla y puede tardar minutos u horas. Si manda su aviso de «descargando», vuelves a la que ves en el mismo punto.") }
        .alert("¿Sigues viendo?", isPresented: Binding(get: { model.stillWatchingPrompt }, set: { _ in })) {
            Button("Seguir") { Task { await model.confirmStillWatching() } }
            Button("Salir", role: .cancel) { Task { await close() } }
        } message: { Text("Llevas tres episodios seguidos.") }
        // Con «Audio y subtítulos» abierto la tarjeta de «Siguiente» no se ve: su cuenta se detiene (no cambia de episodio a escondidas).
        .onChange(of: subtitleDock) { _, open in holder.model.panelOpen = open }
        // Girar el teléfono gira el video: el aviso de giro del sistema no llega con el candado de rotación puesto,
        // así que con el candado el video se queda como abrió. Con «Bloquear» se ignora.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            followDevice()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            UIApplication.shared.isIdleTimerDisabled = false; pip.stop(); nowPlaying.stop(); unlockPortrait()
            UIScreen.main.brightness = CGFloat(originalBrightness)   // el brillo es del sistema: no se queda en lo que dejó el gesto
            // Ningún reloj de la pantalla sigue vivo al cerrar (antes retenían el motor y podían escribir avisos tarde).
            for task in [hideTask, frozenTask, zoomToastTask, indicatorHideTask, skipChainTask, flashTask] { task?.cancel() }
            presentation.cancel()
        }
    }

}

/// Un toque con dos dedos (SwiftUI no lo trae): el reconocedor de UIKit dentro de los gestos de SwiftUI, así convive con el
/// doble toque, el pellizco y los arrastres del reproductor.
struct TwoFingerTap: UIGestureRecognizerRepresentable {
    let action: () -> Void
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.numberOfTouchesRequired = 2
        tap.numberOfTapsRequired = 1
        return tap
    }
    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}

extension PlayerLayout {
    /// Las medidas del reproductor, de los tokens de diseño.
    static let app = PlayerLayout(topClearance: DS.PlayerPanel.portraitTopClearance, controlsReserve: DS.PlayerPanel.portraitControlsReserve,
                                  minAspect: DS.PlayerPanel.portraitMinAspect, wideAspect: DS.Poster.stillAspect,
                                  defaultCenter: Double(DS.PlayerPanel.portraitCenter), panelWidth: DS.PlayerPanel.width,
                                  panelShare: DS.PlayerPanel.widthShare)
}
