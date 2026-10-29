import SwiftUI
import OrbitalCore
import OrbitalModels

/// El candado del reproductor: bloquear la pantalla, su aviso y desbloquear.
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
            if padlock.lockNoticeVisible {
                VStack {
                    PlayerLockNotice(showsUnlock: padlock.lockNoticeShowsUnlock, collapsed: padlock.lockNoticeCollapsed, risen: padlock.lockNoticeRisen, unlock: unlock)
                    Spacer(minLength: 0)
                }
                .padding(.top, DS.Space.s2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    func lock() {
        hideTask?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { controlsVisible = false; padlock.locked = true }
        freezeOrientation()
        showLockNotice(withUnlock: false)
    }

    func showUnlockPrompt() { showLockNotice(withUnlock: true) }

    /// La cápsula de arriba. Al bloquear dura un instante y no trae botón; un toque la trae con «Desbloquear» y se queda más.
    /// Luego se encoge al candado, sube y se desvanece (con «Reducir movimiento», solo se desvanece).
    func showLockNotice(withUnlock: Bool) {
        // Primero se retiene: lo que llegue a partir de aquí espera. Lo que ya se veía arriba se quita.
        notices.heldNotices.hold()
        cancelHeldDrain()
        clearTopNotices()
        padlock.lockNoticeGeneration += 1
        let generation = padlock.lockNoticeGeneration
        padlock.lockNoticeShowsUnlock = withUnlock
        withAnimation(DS.Motion.lockNoticeIn()) {
            padlock.lockNoticeCollapsed = false
            padlock.lockNoticeRisen = false
            padlock.lockNoticeVisible = true
        }
        padlock.unlockHide?.cancel()
        padlock.unlockHide = Task { @MainActor in
            try? await Task.sleep(nanoseconds: withUnlock ? DS.Timing.unlockPrompt : DS.Timing.lockNotice)
            guard !Task.isCancelled, generation == padlock.lockNoticeGeneration else { return }
            await dismissLockNotice(generation: generation)
        }
    }

    func dismissLockNotice(generation: Int) async {
        if reduceMotion {
            withAnimation(DS.Motion.lockRise(true)) { padlock.lockNoticeRisen = true }
            try? await Task.sleep(nanoseconds: UInt64(DesignTokens.Motion.base * 1_000_000_000))
        } else {
            withAnimation(DS.Motion.lockShrink(false)) { padlock.lockNoticeCollapsed = true }
            try? await Task.sleep(nanoseconds: DS.Timing.lockNoticeShrink)
            guard !Task.isCancelled, generation == padlock.lockNoticeGeneration else { return }
            withAnimation(DS.Motion.lockRise(false)) { padlock.lockNoticeRisen = true }
            try? await Task.sleep(nanoseconds: DS.Timing.lockNoticeRise)
        }
        guard !Task.isCancelled, generation == padlock.lockNoticeGeneration else { return }
        padlock.lockNoticeVisible = false
        padlock.lockNoticeCollapsed = false
        padlock.lockNoticeRisen = false
        padlock.lockNoticeShowsUnlock = false
        flushHeldNotices()
    }

    /// Lo que ya está arriba (toast, subtítulos, zoom) se quita: el candado no se apila con ello.
    /// Lo que llegue mientras la cápsula sigue en pantalla no se tira: queda en `heldNotices`.
    func clearTopNotices() {
        framing.zoomToastTask?.cancel()
        notices.notice = nil
        notices.subtitleToast = nil
        framing.zoomToast = nil
    }

    func unlock() {
        padlock.unlockHide?.cancel()
        padlock.lockNoticeGeneration += 1
        padlock.lockNoticeVisible = false
        padlock.lockNoticeCollapsed = false
        padlock.lockNoticeRisen = false
        padlock.lockNoticeShowsUnlock = false
        withAnimation(DS.Motion.base(reduceMotion)) { padlock.locked = false; controlsVisible = true }
        Orientation.allowAll()
        scheduleHide()
        flushHeldNotices()
    }

    /// La cápsula del candado está en pantalla, o todavía salen los avisos que esperaron detrás de ella.
    var topNoticesAreWaiting: Bool {
        notices.heldNotices.isHolding || !notices.heldNotices.isEmpty || notices.heldDrain?.isCancelled == false
    }

    func cancelHeldDrain() {
        notices.heldDrainGeneration += 1
        notices.heldDrain?.cancel()
        notices.heldDrain = nil
    }

    /// La cápsula ya se fue (se encogió, o se desbloqueó): los avisos que esperaron salen uno tras otro,
    /// cada uno el tiempo de siempre. Si el candado vuelve antes de vaciar la cola, lo que falta se queda.
    func flushHeldNotices() {
        notices.heldNotices.resume()
        guard !notices.heldNotices.isEmpty else { return }
        if let heldDrain = notices.heldDrain, !heldDrain.isCancelled { return }
        notices.heldDrainGeneration += 1
        let generation = notices.heldDrainGeneration
        notices.heldDrain?.cancel()
        notices.heldDrain = Task { @MainActor in
            while !Task.isCancelled, !notices.heldNotices.isHolding, !padlock.lockNoticeVisible {
                guard let item = notices.heldNotices.next() else { break }
                await presentHeld(item)
            }
            guard generation == notices.heldDrainGeneration, !Task.isCancelled else { return }
            notices.heldDrain = nil
            if !notices.heldNotices.isEmpty, !notices.heldNotices.isHolding, !padlock.lockNoticeVisible {
                flushHeldNotices()
            }
        }
    }

    /// Muestra un aviso que estaba en espera. VoiceOver se entera aquí, cuando de verdad aparece.
    func presentHeld(_ item: QueuedNotice) async {
        switch item {
        case .player(let new):
            framing.zoomToastTask?.cancel()
            withAnimation(DS.Motion.base(reduceMotion)) { notices.subtitleToast = nil; framing.zoomToast = nil }
            reveal(new)
            try? await Task.sleep(nanoseconds: Toast.duration(new.tone, hasAction: new.showsDownloads || new.switchTo != nil) ?? DS.Timing.toastAction)
        case .subtitle(let text):
            framing.zoomToastTask?.cancel()
            withAnimation(DS.Motion.base(reduceMotion)) { notices.notice = nil; framing.zoomToast = nil }
            await revealSubtitle(text)
        case .zoom(let target):
            withAnimation(DS.Motion.base(reduceMotion)) { notices.notice = nil; notices.subtitleToast = nil }
            await revealZoom(target)
        }
    }

    func revealZoom(_ target: VideoZoom) async {
        withAnimation(DS.Motion.base(reduceMotion)) { framing.zoomToast = target }
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { if framing.zoomToast == target { framing.zoomToast = nil } }
    }
}
