import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Gestos del reproductor: bloquear, toques, doble toque, pellizco, arrastres (brillo, volumen, buscar, mover el video) y ×2. (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: bloquear
    /// Bloqueado: todo toque solo enseña la cápsula; nada pausa, adelanta ni mueve el video, y el giro se congela
    /// en la orientación de ese momento (girar el teléfono no voltea el video).
    /// El aviso va arriba, dentro del área segura, en los dos sentidos: nunca tapa el centro del video.
    var lockLayer: some View {
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

    func lock() {
        hideTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; locked = true }
        freezeOrientation()
        showLockNotice(withUnlock: false)
    }

    func showUnlockPrompt() { showLockNotice(withUnlock: true) }

    /// La cápsula de arriba. Al bloquear dura un instante y no trae botón; un toque la trae con «Desbloquear» y se queda más.
    /// Luego se encoge al candado, sube y se desvanece (con «Reducir movimiento», solo se desvanece).
    func showLockNotice(withUnlock: Bool) {
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

    func dismissLockNotice(generation: Int) async {
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
    func clearTopNotices() {
        zoomToastTask?.cancel()
        notice = nil
        subtitleToast = nil
        zoomToast = nil
    }

    func unlock() {
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
    var topNoticesAreWaiting: Bool {
        heldNotices.isHolding || !heldNotices.isEmpty || heldDrain?.isCancelled == false
    }

    func cancelHeldDrain() {
        heldDrainGeneration += 1
        heldDrain?.cancel()
        heldDrain = nil
    }

    /// La cápsula ya se fue (se encogió, o se desbloqueó): los avisos que esperaron salen uno tras otro,
    /// cada uno el tiempo de siempre. Si el candado vuelve antes de vaciar la cola, lo que falta se queda.
    func flushHeldNotices() {
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
    func presentHeld(_ item: QueuedNotice) async {
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

    func revealZoom(_ target: VideoZoom) async {
        withAnimation(DS.Motion.base(reduceMotion)) { zoomToast = target }
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { if zoomToast == target { zoomToast = nil } }
    }

    // MARK: gestos
    func gestureLayer(_ model: PlayerModel) -> some View {
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
                // Un toque justo mientras se desvanecen los vuelve a mostrar (no los alterna: «toqué y no salió nada»).
                if !controlsVisible || Date().timeIntervalSince(controlsHiddenAt) < DS.Timing.controlsFadeGrace { controlsVisible = true } else { controlsVisible = false }
                if controlsVisible { scheduleHide() }
            }
            // Tocar con dos dedos, en cualquier parte: pausa o sigue (como en Infuse y en la app TV de Apple).
            .gesture(TwoFingerTap {
                twoFingerTapAt = Date()
                // Un toque con dos dedos también le llega al pellizco (iOS lo mide como si los dedos se abrieran): si ya alcanzó a
                // cambiar el zoom, se deshace. Así pausar con dos dedos nunca deja la imagen agrandada.
                if let undo = zoomBeforePinch, Date().timeIntervalSince(undo.at) < DS.Gesture.pinchTapGuard {
                    zoomBeforePinch = nil; setZoom(undo.zoom, cause: "deshecho: era un toque con dos dedos")
                }
                // Si el mismo toque ya alcanzó a contar como uno de un dedo, se deshace lo que hizo con los controles.
                if Date().timeIntervalSince(singleTapAt) < DS.Gesture.twoFingerTapGuard { controlsVisible.toggle(); singleTapAt = .distantPast }
                userTogglePlay(model)
                flash(model.snapshot.state == .playing ? "pause.fill" : "play.fill")
            })
            .gesture(MagnifyGesture().onChanged { _ in if pinchStartedAt == nil { pinchStartedAt = Date() } }.onEnded { value in
                // Abrir los dedos llena la pantalla; cerrarlos vuelve al cuadro completo (como la app TV de Apple).
                let lasted = pinchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                pinchStartedAt = nil
                #if DEBUG
                lastPinch = Double(value.magnification)   // para las pruebas de interfaz (sale en el renglón «Zoom» del «⋯»)
                #endif
                // No cuentan: un pellizco justo al girar (el agarre), uno instantáneo o uno junto a un toque con dos dedos (pausar):
                // iOS los reporta como si abrieras los dedos y la imagen quedaba agrandada en vertical sin querer.
                guard Date().timeIntervalSince(rotatedAt) > DS.Gesture.pinchAfterRotationGuard,
                      lasted >= DS.Gesture.pinchMinDuration,
                      Date().timeIntervalSince(twoFingerTapAt) > DS.Gesture.pinchTapGuard,
                      let target = VideoZoom.pinched(magnification: Double(value.magnification)), target != zoom else { return }
                zoomBeforePinch = (zoom, Date())
                setZoom(target, cause: String(format: "pellizco %.2f× en %.2f s", Double(value.magnification), lasted))
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
    func dragGesture(_ model: PlayerModel, size: CGSize) -> some Gesture {
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

    @ViewBuilder var gestureOverlays: some View {
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
        // Buscar arrastrando sobre el video: la burbuja es la misma de la barra (los controles se ven mientras arrastras). Solo el
        // iPod, que no tiene esa barra, usa la suya.
        if ipod != nil, dragAxis == .horizontal, let target = seekPreview, let start = seekPositionAtDragStart {
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
            // Los avisos de texto, todos en el mismo lugar (arriba, como el de subtítulos); antes el del zoom en vertical salía al
            // centro del video. Al centro del video solo van los glifos de los gestos.
            VStack {
                DSToastPill(text: LocalizedStringKey(zoomToast.title), detail: zoomToast == .fill ? Text("Llena la pantalla y recorta los lados")
                            : zoomToast == .stretch ? Text("Llena la pantalla deformando la imagen") : nil)
                Spacer()
            }
            .padding(.top, DS.Space.s14)
            .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
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
            // Al centro del video (donde va el botón grande), no de la pantalla: en vertical quedaba debajo de la imagen.
            GeometryReader { geo in
                let rect = videoRect(in: geo.size)
                Image(systemName: flashSymbol).font(DS.TextRecipe.display.font).foregroundStyle(DS.text)
                    .frame(width: DS.Size.touchTarget * 2, height: DS.Size.touchTarget * 2)
                    .glassEffect(.regular, in: Circle())
                    .position(x: rect.midX, y: rect.midY)
            }
            .transition(.scale.combined(with: .opacity)).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// La burbuja de buscar, justo encima de la barra de avance, en la x del tiempo destino (sin salirse de los bordes).
    func seekBubble(target: Double, start: Double) -> some View {
        let delta = target - start
        let duration = max(holder.model.snapshot.duration, 1)
        return GeometryReader { geo in
            let fraction = CGFloat(max(0, min(1, target / duration)))
            let rawX = DS.Space.gutter + (geo.size.width - DS.Space.gutter * 2) * fraction
            let x = min(max(rawX, DS.Gesture.seekBubbleSideMargin), geo.size.width - DS.Gesture.seekBubbleSideMargin)
            let y = geo.size.height - DS.Gesture.seekBubbleBottomInset   // solo el iPod: sobre su rueda
            DSSeekBubble(time: clock(target), delta: "\(delta >= 0 ? "+" : "−")\(clock(abs(delta)))")
                .position(x: x, y: y)
        }
        .transition(.opacity).allowsHitTesting(false)
    }

    func scheduleIndicatorHide() {
        indicatorHideTask?.cancel()
        indicatorHideTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { indicatorVisible = false }
        }
    }

    /// La píldora «2×» se ve mientras mantienes el dedo y, si quedó fija, cuando hay controles. Bloqueada la pantalla, no.
    var speedPillVisible: Bool { isFastForwarding && (fastForwardHolding || controlsVisible) && !locked }

    /// Abajo al centro. Horizontal: justo encima de la barra. Vertical: al pie del área segura, salvo «Recortar» con
    /// controles, que va encima de su barra.
    var speedPillBottomInset: CGFloat {
        if landscape { return DS.Gesture.fastForwardPillBottomInset }
        if fillsPortrait && controlsVisible { return DS.Gesture.fastForwardPillFillInset }
        return DS.Space.s2
    }

    var speedPill: some View {
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
    func cancelVideoMove() {
        portraitDrag = nil
        movingVideo = false
        if dragAxis == .vertical { dragAxis = .undecided; verticalKind = nil }
    }

    /// ×2 como TikTok: mantener el dedo lo pone mientras dure. Hacia abajo se fija; hacia arriba vuelve a la velocidad previa.
    func holdFastForward(_ model: PlayerModel) {
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
    func fastForwardDrag(translationY: CGFloat, screenHeight: CGFloat, model: PlayerModel) {
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
    func releaseFastForward(_ model: PlayerModel) {
        let wasHolding = fastForwardHolding
        fastForwardHolding = false
        fastForwardOwnsTouch = false
        fastForwardProgress = 0
        if wasHolding, !fastForwardLocked { endFastForward(model, force: true) }
        if controlsVisible { scheduleHide() }
    }

    func endFastForward(_ model: PlayerModel, force: Bool = false) {
        guard isFastForwarding, force || !fastForwardLocked else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { isFastForwarding = false; fastForwardLocked = false }
        fastForwardProgress = 0
        Task { await model.setRate(rateBeforeFastForward) }
    }

    #if DEBUG
    /// Para `-demo-gesture`: pone el indicador a medio camino sin tocar la pantalla, para capturarlo en el simulador.
    /// `fastforward-locked` deja el ×2 fijo, con la píldora y los controles a la vista.
    func simulateGesture(_ kind: String, model: PlayerModel) {
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

    func pulse() { controlsVisible = true; scheduleHide() }

    /// Cambia el zoom (botón o pellizco), lo recuerda para la próxima vez y avisa un momento cuál quedó.
    func setZoom(_ target: VideoZoom, cause: String = "menú") {
        PlayerModel.note("zoom \(landscape ? "horizontal" : "vertical") → \(target.rawValue) (\(cause))")
        let queueToast = topNoticesAreWaiting
        if queueToast { heldNotices.hold(.zoom(target), key: QueuedNoticeKey.zoom) }
        withAnimation(DS.Motion.base(reduceMotion)) {
            if landscape { landscapeZoom = target } else { portraitZoom = target }
            if !queueToast { zoomToast = target }
        }
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
    func skip(_ model: PlayerModel, forward: Bool, taps: Int = 1) {
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
    func continuesSkip(at location: CGPoint, width: CGFloat) -> Bool? {
        guard let chain = skipChain, Date().timeIntervalSince(chain.at) < DS.Gesture.skipChain else { return nil }
        let third = width * DS.Gesture.edgeShare
        if chain.forward && location.x > width - third { return true }
        if !chain.forward && location.x < third { return false }
        return nil
    }

    /// Un ícono grande que aparece y se va (el doble toque se nota sin abrir los controles).
    func flash(_ symbol: String) {
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
    func indicatorPlacement(in size: CGSize) -> (y: CGFloat, bar: CGFloat) {
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
    func startsOnHandle(_ point: CGPoint, size: CGSize) -> Bool {
        guard !landscape, !fillsPortrait, ipod == nil else { return false }
        let rect = videoRect(in: size)
        return point.y >= rect.maxY - DS.PlayerPanel.handleGrab && point.y <= rect.maxY + DS.PlayerPanel.handleBelow
    }

    func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: DS.Timing.controlsHide)
            // Con la barra de avance bajo el dedo, los controles no se esconden (se iría el slider a media búsqueda).
            if !Task.isCancelled, !voiceOver, !moreOpen, scrubbing == nil, holder.model.snapshot.state == .playing {
                controlsVisible = false; controlsHiddenAt = Date()
            }
        }
    }
}
