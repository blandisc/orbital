import Foundation
import OrbitalCore

/// Lo que dice el motor en cada instante: avance, pistas, fin del video, fallas; y lo que el modelo decide con eso.
extension PlayerModel {
    // MARK: lo que dice el motor
    func handle(_ raw: EngineSnapshot) async {
        guard phase != .closed, acceptingSnapshots, !retrying else { return }
        // Hasta que el motor abre el archivo nuevo, lo que diga es del video anterior (avisos que se quedaron formados): antes un
        // «suena» viejo daba por arrancada una versión que no había abierto, se quitaba su plazo y cargaba para siempre.
        if !engineOpened, raw.state != .loading, raw.state != .idle { return }
        var s = raw
        s.position = StremioLibrary.finite(s.position); s.duration = StremioLibrary.finite(s.duration)   // NaN o infinito (en vivo) no valen
        let now = clock()
        let previous = snapshot
        // Segundos vistos: solo cuenta el tiempo en que estuvo reproduciendo (y sin saltos raros).
        if previous.state == .playing, let last = lastSnapshotAt { watchedUnsaved += min(max(0, now.timeIntervalSince(last)), 5) }
        lastSnapshotAt = now
        snapshot = s
        restoreOffsetIfVersionChanged()
        if pendingResumeFraction != nil, s.state == .playing || s.state == .paused, !isPlaceholder(s) { await seekToPendingResume(s) }

        if case .failed(let message) = s.state {
            // Una fuente que se corta (antes o después de empezar) se cambia por otra en el mismo punto, como en Orbital.
            // El cambio corre aparte: así los avisos repetidos del mismo fallo, que ya están en cola, se descartan mientras se carga la otra.
            // La que elegiste a mano y no llegó a sonar: se vuelve a la tuya.
            _ = message
            if !goBackAfterSwitch() { retryWithAnotherSource() }
            return
        }
        // El aviso de Real-Debrid (una versión que aún no tiene): no es el título. Nunca cuenta como visto, terminado ni pasa
        // al siguiente episodio; se vuelve a la tuya (si la cambiaste a mano) o se prueba otra.
        if !hasPlayed, isPlaceholder(s) {
            if let source { failedSources.insert(source.index) }
            notice = .notReadyOnRealDebrid
            if !goBackAfterSwitch() { retryWithAnotherSource() }
            return
        }
        if !hasPlayed, acceptingSnapshots, "\(s.state)" != lastLoggedState {   // antes de sonar: cada cambio del motor, con su tiempo
            lastLoggedState = "\(s.state)"
            Self.note(String(format: "motor: %@ (%.1f s)", lastLoggedState, clock().timeIntervalSince(loadStartedAt)))
        }
        if s.state == .playing && !hasPlayed { Self.note(String(format: "suena en %d s (%.1f s desde que empezó a cargar)", Int(s.position), clock().timeIntervalSince(loadStartedAt))); hasPlayed = true; startupPosition = s.position; startupDeadline = nil; phase = .playing; switchBack = nil }
        if let request = playRequest, s.state == .playing, s.position > request.position + 0.3 { playRequest = nil }   // ya avanza
        // Rearmando el mismo video en pausa (al volver de segundo plano): en pausa también es «ya está». Antes se esperaba a que
        // sonara, se quedaba en «preparando» sin botones y a los 45 s cambiaba de fuente y arrancaba solo.
        if restoringInPlace, !hasPlayed, s.state == .paused, s.duration > 0 {
            hasPlayed = true; startupDeadline = nil; phase = .playing; restoringInPlace = false
        }
        if hasPlayed, !playbackSettled, s.state == .paused || s.state == .ended || (s.state == .playing && s.position >= startupPosition + Self.startupSettleSeconds) {
            playbackSettled = true
        }
        if reconnecting, hasPlayed, foregroundCheck == nil, s.state == .playing || s.state == .paused { reconnecting = false }
        if hasPlayed {
            // Primero el audio y los subtítulos, pero sin detener al reproductor: si piden red (buscar subtítulos, la huella de la
            // copia) y tardan, se terminan solos y el video sigue respondiendo. Antes la barra y la pausa no respondían hasta 30 s.
            if !tracksApplied { await Self.waitBriefly(Task { await self.applyTracksOnce(s) }, seconds: Self.trackSetupWait) }
            await selectNewSubtitleIfAny(s)
            updateSkipIntro(s)
            await evaluateUpNext(s, now: now)
        }
        guard phase != .closed, acceptingSnapshots else { return }
        if hasPlayed { await scrobbleIfNeeded(s) }
        if s.state == .ended && !reachedEnd { reachedEnd = true; await finishAndAdvance() }
    }

    /// Lo que Trakt debe saber ahora. El `start` sale cuando el motor de verdad suena (no al pedir el video) y ya se sabe la duración
    /// (sin ella no hay porcentaje: se manda en cuanto aparece). Después se sigue lo que Trakt sabe, no la transición del motor:
    /// pausar → `pause`; volver a sonar, aunque sea tras pasar por «cargando» (pausa, salto y seguir), → `start`; y un salto grande → `start`
    /// con el avance nuevo (su «Viendo ahora» calcula cuándo terminas con el último aviso).
    func scrobbleIfNeeded(_ s: EngineSnapshot) async {
        // Ya se dijo «terminé» (p. ej. «¿Sigues viendo?» pausa después): una pausa ahí dejaría en Trakt un «en pausa» de algo visto.
        guard !finalReported, let known = event()?.duration, known > 0 else { return }
        if !scrobbleStarted {
            guard s.state == .playing else { return }
            scrobbleStarted = true; scrobblePlaying = true; rescrobbleAfterSeek = false
            await report(.started)
        } else if s.state == .paused && scrobblePlaying {
            scrobblePlaying = false
            await report(.paused)
        } else if s.state == .playing && (!scrobblePlaying || rescrobbleAfterSeek) {
            scrobblePlaying = true; rescrobbleAfterSeek = false
            await report(.started)
        }
    }

    /// Cada segundo desde la vista: guardado cada minuto, plazo de arranque y cuenta atrás.
    public func tick() async {
        guard phase != .closed, !closing else { return }
        let now = clock()
        defer { lastTick = now }
        // El reloj nunca se queda esperando una carga: si el motor se colgaba abriendo el archivo, `tick` no volvía, nadie revisaba
        // el plazo y la pantalla cargaba para siempre (44 min en el iPhone el 29 oct). Lo largo corre aparte (`transition`).
        if foregroundCheck != nil { checkForegroundStall(now: now) }
        if playRequest != nil { checkPlayRequest(now: now) }
        checkBufferingStall(now: now)
        if foregroundPending, acceptingSnapshots, !retrying {
            foregroundPending = false
            transition = Task { [weak self] in await self?.appDidBecomeActive() }
        }
        if let deadline = startupDeadline, now >= deadline, !hasPlayed, phase == .preparing, !retrying {
            Self.note("no arrancó en \(Int(PlaybackRules.startupTimeout)) s")
            if goBackAfterSwitch() { return }
            _ = retryWithAnotherSource()   // corre aparte: el reloj sigue revisando
            return
        }
        // En pausa la cuenta de «Siguiente» también se detiene (antes, al seguir, saltaba de golpe).
        if snapshot.state != .playing, upNext != nil, let deadline = upNextDeadline {
            upNextDeadline = deadline.addingTimeInterval(now.timeIntervalSince(lastTick ?? now))
        }
        if snapshot.state == .playing {
            if now.timeIntervalSince(lastSave) >= PlaybackRules.saveEvery { await report(.tick) }
            if var card = upNext, let deadline = upNextDeadline {
                // Con un panel abierto la tarjeta no se ve: la cuenta se detiene (no cambia de episodio a escondidas).
                if panelOpen { upNextDeadline = deadline.addingTimeInterval(now.timeIntervalSince(lastTick ?? now)); lastTick = now; return }
                card.secondsLeft = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
                upNext = card
                // Sin esperar: si el siguiente episodio se colgaba al abrir, el reloj se quedaba ahí y nadie revisaba su plazo.
                if now >= deadline { _ = advance(auto: true) }
            }
        }
    }

    /// Cambia a otra fuente en el mismo punto. Marca el cambio de forma síncrona (lo que el motor diga ahora se ignora) y carga aparte.

    /// Cambia a otra fuente en el mismo punto. Marca el cambio de forma síncrona (lo que el motor diga ahora se ignora) y carga aparte.
    @discardableResult
    func retryWithAnotherSource() -> Task<Void, Never>? {
        guard !retrying, !closing else { return transition }
        guard request?.localFile == nil else { fail("No pude abrir el archivo descargado.", .localFile); return nil }
        retrying = true; acceptingSnapshots = false; startupDeadline = nil
        Self.note("otra versión (ya fallaron \(failedSources.count + 1))")
        if let source { failedSources.insert(source.index) }
        attempts = failedSources.count
        guard failedSources.count <= PlaybackRules.maxSourceRetries else { retrying = false; fail("Ninguna versión funcionó.", .noneWorked); return nil }
        notice = .triedAnotherSource(attempt: failedSources.count)
        let position = snapshot.position
        generation += 1
        let mine = generation
        phase = .preparing
        let task = Task { [weak self] in
            guard let self else { return }
            await engine.stop()
            await prepare(startAt: position > 5 ? position : nil, generation: mine)
        }
        transition = task
        return task
    }
}
