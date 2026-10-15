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
                            })
        subscription = model.onChange { [weak self] in self?.objectWillChange.send() }
    }
}

/// El reproductor a pantalla completa, con gestos: un toque muestra los controles, doble toque a los lados salta ±10 s.
struct PlayerScreen: View {
    let request: PlayRequest
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var holder = PlayerHolder()
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var panel = false
    @State private var sources = false
    @State private var scrubbing: Double?
    @State private var finished = false
    @StateObject private var pip = PictureInPicture()
    @State private var nowPlaying = NowPlaying()
    /// Pellizcar para llenar la pantalla (recorta los bordes) o ver el cuadro completo.
    @State private var fillsScreen = false

    var body: some View {
        let model = holder.model
        ZStack {
            DS.video.ignoresSafeArea()
            holder.engine.surface
            holder.engine.subtitleOverlay(lifted: controlsVisible, heightFraction: env.services.appSettings.subtitleHeightFraction)
                .ignoresSafeArea()
                .animation(DS.Motion.base(reduceMotion), value: controlsVisible)
            gestureLayer(model)
            statusOverlays(model)
            if controlsVisible { controls(model).transition(.opacity) }
            if let up = model.upNext { UpNextCard(card: up, watchNow: { Task { await model.playNextNow() } }, cancel: { model.cancelUpNext() }) }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(DS.Motion.base(reduceMotion), value: controlsVisible)
        .task {
            lockLandscape()
            UIApplication.shared.isIdleTimerDisabled = true
            // `begin` va aparte: el plazo de arranque (45 s) tiene que seguir corriendo mientras carga.
            let engine = holder.engine
            pip.onActiveChange = { engine.setPictureInPictureActive($0) }
            nowPlaying.start(model: model)
            Task {
                await model.begin(request); scheduleHide()
                #if DEBUG
                if Demo.isOn, let open = Demo.player {
                    try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
                    if open == "panel" { panel = true } else if open == "sources" { sources = true } else if open == "close" { await close() }
                }
                #endif
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: DS.Timing.tick)
                await model.tick()
                pip.update(engine.pictureInPicture)
                nowPlaying.update(title: request.displayTitle, subtitle: request.episodeLabel, poster: request.poster, snapshot: model.snapshot)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.appDidEnterBackground() } } }
        .onChange(of: model.phase) { _, phase in if phase == .closed { finish() } }
        .alert("¿Sigues viendo?", isPresented: Binding(get: { model.stillWatchingPrompt }, set: { _ in })) {
            Button("Seguir") { Task { await model.confirmStillWatching() } }
            Button("Salir", role: .cancel) { Task { await close() } }
        } message: { Text("Llevas tres episodios seguidos.") }
        .sheet(isPresented: $panel) { TrackPanel(model: model, openSources: { panel = false; Task { try? await Task.sleep(nanoseconds: DS.Timing.controlsHide / 8); sources = true } }, openInInfuse: { Task { await openInInfuse() } }).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $sources) { PlayerSources(model: model) { sources = false }.presentationDetents([.large]).presentationDragIndicator(.visible) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; pip.stop(); nowPlaying.stop(); unlockPortrait() }
    }

    // MARK: gestos
    private func gestureLayer(_ model: PlayerModel) -> some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { Task { await model.skip(-PlaybackRules.skipSeconds) }; pulse() }
            Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { Task { await model.skip(PlaybackRules.skipSeconds) }; pulse() }
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
        .accessibilityHidden(true)
    }

    private func pulse() { controlsVisible = true; scheduleHide() }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
            if !Task.isCancelled, holder.model.snapshot.state == .playing { controlsVisible = false }
        }
    }

    // MARK: estados
    @ViewBuilder private func statusOverlays(_ model: PlayerModel) -> some View {
        switch model.phase {
        case .preparing: VStack(spacing: DS.Space.s3) { ProgressView().tint(DS.text); Text(preparingText(model)).font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
        case .failed(let message):
            VStack(spacing: DS.Space.s4) {
                DSNotice(text: LocalizedStringKey(message), tone: .error)
                HStack { Button("Cerrar") { Task { await close() } }.buttonStyle(.glass); Button("Abrir en Infuse") { Task { await openInInfuse() } }.dsPrimaryButton() }
            }.padding(DS.Space.s6)
        default: if !controlsVisible, model.snapshot.state == .buffering || model.snapshot.state == .loading { ProgressView().tint(DS.text) }   // con controles, va en el centro
        }
    }

    private func preparingText(_ model: PlayerModel) -> LocalizedStringKey {
        if case .triedAnotherSource(let n)? = model.notice { return "Probando otra fuente (\(n))…" }
        return "Buscando la mejor fuente…"
    }

    // MARK: controles
    private func controls(_ model: PlayerModel) -> some View {
        ZStack {
            LinearGradient(colors: [DS.scrim, .clear, DS.scrim], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack(spacing: DS.Space.s3) {
                    DSIconButton(symbol: "chevron.down", label: "Cerrar") { Task { await close() } }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(request.displayTitle).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                        if !request.episodeLabel.isEmpty { Text(request.episodeLabel).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1) }
                    }
                    Spacer()
                    if model.skipIntroTo != nil { Button("Saltar intro") { Task { await model.skipIntro() } }.buttonStyle(.glass) }
                    if pip.isPossible { DSIconButton(symbol: "pip.enter", label: "Imagen dentro de imagen") { pip.toggle() } }
                    AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                        .accessibilityLabel(Text("AirPlay"))
                    DSIconButton(symbol: "text.bubble", label: "Audio y subtítulos") { panel = true }
                }
                Spacer()
                if model.phase != .preparing { transport(model) }
                Spacer()
                if model.snapshot.duration > 0 { scrubber(model) }
            }
            .padding(DS.Space.s6)
        }
    }

    /// Retroceder, pausa y adelantar (solo cuando ya hay video: mientras busca fuente no hacen nada).
    private func transport(_ model: PlayerModel) -> some View {
        HStack(spacing: DS.Space.s10) {
            DSIconButton(symbol: "gobackward.10", label: "Retroceder 10 segundos") { Task { await model.skip(-PlaybackRules.skipSeconds) }; pulse() }
            if model.snapshot.state == .loading || model.snapshot.state == .buffering {
                ProgressView().tint(DS.text).controlSize(.large).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            } else {
                DSIconButton(symbol: model.snapshot.state == .playing ? "pause.fill" : "play.fill", label: model.snapshot.state == .playing ? "Pausa" : "Reproducir", prominent: true) { Task { await model.togglePlay() }; pulse() }
            }
            DSIconButton(symbol: "goforward.10", label: "Adelantar 10 segundos") { Task { await model.skip(PlaybackRules.skipSeconds) }; pulse() }
        }
    }

    private func scrubber(_ model: PlayerModel) -> some View {
        let duration = max(model.snapshot.duration, 1)
        let shown = scrubbing ?? model.snapshot.position
        return VStack(spacing: DS.Space.s1) {
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...duration) { editing in
                if !editing, let target = scrubbing { Task { await model.seek(to: target); scrubbing = nil } }
                pulse()
            }
            .tint(DS.primary)
            HStack {
                Text(clock(shown)).font(DS.font(.xs)).foregroundStyle(DS.textMuted).monospacedDigit()
                Spacer()
                Text("−\(clock(max(0, duration - shown)))").font(DS.font(.xs)).foregroundStyle(DS.textMuted).monospacedDigit()
            }
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: salir
    private func close() async {
        await holder.model.close()
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if request.localFile != nil {
            let id = DownloadItem.makeID(metaID: request.metaID, videoID: request.videoID)
            let snapshot = holder.model.snapshot
            if snapshot.duration > 0, snapshot.position >= snapshot.duration * StremioLibrary.watchedAt {
                Task { if let item = await env.services.downloads.item(id) { await DownloadsModel(env.services, freeSpace: { DiskSpace.freeBytes() }).afterWatching(item) } }
            }
        }
        dismiss()
    }

    private func openInInfuse() async {
        await holder.model.close()
        dismiss()
        await env.playExternal(request, source: holder.model.source)
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
                Text("Siguiente episodio").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
                Text("\(card.label) · \(card.title)").font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(2)
                if card.secondsLeft > 0 { Text("Empieza en \(card.secondsLeft) s").font(DS.font(.xs)).foregroundStyle(DS.textMuted) }
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
/// van en dos columnas (como el panel de la TV) para no tener que desplazarse.
struct TrackPanel: View {
    let model: PlayerModel
    let openSources: () -> Void
    let openInInfuse: () -> Void
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.verticalSizeClass) private var verticalSize
    @StateObject private var observer: ModelObserver<PlayerModel>

    init(model: PlayerModel, openSources: @escaping () -> Void, openInInfuse: @escaping () -> Void) {
        self.model = model; self.openSources = openSources; self.openInInfuse = openInInfuse
        _observer = StateObject(wrappedValue: ModelObserver(model))
    }

    private var locale: Locale { Locale(identifier: env.services.appSettings.uiLanguage) }

    var body: some View {
        if verticalSize == .compact {
            VStack(spacing: 0) {
                speed.padding(.horizontal, DS.Space.s4).padding(.top, DS.Space.s4)
                HStack(spacing: 0) {
                    List { audioSection }.listStyle(.insetGrouped)
                    List { subtitleSection }.listStyle(.insetGrouped)
                }
                .scrollContentBackground(.hidden)
                HStack(spacing: DS.Space.s3) {
                    Button("Otra fuente…", systemImage: "list.bullet", action: openSources).buttonStyle(.glass)
                    Button("Abrir en Infuse", systemImage: "arrow.up.forward.app", action: openInInfuse).buttonStyle(.glass)
                }
                .padding(.bottom, DS.Space.s4)
            }
        } else {
            List {
                Section { speed }.listRowBackground(DS.fill)
                audioSection
                subtitleSection
                Section("Más") {
                    Button("Otra fuente…", action: openSources)
                    Button { openInInfuse() } label: { Label("Abrir en Infuse", systemImage: "arrow.up.forward.app") }
                }
                .listRowBackground(DS.fill)
            }
        }
    }

    private var speed: some View {
        HStack(spacing: DS.Space.s3) {
            Label("Velocidad", systemImage: "gauge.with.dots.needle.67percent").foregroundStyle(DS.text).labelStyle(.titleAndIcon).fixedSize()
            DSSegmented(options: PlayerModel.rates.map { ($0, LocalizedStringKey(Self.rateText($0))) },
                        selection: Binding(get: { model.rate }, set: { (v: Float) in Task { @MainActor in await model.setRate(v) } }))
        }
    }

    static func rateText(_ rate: Float) -> String { rate == 1 ? "1×" : String(format: "%g×", rate) }

    private var audioSection: some View {
        let snapshot = model.snapshot
        return Section("Audio") {
            ForEach(snapshot.audioTracks) { track in
                row(TrackChooser.label(track, locale: locale), selected: snapshot.selectedAudio == track.id) { Task { await model.selectAudio(track.id) } }
            }
            if snapshot.audioTracks.isEmpty { Text("Sin pistas de audio").foregroundStyle(DS.textMuted) }
        }
        .listRowBackground(DS.fill)
    }

    private var subtitleSection: some View {
        let snapshot = model.snapshot
        return Section("Subtítulos") {
            row(Strings.tr("Sin subtítulos", language: env.services.appSettings.uiLanguage), selected: snapshot.selectedSubtitle == nil) { Task { await model.selectSubtitle(nil) } }
            ForEach(snapshot.subtitleTracks) { track in
                row(TrackChooser.label(track, locale: locale), selected: snapshot.selectedSubtitle == track.id) { Task { await model.selectSubtitle(track.id) } }
            }
        }
        .listRowBackground(DS.fill)
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).foregroundStyle(DS.text); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(DS.good) } }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Otra fuente…» dentro del reproductor: cambia de fuente en el mismo punto.
struct PlayerSources: View {
    let model: PlayerModel
    let done: () -> Void
    @StateObject private var observer: ModelObserver<PlayerModel>

    init(model: PlayerModel, done: @escaping () -> Void) {
        self.model = model; self.done = done
        _observer = StateObject(wrappedValue: ModelObserver(model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("Otra fuente").font(DS.font(.xl, weight: .bold)).foregroundStyle(DS.text)
            ScrollView {
                VStack(spacing: DS.Space.s2) {
                    ForEach(model.sourceChoices) { source in
                        Button { Task { await model.switchSource(to: source.index); done() } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: DS.Space.s1) {
                                    Text([source.resolution, source.languages.prefix(2).map { Streams.languageNames[$0] ?? $0 }.joined(separator: " + ")].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text)
                                    Text(source.release).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1)
                                }
                                Spacer()
                                if source.index == model.source?.index { Image(systemName: "checkmark").foregroundStyle(DS.good) }
                            }
                            .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                        }
                    }
                }
            }
        }
        .padding(DS.Space.s4)
    }
}
