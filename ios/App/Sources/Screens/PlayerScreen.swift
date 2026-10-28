import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Guarda el motor y el modelo juntos (el motor se arma una sola vez por reproducción). Vive en un `@State`, que evalúa su
/// valor inicial en cada `init` de la vista: por eso el motor y el modelo se arman la primera vez que se piden, no al crearlo.
@MainActor
final class PlayerHolder {
    private var parts: (engine: VideoPlayerEngine, model: PlayerModel)?

    var engine: VideoPlayerEngine { built.engine }
    /// La vista que lee el modelo mientras se pinta se vuelve a pintar con cada cambio suyo (Observation).
    var model: PlayerModel { let model = built.model; model.track(); return model }

    private var built: (engine: VideoPlayerEngine, model: PlayerModel) {
        if let parts { return parts }
        let made = Self.make()
        parts = made
        return made
    }

    private static func make() -> (engine: VideoPlayerEngine, model: PlayerModel) {
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
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Con VoiceOver los controles no se esconden solos (si no, no queda nada que tocar).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var holder = PlayerHolder()
    @State private var controlsVisible = true
    /// Cuándo fue el último toque de un dedo y el último de dos (para que uno de dos dedos no mueva también los controles).
    @State private var singleTapAt = Date.distantPast
    @State private var twoFingerTapAt = Date.distantPast
    /// «Bloquear» (como Netflix): sin controles y la pantalla no responde a toques ni deslizamientos (para no pausar o adelantar
    /// sin querer). Un toque enseña la cápsula de arriba con «Desbloquear».
    @State private var locked = false
    /// La cápsula de «Pantalla bloqueada» (arriba). `showsUnlock`: tras un toque, con el botón. `collapsed`: ya es el
    /// círculo del candado. `risen`: sube y se desvanece. `generation` descarta un cierre si llegó otro aviso.
    @State private var lockNoticeVisible = false
    @State private var lockNoticeShowsUnlock = false
    @State private var lockNoticeCollapsed = false
    @State private var lockNoticeRisen = false
    @State private var lockNoticeGeneration = 0
    @State private var unlockHide: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    /// El «⋯» de la barra horizontal abierto: mientras está, los controles no se esconden (si no, se cerraba solo).
    @State private var moreOpen = false
    /// «Descargar» desde el reproductor: si este video (película o episodio) ya está en Descargas (o se está bajando).
    @State private var inDownloads = false
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var scrubbing: Double?
    /// A dónde se pidió ir y el video todavía no llega.
    @State private var pendingSeek: Double?
    @AppStorage("scare-warnings") private var scareWarnings = true
    @State private var finished = false
    @State private var pip = PictureInPicture()
    @State private var nowPlaying = NowPlaying()
    /// En vertical, a qué altura va el video (lo mueves arrastrándolo; se recuerda) y su valor mientras arrastras.
    @AppStorage(PlayerScreen.portraitCenterKey) private var portraitCenter = Double(DS.PlayerPanel.portraitCenter)
    @State private var portraitDrag: Double?
    @State private var portraitAtDragStart: Double = 0
    /// «Modo iPod» (vertical): "" apagado, "white" o "black". Se queda para la próxima.
    @AppStorage("player-ipod") private var ipodFace = ""
    /// Girando la rueda del iPod: a dónde vas (se va al soltar) y cuándo fue la última muesca (rápido = de a minuto).
    @State private var wheelTarget: Double?
    /// De vuelta de segundo plano: el cuadro donde ibas, a la vista mientras el motor rearma el video (antes, negro y a esperar).
    @State private var frozenFrame: UIImage?
    @State private var frozenTask: Task<Void, Never>?
    /// Si la app está al frente. Un `@State` y no `scenePhase`: dentro de una tarea, `scenePhase` es una copia del momento
    /// en que empezó (se quedaba en «segundo plano» para siempre y el cuadro guardado no se quitaba).
    @State private var appActive = true
    @State private var lastNotch: Date?
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    /// El zoom de cada sentido: el de horizontal se recuerda (Ajustes); el de vertical arranca siempre en el cuadro completo. Antes
    /// era uno solo y al volver de horizontal con «Llenar» el video quedaba en vertical a pantalla completa, recortado.
    @State private var landscapeZoom: VideoZoom = .fit
    @State private var portraitZoom: VideoZoom = .fit
    /// Cuándo cambió el sentido: un pellizco que termina justo después (los pulgares al girar) no cuenta.
    @State private var rotatedAt = Date.distantPast
    private var zoom: VideoZoom { landscape ? landscapeZoom : portraitZoom }
    @State private var zoomToast: VideoZoom?
    /// «Subtítulos desactivados» o «Español · 1 de 4», un momento, al apagar o prender con el botón.
    @State private var subtitleToast: String?
    /// Lo que pasó al pedir «Descargar» (el mismo aviso que en el resto de la app, arriba: abajo están los controles).
    @State private var notice: PlayerNotice?
    /// Avisos que llegaron con la cápsula del candado en pantalla. Salen, en orden, cuando esa cápsula se va.
    @State private var heldNotices = HeldNotices<QueuedNotice>()
    @State private var heldDrain: Task<Void, Never>?
    @State private var heldDrainGeneration = 0
    struct PlayerNotice: Equatable {
        var title: String, detail: String?, tone: DSNotice.Tone
        var showsDownloads = false
        /// «Cambiar a latino»: otra versión que sí trae tu idioma (su índice), en el mismo segundo.
        var switchTo: Int? = nil
        var switchTitle: String? = nil
        let id = UUID()
    }
    /// Lo que espera turno. Subtítulos y zoom se quedan con el último; los demás, todos, en orden.
    private enum QueuedNotice {
        case player(PlayerNotice)
        case subtitle(String)
        case zoom(VideoZoom)
    }
    private enum QueuedNoticeKey: Hashable { case subtitle, zoom }
    /// Subtítulos rápidos (el panel chico sobre el video) y su lista de idiomas.
    @State private var subtitleDock = false
    /// La hoja «Audio y subtítulos» tiene dos páginas: lo de siempre y «Versión» (por idioma o todas las fuentes).
    enum DockPage { case media, version, episodes }
    @State private var dockPage: DockPage = .media
    /// Las temporadas de la serie que suena, para «Episodios» (se leen al abrirlo: son cientos de episodios).
    @State private var episodeSeasons: [Season] = []
    /// Viendo un archivo descargado, los episodios que también están bajados (los demás no se pueden poner).
    @State private var playableEpisodes: Set<String>?
    @State private var dockOpens: SubtitleDock.Section? = .subtitles
    @State private var versionShowsAll = false
    /// Una versión que Real-Debrid aún no tiene: se pregunta antes de abrirla (puede tardar o no abrir).
    @State private var slowPick: Int?
    /// Lo que mide la hoja (para que en vertical ocupe lo suyo y, si no cabe, se recorra).
    @State private var dockLanguages = false
    /// «Todas las versiones» desde el panel chico: media hoja (el video sigue a la vista arriba).
    @State private var dockVersions = false
    /// «Sincronizar con una línea»: las frases congeladas (nil: no está abierto), la que tocaste y el ajuste que quedó.
    @State private var syncLines: [SubtitleLine]?
    @State private var syncPicked: Double?
    @State private var syncResult: Double?
    @State private var zoomToastTask: Task<Void, Never>?
    /// Cuántas veces se ha visto «Arrastra para mover» junto a la agarradera (se deja de decir después de unas pocas).
    @AppStorage("player-move-hint-seen") private var moveHintSeen = 0
    /// En esta función se dice (se decide al abrir, para que no aparezca y desaparezca a media película).
    /// En vertical, este arrastre mueve el video (empezó en la agarradera o fuera del video); si no, es brillo o volumen.
    @State private var movingVideo = false

    // MARK: gestos como Infuse (brillo, volumen, buscar arrastrando, 2×)
    @State private var dragAxis: GestureAxis = .undecided
    @GestureState private var dragging = false
    @State private var verticalKind: VerticalGesture?
    @State private var brightnessAtDragStart: Double = 1
    @State private var volumeAtDragStart: Double = 0
    @State private var originalBrightness: Double = 1
    @State private var requestedVolume: Float?
    @State private var indicator: (kind: VerticalGesture, symbol: String, value: Double)?
    /// Aparte de `indicator` (que se actualiza en cada punto del arrastre, sin animar) para que solo la entrada
    /// y la salida se animen; moverlo de golpe en cada cuadro se vería tembloroso.
    @State private var indicatorVisible = false
    @State private var indicatorHideTask: Task<Void, Never>?
    @State private var seekPositionAtDragStart: Double?
    @State private var seekPreview: Double?
    @State private var isFastForwarding = false
    /// ×2 fijo: deslizaste hacia abajo hasta que vibró; sigue al soltar y un toque en la píldora lo quita.
    @State private var fastForwardLocked = false
    /// El dedo sigue puesto después de la pulsación larga (el ×2 dura lo que dure el dedo, como TikTok).
    @State private var fastForwardHolding = false
    /// El ×2 se quedó con este toque (aunque ya hayas deslizado hacia arriba para quitarlo): el arrastre del video no lo roba.
    @State private var fastForwardOwnsTouch = false
    /// Cómo estaba al empezar a mantener: si ya iba fijo, el aviso dice deslizar hacia arriba para quitarlo.
    @State private var fastForwardLockedAtStart = false
    @State private var fastForwardToggledThisHold = false
    /// Dónde empezó el toque (el ×2 es del lado derecho, como YouTube; hacia abajo se mide desde aquí).
    @State private var touchStartX: CGFloat?
    @State private var touchStartY: CGFloat?
    /// El ícono que aparece un momento al centro tras un doble toque (pausa, ±10 s).
    @State private var flashSymbol: String?
    /// Dobles toques en una orilla: cuántos segundos llevan sumados y de qué lado (la burbuja va de ese lado).
    @State private var skipChain: (forward: Bool, seconds: Int, at: Date)?
    @State private var skipChainTask: Task<Void, Never>?
    @State private var skipHaptic = 0
    @State private var skipEdgeHaptic = 0
    /// ×2: lo que lleva el anillo al deslizar hacia abajo, antes de quedarse fijo.
    @State private var fastForwardProgress: Double = 0
    @State private var flashTask: Task<Void, Never>?
    /// Lo que mide la tarjeta de «Siguiente episodio» (para subir los subtítulos sobre ella).
    @State private var upNextHeight: CGFloat = 0
    @State private var rateBeforeFastForward: Float = 1

    /// Lo que suena ahora: cambia al pasar solo al siguiente episodio (el `request` es solo con el que se abrió).
    private var current: PlayRequest { holder.model.request ?? request }
    @State private var ambientURL: URL?
    @State private var knownAspect: Double?
    /// El alto que pide «Audio y subtítulos» en vertical (para subir el video lo justo y que quepa sin desplazarse).
    @State private var dockNeed: CGFloat = 0
    /// Lo que enseña el botón grande: la carga o el play. Al abrir, la carga hasta que el video de verdad suena (antes parpadeaba
    /// el play entre dos estados de carga); ya sonando, solo si se atora más de un momento (antes, al pausar o seguir, salía la
    /// carga un segundo).
    @State private var loadingShown = true
    @State private var loadingTask: Task<Void, Never>?
    @State private var playedVideo: String?
    /// Lo que dice el botón grande (pausa o play): lo que tú pediste. Al tocarlo cambia al momento; si el motor se detiene o
    /// sigue solo, solo cambia si dura (al arrancar se detiene un instante para sus ajustes y el botón brincaba play → pausa → play).
    @State private var glyphPlaying = true
    @State private var glyphTask: Task<Void, Never>?
    @State private var playedAt = Date.distantPast

    var body: some View {
        let model = holder.model
        ZStack {
            if let face = ipod { Rectangle().fill(face.body).ignoresSafeArea() } else { DS.video.ignoresSafeArea() }
            if !landscape && !fillsPortrait && ipod == nil { ambientLayer }
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
            let controlsShown = controlsVisible && !locked && !failed(model) && !subtitleDock && ipod == nil
            if controlsShown { controls(model).transition(.opacity) }
            // ±10 y el botón grande, siempre al centro del video (en vertical también, encima de la imagen): el mismo punto donde
            // está la imagen del episodio al abrir y donde se ve la carga.
            if transportShown(model) {
                GeometryReader { geo in
                    let rect = videoRect(in: geo.size)
                    transport(model).position(x: rect.midX, y: rect.midY)
                }
                .ignoresSafeArea(edges: landscape ? .all : [])
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
            engine.setZoom(zoom)
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
        .task(id: current.videoID) { knownAspect = nil; await loadAmbient(); await loadLocalizedEpisodes() }
        .onChange(of: loadingKind(model), initial: true) { _, kind in updateLoading(kind, model) }
        .onChange(of: model.snapshot.state == .playing, initial: true) { _, playing in followEngineGlyph(playing, model) }
        // Al girar, cada sentido con su zoom; y otra vez cuando termina la animación del giro (el motor del iPhone a veces se
        // quedaba con el «Llenar» de horizontal y la imagen seguía agrandada en vertical).
        .onChange(of: landscape) {
            rotatedAt = Date()
            // Vertical vuelve siempre al cuadro completo al girar: si algo puso «Recortar» sin querer (un pellizco al sujetar el
            // teléfono), el giro lo deshace.
            portraitZoom = .fit
            holder.engine.setZoom(zoom)
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
        }
    }

    // MARK: bloquear
    /// Bloqueado: todo toque solo enseña la cápsula; nada pausa, adelanta ni mueve el video, y el giro se congela
    /// en la orientación de ese momento (girar el teléfono no voltea el video).
    /// El aviso va arriba, dentro del área segura, en los dos sentidos: nunca tapa el centro del video.
    private var lockLayer: some View {
        ZStack {
            // Cualquier toque (o arrastre) trae la cápsula con «Desbloquear».
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showUnlockPrompt() }
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in showUnlockPrompt() })
                .accessibilityHidden(true)
            if lockNoticeVisible {
                VStack {
                    PlayerLockNotice(showsUnlock: lockNoticeShowsUnlock, collapsed: lockNoticeCollapsed, risen: lockNoticeRisen, unlock: unlock)
                    Spacer(minLength: 0)
                }
                .padding(.top, DS.Space.s2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func lock() {
        hideTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; locked = true }
        freezeOrientation()
        showLockNotice(withUnlock: false)
    }

    private func showUnlockPrompt() { showLockNotice(withUnlock: true) }

    /// La cápsula de arriba. Al bloquear dura un instante y no trae botón; un toque la trae con «Desbloquear» y se queda más.
    /// Luego se encoge al candado, sube y se desvanece (con «Reducir movimiento», solo se desvanece).
    private func showLockNotice(withUnlock: Bool) {
        // Primero se retiene: lo que llegue a partir de aquí espera. Lo que ya se veía arriba se quita.
        heldNotices.hold()
        cancelHeldDrain()
        clearTopNotices()
        lockNoticeGeneration += 1
        let generation = lockNoticeGeneration
        lockNoticeShowsUnlock = withUnlock
        withAnimation(DS.Motion.lockNoticeIn()) {
            lockNoticeCollapsed = false
            lockNoticeRisen = false
            lockNoticeVisible = true
        }
        unlockHide?.cancel()
        unlockHide = Task { @MainActor in
            try? await Task.sleep(nanoseconds: withUnlock ? DS.Timing.unlockPrompt : DS.Timing.lockNotice)
            guard !Task.isCancelled, generation == lockNoticeGeneration else { return }
            await dismissLockNotice(generation: generation)
        }
    }

    private func dismissLockNotice(generation: Int) async {
        if reduceMotion {
            withAnimation(DS.Motion.lockRise(true)) { lockNoticeRisen = true }
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Motion.base * 1_000_000_000))
        } else {
            withAnimation(DS.Motion.lockShrink(false)) { lockNoticeCollapsed = true }
            try? await Task.sleep(nanoseconds: DS.Timing.lockNoticeShrink)
            guard !Task.isCancelled, generation == lockNoticeGeneration else { return }
            withAnimation(DS.Motion.lockRise(false)) { lockNoticeRisen = true }
            try? await Task.sleep(nanoseconds: DS.Timing.lockNoticeRise)
        }
        guard !Task.isCancelled, generation == lockNoticeGeneration else { return }
        lockNoticeVisible = false
        lockNoticeCollapsed = false
        lockNoticeRisen = false
        lockNoticeShowsUnlock = false
        flushHeldNotices()
    }

    /// Lo que ya está arriba (toast, subtítulos, zoom) se quita: el candado no se apila con ello.
    /// Lo que llegue mientras la cápsula sigue en pantalla no se tira: queda en `heldNotices`.
    private func clearTopNotices() {
        zoomToastTask?.cancel()
        notice = nil
        subtitleToast = nil
        zoomToast = nil
    }

    private func unlock() {
        unlockHide?.cancel()
        lockNoticeGeneration += 1
        lockNoticeVisible = false
        lockNoticeCollapsed = false
        lockNoticeRisen = false
        lockNoticeShowsUnlock = false
        withAnimation(DS.Motion.base(reduceMotion)) { locked = false; controlsVisible = true }
        AppDelegate.orientations = .allButUpsideDown; refreshSupportedOrientations()
        scheduleHide()
        flushHeldNotices()
    }

    /// La cápsula del candado está en pantalla, o todavía salen los avisos que esperaron detrás de ella.
    private var topNoticesAreWaiting: Bool {
        heldNotices.isHolding || !heldNotices.isEmpty || heldDrain?.isCancelled == false
    }

    private func cancelHeldDrain() {
        heldDrainGeneration += 1
        heldDrain?.cancel()
        heldDrain = nil
    }

    /// La cápsula ya se fue (se encogió, o se desbloqueó): los avisos que esperaron salen uno tras otro,
    /// cada uno el tiempo de siempre. Si el candado vuelve antes de vaciar la cola, lo que falta se queda.
    private func flushHeldNotices() {
        heldNotices.resume()
        guard !heldNotices.isEmpty else { return }
        if let heldDrain, !heldDrain.isCancelled { return }
        heldDrainGeneration += 1
        let generation = heldDrainGeneration
        heldDrain?.cancel()
        heldDrain = Task { @MainActor in
            while !Task.isCancelled, !heldNotices.isHolding, !lockNoticeVisible {
                guard let item = heldNotices.next() else { break }
                await presentHeld(item)
            }
            guard generation == heldDrainGeneration, !Task.isCancelled else { return }
            heldDrain = nil
            if !heldNotices.isEmpty, !heldNotices.isHolding, !lockNoticeVisible {
                flushHeldNotices()
            }
        }
    }

    /// Muestra un aviso que estaba en espera. VoiceOver se entera aquí, cuando de verdad aparece.
    private func presentHeld(_ item: QueuedNotice) async {
        switch item {
        case .player(let new):
            zoomToastTask?.cancel()
            withAnimation(DS.Motion.base(reduceMotion)) { subtitleToast = nil; zoomToast = nil }
            reveal(new)
            try? await Task.sleep(nanoseconds: Toast.duration(new.tone, hasAction: new.showsDownloads || new.switchTo != nil) ?? DS.Timing.toastAction)
        case .subtitle(let text):
            zoomToastTask?.cancel()
            withAnimation(DS.Motion.base(reduceMotion)) { notice = nil; zoomToast = nil }
            await revealSubtitle(text)
        case .zoom(let target):
            withAnimation(DS.Motion.base(reduceMotion)) { notice = nil; subtitleToast = nil }
            await revealZoom(target)
        }
    }

    private func revealZoom(_ target: VideoZoom) async {
        withAnimation(DS.Motion.base(reduceMotion)) { zoomToast = target }
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { if zoomToast == target { zoomToast = nil } }
    }

    // MARK: gestos
    private func gestureLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            // Un solo doble toque en toda la pantalla (también en lo negro de arriba y abajo) y lo que hace depende de dónde:
            // tercio izquierdo −10 s, centro pausa o sigue, tercio derecho +10 s. Antes cada zona tenía su gesto y a veces el
            // toque caía en otra capa.
            Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                let third = geo.size.width * DS.Gesture.edgeShare
                // Si ya venías sumando de ese lado, el doble toque cuenta como dos toques (+20 s).
                if location.x < third { skip(model, forward: false, taps: 2) }
                else if location.x > geo.size.width - third { skip(model, forward: true, taps: 2) }
                else { userTogglePlay(model); flash(model.snapshot.state == .playing ? "pause.fill" : "play.fill") }
            }
            .onTapGesture { location in
                // Tras un doble toque en una orilla, cada toque sencillo del mismo lado suma otros 10 s (como YouTube).
                if let forward = continuesSkip(at: location, width: geo.size.width) { skip(model, forward: forward); return }
                // Con los subtítulos rápidos abiertos, tocar el video los cierra (y nada más).
                if subtitleDock { withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false }; return }
                // Un toque con dos dedos también puede contar como toque: ese no mueve los controles.
                if Date().timeIntervalSince(twoFingerTapAt) < DS.Gesture.twoFingerTapGuard { return }
                singleTapAt = Date()
                controlsVisible.toggle(); if controlsVisible { scheduleHide() }
            }
            // Tocar con dos dedos, en cualquier parte: pausa o sigue (como en Infuse y en la app TV de Apple).
            .gesture(TwoFingerTap {
                twoFingerTapAt = Date()
                // Si el mismo toque ya alcanzó a contar como uno de un dedo, se deshace lo que hizo con los controles.
                if Date().timeIntervalSince(singleTapAt) < DS.Gesture.twoFingerTapGuard { controlsVisible.toggle(); singleTapAt = .distantPast }
                userTogglePlay(model)
                flash(model.snapshot.state == .playing ? "pause.fill" : "play.fill")
            })
            .gesture(MagnifyGesture().onEnded { value in
                // Abrir los dedos llena la pantalla; cerrarlos vuelve al cuadro completo (como la app TV de Apple).
                // Un pellizco que termina en el segundo siguiente al giro es el agarre, no una orden.
                guard Date().timeIntervalSince(rotatedAt) > DS.Gesture.pinchAfterRotationGuard,
                      let target = VideoZoom.pinched(magnification: Double(value.magnification)), target != zoom else { return }
                setZoom(target)
            })
            .sensoryFeedback(.impact, trigger: zoom)
            .simultaneousGesture(dragGesture(model, size: geo.size))
            .onChange(of: dragging) { _, now in
                // Un arrastre cancelado (sin `onEnded`): se limpia todo sin buscar ni mover nada. Un momento después, para que
                // un arrastre normal termine primero con `onEnded` (que sí busca) y aquí ya no haya nada que limpiar.
                guard !now else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !dragging, dragAxis != .undecided || seekPreview != nil || portraitDrag != nil else { return }
                    portraitDrag = nil; movingVideo = false
                    dragAxis = .undecided; verticalKind = nil; seekPositionAtDragStart = nil; seekPreview = nil
                    scheduleIndicatorHide()
                    if controlsVisible { scheduleHide() }
                }
            }
            // Dónde empieza el dedo, sin quitarle nada a los demás gestos.
            // Y cuándo lo levantas de verdad: el `onPressingChanged` de la pulsación larga avisa «ya no» en cuanto la reconoce
            // (no al soltar), y el ×2 se prendía y se apagaba casi a la vez.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                if touchStartX == nil { touchStartX = value.startLocation.x; touchStartY = value.startLocation.y }
                if fastForwardHolding { fastForwardDrag(translationY: value.translation.height, screenHeight: geo.size.height, model: model) }
            }.onEnded { _ in touchStartX = nil; touchStartY = nil; releaseFastForward(model) })
            // ×2 del lado derecho: casi al instante. Hacia abajo se fija (vibra); hacia arriba se quita al momento.
            // Simultánea: como gesto normal competía con los dobles toques de las orillas y casi nunca ganaba.
            .simultaneousGesture(LongPressGesture(minimumDuration: DS.Timing.fastForwardStart, maximumDistance: DS.Gesture.axisThreshold)
                .onEnded { _ in if (touchStartX ?? geo.size.width) >= geo.size.width / 2 { holdFastForward(model) } })
            .sensoryFeedback(.impact, trigger: isFastForwarding)
            .sensoryFeedback(.impact(weight: .light), trigger: skipHaptic)
            .sensoryFeedback(.impact(weight: .heavy), trigger: skipEdgeHaptic)
            .sensoryFeedback(.success, trigger: fastForwardLocked)
        }
        .accessibilityHidden(true)
    }

    /// Brillo (mitad izquierda), volumen (mitad derecha) o buscar (cualquier zona), según el eje que gane los
    /// primeros puntos del arrastre. Mientras tanto no se toca si se muestran o se esconden los controles (ni a
    /// medias ni de golpe): el reloj que los esconde solo se reanuda al soltar.
    private func dragGesture(_ model: PlayerModel, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: DS.Gesture.axisThreshold)
            // Vuelve a false sola si iOS cancela el arrastre (otro gesto, una llamada, el centro de control): ahí `onEnded`
            // no llega y la burbuja de buscar se quedaba pegada en pantalla. Ver `.onChange(of: dragging)`.
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                // Con el ×2 puesto, deslizar fija o quita: ni brillo, ni volumen, ni mover el video (aunque el dedo
                // haya empezado en la agarradera). Si el video ya se había movido, se deshace.
                if fastForwardOwnsTouch { cancelVideoMove(); return }
                let dx = Double(value.translation.width), dy = Double(value.translation.height)
                if dragAxis == .undecided {
                    hideTask?.cancel()
                    dragAxis = PlayerGestures.dominantAxis(dx: dx, dy: dy)
                    switch dragAxis {
                    // En vertical: arrastrar sobre el video es brillo (izquierda) o volumen (derecha), como en horizontal y en
                    // Infuse; desde la agarradera de abajo o lo negro de fuera, mueve el video (antes todo arrastre lo movía y
                    // se perdían el brillo y el volumen).
                    // Con un panel abierto (Episodios, Audio y subtítulos) el video no se mueve: el panel cuelga de él y se movía
                    // al arrastrar entre las pastillas de temporada.
                    case .vertical where !subtitleDock && (!landscape && !fillsPortrait && ipod == nil
                                          && !videoRect(in: size).insetBy(dx: 0, dy: -DS.PlayerPanel.handleReach).contains(value.startLocation)
                                          || startsOnHandle(value.startLocation, size: size)):
                        movingVideo = true
                        portraitAtDragStart = Self.resolvedCenter(portraitCenter, in: size, aspect: portraitAspect)   // en vertical, arrastrar arriba o abajo mueve el video
                        controlsVisible = true                 // se mueve a la altura de los controles (sin ellos va al centro)
                    case .vertical:
                        let kind = PlayerGestures.verticalGesture(startX: Double(value.startLocation.x), screenWidth: Double(size.width))
                        verticalKind = kind
                        if kind == .brightness { brightnessAtDragStart = Double(UIScreen.main.brightness) }
                        else { volumeAtDragStart = Double(AVAudioSession.sharedInstance().outputVolume) }
                    case .horizontal:
                        seekPositionAtDragStart = model.snapshot.position
                        controlsVisible = true   // se ve la barra: el pulgar sigue el tiempo destino mientras arrastras
                    case .undecided: break
                    }
                }
                switch dragAxis {
                case .vertical where movingVideo:
                    // Libre, entre lo más arriba y lo más abajo que puede ir.
                    let limits = Self.portraitLimits(in: size, aspect: portraitAspect)
                    portraitDrag = min(max(portraitAtDragStart + dy / Double(size.height), limits.lowerBound), limits.upperBound)
                case .vertical:
                    guard let kind = verticalKind else { return }
                    let start = kind == .brightness ? brightnessAtDragStart : volumeAtDragStart
                    let value2 = PlayerGestures.verticalValue(start: start, dragHeight: dy, screenHeight: Double(size.height))
                    if kind == .brightness { UIScreen.main.brightness = CGFloat(value2) } else { requestedVolume = Float(value2) }
                    indicator = (kind, kind == .brightness ? "sun.max.fill" : "speaker.wave.2.fill", value2)
                    if !indicatorVisible { indicatorHideTask?.cancel(); withAnimation(DS.Motion.base(reduceMotion)) { indicatorVisible = true } }
                case .horizontal:
                    guard let start = seekPositionAtDragStart else { return }
                    seekPreview = PlayerGestures.seekTarget(startPosition: start, duration: model.snapshot.duration, dragWidth: dx, screenWidth: Double(size.width))
                    if let target = seekPreview { model.scrub(to: target) }
                case .undecided: break
                }
            }
            .onEnded { _ in
                // El ×2 se quedó con el toque: no se confirma el movimiento del video.
                if fastForwardOwnsTouch { cancelVideoMove(); dragAxis = .undecided; verticalKind = nil; seekPositionAtDragStart = nil; seekPreview = nil; return }
                // Se queda donde lo sueltas (sin imanes).
                if let moved = portraitDrag { withAnimation(DS.Motion.base(reduceMotion)) { portraitCenter = moved; portraitDrag = nil; movingVideo = false } }
                movingVideo = false
                if dragAxis == .horizontal, let target = seekPreview { pendingSeek = target; Task { await model.seek(to: target) } }
                dragAxis = .undecided; verticalKind = nil; seekPositionAtDragStart = nil; seekPreview = nil
                scheduleIndicatorHide()
                if controlsVisible { scheduleHide() }
            }
    }

    @ViewBuilder private var gestureOverlays: some View {
        if indicatorVisible, let indicator {
            // Antes iba centrado en toda la pantalla: en vertical caía debajo del video, encima de la barra de avance, y en
            // horizontal casi la tocaba. Ahora: en vertical, a media altura del video y de su tamaño; en horizontal, entre la
            // barra de arriba y la de avance.
            GeometryReader { geo in
                let place = indicatorPlacement(in: geo.size)
                HStack {
                    if indicator.kind == .brightness { DSGestureIndicator(symbol: indicator.symbol, value: indicator.value, barHeight: place.bar); Spacer() }
                    else { Spacer(); DSGestureIndicator(symbol: indicator.symbol, value: indicator.value, barHeight: place.bar) }
                }
                .padding(.horizontal, landscape ? DS.Gesture.indicatorInsetLandscape : DS.Gesture.indicatorInsetPortrait)
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: place.y)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
        if dragAxis == .horizontal, let target = seekPreview, let start = seekPositionAtDragStart {
            seekBubble(target: target, start: start)
        }
        if let notice, !lockNoticeVisible {
            VStack {
                Toast(tone: notice.tone, title: Text(verbatim: notice.title), detail: notice.detail.map { Text(verbatim: $0) },
                      actionTitle: notice.switchTitle.map { LocalizedStringKey($0) } ?? (notice.showsDownloads ? "Ver" : nil),
                      action: notice.switchTo.map { index in { Task { await holder.model.switchSource(to: index) } } }
                        ?? (notice.showsDownloads ? { Task { await close(); env.openTab = AppEnvironment.downloadsTab } } : nil),
                      seconds: Toast.duration(notice.tone, hasAction: notice.showsDownloads || notice.switchTo != nil) ?? DS.Timing.toastAction,
                      dismiss: { withAnimation(DS.Motion.base(reduceMotion)) { if self.notice?.id == notice.id { self.notice = nil } } })
                    .id(notice.id)
                Spacer()
            }
            // Bajo la barra de arriba con aire (antes quedaba pegado a ella).
            .padding(.top, DS.Space.s14 + DS.Space.s4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let subtitleToast, !lockNoticeVisible {
            VStack { DSToastPill(text: LocalizedStringKey(subtitleToast)); Spacer() }.padding(.top, DS.Space.s14)
                .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
        }
        if let zoomToast, !lockNoticeVisible {
            // Siempre se ve: en horizontal arriba; en vertical sobre el video (arriba lo tapaba la barra), y si el modo no
            // cambia nada en vertical, lo dice.
            if landscape {
                VStack { DSToastPill(text: LocalizedStringKey(zoomToast.title)); Spacer() }.padding(.top, DS.Space.s14)
                    .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
            } else {
                GeometryReader { geo in
                    let rect = videoRect(in: geo.size)
                    DSToastPill(text: LocalizedStringKey(zoomToast.title), detail: zoomToast == .fill ? Text("Llena la pantalla y recorta los lados")
                                : zoomToast == .stretch ? Text("Llena la pantalla deformando la imagen") : nil)
                        .position(x: rect.midX, y: rect.midY)
                }
                .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        if let chain = skipChain {
            // La onda en media luna desde la orilla que tocaste, con flechas y lo que llevas sumado («+30 s»), como YouTube.
            GeometryReader { geo in
                let rect = videoRect(in: geo.size)
                let side = rect.width * DS.Gesture.edgeShare
                SkipRipple(forward: chain.forward, seconds: chain.seconds)
                    .frame(width: side, height: rect.height)
                    .position(x: chain.forward ? rect.maxX - side / 2 : rect.minX + side / 2, y: rect.midY)
            }
            .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
        }
        if let flashSymbol, !controlsVisible {
            Image(systemName: flashSymbol).font(DS.TextRecipe.display.font).foregroundStyle(DS.text)
                .frame(width: DS.Size.touchTarget * 2, height: DS.Size.touchTarget * 2)
                .glassEffect(.regular, in: Circle())
                .transition(.scale.combined(with: .opacity)).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// La burbuja de buscar, justo encima de la barra de avance, en la x del tiempo destino (sin salirse de los bordes).
    private func seekBubble(target: Double, start: Double) -> some View {
        let delta = target - start
        let duration = max(holder.model.snapshot.duration, 1)
        return GeometryReader { geo in
            let fraction = CGFloat(max(0, min(1, target / duration)))
            let rawX = DS.Space.gutter + (geo.size.width - DS.Space.gutter * 2) * fraction
            let x = min(max(rawX, DS.Gesture.seekBubbleSideMargin), geo.size.width - DS.Gesture.seekBubbleSideMargin)
            // En vertical, dentro del borde de abajo del video, justo encima de la barra (antes flotaba en lo negro del pie).
            let y = landscape || fillsPortrait || ipod != nil ? geo.size.height - DS.Gesture.seekBubbleBottomInset
                : videoRect(in: geo.size).maxY - DS.Gesture.seekBubblePortraitLift
            DSSeekBubble(time: clock(target), delta: "\(delta >= 0 ? "+" : "−")\(clock(abs(delta)))")
                .position(x: x, y: y)
        }
        .transition(.opacity).allowsHitTesting(false)
    }

    private func scheduleIndicatorHide() {
        indicatorHideTask?.cancel()
        indicatorHideTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { indicatorVisible = false }
        }
    }

    /// La píldora «2×» se ve mientras mantienes el dedo y, si quedó fija, cuando hay controles. Bloqueada la pantalla, no.
    private var speedPillVisible: Bool { isFastForwarding && (fastForwardHolding || controlsVisible) && !locked }

    /// Abajo al centro. Horizontal: justo encima de la barra. Vertical: al pie del área segura, salvo «Recortar» con
    /// controles, que va encima de su barra.
    private var speedPillBottomInset: CGFloat {
        if landscape { return DS.Gesture.fastForwardPillBottomInset }
        if fillsPortrait && controlsVisible { return DS.Gesture.fastForwardPillFillInset }
        return DS.Space.s2
    }

    private var speedPill: some View {
        VStack {
            Spacer(minLength: 0)
            Button { if !fastForwardHolding { endFastForward(holder.model, force: true) } } label: {
                DSSpeedPill(locked: fastForwardLocked, progress: fastForwardProgress, holding: fastForwardHolding,
                            unlocks: fastForwardLockedAtStart)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, speedPillBottomInset)
    }

    /// El arrastre del video en vertical no se queda con el toque del ×2.
    private func cancelVideoMove() {
        portraitDrag = nil
        movingVideo = false
        if dragAxis == .vertical { dragAxis = .undecided; verticalKind = nil }
    }

    /// ×2 como TikTok: mantener el dedo lo pone mientras dure. Hacia abajo se fija; hacia arriba vuelve a la velocidad previa.
    private func holdFastForward(_ model: PlayerModel) {
        if movingVideo { cancelVideoMove() }
        guard dragAxis == .undecided else { return }
        fastForwardOwnsTouch = true
        fastForwardHolding = true
        fastForwardLockedAtStart = fastForwardLocked
        fastForwardToggledThisHold = false
        fastForwardProgress = 0
        hideTask?.cancel()
        // En vertical (sin «Recortar») la pantalla queda limpia mientras el dedo sigue puesto.
        if !landscape && !fillsPortrait {
            withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false }
        }
        guard !isFastForwarding else { return }   // ya iba fijo: mantener solo deja deslizar para quitarlo
        rateBeforeFastForward = model.rate
        withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = true }
        Task { await model.setRate(PlaybackRules.fastForwardRate) }
    }

    /// Hacia abajo llena el anillo y, al completar la distancia, fija el ×2 (vibra). Hacia arriba lo quita al momento.
    /// La distancia hacia abajo se acorta si el dedo empezó cerca del borde, pero no baja de `fastForwardLockDragMin`.
    private func fastForwardDrag(translationY: CGFloat, screenHeight: CGFloat, model: PlayerModel) {
        guard fastForwardHolding else { return }
        let down = max(0, translationY)
        let up = max(0, -translationY)
        if up >= DS.Gesture.fastForwardLockDrag {
            fastForwardHolding = false
            fastForwardProgress = 0
            endFastForward(model, force: true)
            return
        }
        let room = max(0, screenHeight - (touchStartY ?? 0))
        let distance = CGFloat(PlayerGestures.fastForwardLockDistance(
            roomBelow: Double(room), preferred: Double(DS.Gesture.fastForwardLockDrag), minimum: Double(DS.Gesture.fastForwardLockDragMin)))
        guard distance > 0 else { return }
        fastForwardProgress = Double(min(1, down / distance))
        guard down >= distance, !fastForwardToggledThisHold else { return }
        fastForwardToggledThisHold = true
        withAnimation(DS.Motion.base(reduceMotion)) { fastForwardLocked = true }
    }

    /// Al soltar: si quedó fijo sigue en ×2 (y la píldora se va con los controles); si no, vuelve a la velocidad de antes.
    private func releaseFastForward(_ model: PlayerModel) {
        let wasHolding = fastForwardHolding
        fastForwardHolding = false
        fastForwardOwnsTouch = false
        fastForwardProgress = 0
        if wasHolding, !fastForwardLocked { endFastForward(model, force: true) }
        if controlsVisible { scheduleHide() }
    }

    private func endFastForward(_ model: PlayerModel, force: Bool = false) {
        guard isFastForwarding, force || !fastForwardLocked else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = false; fastForwardLocked = false }
        fastForwardProgress = 0
        Task { await model.setRate(rateBeforeFastForward) }
    }

    #if DEBUG
    /// Para `-demo-gesture`: pone el indicador a medio camino sin tocar la pantalla, para capturarlo en el simulador.
    /// `fastforward-locked` deja el ×2 fijo, con la píldora y los controles a la vista.
    private func simulateGesture(_ kind: String, model: PlayerModel) {
        switch kind {
        case "brightness": verticalKind = .brightness; indicator = (.brightness, "sun.max.fill", 0.65); indicatorVisible = true
        case "volume": verticalKind = .volume; indicator = (.volume, "speaker.wave.2.fill", 0.4); indicatorVisible = true
        case "seek": dragAxis = .horizontal; seekPositionAtDragStart = model.snapshot.position; seekPreview = model.snapshot.position + 80
        case "fastforward": holdFastForward(model)
        case "controls": hideTask?.cancel(); controlsVisible = true
        case "skip": skip(model, forward: true); skip(model, forward: true); skip(model, forward: true); skipChainTask?.cancel()
        case "fastforward-locked":
            hideTask?.cancel()
            rateBeforeFastForward = model.rate
            fastForwardLocked = true
            fastForwardHolding = false
            fastForwardOwnsTouch = false
            fastForwardLockedAtStart = true
            fastForwardProgress = 0
            withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = true; controlsVisible = true }
            Task { await model.setRate(PlaybackRules.fastForwardRate) }
        default: break
        }
    }
    #endif

    private func pulse() { controlsVisible = true; scheduleHide() }

    /// Cambia el zoom (botón o pellizco), lo recuerda para la próxima vez y avisa un momento cuál quedó.
    private func setZoom(_ target: VideoZoom) {
        let queueToast = topNoticesAreWaiting
        if queueToast { heldNotices.hold(.zoom(target), key: QueuedNoticeKey.zoom) }
        withAnimation(DS.Motion.base(reduceMotion)) {
            if landscape { landscapeZoom = target } else { portraitZoom = target }
            if !queueToast { zoomToast = target }
        }
        holder.engine.setZoom(target)
        if landscape { env.services.settings.update { $0.videoZoom = target.rawValue } }   // el de vertical no se guarda
        guard !queueToast else { return }
        zoomToastTask?.cancel()
        zoomToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { if zoomToast == target { zoomToast = nil } }
        }
    }

    /// Doble toque en una orilla: ±10 s. Mientras la onda sigue a la vista (`DS.Gesture.skipChain`), cada toque más del mismo lado
    /// (sencillo o doble) suma otros 10 s, siempre 10: así se sabe dónde vas a caer (antes cada toque saltaba más, 10 → 20 → 40…).
    /// Vibra leve en cada suma y firme si llegas al principio o al final.
    private func skip(_ model: PlayerModel, forward: Bool, taps: Int = 1) {
        let now = Date()
        let chained = skipChain.map { $0.forward == forward && now.timeIntervalSince($0.at) < DS.Gesture.skipChain } ?? false
        let before = chained ? skipChain?.seconds ?? 0 : 0
        let step = PlaybackRules.skipSeconds * Double(chained ? taps : 1)
        withAnimation(DS.Motion.base(reduceMotion)) { skipChain = (forward, before + Int(step), now) }
        let target = model.snapshot.position + (forward ? step : -step)
        if target <= 0 || (model.snapshot.duration > 0 && target >= model.snapshot.duration) { skipEdgeHaptic += 1 } else { skipHaptic += 1 }
        Task { await model.skip(forward ? step : -step) }
        skipChainTask?.cancel()
        skipChainTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(DS.Gesture.skipChain))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { skipChain = nil }
        }
    }

    /// ¿Este toque sencillo sigue sumando? Sí si la onda de un salto sigue a la vista y tocaste el mismo lado.
    private func continuesSkip(at location: CGPoint, width: CGFloat) -> Bool? {
        guard let chain = skipChain, Date().timeIntervalSince(chain.at) < DS.Gesture.skipChain else { return nil }
        let third = width * DS.Gesture.edgeShare
        if chain.forward && location.x > width - third { return true }
        if !chain.forward && location.x < third { return false }
        return nil
    }

    /// Un ícono grande que aparece y se va (el doble toque se nota sin abrir los controles).
    private func flash(_ symbol: String) {
        flashTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { flashSymbol = symbol }
        flashTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { flashSymbol = nil }
        }
    }

    /// Dónde va el indicador de brillo o volumen (su centro a lo alto) y de qué largo es su barra, para que nunca toque la barra
    /// de avance.
    private func indicatorPlacement(in size: CGSize) -> (y: CGFloat, bar: CGFloat) {
        func bar(_ room: CGFloat) -> CGFloat { min(DS.Gesture.indicatorBarHeight, max(DS.Gesture.indicatorBarMin, room - DS.Gesture.indicatorChrome)) }
        if landscape {
            let top = DS.Space.s8, bottom = DS.Gesture.fastForwardPillBottomInset
            let room = max(0, size.height - top - bottom)
            return (top + room / 2, bar(room))
        }
        if fillsPortrait || ipod != nil { return (size.height / 2, DS.Gesture.indicatorBarHeight) }
        let rect = videoRect(in: size)
        return (rect.midY, bar(rect.height - DS.Space.s4))
    }

    /// La agarradera: una franja a lo ancho justo debajo del video (fácil de agarrar aunque la rayita sea chica).
    private func startsOnHandle(_ point: CGPoint, size: CGSize) -> Bool {
        guard !landscape, !fillsPortrait, ipod == nil else { return false }
        let rect = videoRect(in: size)
        return point.y >= rect.maxY - DS.PlayerPanel.handleGrab && point.y <= rect.maxY + DS.PlayerPanel.handleBelow
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
            // Con la barra de avance bajo el dedo, los controles no se esconden (se iría el slider a media búsqueda).
            if !Task.isCancelled, !voiceOver, !moreOpen, scrubbing == nil, holder.model.snapshot.state == .playing { controlsVisible = false }
        }
    }

    // MARK: estados
    @ViewBuilder private func statusOverlays(_ model: PlayerModel) -> some View {
        switch model.phase {
        // Volviendo a abrir el mismo video (al regresar a la app): solo la ruedita, sin letrero (antes «Reconectando…»).
        case .preparing where model.reconnecting: LoadingSpinner()
        // Abriendo o buscando versión: la misma animación, sin textos (antes la órbita decía qué complemento contestaba).
        case .preparing: LoadingSpinner()
        case .failed(let message):
            // Una pantalla por cada caso (sin fuentes, ninguna sirvió, sin red…), sobre los controles, que se esconden.
            PlayerFailureView(failure: model.failure ?? .sourceDied, isEpisode: model.request?.kind == "series",
                              retry: { Task { await model.retry() } },
                              infuse: model.source == nil ? nil : { Task { await openInInfuse() } },
                              close: { Task { await close() } })
                .accessibilityHint(Text(verbatim: env.message(message)))
        default:
            // Con o sin controles, la misma ruedita en el mismo lugar (antes, con controles, brincaba al botón grande).
            if loadingShown { LoadingSpinner() }
        }
    }

    /// «Latino · 1080p»: el idioma que va a sonar y la calidad de una versión. El idioma solo si la versión lo dice (o ya se
    /// comprobó): si nada lo dice, se suponía inglés y luego el archivo traía español («Elegimos Inglés» y sonaba latino).
    private func versionText(_ src: Source, _ model: PlayerModel) -> String {
        let ui = env.services.appSettings.uiLanguage
        let playing = Streams.playingLanguage(src, heardPrefs(model)).flatMap { AllSources.EvidenceKind($0.evidence) == .assumed ? nil : $0 }
        let language = playing.map { LanguageFlags.flagged(Streams.versionLanguageName($0.code, in: ui), $0.code) }
        return ([language].compactMap { $0 } + src.qualitySummary).joined(separator: " · ")
    }

    /// Los idiomas con que el reproductor elige la pista (`PlayerModel.loadVideo`): los de este título y, al continuar, el
    /// audio con que lo dejaste. Antes la órbita usaba los de Ajustes y podía decir un idioma y sonar otro.
    private func heardPrefs(_ model: PlayerModel) -> Preferences {
        let settings = env.services.appSettings
        guard let request = model.request else { return settings.preferences() }
        var prefs = env.services.titlePrefs.languages(for: request.metaID, settings: settings).prefs
        if !request.fromStart, let last = env.services.titlePrefs.lastChoice(metaID: request.metaID)?.audio?.language,
           let base = PlaybackRules.languageCode(last), !base.isEmpty, base != prefs.audio {
            prefs.audio = base
            prefs.spanish = ""
        }
        return prefs
    }

    /// La única animación de carga del reproductor (`DSLoader`), dentro del botón grande y al centro del video. Cuándo sale lo
    /// decide `loadingKind`.
    private struct LoadingSpinner: View {
        var body: some View {
            // El mismo botón grande con la carga dentro: con o sin controles se ve igual y en el mismo punto.
            PlayPauseButton(playing: false, loading: true) {}
                .accessibilityIdentifier("player-loading")
        }
    }

    /// Cuándo se ve la carga en el botón grande (una sola regla para todo el reproductor):
    /// - `now`: abriendo el video (hasta que suena por primera vez) o pidiéndolo otra vez (se cortó, o al volver a la app). Al
    ///   momento y sin asomar el play: ahí el play no haría nada.
    /// - `soon`: pediste que sonara y aún no avanza, o se atoró sonando. Solo si dura (un momento; más en los primeros segundos,
    ///   cuando el motor hace sus últimos ajustes): así pausar y seguir nunca enseñan la carga.
    /// - `none`: listo, o en pausa sin nada pendiente.
    enum LoadKind: Equatable { case none, soon, now }
    private func loadingKind(_ model: PlayerModel) -> LoadKind {
        if model.phase == .preparing || !model.hasPlayed || model.reconnecting { return .now }
        if model.awaitingPlayback { return .soon }
        if model.snapshot.state == .loading || model.snapshot.state == .buffering { return .soon }
        return .none
    }

    private func updateLoading(_ kind: LoadKind, _ model: PlayerModel) {
        loadingTask?.cancel()
        let video = current.videoID
        switch kind {
        case .none:
            loadingShown = false
            if model.snapshot.state == .playing && playedVideo != video { playedVideo = video; playedAt = Date() }
        case .now:
            loadingShown = true
        case .soon:
            let settling = playedVideo != video || Date().timeIntervalSince(playedAt) < DS.Timing.loadingSettleWindow
            loadingTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: settling ? DS.Timing.loadingSettleDelay : DS.Timing.quietSpinnerDelay)
                guard !Task.isCancelled else { return }
                loadingShown = true
            }
        }
    }

    /// Tocar play o pausa (botón, doble toque, dos dedos, el iPod o VoiceOver): el botón cambia ya, sin esperar al motor.
    private func userTogglePlay(_ model: PlayerModel) {
        glyphTask?.cancel()
        glyphPlaying = model.snapshot.state != .playing
        Task { await model.togglePlay() }
    }

    /// El motor cambió: el botón lo sigue solo si el cambio dura (`glyphSettle`), y entonces dice lo que de verdad pasa. Lo que
    /// tocaste ya se ve desde el toque; un parpadeo del motor en medio no lo mueve.
    private func followEngineGlyph(_ playing: Bool, _ model: PlayerModel) {
        glyphTask?.cancel()
        glyphTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: DS.Timing.glyphSettle)
            guard !Task.isCancelled else { return }
            glyphPlaying = model.snapshot.state == .playing
        }
    }

    private func failed(_ model: PlayerModel) -> Bool { if case .failed = model.phase { true } else { false } }

    /// ¿Se ven ±10 y el botón grande? Con los controles, ya con video (buscando versión no hacen nada).
    private func transportShown(_ model: PlayerModel) -> Bool {
        controlsVisible && !locked && !failed(model) && !subtitleDock && ipod == nil && model.phase != .preparing
    }

    // MARK: controles
    /// Una sola identidad en los dos sentidos («barra limpia»): arriba ✕, el nombre y el episodio, subtítulos, AirPlay y «⋯»
    /// (lo demás: audio y subtítulos, zoom, ventana, la TV, descargar y bloquear); la barra fina con las horas a los lados;
    /// ±10 (flecha en círculo) y el botón grande de vidrio; «Saltar intro», una cápsula sólida.
    /// Horizontal: arriba la barra de botones, al centro ±10 y el botón grande, abajo la barra con «Saltar intro» a su lado.
    /// Vertical: la barra pegada al video, «Saltar intro» debajo a la derecha, ±10 y el botón grande al centro de lo que queda
    /// y, al pie, cómo mover el video. Nada tapa la imagen ni los subtítulos.
    private func controls(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            if landscape {
                ZStack {
                    LinearGradient(colors: [DS.scrim, .clear, DS.scrim], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
                    topScrim
                    VStack(spacing: DS.Space.s3) {
                        topBar(model)
                        Spacer()
                        HStack(spacing: DS.Space.s3) {
                            if model.snapshot.duration > 0 { scrubber(model) } else { Spacer() }
                            nextEpisode(model)
                            skipIntro(model)
                        }
                    }
                    .padding(DS.Space.s6)
                }
            } else {
                let rect = videoRect(in: geo.size)
                ZStack(alignment: .top) {
                    topScrim
                    // Con el video a pantalla completa, los controles van encima: un velo abajo para que se lean.
                    if fillsPortrait {
                        LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
                    }
                    if !raisedPortrait(rect) { topBar(model).padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2) }
                    // Sin agarradera a la vista (se pidió quitarla): el video se sigue moviendo arrastrando desde su borde de abajo o
                    // desde lo negro. Para VoiceOver queda un elemento invisible con «Subir el video» y «Bajar el video».
                    if !fillsPortrait {
                        Color.clear
                            .frame(width: rect.width, height: DS.PlayerPanel.handleGrab)
                            .padding(.top, rect.maxY - DS.PlayerPanel.handleGrab)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityLabel(Text("Mover el video"))
                            .accessibilityHint(Text("Arrastra hacia arriba o hacia abajo"))
                            .accessibilityAction(named: Text("Subir el video")) { stepVideo(-1, size: geo.size) }
                            .accessibilityAction(named: Text("Bajar el video")) { stepVideo(1, size: geo.size) }
                            .accessibilityIdentifier("player-drag-hint")
                    }
                    VStack(spacing: DS.Space.s3) {
                        // «Siguiente episodio» entre el video y la barra (antes tapaba los controles).
                        if let up = model.upNext, !locked { upNextCard(model, up) }
                        if model.snapshot.duration > 0 { scrubber(model) }
                        // Su lugar está apartado aunque no salga: ±10 y el botón grande no brincan cuando aparece.
                        // Solo cuando hay algo que ofrecer: el botón grande ya va sobre el video, así que su lugar apartado sobraba
                        // (dejaba una franja negra vacía bajo la barra, más notoria con el video hasta arriba).
                        if offersSkipOrNext(model) {
                            HStack(spacing: DS.Space.s2) { Spacer(); nextEpisode(model); skipIntro(model) }.frame(minHeight: DS.Size.touchTarget)
                        }
                        // Con el video hasta arriba, la barra de ✕ y el nombre baja aquí.
                        if raisedPortrait(rect) { topBar(model).padding(.top, DS.Space.s4) }
                        if !fillsPortrait { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, fillsPortrait ? DS.Space.s8 : DS.Space.s4)
                    .padding(.top, fillsPortrait ? 0 : rect.maxY + DS.PlayerPanel.handleGap)
                    .frame(maxHeight: .infinity, alignment: fillsPortrait ? .bottom : .top)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }

    /// Vertical: detrás de todo, la imagen del episodio (o de la serie) muy difuminada y tenue, como el modo ambiente de YouTube:
    /// el color del video llega más allá del cuadro. Se apaga hacia abajo para que los controles se lean.
    @ViewBuilder private var ambientLayer: some View {
        if let url = ambientURL {
            RemoteImage(url: url, maxPoints: DS.PlayerPanel.ambientImage) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                        .blur(radius: DS.PlayerPanel.ambientBlur)
                        .opacity(DS.PlayerPanel.ambientOpacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, DS.video], startPoint: .center, endPoint: .bottom))
            .ignoresSafeArea()
            .allowsHitTesting(false).accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    /// Los nombres de los episodios en tu idioma (el mismo traductor que la ficha, ya en caché si vienes de ella): «Episodios» y
    /// «Siguiente episodio» dicen lo mismo que la ficha de la serie, no el inglés de Cinemeta.
    private func loadLocalizedEpisodes() async {
        let request = current
        guard request.kind == "series", let meta = request.meta else { return }
        let local = await env.services.localizer.meta(kind: "series", meta: meta)
        guard !Task.isCancelled else { return }
        holder.model.useLocalizedMeta(local, for: request.videoID)
        if !episodeSeasons.isEmpty {
            episodeSeasons = await Task.detached(priority: .userInitiated) { CinemetaParsing.seasons(local).filter { !$0.isSpecials } }.value
        }
    }

    /// La imagen del fondo ambiente: la del episodio si la ficha la trae; si no, el fondo de la serie (o película).
    private func loadAmbient() async {
        let request = current
        let meta = request.meta, videoID = request.videoID, metaID = request.metaID
        let still = await Task.detached(priority: .utility) { () -> String? in
            guard let meta else { return nil }
            return CinemetaParsing.seasons(meta).flatMap(\.episodes).first { $0.id == videoID }?.thumbnail
        }.value
        let text = still ?? (metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, metaID) : request.poster)
        ambientURL = text.flatMap(URL.init(string:))
    }

    /// El degradado oscuro de arriba: el nombre y el episodio se leen aunque el video sea claro.
    private var topScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DS.scrimStrong, DS.scrim, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: DS.PlayerPanel.topScrimHeight)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }

    /// La barra de arriba, igual en los dos sentidos: ✕, el nombre y el episodio, subtítulos, AirPlay y «⋯».
    private func topBar(_ model: PlayerModel) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            PlayerCircleButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                .accessibilityIdentifier("player-close")
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(current.displayTitle).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if !current.episodeLabel.isEmpty { Text(current.episodeLabel).recipe(.footnote).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
            // «Episodios», solo el ícono (en una serie): la lista de la temporada sin parar el video.
            if current.kind == "series", current.meta != nil {
                PlayerCircleButton(symbol: "rectangle.stack", label: "Episodios") { openEpisodes(model) }
                    .accessibilityIdentifier("player-episodes")
            }
            SubtitleButton(code: currentSubtitleCode(model), state: subtitleState(model), loading: model.loadingSubtitle,
                           open: { openDock(.subtitles) },
                           toggle: { toggleSubtitles(model) })
                .accessibilityIdentifier("player-next-subtitle")
            AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("AirPlay"))
            // Un globo propio (no un `Menu` del sistema): así se sabe cuándo está abierto y los controles no se esconden debajo de
            // él. Se dibuja en `moreLayer` (antes un `popover`: la esquina junto a su colita quedaba recta y las otras tres no).
            PlayerCircleButton(symbol: "ellipsis", label: "Más opciones") {
                hideTask?.cancel(); withAnimation(DS.Motion.base(reduceMotion)) { moreOpen.toggle() }
            }
            .accessibilityIdentifier("player-more")
        }
    }

    /// El globo del «⋯», debajo de su botón: las cuatro esquinas iguales, en vidrio. Tocar fuera lo cierra.
    private func moreLayer(_ model: PlayerModel) -> some View {
        let top = (landscape ? DS.Space.s6 : DS.Space.s2) + DS.Size.touchTarget + DS.Space.s2
        return GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                    .accessibilityHidden(true)
                // Nunca más alto que lo que queda de pantalla: en horizontal los nueve renglones no caben y el globo crecía,
                // empujaba la barra de arriba fuera de la pantalla y se cortaba abajo. Si no cabe, se desplaza por dentro.
                let room = max(0, geo.size.height - top - DS.Space.s4)
                let glass = RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                ViewThatFits(in: .vertical) {
                    moreMenu(model).glassEffect(.regular, in: glass)
                    ScrollView { moreMenu(model) }.scrollBounceBehavior(.basedOnSize).frame(height: room).glassEffect(.regular, in: glass)
                }
                .frame(maxHeight: room, alignment: .top)
                .padding(.top, top)
                .padding(.trailing, landscape ? DS.Space.s6 : DS.Space.gutter)
                .accessibilityAction(.escape) { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                .transition(.scale(scale: DS.PlayerPanel.lockScale, anchor: .topTrailing).combined(with: .opacity))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
        }
    }

    /// El «⋯»: audio y subtítulos, el zoom (con el puesto a la derecha), ventana, la TV, descargar y, aparte, bloquear.
    private func moreMenu(_ model: PlayerModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: 0) {
            // La misma hoja que el botón de subtítulos (antes abría otra, «Ajustes del video», que hacía la mitad).
            // «Audio y subtítulos» ya no va aquí: se abre con el botón de subtítulos de la barra (era la misma hoja dos veces).
            // «Episodios» va solo en su botón de la barra de arriba (no también aquí).
            if model.sourceChoices.count > 1 {
                PlayerMenuRow(title: "Versión", symbol: "square.stack", detail: Text(verbatim: videoVersionShort(model))) { openDock(nil, version: true) }
                    .accessibilityIdentifier("player-versions")
            }
            // La velocidad, aquí como el zoom: cada toque la siguiente (antes vivía escondida en «Ajustes del video»).
            PlayerMenuRow(title: "Velocidad", symbol: "gauge.with.dots.needle.67percent", detail: Text(verbatim: rateText(model.rate))) {
                let rates = PlayerModel.rates
                let next = rates[((rates.firstIndex(of: model.rate) ?? 1) + 1) % rates.count]
                Task { await model.setRate(next) }
            }
            .accessibilityIdentifier("player-speed")
            PlayerMenuRow(title: "Zoom", symbol: zoom.symbol, detail: Text(verbatim: Strings.tr(zoom.title, language: language))) { setZoom(nextZoom) }
                .accessibilityHint(Text("Cambia el zoom del video"))
                .accessibilityIdentifier("player-zoom")
            if !landscape {
                // Prender o apagar el iPod (y su color): no → blanco → negro → no.
                PlayerMenuRow(title: "Modo iPod", symbol: "ipod", detail: Text(verbatim: Strings.tr(IPodFace.name(ipodFace), language: language))) {
                    // Al apagarlo vuelven los controles de siempre (con el globo abierto, para seguir cambiando si quieres).
                    hideTask?.cancel(); controlsVisible = true
                    ipodFace = IPodFace.next(after: ipodFace)
                }
                .accessibilityIdentifier("player-ipod")
            }
            if pip.isPossible { PlayerMenuRow(title: "Ventana (PiP)", symbol: "pip.enter") { moreOpen = false; pip.toggle() } }
            if canHandOffToTV(model) {
                PlayerMenuRow(title: "Ver en la TV", symbol: "tv") { moreOpen = false; Task { await continueOnTV() } }
            }
            if canDownload { downloadRow { moreOpen = false } }
            if model.source != nil {
                PlayerMenuRow(title: "Abrir en Infuse", symbol: "arrow.up.forward.app") { moreOpen = false; Task { await openInInfuse() } }
            }
            Divider().padding(.vertical, DS.Space.s1)
            PlayerMenuRow(title: "Bloquear pantalla", symbol: "lock") { moreOpen = false; lock() }
                .accessibilityIdentifier("player-lock")
        }
        .padding(.vertical, DS.Space.s2)
        .frame(width: DS.PlayerPanel.menuWidth)
    }

    // MARK: volver de segundo plano
    /// Al irse a segundo plano: se guarda el cuadro que se ve (leído de la capa del video, con tiempo prestado por iOS). Si el
    /// motor suelta el video (en pausa, pasado el plazo), al volver se ve ese cuadro en su lugar y no negro.
    private func captureFrozenFrame() {
        guard holder.model.phase == .playing else { return }
        let engine = holder.engine
        let app = UIApplication.shared
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = app.beginBackgroundTask(withName: "orbital.frozenFrame") { app.endBackgroundTask(assertion); assertion = .invalid }
        frozenTask?.cancel()
        frozenTask = Task {
            let image = await engine.stillFrame(maxSize: DS.PlayerPanel.frozenFrameMax)
            if !Task.isCancelled, let image, !appActive || !engine.showsVideo { frozenFrame = image }
            if assertion != .invalid { app.endBackgroundTask(assertion); assertion = .invalid }
        }
    }

    /// El cuadro guardado, con el mismo zoom que el video.
    @ViewBuilder private func frozenCover(_ image: UIImage) -> some View {
        switch zoom {
        case .fill: Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        case .stretch: Image(uiImage: image).resizable()
        default: Image(uiImage: image).resizable().scaledToFit()
        }
    }

    // MARK: modo iPod
    /// El iPod: arriba ✕, AirPlay y «⋯» (los de siempre); la pantalla con el video, el nombre, la versión y el avance; la rueda.
    private func ipodChrome(_ model: PlayerModel, face: IPodFace) -> some View {
        GeometryReader { geo in
            let layout = IPodLayout(in: geo.size, aspect: portraitAspect)
            let shown = wheelTarget ?? (dragAxis == .horizontal ? seekPreview : nil) ?? pendingSeek ?? model.snapshot.position
            let state = model.snapshot.state
            ZStack(alignment: .topLeading) {
                HStack(spacing: DS.Space.s3) {
                    PlayerCircleButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                        .accessibilityIdentifier("player-close")
                    Spacer()
                    AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                        .accessibilityLabel(Text("AirPlay"))
                    PlayerCircleButton(symbol: "ellipsis", label: "Más opciones") {
                        withAnimation(DS.Motion.base(reduceMotion)) { moreOpen.toggle() }
                    }
                    .accessibilityIdentifier("player-more")
                }
                .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
                .frame(width: geo.size.width)
                IPodScreen(face: face, status: state == .playing ? "Reproduciendo" : state == .loading || state == .buffering || model.phase == .preparing ? "Cargando" : "En pausa",
                           playing: state == .playing, title: current.displayTitle, detail: ipodDetail(model),
                           position: shown, duration: model.snapshot.duration)
                    .frame(width: layout.screen.width, height: layout.screen.height)
                    .offset(x: layout.screen.minX, y: layout.screen.minY)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityAdjustableAction { d in
                        Task { await model.skip(d == .increment ? PlaybackRules.skipSeconds : -PlaybackRules.skipSeconds) }
                    }
                // «Saltar intro», en la esquina del video.
                skipIntro(model).padding(DS.Space.s2)
                    .frame(width: layout.video.width, height: layout.video.height, alignment: .bottomTrailing)
                    .offset(x: layout.video.minX, y: layout.video.minY)
                IPodWheel(face: face,
                          menu: { Task { await close() } },
                          hold: { lock() },
                          back: { Task { await model.skip(-PlaybackRules.skipSeconds) } },
                          forward: { Task { await model.skip(PlaybackRules.skipSeconds) } },
                          playPause: { userTogglePlay(model) },
                          center: { openDock(.subtitles) },
                          turn: { turnWheel($0, model) },
                          turned: { releaseWheel(model) })
                    .frame(width: layout.wheel.width, height: layout.wheel.height)
                    .offset(x: layout.wheel.minX, y: layout.wheel.minY)
                    .disabled(model.phase == .preparing)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .environment(\.colorScheme, face.scheme)
        .allowsHitTesting(!locked)
    }

    /// Una muesca de la rueda: 10 s (de a minuto si giras rápido); el avance enseña a dónde vas.
    private func turnWheel(_ notches: Int, _ model: PlayerModel) {
        let now = Date()
        let fast = lastNotch.map { now.timeIntervalSince($0) < DS.IPod.fastNotch } ?? false
        lastNotch = now
        let start = wheelTarget ?? model.snapshot.position
        let target = min(max(0, start + Double(notches) * (fast ? DS.IPod.fastStep : PlaybackRules.skipSeconds)), max(0, model.snapshot.duration))
        wheelTarget = target
        model.scrub(to: target)
    }

    private func releaseWheel(_ model: PlayerModel) {
        lastNotch = nil
        guard let target = wheelTarget else { return }
        wheelTarget = nil; pendingSeek = target
        Task { await model.seek(to: target) }
    }

    /// Bajo el nombre: el episodio («T5 · E12») o, en una película, la versión («Latino · 1080p»).
    private func ipodDetail(_ model: PlayerModel) -> String {
        if !current.episodeLabel.isEmpty { return current.episodeLabel }
        guard let src = model.source else { return "" }
        return versionText(src, model)
    }

    // MARK: descargar
    /// Lo que se está viendo en línea y se puede guardar (una descarga ya está; un archivo que te pasaron no tiene ficha).
    private var canDownload: Bool { current.localFile == nil && !current.metaID.hasPrefix("file:") }

    /// «Descargar»: la misma versión que estás viendo (si es un archivo; si es una lista HLS, la recomendada para guardar).
    /// Ya en Descargas: «Descargada» y el toque lleva a Descargas.
    private func downloadRow(_ before: @escaping () -> Void = {}) -> some View {
        PlayerMenuRow(title: inDownloads ? "Descargada" : "Descargar", symbol: inDownloads ? "checkmark.circle" : "arrow.down.circle") {
            before()
            Task { if inDownloads { alreadyDownloaded() } else { await downloadCurrent() } }
        }
        .accessibilityIdentifier("player-download")
        .task(id: current.videoID) { await refreshInDownloads() }
    }

    private func refreshInDownloads() async {
        inDownloads = await env.services.downloads.item(DownloadItem.makeID(metaID: current.metaID, videoID: current.videoID)) != nil
    }

    private func downloadCurrent() async {
        let r = current, language = env.services.appSettings.uiLanguage
        let subtitle = r.episodeLabel
        let outcome = await env.services.queueDownload(kind: r.kind, metaID: r.metaID, videoID: r.videoID, title: r.displayTitle, originalTitle: r.originalTitle,
                                                       subtitle: subtitle, poster: r.poster, source: holder.model.source)
        let tr = { (k: String) in Strings.tr(k, language: language) }
        let message = { (k: String) in Strings.message(k, language: language) }
        switch outcome {
        case .queued:
            inDownloads = true
            // La misma versión que estás viendo; se sigue bajando aunque cierres el reproductor.
            show(PlayerNotice(title: String(format: tr("Bajando %@"), subtitle.isEmpty ? r.displayTitle : subtitle), detail: tr("La misma versión que estás viendo"),
                              tone: .success, showsDownloads: true))
        case .already: inDownloads = true; alreadyDownloaded()
        case .noSources: show(PlayerNotice(title: tr("No hay una versión para bajar"), detail: tr("Real-Debrid no tiene un archivo de este título"), tone: .info))
        case .notEnoughSpace(let text): show(PlayerNotice(title: tr("No cabe en el iPhone"), detail: message(text), tone: .warn, showsDownloads: true))
        case .failed(let text): show(PlayerNotice(title: tr("No pude preparar la descarga"), detail: message(text), tone: .warn))
        }
    }

    private func alreadyDownloaded() {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        show(PlayerNotice(title: tr("Ya está en Descargas"), detail: tr("En el iPhone, para ver sin conexión"), tone: .info, showsDownloads: true))
    }

    private func show(_ new: PlayerNotice) {
        if topNoticesAreWaiting {
            heldNotices.hold(.player(new))
            return
        }
        reveal(new)
    }

    /// El aviso de arriba, ya en pantalla. VoiceOver lo dice en este momento, no cuando se encoló.
    private func reveal(_ new: PlayerNotice) {
        UIAccessibility.post(notification: .announcement, argument: new.title)
        withAnimation(DS.Motion.base(reduceMotion)) { notice = new }
    }

    /// Un video que te pasaron (sin reconocer) no lo puede poner la TV.
    private func canHandOffToTV(_ model: PlayerModel) -> Bool {
        env.services.orbital.isConfigured && model.request?.metaID.hasPrefix("file:") != true
    }

    @ViewBuilder private func upNextCard(_ model: PlayerModel, _ up: UpNext) -> some View {
        UpNextCard(card: up, total: PlaybackRules.upNextCountdown, watchNow: { Task { await model.playNextNow() } }, cancel: { model.cancelUpNext() })
            .transition(.opacity)
    }

    /// El zoom siguiente del botón: los cuatro de Infuse en orden, en los dos sentidos (antes en vertical solo había dos).
    private var nextZoom: VideoZoom { zoom.next }

    // MARK: subtítulos rápidos
    /// El panel chico: en horizontal abajo y al centro, sobre el video; en vertical bajo el video (en el lugar de los controles).
    private func subtitleDockLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            let dock = Group {
                if dockPage == .episodes { episodesPage(model) }
                else if let syncLines { subtitleSyncView(model, lines: syncLines) }
                else if dockPage == .version { versionPage(model) }
                else {
                    // Si cabe, sin desplazarse ni rebotar (antes siempre iba en un ScrollView: en vertical se movía y al jalarlo
                    // hacia abajo parecía «actualizar»); solo si un renglón abierto ya no cabe, se desplaza.
                    ViewThatFits(in: .vertical) {
                        subtitleDockView(model)
                        ScrollView { subtitleDockView(model) }.scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
            if landscape {
                // A la derecha, de arriba abajo, con dos pestañas fijas: «Audio y subtítulos» y «Versión» (antes la versión no se
                // veía: el panel cortaba su pie). El video queda a la izquierda, a la vista.
                HStack {
                    Spacer()
                    VStack(spacing: DS.Space.s2) {
                        if dockPage != .episodes { HStack(spacing: DS.Space.s2) {
                            Picker(selection: Binding(get: { dockPage == .version }, set: { v in withAnimation(DS.Motion.base(reduceMotion)) { dockPage = v ? .version : .media } })) {
                                Text("Audio y subtítulos").tag(false)
                                Text("Versión").tag(true)
                            } label: { Text("Ver") }
                            .pickerStyle(.segmented)
                            Button { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media } } label: { Text("Listo").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                                .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
                        } }
                        dock.contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                    }
                    .frame(width: DS.PlayerPanel.width)
                }
                .padding(DS.Space.s3)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // Pegado abajo y del alto que pide: chico (subtítulos apagados) no deja hueco debajo; grande, el video sube para
                // dejarle lugar (`videoRect`) y no hace falta desplazarse. Solo si ni así cabe, se desplaza por dentro.
                let top = rect.maxY + DS.Space.s4
                // Todo el panel recibe el toque (entre las pastillas pasaba al video de abajo).
                dock.contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                    .frame(maxWidth: DS.PlayerPanel.dockWidth)
                    .frame(maxHeight: max(0, geo.size.height - top - DS.Space.s2), alignment: .bottom)
                    .padding(.horizontal, DS.Space.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, DS.Space.s2)
                    // Lo que mediría sin límite (invisible): cuánto debe subir el video.
                    .background(alignment: .top) {
                        if dockPage != .episodes, syncLines == nil {
                            Group { dockPage == .version ? AnyView(versionPage(model)) : AnyView(subtitleDockView(model)) }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: DS.PlayerPanel.dockWidth).padding(.horizontal, DS.Space.gutter)
                                .hidden().allowsHitTesting(false).accessibilityHidden(true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                                    withAnimation(DS.Motion.base(reduceMotion)) { dockNeed = h }
                                }
                        }
                    }
            }
        }
        .sheet(isPresented: $dockLanguages) {
            LanguageSearchList(codes: SubtitleLanguage.all, available: model.subtitleLanguages.filter { !["es", "en"].contains($0.code) },
                               name: { LanguageFlags.flagged(Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: SubtitleLanguage.code($0) ?? $0)?.capitalized ?? $0, SubtitleLanguage.code($0) ?? $0) }) { code in
                Task { await model.chooseLanguage(code) }
            }
        }
        .sheet(isPresented: $dockVersions) { subtitleVersionsSheet(model) }
        .task { await model.ensureSubtitleSearch() }
        .onDisappear { syncLines = nil; syncResult = nil; syncPicked = nil }
    }

    /// Las frases que vienen (según el tiempo del subtítulo, no el del video), congeladas para poder tocarlas con calma.
    private func startSync(_ model: PlayerModel) {
        let engine = holder.engine
        syncLines = engine.subtitleLines(from: engine.shownTime - model.subtitleDelay - Self.syncLookBack, count: 3)
        syncPicked = nil; syncResult = nil
    }
    /// Unos segundos hacia atrás: la frase que ya empezó a sonar también se puede tocar.
    static let syncLookBack = 2.0

    private func subtitleSyncView(_ model: PlayerModel, lines: [SubtitleLine]) -> some View {
        SubtitleSyncView(lines: lines, picked: syncPicked, result: syncResult,
                         pick: { line in
                             // La oíste ahora: el subtítulo tenía que salir en este cuadro.
                             model.setSubtitleDelay(holder.engine.shownTime - line.start)
                             syncPicked = line.start
                             withAnimation(DS.Motion.base(reduceMotion)) { syncResult = model.subtitleDelay }
                         },
                         confirm: { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { syncLines = nil } },
                         again: { withAnimation(DS.Motion.base(reduceMotion)) { startSync(model) } },
                         back: { withAnimation(DS.Motion.base(reduceMotion)) { syncLines = nil } },
                         compact: landscape, language: env.services.appSettings.uiLanguage)
    }

    /// Todas las versiones del idioma puesto: la recomendada primero, «Del video», las que ya probaste marcadas y la
    /// traducción automática al final (así las ordena `SubtitleVersions.ranked`).
    private func subtitleVersionsSheet(_ model: PlayerModel) -> some View {
        let uiLanguage = env.services.appSettings.uiLanguage
        let code = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 } ?? "es"
        let versions = model.subtitleVersions(language: code)
        let locale = Locale(identifier: uiLanguage)
        let name = LanguageFlags.flagged(locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code, code)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        let selected = model.selectedVersionID == version.id
                        let tried = model.triedVersionIDs.contains(version.id) && !selected
                        SubtitleVersionRow(title: dockVersionTitle(version, index: index) + (index == 0 ? " · " + Strings.tr("Recomendada", language: uiLanguage) : ""),
                                           selected: selected, fromVideo: version.fromVideo, matchesCopy: version.match >= 2, downloads: version.downloads,
                                           loading: version.option.map { model.addedSubtitleURLs.contains($0.url) && model.addedTracks[$0.url] == nil } ?? false,
                                           detail: tried ? "\(Strings.tr("Ya la probaste", language: uiLanguage)) · \(version.name ?? "")" : version.name) {
                            Task { await model.selectVersion(version) }
                        }
                    }
                    if versions.isEmpty {
                        Text(model.searchingSubtitles ? "Buscando versiones en internet…" : model.subtitlesOffline ? "Sin conexión: no hay subtítulos guardados en este idioma." : "No hay subtítulos en este idioma.").recipe(.footnote)
                    }
                }
                .padding(DS.Space.gutter)
            }
            .navigationTitle(Text(verbatim: String(format: Strings.tr("%@ · %lld versiones", language: uiLanguage), name, versions.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dockVersions = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// «WEB-DL · 1080p», «Del video» o «Versión 3».
    private func dockVersionTitle(_ v: SubtitleVersion, index: Int) -> String {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        let res = v.name.flatMap { n in n.range(of: #"(2160|1080|720|480)[pi]"#, options: [.regularExpression, .caseInsensitive]).map { String(n[$0]).lowercased() } }
        let named = [v.traits.source, res].compactMap { $0 }.joined(separator: " · ")
        // Guardado con la descarga: «Español 2 · OpenSubtitles · para sordos» (la copia va debajo, en la hoja de versiones).
        if let saved = v.saved {
            let locale = Locale(identifier: env.services.appSettings.uiLanguage)
            let language = LanguageFlags.flagged(locale.localizedString(forLanguageCode: v.language)?.capitalized(with: locale) ?? v.language, v.language)
            return ["\(language) \(v.savedNumber ?? index + 1)", saved.source,
                    saved.hearingImpaired ? tr("para sordos") : saved.foreignOnly ? tr("forzados") : nil].compactMap { $0 }.joined(separator: " · ")
        }
        // Una pista del video de las que se esconden (venía puesta): dice cuál es.
        if case .embedded(let track) = v.origin, SubtitleFilter.hides(track) {
            let forced = track.isForced || (track.title ?? "").range(of: #"forc|forz|sign|song|carteles"#, options: [.regularExpression, .caseInsensitive]) != nil
            return tr(forced ? "Del video · forzados" : "Del video · para sordos")
        }
        return v.fromVideo ? tr("Del video") : (named.isEmpty ? String(format: tr("Subtítulo %lld"), index + 1) : named)
    }

    private func subtitleDockView(_ model: PlayerModel) -> some View {
        let settings = env.services.appSettings
        let locale = Locale(identifier: settings.uiLanguage)
        let name = { (code: String) in LanguageFlags.flagged(locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code, code) }
        let on = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 }
        let off = model.snapshot.selectedSubtitle == nil
        var codes = ["es", "en"]
        if let on, !codes.contains(on) { codes.append(on) }
        // Sin conexión: también los idiomas que sí hay (los del video y los guardados con la descarga), y los que no, apagados.
        let offline = model.subtitlesOffline
        if offline { codes += model.subtitleLanguages.map(\.code).filter { !codes.contains($0) }.prefix(DS.PlayerPanel.offlineExtraLanguages) }
        var languages = [SubtitleDock.Language(id: "", title: Strings.tr("Apagados", language: settings.uiLanguage), selected: off)]
        languages += codes.map { SubtitleDock.Language(id: $0, title: name($0), selected: !off && on == $0, unavailable: offline && !model.hasSubtitles(language: $0)) }
        let versions = on.map { model.subtitleVersions(language: $0) } ?? []
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let tr = { (k: String) in Strings.tr(k, language: settings.uiLanguage) }
        // La etiqueta dice por qué está ahí, sin prometer de más: «Hecho para tu copia» es por el nombre de la copia (el
        // mismo grupo), no una huella confirmada.
        let version: SubtitleDock.Version? = off ? nil : at.map { i in
            let v = versions[i]
            let badge: String? = v.match >= 2 ? tr("Hecho para tu copia") : v.match == 1 ? tr("Misma versión")
                // «Del video» ya lo dice el título: sin «Viene dentro del archivo» debajo (era lo mismo dos veces).
                : v.fromVideo ? nil
                : v.downloads.flatMap { $0 > 0 ? String(format: tr("%@ descargas"), $0.formatted(.number.notation(.compactName).locale(Locale(identifier: settings.uiLanguage)))) : nil }
            return SubtitleDock.Version(title: dockVersionTitle(v, index: i), badge: badge, strong: v.match >= 2,
                                        position: String(format: tr("Subtítulo %lld de %lld"), i + 1, versions.count))
        } ?? SubtitleDock.Version(title: tr("Cargando…"), badge: nil, strong: false, position: "")
        // Sin «¿Va a tiempo? Sí, va bien / Probar otra»: el subtítulo se cambia con las flechas ‹ › y la elección ya se
        // recuerda sola al cambiarlo. Solo queda el aviso de un ajuste de tiempo recordado.
        let check: SubtitleDock.Check? = model.restoredDelay.map { .restored($0) }
        let tried = versions.enumerated().filter { model.triedVersionIDs.contains($0.element.id) && $0.element.id != model.selectedVersionID }
            .map { dockVersionTitle($0.element, index: $0.offset) }
        // Un subtítulo de imagen (PGS) no trae frases: la vista de sincronizar lo dice y deja Antes/Después.
        let canSync = holder.engine.drawsSubtitles
        let sizes = ["small", "medium", "large"]
        let sizeAt = sizes.firstIndex(of: settings.subtitleSize) ?? 1
        let sizeNames = ["Chico", "Mediano", "Grande"].map { Strings.tr($0, language: settings.uiLanguage) }
        func setSize(_ i: Int) { env.services.settings.update { $0.subtitleSize = sizes[i] } }
        func step(_ d: Int) {
            guard !versions.isEmpty else { return }
            let next = at.map { (($0 + d) % versions.count + versions.count) % versions.count } ?? 0
            Task { await model.selectVersion(versions[next]) }
        }
        // El audio: las pistas de este archivo (sin repetir idioma) y los idiomas que solo trae otra versión (seguro).
        let ui = settings.uiLanguage
        let audioTracks = model.snapshot.audioTracks.filter { $0.kind == .audio }
        var seenAudio = Set<String>()
        let audio: [SubtitleDock.Language] = audioTracks.compactMap { t in
            let code = TrackChooser.audioCode(t) ?? "t\(t.id)"
            guard seenAudio.insert(code).inserted else { return nil }
            let title = TrackChooser.audioCode(t).map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: ui), $0) } ?? TrackChooser.label(t, locale: Locale(identifier: ui), technical: false)
            return .init(id: String(t.id), title: title, selected: model.snapshot.selectedAudio == t.id)
        }
        // Los idiomas que solo trae otra versión: sin cine ni tráileres, la más parecida a la tuya y diciendo a qué va.
        let others: [SubtitleDock.Language] = model.otherVersionAudio(excluding: seenAudio).prefix(DS.PlayerPanel.otherVersionsShown).map { o in
            let speed = o.instant ? Strings.tr("en Real-Debrid", language: ui) : Strings.tr("Real-Debrid aún no la tiene", language: ui)
            let detail = "↻ " + ([o.sure ? nil : Strings.tr("se supone", language: ui), o.quality.isEmpty ? nil : o.quality, speed].compactMap { $0 }.joined(separator: " · "))
            return .init(id: String(o.sourceIndex), title: LanguageFlags.flagged(o.code == "es" ? VersionLanguageRow.spanish(ui) : Streams.versionLanguageName(o.code, in: ui), o.code),
                         selected: false, detail: detail, guessed: !o.sure)
        }
        let otherLanguage = Dictionary(model.otherVersionAudio(excluding: seenAudio).map { (String($0.sourceIndex), $0.code) }, uniquingKeysWith: { a, _ in a })
        let currentAudio = audio.first { $0.selected }?.title ?? audio.first?.title ?? ""
        let subtitleValue = off ? Strings.tr("Apagados", language: ui)
            : [on.map(name), at.map { String(format: Strings.tr("%lld de %lld", language: ui), $0 + 1, versions.count) }].compactMap { $0 }.joined(separator: " · ")
        return SubtitleDock(
            audio: audio, pickAudio: { id in if let n = Int(id) { Task { await model.selectAudio(n) } } },
            otherVersions: others, pickVersion: { id in if let n = Int(id) { pickSource(n, model, language: otherLanguage[id]) } },
            languages: languages,
            pickLanguage: { code in Task { if code.isEmpty { await model.selectSubtitle(nil) } else { await pickSubtitleLanguage(code, model) } } },
            otherLanguage: { dockLanguages = true },
            version: version, loading: at == nil && !off, canStep: versions.count > 1,
            previous: { step(-1) }, next: { step(1) },
            allVersions: { dockVersions = true },
            check: check, confirm: { model.confirmInSync() },
            tryAnother: versions.count > 1 ? { Task { await model.tryAnotherVersion() } } : nil,
            tried: tried,
            delay: holder.engine.drawsSubtitles ? model.subtitleDelay : nil,
            nudge: { model.nudgeSubtitles(by: $0) }, resetDelay: { model.resetSubtitleDelay() },
            sync: canSync ? { withAnimation(DS.Motion.base(reduceMotion)) { startSync(model) } } : nil,
            sizeName: sizeNames[sizeAt],
            smaller: sizeAt > 0 ? { setSize(sizeAt - 1) } : nil, larger: sizeAt < 2 ? { setSize(sizeAt + 1) } : nil,
            done: { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false } },
            compact: false, language: settings.uiLanguage,
            audioValue: currentAudio, subtitleValue: subtitleValue,
            videoVersion: videoVersionText(model), openVersion: model.sourceChoices.count > 1 ? { withAnimation(DS.Motion.base(reduceMotion)) { dockPage = .version } } : nil,
            showsHeader: !landscape,
            offlineNote: model.subtitlesOffline ? tr(current.localFile != nil ? "Sin conexión: solo los subtítulos del video y los guardados con la descarga." : "Sin conexión: solo los subtítulos del video.") : nil,
            initiallyOpen: dockOpens)
    }

    /// Tocar un idioma: pone su mejor versión; si no hay (sin red, o no existe), lo dice en vez de quedarse callado.
    private func pickSubtitleLanguage(_ code: String, _ model: PlayerModel) async {
        guard !(await model.chooseLanguage(code)) else { return }
        let ui = env.services.appSettings.uiLanguage
        let name = Locale(identifier: ui).localizedString(forLanguageCode: code)?.capitalized ?? code
        await toast(String(format: Strings.tr(model.subtitlesOffline ? "Sin conexión: no hay subtítulos en %@ en esta descarga" : "No encontré subtítulos en %@", language: ui), name))
    }

    /// «Inglés · 1080p · 12.3 GB», la versión que suena (o «Descarga en el iPhone»).
    private func videoVersionText(_ model: PlayerModel) -> String {
        let ui = env.services.appSettings.uiLanguage
        if current.localFile != nil { return Strings.tr("Descarga en el iPhone", language: ui) }
        guard let src = model.source else { return "" }
        // El idioma que de verdad suena (la pista puesta) gana a lo que decía el nombre.
        let heard = model.snapshot.audioTracks.first { $0.id == model.snapshot.selectedAudio }.flatMap(TrackChooser.audioCode)
        let language = (heard ?? Streams.playingLanguage(src, heardPrefs(model))?.code).map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: ui), $0) }
        let size = src.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(src.size), countStyle: .file) : nil
        return ([language, src.resolution.isEmpty ? nil : src.resolution, size].compactMap { $0 }).joined(separator: " · ")
    }

    /// Cambiar a otra versión. Si Real-Debrid aún no la tiene, se pregunta antes (puede tardar, o mandar su aviso).
    private func pickSource(_ index: Int, _ model: PlayerModel, language: String? = nil) {
        guard index != model.source?.index else { return }
        if let src = model.sourceChoices.first(where: { $0.index == index }), !src.cached, src.debrid {
            slowPick = index; return
        }
        withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media }
        Task { await model.switchSource(to: index, language: language) }
    }

    /// La página «Versión»: por idioma (como «Elegir versión» de la ficha) o todas las fuentes; tocar una cambia a esa en el
    /// mismo segundo.
    private func versionPage(_ model: PlayerModel) -> some View {
        let ui = env.services.appSettings.uiLanguage
        let prefs = model.request.map { env.services.titlePrefs.languages(for: $0.metaID, settings: env.services.appSettings).prefs } ?? env.services.appSettings.preferences()
        // La que suena va primero: sale marcada como la elegida.
        let ranked = model.sourceChoices.filter { $0.index == model.source?.index } + model.sourceChoices.filter { $0.index != model.source?.index }
        let rows = SourcesModel.languageRows(ranked, prefs: prefs, limitGB: env.services.appSettings.warnCellularOverGB)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            // En horizontal ya lo dice la pestaña de arriba (y se vuelve con ella).
            if !landscape {
                HStack(spacing: DS.Space.s2) {
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { dockPage = .media } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.glass).accessibilityLabel(Text("Atrás")).accessibilityIdentifier("version-back")
                    Text("Versión").recipe(.cardTitle)
                    Spacer()
                }
            }
            Picker(selection: $versionShowsAll) {
                Text("Por idioma").tag(false)
                Text("Todas las fuentes").tag(true)
            } label: { Text("Ver") }
            .pickerStyle(.segmented)
            ScrollView {
                if versionShowsAll {
                    AllSourcesList(sources: model.sourceChoices, current: model.source?.index, currentIsPlaying: true,
                                   primary: ("Cambiar a esta", { pickSource($0.index, model) }), secondary: nil, uiLanguage: ui, prefs: prefs)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        ForEach(rows.main + rows.more) { row in
                            VersionLanguageRow(row: row, uiLanguage: ui) { option in pickSource(option.id, model) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    /// El idioma puesto, en corto («es»); nil: apagados.
    private func currentSubtitleCode(_ model: PlayerModel) -> String? {
        let s = model.snapshot
        return s.selectedSubtitle.flatMap { id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) ?? "" }
            .map { $0.isEmpty ? "CC" : $0 }
    }

    /// «Español · 2 de 7» o «Desactivados» (para VoiceOver y el aviso).
    private func subtitleState(_ model: PlayerModel) -> String {
        subtitleInfo(model)?.title ?? Strings.tr("Desactivados", language: env.services.appSettings.uiLanguage)
    }

    /// Mantener presionado el botón: apaga o prende, y lo dice un momento.
    private func toggleSubtitles(_ model: PlayerModel) {
        pulse()
        let settings = env.services.appSettings
        var languages: [String] = []
        for code in [settings.subtitles, settings.audio, settings.uiLanguage].compactMap(SubtitleLanguage.code) where !languages.contains(code) { languages.append(code) }
        Task {
            await model.toggleSubtitles(languages: languages)
            await toast(model.snapshot.selectedSubtitle == nil ? Strings.tr("Subtítulos desactivados", language: settings.uiLanguage) : subtitleState(model))
        }
    }

    /// Un aviso breve arriba del video (sin tapar los controles), que VoiceOver también dice.
    private func toast(_ text: String) async {
        if topNoticesAreWaiting {
            heldNotices.hold(.subtitle(text), key: QueuedNoticeKey.subtitle)
            return
        }
        await revealSubtitle(text)
    }

    private func revealSubtitle(_ text: String) async {
        withAnimation(DS.Motion.base(reduceMotion)) { subtitleToast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { if subtitleToast == text { subtitleToast = nil } }
    }

    /// «Español · 3 de 7» y por qué está esa versión («WEB-DL · coincide con tu copia», «Del video»…); nil sin subtítulos.
    private func subtitleInfo(_ model: PlayerModel, language: String? = nil) -> (title: String, reason: Text)? {
        let s = model.snapshot
        guard let language = language ?? model.tryingSubtitles
                ?? s.selectedSubtitle.flatMap({ id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) }) else { return nil }
        let versions = model.subtitleVersions(language: language)
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let name = LanguageFlags.flagged(Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: language)?.capitalized ?? language, language)
        // En el idioma de la app (no el del sistema: salía «1 of 3» con la app en español).
        let title = at.map { String(format: Strings.tr("%@ · %lld de %lld", language: env.services.appSettings.uiLanguage), name, $0 + 1, versions.count) } ?? name
        guard let at else { return (title, Text("Cargando…")) }
        let v = versions[at]
        if v.fromVideo { return (title, Text("Del video")) }
        if v.saved != nil { return (title, Text("Guardado con la descarga")) }
        let source = v.traits.source
        if v.matchesCopy { return (title, source.map { Text("\($0) · coincide con tu copia") } ?? Text("Coincide con tu copia")) }
        if let d = v.downloads, d > 0 { return (title, Text("\(d.formatted(.number.notation(.compactName))) descargas")) }
        return (title, Text("De internet"))
    }

    /// «Saltar intro» (o «Saltar resumen»): abajo a la derecha, justo encima de la barra de avance (donde lo buscas al verla).
    @ViewBuilder private func skipIntro(_ model: PlayerModel) -> some View {
        if model.skipIntroTo != nil {
            // Sólida (papel): lo único que se ofrece en ese momento, se distingue del vidrio de los demás.
            Button(model.skipKind == .recap ? "Saltar resumen" : "Saltar intro", systemImage: "forward.fill") { Task { await model.skipIntro() } }
                .fontWeight(.semibold)
                .buttonStyle(.glassProminent).tint(DS.primary).foregroundStyle(DS.onPrimary).controlSize(.regular)
                .fixedSize()
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .accessibilityIdentifier("player-skip-intro")
        }
    }

    /// «Siguiente · T5 E3»: solo desde el 90 % del episodio (antes no estorba) y mientras no esté la tarjeta del final.
    /// ¿Hay «Saltar intro» o «Siguiente» que enseñar ahora?
    private func offersSkipOrNext(_ model: PlayerModel) -> Bool {
        let s = model.snapshot
        return model.skipIntroTo != nil || (model.nextUp != nil && model.upNext == nil && s.duration > 0 && s.position >= s.duration * DS.PlayerPanel.nextAt)
    }

    @ViewBuilder private func nextEpisode(_ model: PlayerModel) -> some View {
        let s = model.snapshot
        if let next = model.nextUp, model.upNext == nil, model.skipIntroTo == nil, s.duration > 0, s.position >= s.duration * DS.PlayerPanel.nextAt {
            Button { Task { await model.playEpisode(next.videoID) } } label: {
                Label { Text("Siguiente · \(next.label)") } icon: { Image(systemName: "forward.end.fill") }
            }
            .fontWeight(.semibold)
            .buttonStyle(.glass).controlSize(.regular)
            .fixedSize()
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .accessibilityIdentifier("player-next-episode")
        }
    }

    /// Retroceder, el botón grande y adelantar (solo cuando ya hay video: mientras busca fuente no hacen nada).
    private func transport(_ model: PlayerModel) -> some View {
        HStack(spacing: DS.Space.s8) {
            SkipButton(forward: false) { Task { await model.skip(-PlaybackRules.skipSeconds) }; pulse() }
            // Cargando: la animación va dentro del botón grande, en el mismo punto que sin controles (LoadingSpinner).
            PlayPauseButton(playing: glyphPlaying, loading: loadingShown) {
                userTogglePlay(model); pulse()
            }
            SkipButton(forward: true) { Task { await model.skip(PlaybackRules.skipSeconds) }; pulse() }
        }
    }

    private func scrubber(_ model: PlayerModel) -> some View {
        let duration = max(model.snapshot.duration, 1)
        // Buscar arrastrando (gesto de pantalla completa) mueve el pulgar igual que arrastrar el slider a mano.
        // Mientras el video llega a donde soltaste (una descarga tarda en buscar), el pulgar se queda ahí: antes regresaba al
        // punto viejo y parecía que no te hacía caso.
        let shown = scrubbing ?? (dragAxis == .horizontal ? seekPreview : nil) ?? pendingSeek ?? model.snapshot.position
        return VStack(spacing: DS.Space.s1) {
            // Los sustos (Where's The Jump), marcados sobre la barra; vibra unos segundos antes si pediste el aviso.
            if let scares = model.scares {
                ScareMarks(position: shown, duration: duration, scares: scares)
                    .padding(.horizontal, DS.Remote.playhead / 2)
                    .scareWarning(position: model.snapshot.position, scares: scares, enabled: scareWarnings && model.snapshot.state == .playing)
            }
            // La barra a todo lo ancho y, debajo, lo visto y lo que falta (sin la hora a la que terminas: no la querías).
            PlayerScrubBar(value: shown, duration: duration, marks: skipMarks(model), ticks: skipTicks(model), clock: { clock($0) },
                           change: { scrubbing = $0; model.scrub(to: $0) },
                           editing: { editing in
                               if editing { hideTask?.cancel(); controlsVisible = true; return }   // mientras arrastras, nada se esconde
                               if let target = scrubbing { pendingSeek = target; scrubbing = nil; Task { await model.seek(to: target) } }
                               pulse()
                           })
                .accessibilityElement()
                .accessibilityLabel(Text("Avance")).accessibilityValue(Text(verbatim: "\(clock(shown)) / \(clock(duration))"))
                // Con VoiceOver, deslizar arriba/abajo salta 10 s como los botones.
                .accessibilityAdjustableAction { d in
                    Task { await model.skip(d == .increment ? PlaybackRules.skipSeconds : -PlaybackRules.skipSeconds) }
                }
                .accessibilityIdentifier("player-scrub")
            HStack {
                Text(verbatim: clock(shown)).recipe(.data).monospacedDigit()
                Spacer()
                Text(verbatim: "−\(clock(max(0, duration - shown)))").recipe(.data).monospacedDigit()
            }
            .frame(height: DS.PlayerPanel.scrubTimes)
        }
    }

    /// Las rayitas fijas: dónde termina la intro y dónde empiezan los créditos.
    private func skipTicks(_ model: PlayerModel) -> [Double] {
        guard let segments = model.segments else { return [] }
        return [segments.intro?.upperBound, segments.credits?.lowerBound].compactMap { $0 }
    }

    /// La intro, el resumen y los créditos (IntroDB), marcados en la barra.
    private func skipMarks(_ model: PlayerModel) -> [ClosedRange<Double>] {
        guard let segments = model.segments else { return [] }
        return [segments.recap, segments.intro, segments.credits].compactMap { $0 }
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: salir
    /// Cerrar: la pantalla se va al momento y lo demás (guardar dónde ibas en Stremio y Trakt) sigue por detrás. Antes se
    /// esperaba a la red y había que tocar dos o tres veces.
    private func close() async {
        let model = holder.model
        finish()
        await model.close()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let current = current
        if current.localFile != nil {
            let id = DownloadItem.makeID(metaID: current.metaID, videoID: current.videoID)
            let snapshot = holder.model.snapshot
            if StremioLibrary.finished(position: snapshot.position, duration: snapshot.duration, kind: current.kind) {
                Task { if let item = await env.services.downloads.item(id) { await DownloadsModel(env.services, freeSpace: { DiskSpace.freeBytes() }).afterWatching(item) } }
            }
        }
        dismiss()
    }

    /// Sigue en la TV: se guarda dónde ibas (Stremio) y tu Orbital retoma desde ahí.
    /// Pasa a tu Orbital donde vas y avisa en la app: «Pasó a tu Orbital · sigue en 12:34 · Deshacer».
    private func continueOnTV() async {
        // El mismo segundo, la misma fuente, el mismo audio y los mismos subtítulos (se leen antes de cerrar).
        let current = current, position = holder.model.snapshot.position, choice = holder.model.currentChoice()
        await holder.model.close()
        finish()
        await env.handOffToTV(current, position: position, choice: choice)
    }

    private var landscape: Bool { verticalSize == .compact }

    /// Dónde va el video. Horizontal: toda la pantalla (o a la izquierda de «Audio y subtítulos»). Vertical: arriba, a todo lo
    /// ancho y en su proporción y de orilla a orilla (no apachurrado), a la altura que lo dejes al arrastrarlo.
    private func videoRect(in size: CGSize) -> CGRect {
        if landscape && zoom == .fitSafeArea && !subtitleDock {
            // «Ajuste de aspecto» (Aspect Fit de Infuse): el cuadro nunca queda bajo la isla ni bajo el indicador de inicio.
            let inset = Self.windowSafeArea
            return CGRect(x: inset.left, y: inset.top, width: max(0, size.width - inset.left - inset.right),
                          height: max(0, size.height - inset.top - inset.bottom))
        }
        if landscape && subtitleDock {
            // Con el panel: el cuadro completo, en su proporción y centrado en lo que queda libre a la izquierda (sin
            // pegarse a la orilla ni quedar bajo el panel).
            let left = Self.windowSafeArea.left + DS.Space.s4
            let free = CGRect(x: left, y: 0, width: max(0, size.width - DS.PlayerPanel.width - DS.Space.s4 * 3 - left), height: size.height)
            let width = min(free.width, free.height * DS.Poster.stillAspect)
            let height = width / DS.Poster.stillAspect
            return CGRect(x: free.midX - width / 2, y: free.midY - height / 2, width: width, height: height)
        }
        if landscape { return CGRect(x: 0, y: 0, width: size.width, height: size.height) }
        if ipod != nil { return IPodLayout(in: size, aspect: portraitAspect).video }   // dentro de la pantalla del iPod
        // «Recortar» en vertical: el video llena toda la pantalla (recorta los lados) y los controles van encima, abajo.
        if fillsPortrait { return CGRect(origin: .zero, size: size) }
        // Donde lo dejaste, con o sin controles (antes, al esconderse los controles, regresaba al centro).
        var band = Self.portraitVideoRect(in: size, center: portraitDrag ?? portraitCenter, aspect: portraitAspect)
        // Con «Audio y subtítulos» abierto, si no cabe abajo, el video sube lo justo (hasta la orilla) y el panel se ve entero.
        if subtitleDock && dockPage != .episodes && dockNeed > 0 {
            let room = size.height - band.maxY - DS.Space.s4 - DS.Space.s2
            band.origin.y -= min(max(0, dockNeed - room), band.minY)
        }
        // «Ajuste de aspecto» en vertical: el cuadro con su margen a los lados, lejos de las esquinas redondeadas.
        if zoom == .fitSafeArea {
            let width = band.width - DS.Space.gutter * 2, height = width * band.height / max(band.width, 1)
            return CGRect(x: band.minX + DS.Space.gutter, y: band.midY - height / 2, width: width, height: height)
        }
        return band
    }

    /// El video en vertical: de orilla a orilla, el alto sale del ancho y la proporción (sin tope, salvo que no quepa), a la
    /// altura `center` (fracción del alto). `size` es el área segura. Lo usa también la ruleta de Los Simpson, que crece
    /// hasta aquí para que el episodio arranque donde ya está la imagen.
    /// Arriba nunca llega a la barra de botones (antes, subido hasta arriba, se encimaba con ✕ y el nombre) y abajo deja el
    /// lugar de los controles (la barra, «Saltar intro», ±10 y el botón grande).
    /// Sin mover (center negativo) abre bajo la barra de botones; arrastrado, sube hasta la orilla y entonces la barra de ✕ y el
    /// nombre baja con los demás controles (`raisedPortrait`).
    static func portraitVideoRect(in size: CGSize, center: Double, aspect: Double = Double(DS.Poster.stillAspect)) -> CGRect {
        let height = portraitHeight(in: size, aspect: aspect)
        let top = DS.PlayerPanel.portraitTopClearance
        let lowest = max(top, size.height - DS.PlayerPanel.portraitControlsReserve - height)
        let y = center < 0 ? min(top, lowest) : min(max(0, size.height * center - height / 2), lowest)
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }
    /// Lo más arriba y lo más abajo que puede ir el video (como centro, parte del alto): debajo de la barra de botones y
    /// dejando el lugar de los controles.
    static func portraitLimits(in size: CGSize, aspect: Double = Double(DS.Poster.stillAspect)) -> ClosedRange<Double> {
        guard size.height > 0 else { return Double(DS.PlayerPanel.portraitCenter)...Double(DS.PlayerPanel.portraitCenter) }
        let height = portraitHeight(in: size, aspect: aspect)
        let lowest = max(DS.PlayerPanel.portraitTopClearance, size.height - DS.PlayerPanel.portraitControlsReserve - height)
        return Double((height / 2) / size.height)...Double((lowest + height / 2) / size.height)
    }
    /// El centro del video como fracción del alto: el que dejaste, o (negativo: sin mover) el de lo más arriba, donde
    /// `portraitVideoRect` lo pinta. Sin esto, arrastrar o mover con VoiceOver partía de -1 y el video no bajaba.
    static func resolvedCenter(_ stored: Double, in size: CGSize, aspect: Double = Double(DS.Poster.stillAspect)) -> Double {
        if stored >= 0 || size.height <= 0 { return stored }
        return Double(portraitVideoRect(in: size, center: -1, aspect: aspect).midY / size.height)
    }

    /// El video subido hasta tapar la barra de ✕ y el nombre: esa barra pasa abajo, con los demás controles.
    private func raisedPortrait(_ rect: CGRect) -> Bool {
        !landscape && !fillsPortrait && ipod == nil && rect.minY < DS.PlayerPanel.portraitTopClearance - 1
    }

    /// El alto del video en vertical: de orilla a orilla en la proporción del cuadro. Un video más cuadrado que 16:9 (Los
    /// Simpson en 4:3) crece a lo alto en vez de quedar con franjas negras a los lados dentro de una banda 16:9; uno más
    /// ancho (cine) se queda en la banda 16:9 de siempre. Nunca invade el lugar de los controles.
    static func portraitHeight(in size: CGSize, aspect: Double) -> CGFloat {
        let ratio = CGFloat(min(max(aspect, DS.PlayerPanel.portraitMinAspect), Double(DS.Poster.stillAspect)))
        let room = max(size.width / DS.Poster.stillAspect, size.height - DS.PlayerPanel.portraitTopClearance - DS.PlayerPanel.portraitControlsReserve)
        return min(size.width / ratio, room, size.height)
    }

    /// La proporción del cuadro que suena (la mide el motor al cargar); 16:9 mientras no se sabe.
    /// Mientras el motor la vuelve a medir (al regresar a la app suelta el video y la olvida un momento), la última que midió de
    /// este video: antes, al volver, un 4:3 se veía como 16:9 y la imagen se hacía más chica.
    private var portraitAspect: Double { holder.engine.videoAspect ?? knownAspect ?? Double(DS.Poster.stillAspect) }

    /// VoiceOver: subir o bajar el video un tramo.
    private func stepVideo(_ step: Int, size: CGSize) {
        let limits = Self.portraitLimits(in: size, aspect: portraitAspect)
        let next = min(max(Self.resolvedCenter(portraitCenter, in: size, aspect: portraitAspect) + Double(step) * DS.PlayerPanel.voiceOverStep, limits.lowerBound), limits.upperBound)
        withAnimation(DS.Motion.base(reduceMotion)) { portraitCenter = next }
    }

    /// Dónde dejaste el video en vertical (se recuerda entre videos).
    static let portraitCenterKey = "player-portrait-center"

    /// Vertical con «Recortar»: el video a pantalla completa.
    private var fillsPortrait: Bool { !landscape && ipod == nil && (zoom == .fill || zoom == .stretch) }

    /// El iPod se ve en vertical.
    private var ipod: IPodFace? { landscape ? nil : IPodFace(rawValue: ipodFace) }

    /// Los márgenes seguros de la ventana (el video en horizontal ignora el área segura, así que no los trae su `GeometryReader`).
    static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }

    /// «Episodios»: en vertical bajo el video y en horizontal a la derecha (donde va «Audio y subtítulos»); el video sigue.
    private func openEpisodes(_ model: PlayerModel) {
        withAnimation(DS.Motion.base(reduceMotion)) {
            moreOpen = false; controlsVisible = false; dockPage = .episodes; subtitleDock = true
        }
        guard let meta = holder.model.localizedMeta ?? current.meta else { return }   // en tu idioma, como en la ficha
        let local = current.localFile != nil
        Task {
            if episodeSeasons.isEmpty {
                episodeSeasons = await Task.detached(priority: .userInitiated) { CinemetaParsing.seasons(meta).filter { !$0.isSpecials } }.value
            }
            playableEpisodes = local ? await model.playableEpisodes(episodeSeasons.flatMap { $0.episodes.map(\.id) }) : nil
        }
    }

    private func episodesPage(_ model: PlayerModel) -> some View {
        EpisodesPanel(seasons: episodeSeasons, current: current.videoID, next: model.nextUp?.videoID, playable: playableEpisodes,
                      pick: { id in closeEpisodes(); Task { await model.playEpisode(id) } },
                      done: { closeEpisodes() })
    }

    private func closeEpisodes() {
        withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media }
    }

    /// Abre la hoja «Audio y subtítulos» con un renglón abierto, o directo en «Versión».
    private func openDock(_ section: SubtitleDock.Section?, version: Bool = false) {
        dockOpens = section
        withAnimation(DS.Motion.base(reduceMotion)) {
            moreOpen = false; controlsVisible = false; dockPage = version ? .version : .media; subtitleDock = true
        }
    }

    /// «1080p» de la versión que suena (para el renglón del ⋯).
    private func videoVersionShort(_ model: PlayerModel) -> String { model.source?.resolution ?? "" }

    private func rateText(_ rate: Float) -> String { rate == 1 ? "1×" : String(format: "%g×", rate) }

    private func openInInfuse() async {
        await holder.model.close()
        dismiss()
        await env.playExternal(current, source: holder.model.source)
    }


    /// La orientación del teléfono al abrir el reproductor (con el candado de rotación, la última que iOS conoce).
    private static var openingOrientation: UIInterfaceOrientationMask {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeRight      // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: return .landscapeLeft
        default: return .landscape
        }
    }

    /// Sigue al teléfono (solo llega si el candado de rotación del sistema está quitado). Una sola petición, a la
    /// orientación exacta: la preferencia de `requestGeometryUpdate` se queda pegada, así que no basta el giro solo de UIKit.
    private func followDevice() {
        guard !locked else { return }
        let target: UIInterfaceOrientationMask
        switch UIDevice.current.orientation {
        case .portrait: target = .portrait
        case .landscapeLeft: target = .landscapeRight    // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: target = .landscapeLeft
        default: return                                  // boca arriba, boca abajo o de cabeza: se queda como está
        }
        AppDelegate.orientations = .allButUpsideDown
        guard let scene = refreshSupportedOrientations() else { return }
        Self.geometryGeneration += 1                      // cancela los reintentos de la apertura
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
    }

    /// Cada petición nueva invalida los reintentos pendientes de la anterior (no vuelven a forzar el horizontal).
    private static var geometryGeneration = 0
    private func unlockPortrait() { rotate(allowed: .portrait, to: .portrait) }

    /// Desde iOS 16 hay que avisar a la vista raíz de que cambiaron las orientaciones permitidas antes de pedir el giro;
    /// si no, la petición se ignora y el video se queda en vertical.
    private func rotate(allowed: UIInterfaceOrientationMask, to target: UIInterfaceOrientationMask) {
        AppDelegate.orientations = allowed
        guard let scene = refreshSupportedOrientations() else { return }
        Self.geometryGeneration += 1
        Self.requestGeometry(scene, target, attemptsLeft: 10, generation: Self.geometryGeneration)
    }

    /// Avisa a la raíz y a todo lo que presenta encima (el reproductor es una pantalla completa presentada) de que
    /// cambiaron las orientaciones permitidas.
    @discardableResult
    private func refreshSupportedOrientations() -> UIWindowScene? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller { current.setNeedsUpdateOfSupportedInterfaceOrientations(); controller = current.presentedViewController }
        }
        return scene
    }

    /// «Bloquear» también congela el giro: solo se permite la orientación de este momento hasta desbloquear.
    private func freezeOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let mask: UIInterfaceOrientationMask = switch scene.interfaceOrientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
        AppDelegate.orientations = mask
        refreshSupportedOrientations()
    }

    /// Mientras la pantalla completa se está presentando, iOS rechaza el giro («Supported: portrait»): se reintenta
    /// en cuanto termina la animación (unas décimas). Cada intento va en otra vuelta, cuando iOS ya leyó las orientaciones nuevas.
    private static func requestGeometry(_ scene: UIWindowScene, _ target: UIInterfaceOrientationMask, attemptsLeft: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard generation == geometryGeneration else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
                guard attemptsLeft > 1 else { return }
                DispatchQueue.main.async { requestGeometry(scene, target, attemptsLeft: attemptsLeft - 1, generation: generation) }
            }
        }
    }
}

/// Un toque con dos dedos (SwiftUI no lo trae): el reconocedor de UIKit dentro de los gestos de SwiftUI, así convive con el
/// doble toque, el pellizco y los arrastres del reproductor.
private struct TwoFingerTap: UIGestureRecognizerRepresentable {
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
