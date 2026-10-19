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
    @AppStorage("player-portrait-center") private var portraitCenter = Double(DS.PlayerPanel.portraitCenter)
    @State private var portraitDrag: Double?
    @State private var portraitAtDragStart: Double = 0
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    @State private var zoom: VideoZoom = .fit
    /// Cada toque en la tira de probar subtítulos reinicia su tiempo para irse.
    @State private var tryStripTouches = 0
    @State private var zoomToast: VideoZoom?
    /// El aviso del botón de subtítulos («Español · 3 de 7» y por qué); se va solo.
    @State private var subtitleToast = false
    @State private var subtitleToastTask: Task<Void, Never>?
    /// La página con que abre el panel (mantener el botón de subtítulos lo abre en Subtítulos).
    @State private var panelPage: VideoSettingsPanel.Page = .hub
    @State private var zoomToastTask: Task<Void, Never>?

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
                        holder.engine.subtitleOverlay(lifted: controlsVisible && landscape, heightFraction: env.services.appSettings.subtitleHeightFraction, delay: model.subtitleDelay)
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
            if controlsVisible && !locked && !panel { controls(model).transition(.opacity) }
            // «Saltar intro» no depende de los controles (se esconden a los pocos segundos y con ellos se iba el botón):
            // con los controles escondidos queda solo, abajo a la derecha, como en Netflix o Infuse.
            else if !locked && !panel && model.skipIntroTo != nil {
                VStack { Spacer(); skipIntro(model) }.padding(landscape ? DS.Space.s6 : DS.Space.gutter).transition(.opacity)
            }
            // Probando subtítulos (elegidos en el panel): la tira al pie del video (en vertical nunca tapa los controles,
            // que van debajo del video).
            if let language = model.tryingSubtitles, !locked { subtitleTryStrip(model, language: language) }
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
            // Abre como tienes el teléfono (Los Simpson, siempre vertical); boca arriba o sin saberlo, horizontal.
            if request.startPortrait { rotate(allowed: .allButUpsideDown, to: .portrait) } else { rotate(allowed: .allButUpsideDown, to: Self.openingOrientation) }
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
            engine.setZoom(zoom)
            pip.onActiveChange = { engine.setPictureInPictureActive($0) }
            nowPlaying.start(model: model)
            Task {
                await model.begin(request); scheduleHide()
                #if DEBUG
                if Demo.isOn, let open = Demo.player {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
                    if open == "panel" || open == "sources" || open == "subtitles" { panel = true } else if open == "close" { await close() }
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
        ZStack(alignment: .top) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showUnlockPrompt() }
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in showUnlockPrompt() })
            if unlockPrompt {
                Button { unlock() } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "lock.fill").font(DS.TextRecipe.cardTitle.font)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Pantalla y giro bloqueados").recipe(.footnote, color: DS.text).fontWeight(.semibold)
                            Text("Toca para desbloquear").recipe(.caption)
                        }
                    }
                    .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s3)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Space.s4)
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
            .onTapGesture { controlsVisible.toggle(); if controlsVisible { scheduleHide() } }
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
        if subtitleToast, let info = subtitleInfo(holder.model) {
            VStack { DSToastPill(text: LocalizedStringKey(info.title), detail: info.reason); Spacer() }.padding(.top, DS.Space.s14)
                .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
        } else if let zoomToast {
            VStack { DSToastPill(text: LocalizedStringKey(zoomToast.title)); Spacer() }.padding(.top, DS.Space.s14)
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
        default:
            if model.reconnecting { VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text("Reconectando…").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) } }
            else if !controlsVisible, model.snapshot.state == .buffering || model.snapshot.state == .loading { ProgressView().tint(DS.text) }   // con controles, va en el centro
        }
    }

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
            SubtitleCycleButton(on: model.snapshot.selectedSubtitle != nil, loading: model.loadingSubtitle,
                                next: { nextSubtitle(model) }, openList: { panelPage = .subtitles; panel = true })
                .accessibilityIdentifier("player-next-subtitle")
            DSIconButton(symbol: zoom.symbol, label: LocalizedStringKey(zoom.title)) { setZoom(zoom.next) }
                .accessibilityHint(Text("Cambia el zoom del video"))
                .accessibilityIdentifier("player-zoom")
            AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("AirPlay"))
        }
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
            subtitleToastTask?.cancel()
            withAnimation(DS.Motion.base(reduceMotion)) { subtitleToast = true; zoomToast = nil }
            UIAccessibility.post(notification: .announcement, argument: subtitleInfo(model)?.title)
            subtitleToastTask = Task {
                try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
                guard !Task.isCancelled else { return }
                withAnimation(DS.Motion.base(reduceMotion)) { subtitleToast = false }
            }
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
        let title = at.map { String(localized: "\(name) · \($0 + 1) de \(versions.count)") } ?? name
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

    /// Lo que se hace con el video (cada botón dice qué hace; si no cabe, solo el ícono y VoiceOver dice el nombre).
    @ViewBuilder private func actions(_ model: PlayerModel) -> some View {
        PlayerLabelButton(title: "Audio y subtítulos", symbol: "captions.bubble") { panelPage = .hub; panel = true }
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
    /// proporción y de orilla a orilla (no apachurrado), a la altura que lo dejes al arrastrarlo; con el panel abierto, la mitad de arriba.
    private func videoRect(in size: CGSize) -> CGRect {
        if landscape && zoom == .fitSafeArea && !panel {
            // «Ajustar al área segura»: el cuadro nunca queda bajo la isla ni bajo el indicador de inicio.
            let inset = Self.windowSafeArea
            return CGRect(x: inset.left, y: inset.top, width: max(0, size.width - inset.left - inset.right),
                          height: max(0, size.height - inset.top - inset.bottom))
        }
        if landscape {
            return CGRect(x: 0, y: 0, width: panel ? max(0, size.width - DS.PlayerPanel.width - DS.Space.s4 * 2) : size.width, height: size.height)
        }
        if panel { return CGRect(x: 0, y: 0, width: size.width, height: size.height * DS.PlayerPanel.videoShare) }
        // De orilla a orilla: el alto sale del ancho y la proporción (sin tope), salvo que no quepa en la pantalla.
        let height = min(size.width / DS.Poster.stillAspect, size.height)
        let center = size.height * (portraitDrag ?? portraitCenter)
        let y = min(max(0, center - height / 2), max(0, size.height - height))
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// Los márgenes seguros de la ventana (el video en horizontal ignora el área segura, así que no los trae su `GeometryReader`).
    private static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }

    /// «12:34 de 22:00».
    private func positionText(_ model: PlayerModel) -> String {
        guard model.snapshot.duration > 0 else { return "" }
        func t(_ s: Double) -> String { Duration.seconds(s).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond)) }
        return String(format: Strings.tr("%@ de %@", language: env.services.appSettings.uiLanguage), t(model.snapshot.position), t(model.snapshot.duration))
    }

    private func settingsPanel(_ model: PlayerModel) -> some View {
        VideoSettingsPanel(model: model, page: panelPage, close: { panel = false }, openInInfuse: { Task { await openInInfuse() } }, drawsSubtitles: holder.engine.drawsSubtitles)
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
    /// Si la app dibuja los subtítulos (y entonces se pueden adelantar o atrasar).
    var drawsSubtitles = true
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<PlayerModel>
    @State private var page: Page = .hub
    /// El idioma elegido en el menú de Subtítulos («» = sin subtítulos); nil: el de los puestos o el tuyo.
    @State private var subtitleLanguage: String?
    @State private var moreLanguages = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PlayerModel, page: Page = .hub, close: @escaping () -> Void, openInInfuse: @escaping () -> Void, drawsSubtitles: Bool = true) {
        _page = State(initialValue: page)
        self.model = model; self.close = close; self.openInInfuse = openInInfuse; self.drawsSubtitles = drawsSubtitles
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
    /// Arriba el idioma (un menú); debajo, una sola lista con todas las versiones de ese idioma (las del video y las de
    /// internet), la que más probablemente va a tiempo primero. Sin SDH ni forzados (decisión del usuario).
    @ViewBuilder private var subtitles: some View {
        let s = model.snapshot
        let settings = env.services.appSettings
        let lang = chosenSubtitleLanguage
        let counts = Dictionary(model.subtitleLanguages.map { ($0.code, $0.count) }, uniquingKeysWith: +)
        header("Subtítulos", back: true)
        Menu {
            Section("Tus idiomas") {
                ForEach(yourSubtitleLanguages, id: \.self) { code in languageButton(code, count: counts[code] ?? 0) }
            }
            Section("Otros idiomas") {
                ForEach(model.subtitleLanguages.filter { !yourSubtitleLanguages.contains($0.code) }, id: \.code) { languageButton($0.code, count: $0.count) }
            }
            Button("Más idiomas…", systemImage: "globe") { moreLanguages = true }
            Button("Sin subtítulos", systemImage: "captions.bubble") {
                subtitleLanguage = ""
                Task { await model.selectSubtitle(nil) }
            }
        } label: {
            if let lang {
                PanelMenuLabel(title: languageName(lang), detail: model.searchingSubtitles && (counts[lang] ?? 0) == 0 ? Text("Buscando…") : Text("\(counts[lang] ?? 0) opciones"))
            } else {
                PanelMenuLabel(title: String(localized: "Sin subtítulos"), detail: Text(verbatim: ""))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("player-subtitle-language")
        .sheet(isPresented: $moreLanguages) {
            LanguageSearchList(codes: SubtitleLanguage.all, name: languageName) { code in
                subtitleLanguage = code
                Task { await model.ensureSubtitleSearch() }
            }
        }
        // Se busca en internet al abrir (para contar las versiones de cada idioma), sin tocar «Buscar».
        .task { await model.ensureSubtitleSearch() }
        if let lang {
            let versions = model.subtitleVersions(language: lang)
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                SubtitleVersionRow(title: versionTitle(version, index: index), selected: model.selectedVersionID == version.id,
                                   fromVideo: version.fromVideo, matchesCopy: version.matchesCopy, downloads: version.downloads,
                                   loading: version.option.map { model.addedSubtitleURLs.contains($0.url) && model.addedTracks[$0.url] == nil } ?? false) {
                    Task { await model.selectVersion(version, trying: true) }
                }
            }
            if versions.isEmpty {
                if model.searchingSubtitles { Text("Buscando en internet…").recipe(.footnote) }
                else if model.subtitleSearchFailed {
                    DSNotice(text: "No encontré subtítulos (o no hay conexión). Vuelve a intentar.", tone: .warn)
                    PanelChip(title: Text("Volver a buscar"), selected: false, symbol: "magnifyingglass") { Task { await model.searchSubtitles() } }
                        .accessibilityIdentifier("player-search-subtitles")
                } else { Text("No hay subtítulos en este idioma.").recipe(.footnote) }
            }
        }
        // Sincronía (como Infuse): si las líneas salen antes o después de lo que se dice. Solo con subtítulos puestos y si los
        // dibuja la app (AVPlayer pinta los suyos y no se pueden mover).
        if s.selectedSubtitle != nil, drawsSubtitles {
        PanelGroupTitle(title: "Sincronía")
        FlowChips {
            PanelChip(title: Text("Antes"), selected: false, symbol: "minus") { model.nudgeSubtitles(by: -PlayerModel.subtitleStep) }
                .accessibilityLabel(Text("Adelantar medio segundo"))
            PanelChip(title: model.subtitleDelay == 0 ? Text("A tiempo") : Text(verbatim: String(format: "%+.1f s", model.subtitleDelay)),
                      selected: model.subtitleDelay != 0) { model.resetSubtitleDelay() }
            PanelChip(title: Text("Después"), selected: false, symbol: "plus") { model.nudgeSubtitles(by: PlayerModel.subtitleStep) }
                .accessibilityLabel(Text("Atrasar medio segundo"))
        }
        if model.subtitleDelay != 0 { Text("Toca el del centro para volver a como venían.").recipe(.caption) }
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

    private func languageButton(_ code: String, count: Int) -> some View {
        Button { subtitleLanguage = code } label: {
            Text(verbatim: count > 0 ? "\(languageName(code)) · \(count)" : languageName(code))
            if code == chosenSubtitleLanguage { Image(systemName: "checkmark") }
        }
    }

    private func versionTitle(_ version: SubtitleVersion, index: Int) -> String {
        if let name = version.name { return name }
        if let track = version.track { return TrackChooser.label(track, locale: locale, technical: false) }
        return String(localized: "Versión \(index + 1)")
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
