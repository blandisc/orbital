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
    @State private var panel = false
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var scrubbing: Double?
    /// A dónde se pidió ir y el video todavía no llega.
    @State private var pendingSeek: Double?
    @AppStorage("scare-warnings") private var scareWarnings = true
    @State private var finished = false
    @StateObject private var pip = PictureInPicture()
    @State private var tilt = DeviceTilt()
    @State private var nowPlaying = NowPlaying()
    /// En vertical, a qué altura va el video (lo mueves arrastrándolo; se recuerda) y su valor mientras arrastras.
    @AppStorage("player-portrait-center") private var portraitCenter = Double(DS.PlayerPanel.portraitCenter)
    @State private var portraitDrag: Double?
    @State private var portraitAtDragStart: Double = 0
    /// Pellizcar para llenar la pantalla (recorta los bordes) o ver el cuadro completo.
    @State private var fillsScreen = false

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
                    if dragAxis != .horizontal {
                        // Mientras buscas arrastrando, el subtítulo se quita: la burbuja ya dice el tiempo y no hay con qué encimarlo.
                        // Sube con los controles solo en horizontal (en vertical los controles van fuera del video: si subía,
                        // quedaba a media imagen).
                        holder.engine.subtitleOverlay(lifted: controlsVisible && landscape, heightFraction: env.services.appSettings.subtitleHeightFraction)
                            .transition(.opacity)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
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
            statusOverlays(model)
            gestureOverlays
            // En los dos sentidos los controles se esconden solos si no haces nada (un toque los trae); bloqueado, no salen.
            if controlsVisible && !locked && !panel { controls(model).transition(.opacity) }
            if panel && landscape {
                // Tocar fuera del panel lo cierra; el video sigue a la vista (el cambio de subtítulos se ve al momento).
                Color.clear.contentShape(Rectangle()).onTapGesture { panel = false }
                HStack { Spacer(); settingsPanel(model).frame(width: DS.PlayerPanel.width)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous)) }
                    .padding(DS.Space.s4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let up = model.upNext, !panel { UpNextCard(card: up, watchNow: { Task { await model.playNextNow() } }, cancel: { model.cancelUpNext() }) }
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
            lockLandscape()
            // Girar el teléfono gira el video (aunque tengas el candado de rotación).
            tilt.onChange = { pose in
                switch pose {
                case .portrait: rotate(allowed: .allButUpsideDown, to: .portrait)
                case .landscapeLeft: rotate(allowed: .allButUpsideDown, to: .landscapeLeft)
                case .landscapeRight: rotate(allowed: .allButUpsideDown, to: .landscapeRight)
                }
            }
            tilt.start()
            // La sesión de video, siempre (la voz del control la deja en otro modo y con el volumen bajado).
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.isIdleTimerDisabled = true
            originalBrightness = Double(UIScreen.main.brightness)
            // `begin` va aparte: el plazo de arranque (45 s) tiene que seguir corriendo mientras carga.
            let engine = holder.engine
            pip.onActiveChange = { engine.setPictureInPictureActive($0) }
            nowPlaying.start(model: model)
            Task {
                await model.begin(request); scheduleHide()
                #if DEBUG
                if Demo.isOn, let open = Demo.player {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
                    if open == "panel" || open == "sources" { panel = true } else if open == "close" { await close() }
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
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.appDidEnterBackground() } } }
        .onChange(of: model.phase) { _, phase in if phase == .closed { finish() } }
        // El video ya llegó (o pasó un momento): el pulgar vuelve a seguir el avance real.
        .onChange(of: model.snapshot.position) { _, position in
            if let target = pendingSeek, abs(position - target) < DS.Gesture.seekArrived { pendingSeek = nil }
        }
        .task(id: pendingSeek) { if pendingSeek != nil { try? await Task.sleep(nanoseconds: DS.Timing.seekPatience); pendingSeek = nil } }
        .onChange(of: voiceOver) { _, on in if on { controlsVisible = true } }   // con VoiceOver, los controles no se esconden
        .alert("¿Sigues viendo?", isPresented: Binding(get: { model.stillWatchingPrompt }, set: { _ in })) {
            Button("Seguir") { Task { await model.confirmStillWatching() } }
            Button("Salir", role: .cancel) { Task { await close() } }
        } message: { Text("Llevas tres episodios seguidos.") }
        // En vertical, el panel es una hoja ajustada a lo que tiene (sin espacio muerto); en horizontal va a la derecha (arriba).
        .onChange(of: panel) { _, open in holder.model.panelOpen = open }   // la cuenta de «Siguiente» se detiene con el panel abierto
        .sheet(isPresented: Binding(get: { panel && !landscape }, set: { if !$0 { panel = false } })) {
            settingsPanel(model).fittedSheet().presentationDragIndicator(.visible)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false; pip.stop(); nowPlaying.stop(); tilt.stop(); unlockPortrait()
            UIScreen.main.brightness = CGFloat(originalBrightness)   // el brillo es del sistema: no se queda en lo que dejó el gesto
        }
    }

    // MARK: bloquear
    /// Bloqueado: todo toque solo enseña el candado; nada pausa, adelanta ni mueve el video.
    private var lockLayer: some View {
        ZStack(alignment: .bottom) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showUnlockPrompt() }
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in showUnlockPrompt() })
            if unlockPrompt {
                Button { unlock() } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "lock.fill").font(DS.TextRecipe.cardTitle.font)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Pantalla bloqueada").recipe(.footnote, color: DS.text).fontWeight(.semibold)
                            Text("Toca para desbloquear").recipe(.caption)
                        }
                    }
                    .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s3)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, DS.Space.s14)
                .transition(.opacity.combined(with: .scale(scale: DS.PlayerPanel.lockScale)))
                .accessibilityIdentifier("player-unlock")
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: unlockPrompt)
        .accessibilityElement(children: .contain)
    }

    private func lock() {
        panel = false
        hideTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; locked = true }
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
            .onTapGesture { controlsVisible.toggle(); if controlsVisible { scheduleHide() } }
            .gesture(MagnifyGesture().onEnded { value in
                // Abrir los dedos llena la pantalla; cerrarlos vuelve al cuadro completo (como la app TV de Apple).
                let fill = value.magnification > 1
                guard fill != fillsScreen else { return }
                fillsScreen = fill
                holder.engine.setFillsScreen(fill)
            })
            .sensoryFeedback(.impact, trigger: fillsScreen)
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
            if !Task.isCancelled, !voiceOver, scrubbing == nil, holder.model.snapshot.state == .playing { controlsVisible = false }
        }
    }

    // MARK: estados
    @ViewBuilder private func statusOverlays(_ model: PlayerModel) -> some View {
        switch model.phase {
        case .preparing: VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text(preparingText(model)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
        case .failed(let message):
            VStack(spacing: DS.Space.s4) {
                DSNotice(verbatim: env.message(message), tone: .error)
                HStack {
                    Button("Cerrar") { Task { await close() } }.buttonStyle(.glass)
                    Button { Task { await openInInfuse() } } label: { Label { Text("Abrir en Infuse") } icon: { InfuseIcon() } }.dsPrimaryButton()
                }
            }.padding(DS.Space.s6)
        default: if !controlsVisible, model.snapshot.state == .buffering || model.snapshot.state == .loading { ProgressView().tint(DS.text) }   // con controles, va en el centro
        }
    }

    private func preparingText(_ model: PlayerModel) -> LocalizedStringKey {
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
                    topBar(model).padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
                    VStack(spacing: DS.Space.s5) {
                        skipIntro(model)
                        if model.snapshot.duration > 0 { scrubber(model) }
                        if model.phase != .preparing { transport(model) }
                        HStack(spacing: DS.Space.s2) { actions(model) }
                        // Cómo mover el video (una sola vez a la vista, sin estorbar).
                        Label("Arrastra el video para subirlo o bajarlo", systemImage: "arrow.up.and.down").recipe(.caption, color: DS.textFaint)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .offset(y: rect.maxY + DS.Space.s4)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }

    /// `withActions` (horizontal): Audio y subtítulos, Ventana y Ver en la TV van arriba, junto a AirPlay; abajo solo queda
    /// la barra.
    private func topBar(_ model: PlayerModel, withActions: Bool = false) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            DSIconButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                .accessibilityIdentifier("player-close")
            // El nombre y el episodio completos (dos renglones si hace falta), sin botones que los corten.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(current.displayTitle).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if !current.episodeLabel.isEmpty { Text(current.episodeLabel).recipe(.footnote).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
            if withActions { actions(model) }
            AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("AirPlay"))
        }
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

    /// Lo que se hace con el video (cada botón dice qué hace; si no cabe, solo el ícono y VoiceOver dice el nombre).
    @ViewBuilder private func actions(_ model: PlayerModel) -> some View {
        PlayerLabelButton(title: "Audio y subtítulos", symbol: "captions.bubble") { panel = true }
        PlayerLabelButton(title: "Bloquear", symbol: "lock") { lock() }
            .accessibilityIdentifier("player-lock")
        if pip.isPossible { PlayerLabelButton(title: "Ventana", symbol: "pip.enter") { pip.toggle() } }
        // Un video que te pasaron (sin reconocer) no lo puede poner la TV.
        if env.services.orbital.isConfigured, model.request?.metaID.hasPrefix("file:") != true {
            PlayerLabelButton(title: "Ver en la TV", symbol: "tv") { Task { await continueOnTV() } }
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
    /// proporción (no apachurrado), a la altura que lo dejes al arrastrarlo; con el panel abierto, la mitad de arriba.
    private func videoRect(in size: CGSize) -> CGRect {
        if landscape {
            return CGRect(x: 0, y: 0, width: panel ? max(0, size.width - DS.PlayerPanel.width - DS.Space.s4 * 2) : size.width, height: size.height)
        }
        if panel { return CGRect(x: 0, y: 0, width: size.width, height: size.height * DS.PlayerPanel.videoShare) }
        let height = min(size.width / DS.Poster.stillAspect, size.height * DS.PlayerPanel.videoShare)
        let center = size.height * (portraitDrag ?? portraitCenter)
        let y = min(max(0, center - height / 2), max(0, size.height - height))
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// «12:34 de 22:00».
    private func positionText(_ model: PlayerModel) -> String {
        guard model.snapshot.duration > 0 else { return "" }
        func t(_ s: Double) -> String { Duration.seconds(s).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond)) }
        return String(format: Strings.tr("%@ de %@", language: env.services.appSettings.uiLanguage), t(model.snapshot.position), t(model.snapshot.duration))
    }

    private func settingsPanel(_ model: PlayerModel) -> some View {
        VideoSettingsPanel(model: model, close: { panel = false }, openInInfuse: { Task { await openInInfuse() } })
    }

    private func openInInfuse() async {
        await holder.model.close()
        dismiss()
        await env.playExternal(current, source: holder.model.source)
    }

    private func lockLandscape() { rotate(allowed: .allButUpsideDown, to: .landscape) }
    private func unlockPortrait() { rotate(allowed: .portrait, to: .portrait) }

    /// Desde iOS 16 hay que avisar a la vista raíz de que cambiaron las orientaciones permitidas antes de pedir el giro;
    /// si no, la petición se ignora y el video se queda en vertical.
    private func rotate(allowed: UIInterfaceOrientationMask, to target: UIInterfaceOrientationMask) {
        AppDelegate.orientations = allowed
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows {
            // La raíz y todo lo que presenta encima (el reproductor es una pantalla completa presentada).
            var controller = window.rootViewController
            while let current = controller { current.setNeedsUpdateOfSupportedInterfaceOrientations(); controller = current.presentedViewController }
        }
        Self.requestGeometry(scene, target, attemptsLeft: 10)
    }

    /// Mientras la pantalla completa se está presentando, iOS rechaza el giro («Supported: portrait»): se reintenta
    /// en cuanto termina la animación (unas décimas). Cada intento va en otra vuelta, cuando iOS ya leyó las orientaciones nuevas.
    private static func requestGeometry(_ scene: UIWindowScene, _ target: UIInterfaceOrientationMask, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
                guard attemptsLeft > 1 else { return }
                DispatchQueue.main.async { requestGeometry(scene, target, attemptsLeft: attemptsLeft - 1) }
            }
        }
    }
}

/// «Siguiente episodio» con cuenta atrás.
struct UpNextCard: View {
    let card: UpNext
    let watchNow: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack { Spacer(); HStack { Spacer()
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Siguiente episodio").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                Text("\(card.label) · \(card.title)").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                if card.secondsLeft > 0 { Text("Empieza en \(card.secondsLeft) s").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
                HStack(spacing: DS.Space.s2) {
                    Button("Ver ahora", action: watchNow).dsPrimaryButton()
                    Button("Cancelar", action: cancel).buttonStyle(.glass)
                }
            }
            .padding(DS.Space.s4).frame(maxWidth: DS.Size.cardMax, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            .padding(DS.Space.s6)
        } }
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
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<PlayerModel>
    @State private var page: Page = .hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PlayerModel, close: @escaping () -> Void, openInInfuse: @escaping () -> Void) {
        self.model = model; self.close = close; self.openInInfuse = openInInfuse
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
            let tech = TrackChooser.technical(track)
            Text(verbatim: [TrackChooser.label(track, locale: locale, technical: false), tech].filter { !$0.isEmpty }.joined(separator: " · "))
                .recipe(.footnote).lineLimit(1)
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
    @ViewBuilder private var subtitles: some View {
        let s = model.snapshot
        let settings = env.services.appSettings
        let mine = [settings.subtitles, settings.audio].filter { !$0.isEmpty }
        // En un orden fijo (por pista): el motor a veces las manda en otro orden y las cápsulas brincaban de lugar.
        let tracks = s.subtitleTracks.sorted { $0.id < $1.id }
        let yours = tracks.filter { t in mine.contains { TrackChooser.matches(t, $0) } }
        let others = tracks.filter { t in !yours.contains(t) }
        header("Subtítulos", back: true)
        if !yours.isEmpty {
            PanelGroupTitle(title: "Tu idioma")
            FlowChips { ForEach(yours) { chip($0, selected: s.selectedSubtitle == $0.id) } }
        }
        PanelGroupTitle(title: yours.isEmpty ? "Idiomas" : "Otros")
        FlowChips {
            ForEach(others) { chip($0, selected: s.selectedSubtitle == $0.id) }
            PanelChip(title: Text("Sin subtítulos"), selected: s.selectedSubtitle == nil) { Task { await model.selectSubtitle(nil) } }
        }
        // Sin el que buscas (o el video no trae ninguno): OpenSubtitles, integrado; con una descarga, los de esa copia exacta.
        PanelGroupTitle(title: "En internet")
        if let found = model.foundSubtitles {
            FlowChips {
                ForEach(subtitleLanguages(found, mine: mine), id: \.self) { code in
                    let options = found.filter { $0.language == code }
                    let added = options.filter { model.addedSubtitleURLs.contains($0.url) }.count
                    // Cada toque suma el siguiente de ese idioma (si el primero no va a tiempo, el otro): «Español · 2 de 12».
                    PanelChip(title: added == 0 ? Text(verbatim: "\(languageName(code)) · \(options.count)") : Text(verbatim: "\(languageName(code)) · \(added)/\(options.count)"),
                              selected: added > 0, symbol: added == options.count ? "checkmark" : "arrow.down.circle") {
                        Task { await model.addFoundSubtitle(language: code) }
                    }
                    .disabled(added == options.count)
                }
            }
        } else {
            if model.subtitleSearchFailed { DSNotice(text: "No encontré subtítulos (o no hay conexión). Vuelve a intentar.", tone: .warn) }
            PanelChip(title: model.searchingSubtitles ? Text("Buscando…") : (model.subtitleSearchFailed ? Text("Volver a buscar") : Text("Buscar subtítulos")),
                      selected: false, symbol: "magnifyingglass") {
                Task { await model.searchSubtitles() }
            }
            .disabled(model.searchingSubtitles)
            .accessibilityIdentifier("player-search-subtitles")
        }
        PanelGroupTitle(title: "Tamaño")
        FlowChips {
            ForEach(["small", "medium", "large"], id: \.self) { size in
                PanelChip(title: Text(verbatim: "Aa"), selected: settings.subtitleSize == size, font: .system(size: DS.PlayerPanel.sampleSizes[size] ?? 15)) {   // ds-exception: la muestra «Aa» se ve del tamaño que elige
                    env.services.settings.update { $0.subtitleSize = size }; observer.objectWillChange.send()
                }
                .accessibilityLabel(size == "small" ? Text("Chico") : size == "large" ? Text("Grande") : Text("Mediano"))
            }
        }
    }

    /// Los idiomas encontrados, el tuyo primero y luego por cuántos hay.
    private func subtitleLanguages(_ found: [SubtitleOption], mine: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for o in found { counts[o.language, default: 0] += 1 }
        let yours = Set(mine.flatMap { [$0, Streams.languageCodes[$0] ?? $0] })
        return counts.keys.sorted { a, b in
            let ya = yours.contains(a), yb = yours.contains(b)
            return ya != yb ? ya : (counts[a] ?? 0) > (counts[b] ?? 0)
        }
    }

    /// «spa» → «Español» (en el idioma de la app).
    private func languageName(_ code: String) -> String {
        let two = Streams.languageCodes.first { $0.value == code }?.key ?? code
        return locale.localizedString(forLanguageCode: two)?.capitalized(with: locale) ?? code
    }

    private func chip(_ track: MediaTrack, selected: Bool) -> some View {
        PanelChip(title: Text(verbatim: TrackChooser.label(track, locale: locale, technical: false)), selected: selected) { Task { await model.selectSubtitle(track.id) } }
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
