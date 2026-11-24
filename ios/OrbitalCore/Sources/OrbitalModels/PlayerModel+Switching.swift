import Foundation
import OrbitalCore

/// Los cambios dentro del reproductor que se tienen que sentir al instante: otra versión del video (en el mismo segundo, y de
/// vuelta a la tuya si no abre) y otra pista de audio (la palomita va donde tocaste mientras el motor la pone). Regla: lo que
/// eliges se ve elegido al tocar, y un toque nuevo gana al anterior aunque el anterior todavía esté cargando (23 nov 2026).
extension PlayerModel {
    /// Lo más que la palomita espera a que el motor confirme la pista de audio (si no la pone, vuelve a la que suena).
    static let pendingAudioWait: Double = 10

    /// Cambiar de versión a mano (en la hoja, o un idioma que solo trae otra versión: `language`). Se pausa y se toma el
    /// segundo exacto; cuenta como «la elegiste tú» (ya no se ofrece cambiar otra vez); si no abre, se vuelve a la que veías
    /// en el mismo segundo (antes caía a cualquier otra); el idioma elegido sigue en los siguientes episodios.
    /// Si la lista de fuentes es vieja (los enlaces de Real-Debrid caducan) se pide de nuevo, ya con la carga a la vista.
    public func switchSource(to index: Int, language: String? = nil) async {
        guard let request, !closing else { return }
        userTouched()
        let wasPlaying = snapshot.state == .playing || snapshot.state == .buffering
        if snapshot.state == .playing { await engine.pause() }
        generation += 1
        let mine = generation
        // Otro cambio que aún no suena (tocaste dos versiones seguidas): se sigue en su segundo y, si esta no abre, se vuelve a
        // la que de verdad veías. Antes se tomaba el 0 del motor abriendo y el video volvía a empezar desde el principio.
        let inFlight = hasPlayed ? nil : switchBack
        let position = hasPlayed ? snapshot.position : (inFlight?.position ?? loadTarget)
        let previous = inFlight?.source ?? source
        let previousPhase = phase
        notice = nil   // el aviso era de la versión que dejas
        acceptingSnapshots = false
        phase = .preparing   // la carga se ve al tocar, también mientras se piden enlaces nuevos
        if clock().timeIntervalSince(choicesAt) > Self.choicesLifetime {
            let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
            if let fresh = try? await finder.find(kind: request.kind, videoID: request.videoID, prefs: prefs, fresh: true) { sourceChoices = fresh; choicesAt = clock() }
        }
        guard mine == generation, !closing else { return }   // ya pediste otra: esa manda
        guard let choice = sourceChoices.first(where: { $0.index == index }) ?? sourceChoices.first(where: { $0.release == source?.release && $0.index == index }),
              let url = choice.playbackURL else {
            // Ya no está (o no tiene enlace): sigues en la que veías, como estaba.
            acceptingSnapshots = true; phase = previousPhase
            if wasPlaying { await engine.play() }
            return
        }
        self.request?.sourceIndex = index
        let subtitlesWereOn = snapshot.selectedSubtitle != nil
        source = choice
        // Suelta lo que el motor estuviera abriendo: si la versión de antes se quedó cargando, la nueva quedaba formada detrás de
        // ella y la pantalla solo enseñaba la carga (el iPhone el 29 oct).
        await engine.stop()
        guard mine == generation, !closing else { return }
        startLoading()
        if !choice.instant { queued.mark(choice.key, at: clock()) }   // abrirla le pide a Real-Debrid que la baje
        if let previous { switchBack = (previous, position) }
        forgetSubtitleSearch()   // otro archivo: «coincide con tu copia» se vuelve a calcular con su huella
        if subtitlesWereOn { askInSync = true }   // otro archivo, la sincronía empieza en 0: «¿Va a tiempo?»
        do {
            try await loadVideo(url, at: position)
            guard mine == generation else { return }
            if let language { titlePrefs.remember(metaID: request.metaID, audioTrack: language) }
        } catch {
            guard mine == generation else { return }
            markFailed(choice, "la elegiste y no abrió: \(error)")
            if !goBackAfterSwitch() { await retryWithAnotherSource("la elegiste y no abrió")?.value }
        }
    }

    /// Vuelve a la versión que veías antes de cambiar a mano, en el mismo segundo. false si no hay a cuál volver.
    @discardableResult
    func goBackAfterSwitch() -> Bool {
        guard let back = switchBack, let url = back.source.playbackURL, !closing else { return false }
        switchBack = nil
        if let source, source.index != back.source.index { markFailed(source, "la elegiste y no llegó a sonar: se vuelve a la de antes") }
        generation += 1
        let mine = generation
        acceptingSnapshots = false
        request?.sourceIndex = back.source.index
        source = back.source
        phase = .preparing
        if notice != .notReadyOnRealDebrid { notice = .switchFailedBack }
        transition = Task { [weak self] in
            guard let self else { return }
            await engine.stop()
            guard mine == generation else { return }
            startLoading()
            do { try await loadVideo(url, at: back.position) } catch { guard mine == generation else { return }; await retryWithAnotherSource()?.value }
        }
        return true
    }

    // MARK: audio

    /// La pista de audio que se ve elegida: la que tocaste mientras el motor la pone (cambiarla rearma el video, ~2 s); si no,
    /// la que suena.
    public var shownAudio: Int? { pendingAudio ?? snapshot.selectedAudio }

    public func selectAudio(_ id: Int?) async {
        userTouched()
        if let id, id != snapshot.selectedAudio { pendingAudio = id; pendingAudioAt = clock() } else { pendingAudio = nil; pendingAudioAt = nil }
        await engine.selectAudio(id)
        if let id, let track = snapshot.audioTracks.first(where: { $0.id == id }), let request {
            titlePrefs.remember(metaID: request.metaID, audioTrack: track.language)
        }
    }

    /// El motor ya puso la pista que tocaste (o no la puso a tiempo): la palomita vuelve a seguir al motor.
    func settlePendingAudio(_ s: EngineSnapshot, now: Date) {
        guard let pending = pendingAudio else { return }
        if s.selectedAudio == pending || now.timeIntervalSince(pendingAudioAt ?? now) >= Self.pendingAudioWait { pendingAudio = nil; pendingAudioAt = nil }
    }
}
