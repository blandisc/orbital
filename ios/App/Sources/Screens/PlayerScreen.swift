import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Guarda el motor y el modelo juntos (el motor se arma una sola vez por reproducción).
@MainActor
final class PlayerHolder: ObservableObject {
    let engine: VideoPlayerEngine
    let model: PlayerModel
    private var subscription: ObservableModel.Subscription?

    init() {
        let services = AppEnvironment.shared.services
        let engine = PlayerEngines.make()
        self.engine = engine
        let library = services.oneDriveLibrary
        model = PlayerModel(engine: engine, finder: services.finder, watch: services.watch, titlePrefs: services.titlePrefs, settings: services.settings,
                            onCellular: { Connectivity.shared.isCellular }, episodeLabel: services.episodeLabel,
                            localEpisode: { metaID, videoID in
                                // El siguiente episodio ya descargado (para seguir viendo sin conexión).
                                guard let item = await services.downloads.item(DownloadItem.makeID(metaID: metaID, videoID: videoID)), item.state == .done else { return nil }
                                let file = await services.downloads.fileURL(item)
                                return LocalEpisode(file: file, subtitles: item.subtitleFiles.map { file.deletingLastPathComponent().appendingPathComponent($0) })
                            },
                            skipSegments: { videoID in await services.introDB.segments(videoID: videoID) },   // saltar intro y resumen (IntroDB, como Infuse)
                            scareMap: { imdb, title in await services.scares(imdb: imdb, fallbackTitle: title) })   // el mapa de sustos
        model.subtitlePicks = SubtitlePicks(services.kv)   // «Este va bien»: el subtítulo que elegiste para la serie
        model.subtitleOffsets = SubtitleOffsets(services.kv)   // la sincronía de cada versión (antes no se conectaba y se perdía)
        model.ownSource = { videoID, preferred in await library.source(videoID, purpose: .watch, preferring: preferred) }   // Mi media: tu copia primero
        subscription = model.onChange { [weak self] in self?.objectWillChange.send() }
        // Episodios descargados que se encadenan solos: cada uno visto se atiende al pasar al siguiente (borrar / bajar el que sigue).
        model.onFinishedLocal = { finished in
            Task {
                guard let item = await services.downloads.item(DownloadItem.makeID(metaID: finished.metaID, videoID: finished.videoID)) else { return }
                await DownloadsModel(services, freeSpace: { DiskSpace.freeBytes() }).afterWatching(item)
            }
        }
    }
}

/// El reproductor a pantalla completa, con gestos: un toque muestra los controles, doble toque a los lados salta ±10 s.
struct PlayerScreen: View {
    let request: PlayRequest
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Con VoiceOver los controles no se esconden solos (si no, no queda nada que tocar).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @StateObject private var holder = PlayerHolder()
    @State private var controlsVisible = true
    /// «Bloquear» (como Netflix): sin controles y la pantalla no responde a toques ni deslizamientos (para no pausar o adelantar
    /// sin querer). Un toque enseña el candado unos segundos; tocarlo desbloquea.
    @State private var locked = false
    @State private var unlockPrompt = false
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
    @StateObject private var pip = PictureInPicture()
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
    @State private var zoom: VideoZoom = .fit
    @State private var zoomToast: VideoZoom?
    /// «Subtítulos desactivados» o «Español · 1 de 4», un momento, al apagar o prender con el botón.
    @State private var subtitleToast: String?
    /// Lo que pasó al pedir «Descargar» (el mismo aviso que en el resto de la app, arriba: abajo están los controles).
    @State private var notice: PlayerNotice?
    struct PlayerNotice: Equatable {
        var title: String, detail: String?, tone: DSNotice.Tone
        var showsDownloads = false
        /// «Cambiar a latino»: otra versión que sí trae tu idioma (su índice), en el mismo segundo.
        var switchTo: Int? = nil
        var switchTitle: String? = nil
        let id = UUID()
    }
    /// Subtítulos rápidos (el panel chico sobre el video) y su lista de idiomas.
    @State private var subtitleDock = false
    /// La hoja «Audio y subtítulos» tiene dos páginas: lo de siempre y «Versión» (por idioma o todas las fuentes).
    enum DockPage { case media, version }
    @State private var dockPage: DockPage = .media
    @State private var dockOpens: SubtitleDock.Section? = .subtitles
    @State private var versionShowsAll = false
    /// Una versión que Real-Debrid aún no tiene: se pregunta antes de abrirla (puede tardar o no abrir).
    @State private var slowPick: Int?
    /// Lo que mide la hoja (para que en vertical ocupe lo suyo y, si no cabe, se recorra).
    @State private var dockContentHeight: CGFloat = 0
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
    /// El ícono que aparece un momento al centro tras un doble toque (pausa, ±10 s).
    @State private var flashSymbol: String?
    @State private var flashTask: Task<Void, Never>?
    @State private var rateBeforeFastForward: Float = 1

    /// Lo que suena ahora: cambia al pasar solo al siguiente episodio (el `request` es solo con el que se abrió).
    private var current: PlayRequest { holder.model.request ?? request }

    var body: some View {
        let model = holder.model
        ZStack {
            if let face = ipod { Rectangle().fill(face.body).ignoresSafeArea() } else { DS.video.ignoresSafeArea() }
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
                        holder.engine.subtitleOverlay(lifted: controlsVisible && landscape, look: SubtitleLook(settings: env.services.appSettings), delay: model.subtitleDelay)
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
                        holder.engine.subtitleOverlay(lifted: false, look: SubtitleLook(settings: env.services.appSettings), delay: model.subtitleDelay)
                            .frame(width: geo.size.width, height: geo.size.width / DS.Poster.stillAspect)
                            .padding(.bottom, controlsVisible ? geo.size.height * DS.PlayerPanel.portraitFillControlsShare : DS.Space.s6)
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
                    statusOverlays(model).position(x: rect.midX, y: rect.midY)
                }
                .ignoresSafeArea(edges: landscape ? .all : [])
                .allowsHitTesting(false)
            }
            gestureOverlays
            // En los dos sentidos los controles se esconden solos si no haces nada (un toque los trae); bloqueado, no salen.
            let controlsShown = controlsVisible && !locked && !failed(model) && !subtitleDock && ipod == nil
            if controlsShown { controls(model).transition(.opacity) }
            // El iPod no se esconde (es el aparato): con la pantalla bloqueada se ve pero no se toca.
            if let face = ipod, !failed(model) { ipodChrome(model, face: face).transition(.opacity) }
            if (controlsShown || (ipod != nil && !locked)) && moreOpen { moreLayer(model) }
            if subtitleDock && !locked { subtitleDockLayer(model).transition(.move(edge: .bottom).combined(with: .opacity)) }
            // «Saltar intro» no depende de los controles (se esconden a los pocos segundos y con ellos se iba el botón):
            // con los controles escondidos queda solo, abajo a la derecha, como en Netflix o Infuse. Con los controles a la
            // vista (en pausa, o con la ventana de PiP afuera) ya va dentro de ellos: antes salía dos veces.
            else if !controlsShown && !locked && ipod == nil && model.skipIntroTo != nil {
                VStack { Spacer(); HStack { Spacer(); skipIntro(model) } }.padding(landscape ? DS.Space.s6 : DS.Space.gutter).transition(.opacity)
            }
            // Bloqueado no se ve (ni se toca): si llega a cero, pasa solo al siguiente. En vertical va entre el video y la barra
            // (dentro de los controles, o sola si están escondidos); en horizontal, abajo a la derecha sobre la barra.
            // Con el panel de subtítulos abierto, tampoco: se encimaba sobre él (sale al cerrarlo, si aún falta).
            if let up = model.upNext, !locked, !subtitleDock {
                if landscape {
                    VStack { Spacer(); HStack { Spacer(); upNextCard(model, up) } }
                        .padding(.horizontal, DS.Space.s6)
                        .padding(.bottom, controlsVisible ? DS.Space.s6 + DS.Size.touchTarget * 2 : DS.Space.s6)
                } else if ipod != nil {
                    // En el iPod, sobre lo de abajo de la pantalla (el nombre y el avance), como un aviso del aparato.
                    GeometryReader { geo in
                        let screen = IPodLayout(in: geo.size).screen
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
        .accessibilityAction(.magicTap) { Task { await holder.model.togglePlay() } }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(DS.Motion.base(reduceMotion), value: controlsVisible)
        .animation(DS.Motion.base(reduceMotion), value: dragAxis)
        .animation(DS.Motion.base(reduceMotion), value: ipodFace)
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
            zoom = VideoZoom(stored: env.services.appSettings.videoZoom)
            #if DEBUG
            if Demo.isOn, let raw = Demo.value(after: "-demo-zoom") { zoom = VideoZoom(stored: raw) }   // `-demo-zoom fill`: para capturas
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
                    // `-demo-player dock|subtitles|audio|version`: la hoja «Audio y subtítulos» (con ese renglón abierto) o «Versión».
                    switch open {
                    case "dock", "subtitles": openDock(.subtitles)
                    case "audio": openDock(.audio)
                    case "version": openDock(nil, version: true)
                    case "close": await close()
                    default: break
                    }
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
    /// Bloqueado: todo toque solo enseña el candado; nada pausa, adelanta ni mueve el video, y el giro se congela
    /// en la orientación de ese momento (girar el teléfono no voltea el video).
    /// El aviso va arriba (en los dos sentidos): abajo tapaba los subtítulos y, en vertical, el pie del video.
    private var lockLayer: some View {
        ZStack {
            // Cualquier toque (o arrastre) solo enseña el aviso; desbloquear es tocar su botón grande, al centro.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showUnlockPrompt() }
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in showUnlockPrompt() })
                .accessibilityHidden(true)
            if unlockPrompt {
                PlayerUnlockPrompt { unlock() }
                    .transition(.opacity.combined(with: .scale(scale: DS.PlayerPanel.lockScale)))
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: unlockPrompt)
        .accessibilityElement(children: .contain)
    }

    private func lock() {
        hideTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; locked = true }
        freezeOrientation()
        showUnlockPrompt()
    }

    private func showUnlockPrompt() {
        unlockPrompt = true
        unlockHide?.cancel()
        unlockHide = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.unlockPrompt)
            if !Task.isCancelled { unlockPrompt = false }
        }
    }

    private func unlock() {
        unlockHide?.cancel()
        unlockPrompt = false
        withAnimation(DS.Motion.base(reduceMotion)) { locked = false; controlsVisible = true }
        AppDelegate.orientations = .allButUpsideDown; refreshSupportedOrientations()
        scheduleHide()
    }

    // MARK: gestos
    private func gestureLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            // Como Infuse: doble toque al centro pausa o sigue; en las orillas, ±10 s.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).frame(width: geo.size.width * DS.Gesture.edgeShare)
                    .onTapGesture(count: 2) { Task { await model.skip(-PlaybackRules.skipSeconds) }; flash("gobackward.10") }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { Task { await model.togglePlay() }; flash(model.snapshot.state == .playing ? "pause.fill" : "play.fill") }
                Color.clear.contentShape(Rectangle()).frame(width: geo.size.width * DS.Gesture.edgeShare)
                    .onTapGesture(count: 2) { Task { await model.skip(PlaybackRules.skipSeconds) }; flash("goforward.10") }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Con los subtítulos rápidos abiertos, tocar el video los cierra (y nada más).
                if subtitleDock { withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false }; return }
                controlsVisible.toggle(); if controlsVisible { scheduleHide() }
            }
            .gesture(MagnifyGesture().onEnded { value in
                // Abrir los dedos llena la pantalla; cerrarlos vuelve al cuadro completo (como la app TV de Apple).
                let target = VideoZoom.pinched(magnification: Double(value.magnification))
                guard target != zoom else { return }
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
            .onLongPressGesture(minimumDuration: DS.Timing.longPressDelay, maximumDistance: DS.Gesture.axisThreshold,
                                 perform: { startFastForward(model) }, onPressingChanged: { pressing in if !pressing { endFastForward(model) } })
            .sensoryFeedback(.impact, trigger: isFastForwarding)
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
                let dx = Double(value.translation.width), dy = Double(value.translation.height)
                if dragAxis == .undecided {
                    hideTask?.cancel()
                    dragAxis = PlayerGestures.dominantAxis(dx: dx, dy: dy)
                    switch dragAxis {
                    // En vertical: arrastrar sobre el video es brillo (izquierda) o volumen (derecha), como en horizontal y en
                    // Infuse; desde la agarradera de abajo o lo negro de fuera, mueve el video (antes todo arrastre lo movía y
                    // se perdían el brillo y el volumen).
                    case .vertical where !landscape && !fillsPortrait && ipod == nil
                                          && !videoRect(in: size).insetBy(dx: 0, dy: -DS.PlayerPanel.handleReach).contains(value.startLocation)
                                          || startsOnHandle(value.startLocation, size: size):
                        movingVideo = true
                        portraitAtDragStart = portraitCenter
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
                    let limits = Self.portraitLimits(in: size)
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
            HStack {
                if indicator.kind == .brightness { DSGestureIndicator(symbol: indicator.symbol, value: indicator.value); Spacer() }
                else { Spacer(); DSGestureIndicator(symbol: indicator.symbol, value: indicator.value) }
            }
            .padding(DS.Space.s8)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
        if dragAxis == .horizontal, let target = seekPreview, let start = seekPositionAtDragStart {
            seekBubble(target: target, start: start)
        }
        if isFastForwarding {
            VStack { DSSpeedPill(); Spacer() }.padding(.top, DS.Space.s14).transition(.opacity).allowsHitTesting(false)
        }
        if let notice {
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
            .padding(.top, DS.Space.s14)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let subtitleToast {
            VStack { DSToastPill(text: LocalizedStringKey(subtitleToast)); Spacer() }.padding(.top, DS.Space.s14)
                .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
        }
        if let zoomToast {
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
            DSSeekBubble(time: clock(target), delta: "\(delta >= 0 ? "+" : "−")\(clock(abs(delta)))")
                .position(x: x, y: geo.size.height - DS.Gesture.seekBubbleBottomInset)
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

    private func startFastForward(_ model: PlayerModel) {
        guard !isFastForwarding, dragAxis == .undecided else { return }
        rateBeforeFastForward = model.rate
        withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = true }
        Task { await model.setRate(PlaybackRules.fastForwardRate) }
    }

    private func endFastForward(_ model: PlayerModel) {
        guard isFastForwarding else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = false }
        Task { await model.setRate(rateBeforeFastForward) }
    }

    #if DEBUG
    /// Para `-demo-gesture`: pone el indicador a medio camino sin tocar la pantalla, para capturarlo en el simulador.
    private func simulateGesture(_ kind: String, model: PlayerModel) {
        switch kind {
        case "brightness": verticalKind = .brightness; indicator = (.brightness, "sun.max.fill", 0.65); indicatorVisible = true
        case "volume": verticalKind = .volume; indicator = (.volume, "speaker.wave.2.fill", 0.4); indicatorVisible = true
        case "seek": dragAxis = .horizontal; seekPositionAtDragStart = model.snapshot.position; seekPreview = model.snapshot.position + 80
        case "fastforward": startFastForward(model)
        default: break
        }
    }
    #endif

    private func pulse() { controlsVisible = true; scheduleHide() }

    /// Cambia el zoom (botón o pellizco), lo recuerda para la próxima vez y avisa un momento cuál quedó.
    private func setZoom(_ target: VideoZoom) {
        withAnimation(DS.Motion.base(reduceMotion)) { zoom = target; zoomToast = target }
        holder.engine.setZoom(target)
        env.services.settings.update { $0.videoZoom = target.rawValue }
        zoomToastTask?.cancel()
        zoomToastTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { zoomToast = nil }
        }
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
        case .preparing where model.reconnecting: QuietSpinner()
        case .preparing: VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text(preparingText(model)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
        case .failed(let message):
            // Una pantalla por cada caso (sin fuentes, ninguna sirvió, sin red…), sobre los controles, que se esconden.
            PlayerFailureView(failure: model.failure ?? .sourceDied, isEpisode: model.request?.kind == "series",
                              retry: { Task { await model.retry() } },
                              infuse: model.source == nil ? nil : { Task { await openInInfuse() } },
                              close: { Task { await close() } })
                .accessibilityHint(Text(verbatim: env.message(message)))
        default:
            if model.reconnecting { QuietSpinner() }
            else if !controlsVisible, model.snapshot.state == .buffering || model.snapshot.state == .loading { ProgressView().tint(DS.text) }   // con controles, va en el centro
        }
    }

    /// La ruedita sola, y solo si tarda más de un instante (lo normal es que el video vuelva antes y no se vea nada).
    private struct QuietSpinner: View {
        @State private var shown = false
        var body: some View {
            ProgressView().tint(DS.text).opacity(shown ? 1 : 0)
                .task { try? await Task.sleep(nanoseconds: DS.Timing.quietSpinnerDelay); shown = true }
        }
    }

    private func failed(_ model: PlayerModel) -> Bool { if case .failed = model.phase { true } else { false } }

    private func preparingText(_ model: PlayerModel) -> LocalizedStringKey {
        if case .triedAnotherSource(let n)? = model.notice { return "Probando otra versión (\(n))…" }
        // Ya sabe qué abrir: la versión que elegiste o tu descarga. «Buscando la mejor fuente» ahí no era cierto.
        if current.localFile != nil { return "Abriendo tu descarga…" }
        if current.sourceIndex != nil { return "Abriendo la versión que elegiste…" }
        return "Buscando la mejor versión…"
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
                        if model.phase != .preparing { transport(model) }
                        Spacer()
                        HStack(spacing: DS.Space.s3) {
                            if model.snapshot.duration > 0 { scrubber(model) } else { Spacer() }
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
                    topBar(model).padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
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
                        HStack { Spacer(); skipIntro(model) }.frame(minHeight: DS.Size.touchTarget)
                        if !fillsPortrait { Spacer(minLength: 0) }
                        if model.phase != .preparing { transport(model) }
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
        ZStack(alignment: .topTrailing) {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                .onTapGesture { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                .accessibilityHidden(true)
            moreMenu(model)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .padding(.top, (landscape ? DS.Space.s6 : DS.Space.s2) + DS.Size.touchTarget + DS.Space.s2)
                .padding(.trailing, landscape ? DS.Space.s6 : DS.Space.gutter)
                .accessibilityAction(.escape) { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                .transition(.scale(scale: DS.PlayerPanel.lockScale, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    /// El «⋯»: audio y subtítulos, el zoom (con el puesto a la derecha), ventana, la TV, descargar y, aparte, bloquear.
    private func moreMenu(_ model: PlayerModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: 0) {
            // La misma hoja que el botón de subtítulos (antes abría otra, «Ajustes del video», que hacía la mitad).
            PlayerMenuRow(title: "Audio y subtítulos", symbol: "slider.horizontal.3") { openDock(.audio) }
                .accessibilityIdentifier("player-settings")
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
            let layout = IPodLayout(in: geo.size)
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
                          playPause: { Task { await model.togglePlay() } },
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
        let ui = env.services.appSettings.uiLanguage
        let language = Streams.playingLanguage(src, env.services.appSettings.preferences()).map { Streams.versionLanguageName($0.code, in: ui) }
        return ([language].compactMap { $0 } + src.qualitySummary).joined(separator: " · ")
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
                if let syncLines { subtitleSyncView(model, lines: syncLines) }
                else if dockPage == .version { versionPage(model) }
                else {
                    ScrollView {
                        subtitleDockView(model).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockContentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: dockContentHeight > 0 ? dockContentHeight : nil)
                }
            }
            if landscape {
                // A la derecha, de arriba abajo, con dos pestañas fijas: «Audio y subtítulos» y «Versión» (antes la versión no se
                // veía: el panel cortaba su pie). El video queda a la izquierda, a la vista.
                HStack {
                    Spacer()
                    VStack(spacing: DS.Space.s2) {
                        HStack(spacing: DS.Space.s2) {
                            Picker(selection: Binding(get: { dockPage == .version }, set: { v in withAnimation(DS.Motion.base(reduceMotion)) { dockPage = v ? .version : .media } })) {
                                Text("Audio y subtítulos").tag(false)
                                Text("Versión").tag(true)
                            } label: { Text("Ver") }
                            .pickerStyle(.segmented)
                            Button { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media } } label: { Text("Listo").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                                .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
                        }
                        dock
                    }
                    .frame(width: DS.PlayerPanel.width)
                }
                .padding(DS.Space.s3)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                let top = min(rect.maxY + DS.Space.s4, geo.size.height * DS.PlayerPanel.dockPortraitMaxTop)
                dock.frame(maxWidth: DS.PlayerPanel.dockWidth)
                    .frame(maxHeight: geo.size.height - top - DS.Space.s2, alignment: .top)
                    .padding(.horizontal, DS.Space.gutter).offset(y: top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $dockLanguages) {
            LanguageSearchList(codes: SubtitleLanguage.all, available: model.subtitleLanguages.filter { !["es", "en"].contains($0.code) },
                               name: { Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: SubtitleLanguage.code($0) ?? $0)?.capitalized ?? $0 }) { code in
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
        let name = locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
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
                        Text(model.searchingSubtitles ? "Buscando versiones en internet…" : "No hay subtítulos en este idioma.").recipe(.footnote)
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
        let name = { (code: String) in locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code }
        let on = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 }
        let off = model.snapshot.selectedSubtitle == nil
        var codes = ["es", "en"]
        if let on, !codes.contains(on) { codes.append(on) }
        var languages = [SubtitleDock.Language(id: "", title: Strings.tr("Apagados", language: settings.uiLanguage), selected: off)]
        languages += codes.map { SubtitleDock.Language(id: $0, title: name($0), selected: !off && on == $0) }
        let versions = on.map { model.subtitleVersions(language: $0) } ?? []
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let tr = { (k: String) in Strings.tr(k, language: settings.uiLanguage) }
        // La etiqueta dice por qué está ahí, sin prometer de más: «Hecho para tu copia» es por el nombre de la copia (el
        // mismo grupo), no una huella confirmada.
        let version: SubtitleDock.Version? = off ? nil : at.map { i in
            let v = versions[i]
            let badge: String? = v.match >= 2 ? tr("Hecho para tu copia") : v.match == 1 ? tr("Misma versión") : v.fromVideo ? tr("Viene dentro del archivo")
                : v.downloads.flatMap { $0 > 0 ? String(format: tr("%@ descargas"), $0.formatted(.number.notation(.compactName).locale(Locale(identifier: settings.uiLanguage)))) : nil }
            return SubtitleDock.Version(title: dockVersionTitle(v, index: i), badge: badge, strong: v.match >= 2,
                                        position: String(format: tr("%lld de %lld"), i + 1, versions.count))
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
            let title = TrackChooser.audioCode(t).map { Streams.versionLanguageName($0, in: ui) } ?? TrackChooser.label(t, locale: Locale(identifier: ui), technical: false)
            return .init(id: String(t.id), title: title, selected: model.snapshot.selectedAudio == t.id)
        }
        // Los idiomas que solo trae otra versión: sin cine ni tráileres, la más parecida a la tuya y diciendo a qué va.
        let others: [SubtitleDock.Language] = model.otherVersionAudio(excluding: seenAudio).prefix(DS.PlayerPanel.otherVersionsShown).map { o in
            let speed = o.instant ? Strings.tr("en Real-Debrid", language: ui) : Strings.tr("Real-Debrid aún no la tiene", language: ui)
            let detail = "↻ " + ([o.sure ? nil : Strings.tr("se supone", language: ui), o.quality.isEmpty ? nil : o.quality, speed].compactMap { $0 }.joined(separator: " · "))
            return .init(id: String(o.sourceIndex), title: o.code == "es" ? VersionLanguageRow.spanish(ui) : Streams.versionLanguageName(o.code, in: ui),
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
            pickLanguage: { code in Task { if code.isEmpty { await model.selectSubtitle(nil) } else { await model.chooseLanguage(code) } } },
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
            showsHeader: !landscape, initiallyOpen: dockOpens)
    }

    /// «Inglés · 1080p · 12.3 GB», la versión que suena (o «Descarga en el iPhone»).
    private func videoVersionText(_ model: PlayerModel) -> String {
        let ui = env.services.appSettings.uiLanguage
        if current.localFile != nil { return Strings.tr("Descarga en el iPhone", language: ui) }
        guard let src = model.source else { return "" }
        // El idioma que de verdad suena (la pista puesta) gana a lo que decía el nombre.
        let heard = model.snapshot.audioTracks.first { $0.id == model.snapshot.selectedAudio }.flatMap(TrackChooser.audioCode)
        let language = (heard ?? Streams.playingLanguage(src, env.services.appSettings.preferences())?.code).map { Streams.versionLanguageName($0, in: ui) }
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
                                   primary: ("Cambiar a esta", { pickSource($0.index, model) }), secondary: nil, uiLanguage: ui)
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
        withAnimation(DS.Motion.base(reduceMotion)) { subtitleToast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        withAnimation(DS.Motion.base(reduceMotion)) { if subtitleToast == text { subtitleToast = nil } }
    }

    /// «Español · 3 de 7» y por qué está esa versión («WEB-DL · coincide con tu copia», «Del video»…); nil sin subtítulos.
    private func subtitleInfo(_ model: PlayerModel, language: String? = nil) -> (title: String, reason: Text)? {
        let s = model.snapshot
        guard let language = language ?? model.tryingSubtitles
                ?? s.selectedSubtitle.flatMap({ id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) }) else { return nil }
        let versions = model.subtitleVersions(language: language)
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let name = Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: language)?.capitalized ?? language
        // En el idioma de la app (no el del sistema: salía «1 of 3» con la app en español).
        let title = at.map { String(format: Strings.tr("%@ · %lld de %lld", language: env.services.appSettings.uiLanguage), name, $0 + 1, versions.count) } ?? name
        guard let at else { return (title, Text("Cargando…")) }
        let v = versions[at]
        if v.fromVideo { return (title, Text("Del video")) }
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

    /// Retroceder, el botón grande y adelantar (solo cuando ya hay video: mientras busca fuente no hacen nada).
    private func transport(_ model: PlayerModel) -> some View {
        HStack(spacing: DS.Space.s8) {
            SkipButton(forward: false) { Task { await model.skip(-PlaybackRules.skipSeconds) }; pulse() }
            if model.snapshot.state == .loading || model.snapshot.state == .buffering {
                ProgressView().tint(DS.text).controlSize(.large).frame(width: DS.PlayerPanel.playButton, height: DS.PlayerPanel.playButton)
            } else {
                PlayPauseButton(playing: model.snapshot.state == .playing) { Task { await model.togglePlay() }; pulse() }
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
            // Las horas a los lados de la barra fina (como en horizontal); la escena sigue al dedo mientras arrastras.
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: clock(shown)).recipe(.data).monospacedDigit().fixedSize()
                PlayerScrubBar(value: shown, duration: duration, marks: skipMarks(model),
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
                // Lo que falta (sin la hora a la que terminas: no la querías).
                Text(verbatim: "−\(clock(max(0, duration - shown)))").recipe(.data).monospacedDigit().fixedSize()
            }
        }
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
            if snapshot.duration > 0, snapshot.position >= snapshot.duration * StremioLibrary.watchedAt {
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
        if ipod != nil { return IPodLayout(in: size).video }   // dentro de la pantalla del iPod
        // «Recortar» en vertical: el video llena toda la pantalla (recorta los lados) y los controles van encima, abajo.
        if fillsPortrait { return CGRect(origin: .zero, size: size) }
        // Donde lo dejaste, con o sin controles (antes, al esconderse los controles, regresaba al centro).
        let band = Self.portraitVideoRect(in: size, center: portraitDrag ?? portraitCenter)
        // «Ajuste de aspecto» en vertical: el cuadro con su margen a los lados, lejos de las esquinas redondeadas.
        if zoom == .fitSafeArea {
            let width = band.width - DS.Space.gutter * 2, height = width / DS.Poster.stillAspect
            return CGRect(x: band.minX + DS.Space.gutter, y: band.midY - height / 2, width: width, height: height)
        }
        return band
    }

    /// El video en vertical: de orilla a orilla, el alto sale del ancho y la proporción (sin tope, salvo que no quepa), a la
    /// altura `center` (fracción del alto). `size` es el área segura. Lo usa también la ruleta de Los Simpson, que crece
    /// hasta aquí para que el episodio arranque donde ya está la imagen.
    /// Arriba nunca llega a la barra de botones (antes, subido hasta arriba, se encimaba con ✕ y el nombre) y abajo deja el
    /// lugar de los controles (la barra, «Saltar intro», ±10 y el botón grande).
    static func portraitVideoRect(in size: CGSize, center: Double) -> CGRect {
        let height = min(size.width / DS.Poster.stillAspect, size.height)
        let top = DS.PlayerPanel.portraitTopClearance
        let lowest = max(top, size.height - DS.PlayerPanel.portraitControlsReserve - height)
        let y = min(max(top, size.height * center - height / 2), lowest)
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }
    /// Lo más arriba y lo más abajo que puede ir el video (como centro, parte del alto): debajo de la barra de botones y
    /// dejando el lugar de los controles.
    static func portraitLimits(in size: CGSize) -> ClosedRange<Double> {
        guard size.height > 0 else { return Double(DS.PlayerPanel.portraitCenter)...Double(DS.PlayerPanel.portraitCenter) }
        let height = min(size.width / DS.Poster.stillAspect, size.height)
        let top = DS.PlayerPanel.portraitTopClearance
        let lowest = max(top, size.height - DS.PlayerPanel.portraitControlsReserve - height)
        return Double((top + height / 2) / size.height)...Double((lowest + height / 2) / size.height)
    }

    /// VoiceOver: subir o bajar el video un tramo.
    private func stepVideo(_ step: Int, size: CGSize) {
        let limits = Self.portraitLimits(in: size)
        let next = min(max(portraitCenter + Double(step) * DS.PlayerPanel.voiceOverStep, limits.lowerBound), limits.upperBound)
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
