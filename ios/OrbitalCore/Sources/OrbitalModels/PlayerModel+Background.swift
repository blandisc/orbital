import Foundation
import OrbitalCore

/// Volver de segundo plano: rearmar el video donde iba (o seguir si nunca se soltó) y qué hacer si el motor no puede.
extension PlayerModel {
    // MARK: volver de segundo plano
    static let foregroundStallSeconds: TimeInterval = 8

    /// Ya sonaba y se detuvo a esperar datos (Real-Debrid o la red se atoraron): pasado este tiempo se pide otra vez en el mismo
    /// punto. Antes se quedaba cargando para siempre; si la nueva petición tampoco arranca, su plazo prueba otra versión.
    static let bufferingStallSeconds: TimeInterval = 20

    func checkBufferingStall(now: Date) {
        guard hasPlayed, phase == .playing, snapshot.state == .buffering || snapshot.state == .loading, acceptingSnapshots, !retrying, !reconnecting,
              foregroundCheck == nil, playRequest == nil, !closing else { bufferingSince = nil; return }
        guard let since = bufferingSince else { bufferingSince = now; return }
        guard now.timeIntervalSince(since) >= Self.bufferingStallSeconds else { return }
        bufferingSince = nil
        Self.note("en búfer \(Int(now.timeIntervalSince(since))) s en \(Int(snapshot.position)) s: se pide otra vez")
        startReload(at: snapshot.position, resume: true)
    }

    /// La app pasó a segundo plano de verdad (no solo el Centro de control): se recuerda si iba sonando.
    public func appDidEnterBackgroundFully() {
        guard hasPlayed, phase == .playing, !closing else { return }
        backgrounded = true
        resumeOnForeground = snapshot.state == .playing || snapshot.state == .buffering
        backgroundPosition = snapshot.position   // al volver, el motor ya soltó el video y dice 0: este es el punto de verdad
        Self.note("a segundo plano en \(Int(backgroundPosition)) s")
    }

    /// De vuelta al frente: el motor rearma su video (lo soltó en segundo plano); si no puede, o si el video no vuelve a
    /// avanzar, se vuelve a pedir la misma fuente en el mismo punto (con enlace nuevo si el de Real-Debrid caducó).
    public func appDidBecomeActive() async {
        guard backgrounded else { return }
        Self.note("de vuelta a la app (sonaba: \(resumeOnForeground))")
        // Volviste justo mientras se cambiaba de versión: todavía no hay qué rearmar. Se queda pendiente y se revisa en cuanto la
        // versión nueva esté lista (`tick`); antes se olvidaba y la pantalla quedaba negra con el play sin responder.
        if !closing, !acceptingSnapshots || retrying { foregroundPending = true; return }
        backgrounded = false
        guard hasPlayed, phase == .playing, !closing else { return }
        let resume = resumeOnForeground
        let position = max(snapshot.position, backgroundPosition)   // antes: el 0 del motor y se volvía a cargar desde el principio
        let mine = generation
        // Sin aviso al volver: casi siempre el video sigue donde estaba. Solo si de verdad hay que pedirlo otra vez
        // (el motor no pudo rearmarlo, o no avanzó en el plazo) se dice que está cargando.
        // El plazo corre desde antes de rearmar: si el motor se colgaba rearmando (un enlace caducado tras mucho rato fuera), nada
        // lo revisaba y cargaba para siempre.
        if resume { foregroundCheck = (clock().addingTimeInterval(Self.foregroundStallSeconds), position) }
        if position > 0 { skipAnchor = position }
        // En pausa, rearmar es cosa del motor: tú ves el cuadro donde ibas y el play, sin la ruedita. Si tocas play mientras,
        // entonces sí se enseña la carga (ya querías verlo) y suena en cuanto el video está listo.
        restoringQuietly = !resume
        let restored = await engine.restoreAfterBackground(resume: resume)
        restoringQuietly = false
        guard mine == generation, !closing else { return }
        if !restored { foregroundCheck = nil; return await reloadCurrentSource(at: position, resume: resume || playRequest != nil) }
        if !resume, playRequest != nil { await engine.play() }   // el motor terminó de rearmar en pausa: lo que pediste
        if hasPlayed { updateSkipIntro(snapshot) }   // en pausa el motor ya no avisa: el botón se decide con lo de ahora
    }

    /// El plazo tras volver: el video tenía que avanzar y no lo hizo (negro o congelado) → se pide de nuevo.
    func checkForegroundStall(now: Date) {
        guard let check = foregroundCheck, !retrying, !reconnecting else { return }
        if snapshot.state == .paused { foregroundCheck = nil; reconnecting = false; return }   // lo pausaste tú
        if snapshot.state == .playing, snapshot.position > check.position + 0.5 { foregroundCheck = nil; reconnecting = false; return }
        guard now >= check.deadline else { return }
        foregroundCheck = nil
        startReload(at: max(check.position, snapshot.position, backgroundPosition), resume: true)
    }

    /// Vuelve a abrir la fuente que sonaba en el mismo punto: la descarga, tu copia (enlace nuevo) o la de Real-Debrid
    /// (con la lista renovada si ya caducó). Si tampoco abre, se prueba otra fuente como en cualquier corte.
    /// Pide el video otra vez sin esperar a que cargue (para el reloj: él tiene que seguir revisando el plazo).
    func startReload(at position: Double, resume: Bool) {
        transition = Task { [weak self] in await self?.reloadCurrentSource(at: position, resume: resume) }
    }

    func reloadCurrentSource(at position: Double, resume: Bool) async {
        guard let request, !closing else { return }
        reconnecting = true
        generation += 1
        let mine = generation
        acceptingSnapshots = false
        var url: URL?
        if let file = request.localFile { url = file }
        else if let current = source {
            if request.ownCopy, !sourceChoices.contains(where: { $0.key == current.key }), let own = await ownSource?(request.videoID, current.index) {
                source = own; url = own.playbackURL
            } else {
                if clock().timeIntervalSince(choicesAt) > Self.choicesLifetime {
                    let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
                    if let fresh = try? await finder.find(kind: request.kind, videoID: request.videoID, prefs: prefs, fresh: true) { sourceChoices = fresh; choicesAt = clock() }
                }
                let pick = sourceChoices.first(where: { $0.key == current.key }) ?? current
                source = pick; url = pick.playbackURL
            }
        }
        guard mine == generation, !closing else { return }
        if position > 0 { skipAnchor = position }
        await engine.stop()   // suelta lo que el motor estuviera abriendo (si se colgó, la carga nueva no queda detrás)
        guard mine == generation, !closing else { return }
        startLoading()
        phase = .preparing
        restoringInPlace = !resume
        guard let url else { await retryWithAnotherSource()?.value; return }
        do {
            try await loadVideo(url, at: position)
            if !resume, mine == generation { await engine.pause() }
        } catch {
            guard mine == generation else { return }
            await retryWithAnotherSource()?.value
        }
    }
}
