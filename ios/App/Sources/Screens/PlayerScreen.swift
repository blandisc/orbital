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
    @State private var panel = false
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
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    @State private var zoom: VideoZoom = .fit
    /// Cada toque en la tira de probar subtítulos reinicia su tiempo para irse.
    @State private var tryStripTouches = 0
    @State private var zoomToast: VideoZoom?
    /// «Subtítulos desactivados» o «Español · 1 de 4», un momento, al apagar o prender con el botón.
    @State private var subtitleToast: String?
    /// Subtítulos rápidos (el panel chico sobre el video) y su lista de idiomas.
    @State private var subtitleDock = false
    @State private var dockLanguages = false
    /// «Todas las versiones» desde el panel chico: media hoja (el video sigue a la vista arriba).
    @State private var dockVersions = false
    /// «Sincronizar con una línea»: las frases congeladas (nil: no está abierto), la que tocaste y el ajuste que quedó.
    @State private var syncLines: [SubtitleLine]?
    @State private var syncPicked: Double?
    @State private var syncResult: Double?
    /// La página con que abre el panel (mantener el botón de subtítulos lo abre en Subtítulos).
    @State private var panelPage: VideoSettingsPanel.Page = .hub
    @State private var zoomToastTask: Task<Void, Never>?
    /// Cuántas veces se ha visto «Arrastra el video…» (se deja de decir después de unas pocas).
    @AppStorage("player-drag-hint-count") private var dragHintCount = 0
    @State private var showsDragHint = false

    // MARK: gestos como Infuse (brillo, volumen, buscar arrastrando, 2×)
    @State private var dragAxis: GestureAxis = .undecided
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
            DS.video.ignoresSafeArea()
            // En vertical con el panel abierto, el video sube a la parte de arriba (la hoja ocupa la de abajo).
            GeometryReader { geo in
                let rect = videoRect(in: geo.size)
                ZStack {
                    holder.engine.surface
                    if dragAxis != .horizontal && !fillsPortrait {
                        // Mientras buscas arrastrando, el subtítulo se quita: la burbuja ya dice el tiempo y no hay con qué encimarlo.
                        // Sube con los controles solo en horizontal (en vertical los controles van fuera del video: si subía,
                        // quedaba a media imagen).
                        holder.engine.subtitleOverlay(lifted: controlsVisible && landscape, look: SubtitleLook(settings: env.services.appSettings), delay: model.subtitleDelay)
                            .transition(.opacity)
                    }
                }
                .frame(width: rect.width, height: rect.height)
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
                .overlay(alignment: .bottom) {
                    // En vertical con el panel: bajo el video, qué es y dónde vas (llena el espacio y orienta).
                    if panel && !landscape {
                        VStack(spacing: DS.Space.s1) {
                            Text(current.displayTitle).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                            Text(verbatim: [current.episodeLabel, positionText(model)].filter { !$0.isEmpty }.joined(separator: " · ")).recipe(.footnote).lineLimit(1)
                        }
                        .padding(.bottom, DS.Space.s4)
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
            if controlsVisible && !locked && !panel && !failed(model) && !subtitleDock { controls(model).transition(.opacity) }
            if subtitleDock && !locked && !panel { subtitleDockLayer(model).transition(.move(edge: .bottom).combined(with: .opacity)) }
            // «Saltar intro» no depende de los controles (se esconden a los pocos segundos y con ellos se iba el botón):
            // con los controles escondidos queda solo, abajo a la derecha, como en Netflix o Infuse.
            else if !locked && !panel && model.skipIntroTo != nil {
                VStack { Spacer(); skipIntro(model) }.padding(landscape ? DS.Space.s6 : DS.Space.gutter).transition(.opacity)
            }
            // Probando subtítulos (elegidos en el panel): la tira al pie del video (en vertical nunca tapa los controles,
            // que van debajo del video).
            if panel && landscape {
                // Tocar fuera del panel lo cierra; el video sigue a la vista (el cambio de subtítulos se ve al momento).
                Color.clear.contentShape(Rectangle()).onTapGesture { panel = false }
                HStack { Spacer(); settingsPanel(model).frame(width: DS.PlayerPanel.width)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous)) }
                    .padding(DS.Space.s4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            // Bloqueado no se ve (ni se toca): si llega a cero, pasa solo al siguiente. En vertical va entre el video y la barra
            // (dentro de los controles, o sola si están escondidos); en horizontal, abajo a la derecha sobre la barra.
            if let up = model.upNext, !panel, !locked {
                if landscape {
                    VStack { Spacer(); HStack { Spacer(); upNextCard(model, up) } }
                        .padding(.horizontal, DS.Space.s6)
                        .padding(.bottom, controlsVisible ? DS.Space.s6 + DS.Size.touchTarget * 2 : DS.Space.s6)
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
        .animation(DS.Motion.base(reduceMotion), value: panel)
        .animation(DS.Motion.base(reduceMotion), value: dragAxis)
        .task {
            // Abre como tienes el teléfono (Los Simpson, siempre vertical); boca arriba o sin saberlo, horizontal.
            showsDragHint = dragHintCount < DS.PlayerPanel.dragHintTimes
            if showsDragHint { dragHintCount += 1 }
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
            #endif
            engine.setZoom(zoom)
            pip.onActiveChange = { engine.setPictureInPictureActive($0) }
            nowPlaying.start(model: model)
            Task {
                await model.begin(request); scheduleHide()
                #if DEBUG
                if Demo.isOn, let open = Demo.player {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
                    if open == "panel" || open == "sources" || open == "subtitles" { panel = true } else if open == "close" { await close() }
                    if open == "dock" { subtitleDock = true }   // `-demo-player dock`: los subtítulos rápidos
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
            if phase == .background { model.appDidEnterBackgroundFully() }
            if phase == .active { Task { await model.appDidBecomeActive() } }
        }
        .onChange(of: model.phase) { _, phase in if phase == .closed { finish() } }
        // El video ya llegó (o pasó un momento): el pulgar vuelve a seguir el avance real.
        .onChange(of: model.snapshot.position) { _, position in
            if let target = pendingSeek, abs(position - target) < DS.Gesture.seekArrived { pendingSeek = nil }
        }
        .task(id: pendingSeek) { if pendingSeek != nil { try? await Task.sleep(nanoseconds: DS.Timing.seekPatience); pendingSeek = nil } }
        .onChange(of: moreOpen) { _, open in if !open, controlsVisible, !locked { scheduleHide() } }   // cerrado el «⋯», vuelve a contar
        .onChange(of: voiceOver) { _, on in if on { controlsVisible = true } }   // con VoiceOver, los controles no se esconden
        .alert("¿Sigues viendo?", isPresented: Binding(get: { model.stillWatchingPrompt }, set: { _ in })) {
            Button("Seguir") { Task { await model.confirmStillWatching() } }
            Button("Salir", role: .cancel) { Task { await close() } }
        } message: { Text("Llevas tres episodios seguidos.") }
        // En vertical, el panel es una hoja ajustada a lo que tiene (sin espacio muerto); en horizontal va a la derecha (arriba).
        .onChange(of: panel) { _, open in holder.model.panelOpen = open }   // la cuenta de «Siguiente» se detiene con el panel abierto
        .sheet(isPresented: Binding(get: { panel && !landscape }, set: { if !$0 { panel = false } })) {
            settingsPanel(model)
        }
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
        panel = false
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
            .onChanged { value in
                let dx = Double(value.translation.width), dy = Double(value.translation.height)
                if dragAxis == .undecided {
                    hideTask?.cancel()
                    dragAxis = PlayerGestures.dominantAxis(dx: dx, dy: dy)
                    switch dragAxis {
                    case .vertical where !landscape:
                        portraitAtDragStart = portraitCenter   // en vertical, arrastrar arriba o abajo mueve el video
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
                case .vertical where !landscape:
                    let range = DS.PlayerPanel.portraitCenterRange
                    portraitDrag = min(max(portraitAtDragStart + dy / Double(size.height), Double(range.lowerBound)), Double(range.upperBound))
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
                if let moved = portraitDrag { portraitCenter = moved; portraitDrag = nil }
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
                    DSToastPill(text: LocalizedStringKey(zoomToast.title), detail: zoomToast == .fill ? Text("Llena la pantalla y recorta los lados") : nil)
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
        case "next-subtitle": nextSubtitle(model)   // el botón de subtítulos, un toque
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
        case .preparing: VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text(preparingText(model)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
        case .failed(let message):
            // Una pantalla por cada caso (sin fuentes, ninguna sirvió, sin red…), sobre los controles, que se esconden.
            PlayerFailureView(failure: model.failure ?? .sourceDied, isEpisode: model.request?.kind == "series",
                              retry: { Task { await model.retry() } },
                              infuse: model.source == nil ? nil : { Task { await openInInfuse() } },
                              close: { Task { await close() } })
                .accessibilityHint(Text(verbatim: env.message(message)))
        default:
            if model.reconnecting { VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text("Reconectando…").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) } }
            else if !controlsVisible, model.snapshot.state == .buffering || model.snapshot.state == .loading { ProgressView().tint(DS.text) }   // con controles, va en el centro
        }
    }

    private func failed(_ model: PlayerModel) -> Bool { if case .failed = model.phase { true } else { false } }

    private func preparingText(_ model: PlayerModel) -> LocalizedStringKey {
        if model.reconnecting { return "Reconectando…" }
        if case .triedAnotherSource(let n)? = model.notice { return "Probando otra fuente (\(n))…" }
        return "Buscando la mejor fuente…"
    }

    // MARK: controles
    /// Horizontal: arriba ✕, el nombre, Audio y subtítulos, Ventana, Ver en la TV y AirPlay; al centro ±10 y el botón
    /// grande; abajo solo la barra.
    /// Vertical: lo mismo pero bajo el video (que va arriba): nada tapa la imagen ni los subtítulos.
    private func controls(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            if landscape {
                ZStack {
                    LinearGradient(colors: [DS.scrim, .clear, DS.scrim], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
                    topScrim
                    VStack(spacing: DS.Space.s3) {
                        topBar(model, withActions: true)
                        Spacer()
                        if model.phase != .preparing { transport(model) }
                        Spacer()
                        skipIntro(model)
                        if model.snapshot.duration > 0 { scrubber(model) }
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
                    // Que se puede arrastrar: una barrita como la de las hojas de iOS, pegada al pie del video (siempre que haya
                    // controles; el letrero de abajo solo sale las primeras veces).
                    if !fillsPortrait {
                        Capsule().fill(DS.textMuted).frame(width: DS.PlayerPanel.dragGrabber.width, height: DS.PlayerPanel.dragGrabber.height)
                            .offset(y: rect.maxY + DS.Space.s1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    VStack(spacing: DS.Space.s5) {
                        // «Siguiente episodio» entre el video y la barra (antes tapaba los controles).
                        if let up = model.upNext, !locked { upNextCard(model, up) }
                        skipIntro(model)
                        if model.snapshot.duration > 0 { scrubber(model) }
                        if model.phase != .preparing { transport(model) }
                        HStack(spacing: DS.Space.s2) { actions(model) }
                        // Cómo mover el video: solo las primeras veces que abres el reproductor.
                        if showsDragHint && !fillsPortrait {
                            Label("Arrastra el video para subirlo o bajarlo", systemImage: "arrow.up.and.down").recipe(.caption, color: DS.textFaint)
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, fillsPortrait ? DS.Space.s8 : 0)
                    .offset(y: fillsPortrait ? 0 : rect.maxY + DS.Space.s6)
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

    /// `withActions` (horizontal): Ajustes del video, subtítulos, zoom, AirPlay, Bloquear, Ventana y En la TV, todos
    /// redondos y del mismo tamaño; abajo solo queda la barra.
    private func topBar(_ model: PlayerModel, withActions: Bool = false) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            PlayerCircleButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                .accessibilityIdentifier("player-close")
            // El nombre y el episodio completos (dos renglones si hace falta), sin botones que los corten.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(current.displayTitle).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if !current.episodeLabel.isEmpty { Text(current.episodeLabel).recipe(.footnote).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
            if withActions {
                PlayerCircleButton(symbol: "slider.horizontal.3", label: "Audio y subtítulos") { panelPage = .hub; panel = true }
                    .accessibilityIdentifier("player-settings")
            }
            SubtitleButton(code: currentSubtitleCode(model), state: subtitleState(model), loading: model.loadingSubtitle,
                           open: { withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; subtitleDock = true } },
                           toggle: { toggleSubtitles(model) })
                .accessibilityIdentifier("player-next-subtitle")
            PlayerCircleButton(symbol: zoom.symbol, label: LocalizedStringKey(zoom.title)) { setZoom(nextZoom) }
                .accessibilityHint(Text("Cambia el zoom del video"))
                .accessibilityIdentifier("player-zoom")
            AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("AirPlay"))
            if withActions {
                // Bloquear, Ventana y Ver en la TV van juntos detrás del «⋯». Es un globo (no un `Menu` del sistema): así se
                // sabe cuándo está abierto y los controles no se esconden debajo de él.
                PlayerCircleButton(symbol: "ellipsis", label: "Más opciones") { hideTask?.cancel(); moreOpen = true }
                    .accessibilityIdentifier("player-more")
                    .popover(isPresented: $moreOpen) {
                        HStack(spacing: DS.Space.s2) {
                            PlayerLabelButton(title: "Bloquear", symbol: "lock") { moreOpen = false; lock() }
                                .accessibilityIdentifier("player-lock")
                            if pip.isPossible { PlayerLabelButton(title: "Ventana", symbol: "pip.enter") { moreOpen = false; pip.toggle() } }
                            if canHandOffToTV(model) {
                                PlayerLabelButton(title: "En la TV", symbol: "tv", accessibility: "Ver en la TV") { moreOpen = false; Task { await continueOnTV() } }
                            }
                            if canDownload { downloadButton { moreOpen = false } }
                        }
                        .frame(width: DS.Size.touchTarget * 2 * CGFloat(moreCount(model)))
                        .padding(DS.Space.s3)
                        .presentationCompactAdaptation(.popover)
                    }
            }
        }
    }

    /// Cuántos botones lleva el «⋯» (para su ancho).
    private func moreCount(_ model: PlayerModel) -> Int { 1 + (pip.isPossible ? 1 : 0) + (canHandOffToTV(model) ? 1 : 0) + (canDownload ? 1 : 0) }

    // MARK: descargar
    /// Lo que se está viendo en línea y se puede guardar (una descarga ya está; un archivo que te pasaron no tiene ficha).
    private var canDownload: Bool { current.localFile == nil && !current.metaID.hasPrefix("file:") }

    /// «Descargar»: la misma versión que estás viendo (si es un archivo; si es una lista HLS, la recomendada para guardar).
    /// Ya en Descargas: «Descargada» y el toque lleva a Descargas.
    private func downloadButton(_ before: @escaping () -> Void = {}) -> some View {
        PlayerLabelButton(title: inDownloads ? "Descargada" : "Descargar", symbol: inDownloads ? "checkmark.circle" : "arrow.down.circle",
                          accessibility: inDownloads ? "Ya está en Descargas" : "Descargar este video") {
            before()
            Task { if inDownloads { await toast(Strings.tr("Ya está en Descargas", language: env.services.appSettings.uiLanguage)) } else { await downloadCurrent() } }
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
        switch outcome {
        case .queued:
            inDownloads = true
            // La misma versión que estás viendo; se sigue bajando aunque cierres el reproductor.
            await toast(String(format: tr("Bajando %@ · la misma versión"), subtitle.isEmpty ? r.displayTitle : subtitle))
        case .already: inDownloads = true; await toast(tr("Ya está en Descargas"))
        case .noSources: await toast(tr("No hay fuentes de Real-Debrid para descargar."))
        case .notEnoughSpace(let text), .failed(let text): await toast(text)
        }
    }

    /// Un video que te pasaron (sin reconocer) no lo puede poner la TV.
    private func canHandOffToTV(_ model: PlayerModel) -> Bool {
        env.services.orbital.isConfigured && model.request?.metaID.hasPrefix("file:") != true
    }

    @ViewBuilder private func upNextCard(_ model: PlayerModel, _ up: UpNext) -> some View {
        UpNextCard(card: up, total: PlaybackRules.upNextCountdown, watchNow: { Task { await model.playNextNow() } }, cancel: { model.cancelUpNext() })
            .transition(.opacity)
    }

    /// El zoom siguiente del botón. En vertical «Ajustar al área segura» no cambia nada (el video ya va dentro del área
    /// segura), así que se salta.
    /// En vertical el botón alterna entre «Ajustar» y «Recortar» (pantalla completa); el área segura y «Estirar» solo tienen
    /// sentido en horizontal.
    private var nextZoom: VideoZoom {
        if !landscape { return zoom == .fill ? .fit : .fill }
        return zoom.next
    }

    // MARK: subtítulos rápidos
    /// El panel chico: en horizontal abajo y al centro, sobre el video; en vertical bajo el video (en el lugar de los controles).
    private func subtitleDockLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            let dock = Group {
                if let syncLines { subtitleSyncView(model, lines: syncLines) } else { subtitleDockView(model) }
            }
            .frame(maxWidth: DS.PlayerPanel.dockWidth)
            if landscape {
                // Arriba: los subtítulos van abajo, y son lo que estás revisando.
                VStack { dock; Spacer() }.frame(maxWidth: .infinity).padding(.top, DS.Space.s3)
            } else {
                dock.padding(.horizontal, DS.Space.gutter).offset(y: min(rect.maxY + DS.Space.s4, geo.size.height * DS.PlayerPanel.dockPortraitMaxTop))
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
        return v.fromVideo ? tr("Del video") : (named.isEmpty ? String(format: tr("Versión %lld"), index + 1) : named)
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
            let badge: String? = v.match >= 2 ? tr("Hecho para tu copia") : v.match == 1 ? tr("Misma fuente") : v.fromVideo ? tr("Viene dentro del archivo")
                : v.downloads.flatMap { $0 > 0 ? String(format: tr("%@ descargas"), $0.formatted(.number.notation(.compactName).locale(Locale(identifier: settings.uiLanguage)))) : nil }
            return SubtitleDock.Version(title: dockVersionTitle(v, index: i), badge: badge, strong: v.match >= 2,
                                        position: String(format: tr("%lld de %lld"), i + 1, versions.count))
        } ?? SubtitleDock.Version(title: tr("Cargando…"), badge: nil, strong: false, position: "")
        let check: SubtitleDock.Check? = model.askInSync ? .inSync : model.restoredDelay.map { .restored($0) }
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
        return SubtitleDock(
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
            compact: landscape, language: settings.uiLanguage)
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

    /// Un toque en el botón de subtítulos: la versión siguiente, sin pausar; los controles se quedan (para seguir tocando),
    /// el aviso arriba y la tira abajo (‹ anterior y «Este va bien»).
    private func nextSubtitle(_ model: PlayerModel) {
        pulse()
        tryStripTouches += 1
        let settings = env.services.appSettings
        var languages: [String] = []
        for code in [settings.subtitles, settings.audio, settings.uiLanguage].compactMap(SubtitleLanguage.code) where !languages.contains(code) { languages.append(code) }
        Task {
            guard await model.cycleSubtitle(languages: languages) != nil else { return }
            // Lo dice la tira de abajo (no un aviso arriba que repetía lo mismo); VoiceOver lo anuncia.
            withAnimation(DS.Motion.base(reduceMotion)) { zoomToast = nil }
            UIAccessibility.post(notification: .announcement, argument: subtitleInfo(model)?.title)
        }
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

    /// La tira de «probar subtítulos»: ‹ › entre versiones del idioma, «Inglés · 2 de 12» y por qué, ±0.5 s y «Este va bien».
    /// Se va sola si no la tocas.
    private func subtitleTryStrip(_ model: PlayerModel, language: String) -> some View {
        let (title, reason) = subtitleInfo(model, language: language) ?? (language, Text("Cargando…"))
        func touched() { tryStripTouches += 1 }
        return GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            SubtitleTryStrip(title: title, reason: reason, delay: model.subtitleDelay, step: PlayerModel.subtitleStep,
                             previous: { touched(); Task { await model.stepVersion(-1) } },
                             next: { touched(); Task { await model.stepVersion(1) } },
                             nudge: { touched(); model.nudgeSubtitles(by: $0) },
                             confirm: { model.confirmSubtitle() })
                .padding(.horizontal, DS.Space.s3)
                // En horizontal, con los controles a la vista, sube sobre la barra de avance.
                .padding(.bottom, landscape && controlsVisible && !panel ? DS.Space.s6 + DS.Size.touchTarget * 2 : DS.Space.s3)
                .frame(width: rect.width, height: rect.height, alignment: .bottom)
                .offset(x: rect.minX, y: rect.minY)
        }
        .ignoresSafeArea(edges: landscape ? .all : [])
        .transition(.opacity)
        .task(id: tryStripTouches) {
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
            if !Task.isCancelled { model.dismissTry() }
        }
        .accessibilityIdentifier("player-subtitle-try")
    }

    /// «Saltar intro» (o «Saltar resumen»): abajo a la derecha, justo encima de la barra de avance (donde lo buscas al verla).
    @ViewBuilder private func skipIntro(_ model: PlayerModel) -> some View {
        if model.skipIntroTo != nil {
            HStack {
                Spacer()
                Button(model.skipKind == .recap ? "Saltar resumen" : "Saltar intro", systemImage: "forward.fill") { Task { await model.skipIntro() } }
                    .buttonStyle(.glass).controlSize(.large)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    /// La fila de vertical: ícono y nombre corto, todos del mismo ancho (VoiceOver dice el nombre largo).
    @ViewBuilder private func actions(_ model: PlayerModel) -> some View {
        PlayerLabelButton(title: "Ajustes", symbol: "slider.horizontal.3", accessibility: "Audio y subtítulos") { panelPage = .hub; panel = true }
            .accessibilityIdentifier("player-settings")
        PlayerLabelButton(title: "Bloquear", symbol: "lock") { lock() }
            .accessibilityIdentifier("player-lock")
        if pip.isPossible { PlayerLabelButton(title: "Ventana", symbol: "pip.enter") { pip.toggle() } }
        if canHandOffToTV(model) {
            PlayerLabelButton(title: "En la TV", symbol: "tv", accessibility: "Ver en la TV") { Task { await continueOnTV() } }
        }
        if canDownload { downloadButton() }
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
            // La escena sigue al dedo mientras arrastras (antes solo cambiaba al soltar).
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0; model.scrub(to: $0) }), in: 0...duration) { editing in
                if editing { hideTask?.cancel(); controlsVisible = true; return }   // mientras arrastras, nada se esconde
                if let target = scrubbing { pendingSeek = target; scrubbing = nil; Task { await model.seek(to: target) } }
                pulse()
            }
            .tint(DS.accent)   // el avance, en el acento (como en toda la app)
            .accessibilityLabel(Text("Avance")).accessibilityValue(Text(verbatim: "\(clock(shown)) / \(clock(duration))"))
            // Con VoiceOver, deslizar arriba/abajo no llama a `onEditingChanged`: salta 10 s como los botones.
            .accessibilityAdjustableAction { d in
                Task { await model.skip(d == .increment ? PlaybackRules.skipSeconds : -PlaybackRules.skipSeconds) }
            }
            HStack {
                Text(verbatim: clock(shown)).recipe(.data)
                Spacer()
                // Lo que falta (sin la hora a la que terminas: no la querías).
                Text(verbatim: "−\(clock(max(0, duration - shown)))").recipe(.data)
            }
        }
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
        let current = current, position = holder.model.snapshot.position
        await holder.model.close()
        finish()
        await env.handOffToTV(current, position: position)
    }

    private var landscape: Bool { verticalSize == .compact }

    /// Dónde va el video. Horizontal: toda la pantalla (o a la izquierda del panel). Vertical: arriba, a todo lo ancho y en su
    /// proporción y de orilla a orilla (no apachurrado), a la altura que lo dejes al arrastrarlo; con el panel abierto, la mitad de arriba.
    private func videoRect(in size: CGSize) -> CGRect {
        if landscape && zoom == .fitSafeArea && !panel {
            // «Ajustar al área segura»: el cuadro nunca queda bajo la isla ni bajo el indicador de inicio.
            let inset = Self.windowSafeArea
            return CGRect(x: inset.left, y: inset.top, width: max(0, size.width - inset.left - inset.right),
                          height: max(0, size.height - inset.top - inset.bottom))
        }
        if landscape && panel {
            // Con el panel: el cuadro completo, en su proporción y centrado en lo que queda libre a la izquierda (sin
            // pegarse a la orilla ni quedar bajo el panel).
            let left = Self.windowSafeArea.left + DS.Space.s4
            let free = CGRect(x: left, y: 0, width: max(0, size.width - DS.PlayerPanel.width - DS.Space.s4 * 3 - left), height: size.height)
            let width = min(free.width, free.height * DS.Poster.stillAspect)
            let height = width / DS.Poster.stillAspect
            return CGRect(x: free.midX - width / 2, y: free.midY - height / 2, width: width, height: height)
        }
        if landscape { return CGRect(x: 0, y: 0, width: size.width, height: size.height) }
        if panel { return CGRect(x: 0, y: 0, width: size.width, height: size.height * DS.PlayerPanel.videoShare) }
        // «Recortar» en vertical: el video llena toda la pantalla (recorta los lados) y los controles van encima, abajo.
        if fillsPortrait { return CGRect(origin: .zero, size: size) }
        // Donde lo dejaste, con o sin controles (antes, al esconderse los controles, regresaba al centro).
        return Self.portraitVideoRect(in: size, center: portraitDrag ?? portraitCenter)
    }

    /// El video en vertical: de orilla a orilla, el alto sale del ancho y la proporción (sin tope, salvo que no quepa), a la
    /// altura `center` (fracción del alto). `size` es el área segura. Lo usa también la ruleta de Los Simpson, que crece
    /// hasta aquí para que el episodio arranque donde ya está la imagen.
    static func portraitVideoRect(in size: CGSize, center: Double) -> CGRect {
        let height = min(size.width / DS.Poster.stillAspect, size.height)
        let y = min(max(0, size.height * center - height / 2), max(0, size.height - height))
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }
    /// Dónde dejaste el video en vertical (se recuerda entre videos).
    static let portraitCenterKey = "player-portrait-center"

    /// Vertical con «Recortar»: el video a pantalla completa.
    private var fillsPortrait: Bool { !landscape && !panel && zoom == .fill }

    /// Los márgenes seguros de la ventana (el video en horizontal ignora el área segura, así que no los trae su `GeometryReader`).
    static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }

    /// «12:34 de 22:00».
    private func positionText(_ model: PlayerModel) -> String {
        guard model.snapshot.duration > 0 else { return "" }
        func t(_ s: Double) -> String { Duration.seconds(s).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond)) }
        return String(format: Strings.tr("%@ de %@", language: env.services.appSettings.uiLanguage), t(model.snapshot.position), t(model.snapshot.duration))
    }

    private func settingsPanel(_ model: PlayerModel) -> some View {
        VideoSettingsPanel(model: model, page: panelPage, close: { panel = false }, openInInfuse: { Task { await openInInfuse() } }, drawsSubtitles: holder.engine.drawsSubtitles,
                           openSubtitleDock: { panel = false; withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; subtitleDock = true } })
    }

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

/// Un solo panel para audio, subtítulos y velocidad (recuerda lo que eliges por serie). En horizontal, audio y subtítulos
/// «Ajustes del video»: un panel con cuatro renglones que dicen cómo está cada cosa (audio, subtítulos, fuente y velocidad,
/// esta última ahí mismo) y, al tocar uno, su página con opciones grandes. En horizontal va a la derecha con el video a la
/// vista; en vertical, como hoja ajustada a lo que tiene (sin espacio muerto).
struct VideoSettingsPanel: View {
    enum Page { case hub, audio, subtitles, source }
    let model: PlayerModel
    let close: () -> Void
    let openInInfuse: () -> Void
    /// Si la app dibuja los subtítulos (y entonces se pueden adelantar o atrasar).
    var drawsSubtitles = true
    /// «Tiempo y tamaño»: cierra el menú y abre el panel chico sobre el video (ahí se ajustan viendo la escena).
    var openSubtitleDock: () -> Void = {}
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<PlayerModel>
    @State private var page: Page = .hub
    /// El idioma elegido en el menú de Subtítulos («» = sin subtítulos); nil: el de los puestos o el tuyo.
    @State private var subtitleLanguage: String?
    @State private var moreLanguages = false
    /// Si queda más lista abajo (se desvanece el pie para que se note que sigue).
    @State private var moreBelow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PlayerModel, page: Page = .hub, close: @escaping () -> Void, openInInfuse: @escaping () -> Void, drawsSubtitles: Bool = true,
         openSubtitleDock: @escaping () -> Void = {}) {
        _page = State(initialValue: page)
        self.model = model; self.close = close; self.openInInfuse = openInInfuse; self.drawsSubtitles = drawsSubtitles
        self.openSubtitleDock = openSubtitleDock
        _observer = StateObject(wrappedValue: ModelObserver(model))
    }

    private var language: String { env.services.appSettings.uiLanguage }
    private var locale: Locale { Locale(identifier: language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                switch page {
                case .hub: hub
                case .audio: audio
                case .subtitles: subtitles
                case .source: source
                }
            }
            .padding(DS.Space.s4)
            .animation(DS.Motion.base(reduceMotion), value: page)
        }
        .scrollBounceBehavior(.basedOnSize)
        // El último renglón no queda bajo la barra de inicio, y si hay más abajo el pie se desvanece (antes se cortaba
        // «Abrir en Infuse» o «Sincronía» sin aviso).
        .contentMargins(.bottom, DS.Space.s6, for: .scrollContent)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.containerSize.height < g.contentSize.height + g.contentInsets.bottom - DS.Space.s2
        } action: { _, more in moreBelow = more }
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, moreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: DS.Space.s14)
            }
        }
        #if DEBUG
        .onAppear { if Demo.isOn, Demo.player == "subtitles" { page = .subtitles } }   // `-demo-player subtitles`
        #endif
        // Mide lo que mide la lista (no `fixedSize`): si la hoja no cabe, se queda al tope y la lista se recorre hasta abajo.
        .fittedScrollSheet()
    }

    private func header(_ title: LocalizedStringKey, back: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            if back {
                Button { page = .hub } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).accessibilityLabel(Text("Atrás")).accessibilityIdentifier("panel-back")
            }
            Text(title).recipe(.section)
            Spacer()
            if !back { Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.glass).accessibilityLabel(Text("Cerrar")) }
        }
        .padding(.bottom, DS.Space.s2)
    }

    // MARK: el panel
    @ViewBuilder private var hub: some View {
        let s = model.snapshot
        header("Ajustes del video", back: false)
        PanelRow(title: "Audio", symbol: "speaker.wave.2.fill", color: DS.ListTint.library, action: { page = .audio }) {
            trackValue(s.audioTracks.first { $0.id == s.selectedAudio }, empty: Text("Sin pistas de audio"))
        }
        .accessibilityIdentifier("panel-audio")
        PanelRow(title: "Subtítulos", symbol: "captions.bubble.fill", color: DS.ListTint.spark, action: { page = .subtitles }) {
            trackValue(s.subtitleTracks.first { $0.id == s.selectedSubtitle }, empty: Text("Sin subtítulos"))
        }
        .accessibilityIdentifier("panel-subtitles")
        PanelRow(title: "Fuente", symbol: "list.bullet", color: DS.ListTint.flame, action: model.sourceChoices.count > 1 ? { page = .source } : nil) {
            if let src = model.source { sourceValue(src) } else { Text("Archivo descargado").recipe(.footnote) }
        }
        .accessibilityIdentifier("panel-source")
        // La velocidad, en el mismo renglón: − 1× + (sin una segunda fila de cápsulas).
        HStack(spacing: DS.Space.s3) {
            PanelIcon(symbol: "gauge.with.dots.needle.67percent", color: DS.ListTint.list)
            Text("Velocidad").recipe(.secondary, color: DS.text).fontWeight(.semibold)
            Spacer(minLength: DS.Space.s2)
            SpeedStepper(rates: PlayerModel.rates, rate: model.rate) { rate in Task { await model.setRate(rate) } }
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        Button(action: openInInfuse) { Label { Text("Abrir en Infuse") } icon: { InfuseIcon() } }
            .buttonStyle(.borderless).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity).padding(.top, DS.Space.s2)
    }


    @ViewBuilder private func trackValue(_ track: MediaTrack?, empty: Text) -> some View {
        if let track {
            Text(verbatim: TrackChooser.label(track, locale: locale, technical: true)).recipe(.footnote).lineLimit(1)
        } else { empty.recipe(.footnote) }
    }

    private func sourceValue(_ src: Source) -> some View {
        HStack(spacing: DS.Space.s1) {
            QualityBadges(items: QualityBadges.items(resolution: src.resolution, hdr: src.hdr, audio: src.audioBadges))
            if src.size > 0 { Text(verbatim: Int64(src.size).formatted(.byteCount(style: .file))).recipe(.footnote).lineLimit(1) }
        }
    }

    // MARK: audio
    @ViewBuilder private var audio: some View {
        let s = model.snapshot
        header("Audio", back: true)
        ForEach(s.audioTracks.sorted { $0.id < $1.id }) { track in
            choiceRow(selected: s.selectedAudio == track.id, title: Text(verbatim: TrackChooser.label(track, locale: locale, technical: false)),
                      detail: Text(verbatim: TrackChooser.technical(track))) { Task { await model.selectAudio(track.id) } }
        }
    }

    private func choiceRow(selected: Bool, title: Text, detail: Text?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.secondary, color: DS.text).fontWeight(.semibold)
                    if let detail { detail.recipe(.footnote) }
                }
                Spacer(minLength: DS.Space.s2)
                if selected { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(DS.accent) }
            }
            .padding(DS.Space.s3)
            .background(selected ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous).stroke(selected ? DS.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: subtítulos
    /// Tres pasos, de arriba abajo: el idioma (fichas, «Desactivar» primero; tocar uno ya pone su mejor versión), el ajuste
    /// de tiempo (si hay subtítulos puestos) y las versiones de ese idioma (la recomendada primero). Abajo, qué se recuerda.
    @ViewBuilder private var subtitles: some View {
        let s = model.snapshot
        let settings = env.services.appSettings
        let lang = chosenSubtitleLanguage
        let off = s.selectedSubtitle == nil && subtitleLanguage == ""
        let available = Set(model.subtitleLanguages.map(\.code))
        // Pocos idiomas a la vista: los tuyos, español e inglés, y el que esté puesto; los demás en «Más idiomas…».
        let shortList = (yourSubtitleLanguages + ["es", "en"] + (lang.map { [$0] } ?? [])).reduce(into: [String]()) { out, c in if !out.contains(c) { out.append(c) } }
        header("Subtítulos", back: true)
        PanelGroupTitle(title: "Idioma")
        FlowChips {
            PanelChip(title: Text("Desactivar"), selected: off || (s.selectedSubtitle == nil && subtitleLanguage == nil), symbol: "captions.bubble") {
                subtitleLanguage = ""
                Task { await model.selectSubtitle(nil) }
            }
            .accessibilityIdentifier("player-subtitles-off")
            ForEach(shortList, id: \.self) { code in
                PanelChip(title: Text(verbatim: languageName(code)), selected: !off && s.selectedSubtitle != nil && code == lang) {
                    subtitleLanguage = code
                    Task { await model.chooseLanguage(code) }
                }
                .opacity(available.contains(code) || model.searchingSubtitles ? 1 : DesignTokens.Opacity.faint)
            }
            PanelChip(title: Text("Más idiomas…"), selected: false, symbol: "globe") { moreLanguages = true }
        }
        .accessibilityIdentifier("player-subtitle-language")
        .sheet(isPresented: $moreLanguages) {
            LanguageSearchList(codes: SubtitleLanguage.all, available: model.subtitleLanguages.filter { !shortList.contains($0.code) }, name: languageName) { code in
                subtitleLanguage = code
                Task { await model.chooseLanguage(code) }
            }
        }
        // Se busca en internet al abrir (para que haya más versiones), sin tocar «Buscar».
        .task { await model.ensureSubtitleSearch() }
        // El tiempo y el tamaño se ajustan en el panel chico, viendo la escena (aquí solo el atajo).
        if s.selectedSubtitle != nil {
            PanelChip(title: Text("Tiempo y tamaño…"), selected: false, symbol: "slider.horizontal.3", action: openSubtitleDock)
                .accessibilityIdentifier("player-subtitle-dock")
        }
        if let lang, !off {
            let versions = model.subtitleVersions(language: lang)
            if !versions.isEmpty { PanelGroupTitle(title: "Versión") }
            // Probar rápido: ‹ › van a la versión anterior o siguiente (se ve al momento en el video, arriba); las que ya
            // probaste quedan marcadas en la lista.
            if versions.count > 1 {
                let at = versions.firstIndex { $0.id == model.selectedVersionID }
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(spacing: DS.Space.s2) {
                        PanelChip(title: Text("‹ Anterior"), selected: false) { step(versions, from: at, by: -1) }
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: at.map { String(format: Strings.tr("%lld de %lld", language: language), $0 + 1, versions.count) } ?? "—")
                            .recipe(.secondary, color: DS.text).fontWeight(.semibold).monospacedDigit()
                        Spacer(minLength: DS.Space.s2)
                        PanelChip(title: Text("Siguiente ›"), selected: false) { step(versions, from: at, by: 1) }
                            .accessibilityIdentifier("player-subtitle-next-version")
                    }
                    Text("¿No va a tiempo o se ve mal? Toca Siguiente para probar otra.").recipe(.caption)
                }
            }
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                let selected = model.selectedVersionID == version.id
                SubtitleVersionRow(title: versionTitle(version, index: index, recommended: index == 0), selected: selected,
                                   fromVideo: version.fromVideo, matchesCopy: version.matchesCopy, downloads: version.downloads,
                                   loading: version.option.map { model.addedSubtitleURLs.contains($0.url) && model.addedTracks[$0.url] == nil } ?? false,
                                   detail: model.triedVersionIDs.contains(version.id) && !selected ? "\(Strings.tr("Ya la probaste", language: language)) · \(version.name ?? "")" : version.name) {
                    Task { await model.selectVersion(version) }
                }
            }
            if versions.isEmpty {
                if model.searchingSubtitles { Text("Buscando versiones en internet…").recipe(.footnote) }
                else if model.subtitleSearchFailed {
                    DSNotice(text: "No pudimos buscar subtítulos. Revisa tu conexión.", tone: .warn)
                    PanelChip(title: Text("Volver a buscar"), selected: false, symbol: "magnifyingglass") { Task { await model.searchSubtitles() } }
                        .accessibilityIdentifier("player-search-subtitles")
                } else { Text("No hay subtítulos en este idioma.").recipe(.footnote) }
            }
        }
        // Qué se recuerda: lo que elijas aquí vale para todo el título (sin confirmar nada).
        Label(model.request?.kind == "series" ? "Se recuerda para toda la serie." : "Se recuerda para esta película.", systemImage: "checkmark.circle")
            .recipe(.caption)
    }

    /// ‹ › de las versiones: pone la anterior o la siguiente y marca la de antes como probada.
    private func step(_ versions: [SubtitleVersion], from at: Int?, by delta: Int) {
        guard !versions.isEmpty else { return }
        let next = at.map { (($0 + delta) % versions.count + versions.count) % versions.count } ?? 0
        Task { await model.selectVersion(versions[next]) }
    }

    /// El idioma de la lista: el que elegiste en el menú; si no, el de los subtítulos puestos; si no, el tuyo (Ajustes:
    /// subtítulos, luego audio). nil: sin subtítulos.
    private var chosenSubtitleLanguage: String? {
        if let subtitleLanguage { return subtitleLanguage.isEmpty ? nil : subtitleLanguage }
        let s = model.snapshot
        if let id = s.selectedSubtitle, let code = SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) { return code }
        return yourSubtitleLanguages.first
    }

    private var yourSubtitleLanguages: [String] {
        let settings = env.services.appSettings
        var out: [String] = []
        for code in [settings.subtitles, settings.audio].compactMap(SubtitleLanguage.code) where !out.contains(code) { out.append(code) }
        return out
    }

    /// Un título que se entiende («Español · del video», «WEB-DL · 1080p»), no el nombre del archivo («SPA (srt)»,
    /// «Show.S01E02.1080p.WEB-DL.srt»), que va abajo, chico.
    private func versionTitle(_ version: SubtitleVersion, index: Int, recommended: Bool = false) -> String {
        let tr = { (key: String) in Strings.tr(key, language: language) }
        let base = versionBaseTitle(version, index: index)
        return recommended ? "\(base) · \(tr("Recomendada"))" : base
    }

    private func versionBaseTitle(_ version: SubtitleVersion, index: Int) -> String {
        let tr = { (key: String) in Strings.tr(key, language: language) }
        if version.fromVideo {
            let name = languageName(version.language)
            return "\(name) · \(tr("del video"))"
        }
        let parts = [version.traits.source, Self.resolution(version.name)].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return String(format: tr("Versión %lld"), index + 1)
    }

    /// «1080p», «720p», «2160p» del nombre de la copia.
    private static func resolution(_ name: String?) -> String? {
        guard let name, let range = name.range(of: #"(2160|1080|720|480)[pi]"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return name[range].lowercased()
    }

    /// «spa» o «es» → «Español» (en el idioma de la app).
    private func languageName(_ code: String) -> String {
        let two = SubtitleLanguage.code(code) ?? code
        return locale.localizedString(forLanguageCode: two)?.capitalized(with: locale) ?? code
    }

    // MARK: fuente
    @ViewBuilder private var source: some View {
        let current = model.source
        let rest = model.sourceChoices.filter { $0.index != current?.index }
        header("Fuente", back: true)
        if let current {
            PanelGroupTitle(title: "La que tienes")
            sourceRow(current, selected: true)
        }
        if !rest.isEmpty { PanelGroupTitle(title: "Otras") }
        ForEach(rest) { sourceRow($0, selected: false) }
    }

    private func sourceRow(_ src: Source, selected: Bool) -> some View {
        let langs = src.languages.prefix(2).map { Streams.languageName($0, in: language) }.joined(separator: " + ")
        let size = src.size > 0 ? Int64(src.size).formatted(.byteCount(style: .file)) : ""
        return Button { if !selected { Task { await model.switchSource(to: src.index); page = .hub } } } label: {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    QualityBadges(items: QualityBadges.items(resolution: src.resolution.isEmpty ? "SD" : src.resolution, hdr: src.hdr, audio: src.audioBadges))
                    Text(verbatim: [langs, size].filter { !$0.isEmpty }.joined(separator: " · ")).recipe(.footnote)
                    (src.cached ? Text("Al instante") : Text("Tarda en empezar")).recipe(.caption, color: src.cached ? DS.good : DS.textMuted)
                }
                Spacer(minLength: DS.Space.s2)
                if selected { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(DS.accent) }
            }
            .padding(DS.Space.s3)
            .background(selected ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous).stroke(selected ? DS.accent : .clear))
        }
        .buttonStyle(.plain)
    }
}
