import Foundation
import OrbitalCore

/// Saltar la intro o el resumen (IntroDB), la cuenta de «Siguiente episodio» y pasar al que sigue.
extension PlayerModel {
    // MARK: intro y siguiente episodio
    func loadSegmentsIfNeeded() {
        guard let videoID = request?.videoID, segmentsFor != videoID else { return }
        segmentsFor = videoID
        segments = nil
        let fetch = skipSegments
        Task { [weak self] in
            // Un tropiezo de red (o el límite de 6 s) no deja el video sin «Saltar intro»: se pide otra vez antes de rendirse.
            var found = await fetch(videoID)
            for delay in self?.segmentRetryDelays ?? [] where found == nil {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.request?.videoID == videoID, self.phase != .closed else { return }
                found = await fetch(videoID)
            }
            guard let self, self.request?.videoID == videoID else { return }
            // Sin marcas: la próxima carga del mismo video (otra fuente, volver a abrirlo) las vuelve a pedir.
            if found == nil { self.segmentsFor = nil; return }
            self.segments = found
            // El botón sale en cuanto llegan, sin esperar al siguiente aviso del motor (en pausa no llega ninguno).
            if self.playbackSettled { self.updateSkipIntro(self.snapshot) }
        }
    }

    /// «Saltar intro» / «Saltar resumen»: primero los capítulos del archivo; si no los trae, las marcas de la comunidad.
    func updateSkipIntro(_ s: EngineSnapshot) {
        if demoPinned { return }
        // Cargando o rearmando al volver de segundo plano, la posición pasa un momento por 0 (o por el inicio): ahí no
        // aplica (salía «Saltar intro» a media película al regresar a la app).
        // Y hasta que el video corre de verdad (`playbackSettled`, lo mismo que quita la carga del botón grande): el motor dice
        // «suena» con casi nada en el búfer y el botón salía con el video aún cargando (30 oct).
        if s.state == .loading || !playbackSettled || reconnecting || backgrounded || restoringQuietly { skipIntroTo = nil; return }
        // De vuelta a la app, el motor rearmado dice un momento 0:00 y luego, en pausa, ya no avisa: el botón salía con la intro
        // ya pasada y se quedaba (31 oct). Hasta que la posición coincide con donde ibas, no hay botón.
        if let anchor = skipAnchor {
            guard abs(s.position - anchor) <= Self.skipAnchorTolerance else { skipIntroTo = nil; return }
            if s.state == .playing { skipAnchor = nil }   // ya corre desde ahí: de aquí en adelante la posición es de verdad
        }
        let sorted = s.chapters.sorted { $0.time < $1.time }
        for (i, chapter) in sorted.enumerated() where PlaybackRules.chapterKind(chapter.title) == .intro {
            let end = i + 1 < sorted.count ? sorted[i + 1].time : s.duration
            if s.position >= chapter.time && s.position < end - 1 { skipKind = .intro; skipIntroTo = end; return }
        }
        for (kind, range) in [(SkipKind.recap, segments?.recap), (.intro, segments?.intro)] {
            if let range, s.position >= range.lowerBound, s.position < range.upperBound - 1 { skipKind = kind; skipIntroTo = range.upperBound; return }
        }
        skipIntroTo = nil
    }

    /// Qué tanto puede diferir la posición del motor rearmado de donde ibas (cae en el cuadro clave anterior).
    static let skipAnchorTolerance: Double = 5

    public func skipIntro() async { if let target = skipIntroTo { await seek(to: target) } }

    func nextEpisodeIDIgnoringLocal() -> String? {
        guard let request, request.kind == "series", let meta = request.meta else { return nil }
        return CinemetaParsing.nextEpisode(meta, after: request.videoID)
    }

    /// El siguiente episodio. Viendo un archivo descargado solo cuenta si el siguiente también está descargado.
    func nextEpisodeID() -> String? {
        guard let next = nextEpisodeIDIgnoringLocal() else { return nil }
        if request?.localFile != nil && nextLocal == nil { return nil }
        return next
    }

    func evaluateUpNext(_ s: EngineSnapshot, now: Date) async {
        if demoPinned { return }
        guard let next = nextEpisodeID(), s.duration > 0, let request else { return }
        let remaining = s.duration - s.position
        if remaining <= PlaybackRules.upNextLookahead && !preloadedNext && request.localFile == nil {
            preloadedNext = true  // que al llegar el momento ya esté buscada la fuente
            let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
            Task { _ = try? await finder.find(kind: request.kind, videoID: next, prefs: prefs) }
        }
        let current = s.chapters.sorted { $0.time < $1.time }.last { $0.time <= s.position }
        // «Opening Credits» al principio no son los créditos del final: solo cuentan en la segunda mitad.
        // Los créditos: por capítulo del archivo o por la marca de la comunidad (IntroDB).
        let inCredits = ((current.map { PlaybackRules.chapterKind($0.title) == .credits } ?? false) || (segments?.credits.map { s.position >= $0.lowerBound } ?? false))
            && s.position > s.duration / 2
        let near = PlaybackRules.shouldShowUpNext(position: s.position, duration: s.duration, inCredits: inCredits)
        if upNext == nil && !upNextDismissed && near {
            upNextDeadline = now.addingTimeInterval(PlaybackRules.upNextCountdown)
            let (label, title) = episodeText(next)
            upNext = UpNext(videoID: next, label: label, title: title, secondsLeft: Int(PlaybackRules.upNextCountdown), thumbnail: episodeThumbnail(next))
        } else if upNext != nil && !near && remaining > PlaybackRules.upNextAt + 5 {
            upNext = nil; upNextDeadline = nil          // retrocediste lejos del final: la tarjeta ya no aplica
        }
    }

    public func useLocalizedMeta(_ meta: JSON, for videoID: String) {
        guard request?.videoID == videoID else { return }
        localizedMeta = meta
    }

    func episodeText(_ videoID: String) -> (String, String) {
        guard let meta = localizedMeta ?? request?.meta else { return ("", "") }
        for season in CinemetaParsing.seasons(meta) {
            if let ep = season.episodes.first(where: { $0.id == videoID }) { return (episodeLabel(season.season, ep.episode), ep.title) }
        }
        return ("", "")
    }

    func episodeThumbnail(_ videoID: String) -> String? {
        guard let meta = request?.meta else { return nil }
        return CinemetaParsing.seasons(meta).lazy.compactMap { $0.episodes.first { $0.id == videoID } }.first?.thumbnail
    }

    #if DEBUG

    /// Solo para el modo demostración: pone el reproductor en un estado difícil de alcanzar en el simulador
    /// («skip-intro», «error», «upnext»).
    public func demoState(_ kind: String) {
        demoPinned = true
        switch kind {
        case "skip-intro": skipKind = .intro; skipIntroTo = snapshot.position + 60
        case "error": fail("No pude abrir este video. La versión dejó de responder.", .sourceDied)
        case "no-sources": fail("No hay versiones en Real-Debrid para este título.", .noSources)
        case "upnext":
            guard let next = nextEpisodeIDIgnoringLocal() else { return }
            let (label, title) = episodeText(next)
            upNextDeadline = nil   // que no avance solo mientras se captura
            upNext = UpNext(videoID: next, label: label, title: title, secondsLeft: Int(PlaybackRules.upNextCountdown) - 3, thumbnail: episodeThumbnail(next))
        default: break
        }
    }

    #endif

    /// Pone otro episodio de la serie: desde «Episodios» o «Siguiente». El que dejas queda guardado donde ibas (visto si pasaste
    /// del 90 %) y el nuevo empieza desde el principio. Viendo un archivo descargado, solo otro descargado.
    public func playEpisode(_ videoID: String) async {
        guard !advancing, !closing, phase != .closed, let base = request, base.kind == "series", videoID != base.videoID else { return }
        userTouched()
        var local: LocalEpisode?
        if base.localFile != nil {
            guard let found = await localEpisode(base.metaID, videoID) else { return }
            local = found
        }
        advancing = true
        upNext = nil; upNextDeadline = nil
        let task = Task { [weak self] in
            guard let self else { return }
            let watched = StremioLibrary.finished(position: snapshot.position, duration: snapshot.duration, kind: base.kind)
            if !finalReported { await report(.stopped(finished: watched)) }
            guard !closing, phase != .closed else { advancing = false; return }
            var next = base
            next.videoID = videoID; next.fromStart = true; next.binge = source?.binge
            let (label, title) = episodeText(videoID)
            next.episodeLabel = title.isEmpty ? label : "\(label) · \(title)"
            if let local { next.localFile = local.file; next.localSubtitles = local.subtitles; next.savedSubtitles = local.saved }
            advancing = false
            await begin(next)
        }
        transition = task
        await task.value
    }

    /// De estos episodios, cuáles se pueden poner ahora: todos, salvo viendo un archivo descargado (entonces solo los bajados).
    public func playableEpisodes(_ ids: [String]) async -> Set<String> {
        guard let request, request.localFile != nil else { return Set(ids) }
        var out = Set<String>()
        for id in ids where await localEpisode(request.metaID, id) != nil { out.insert(id) }
        return out
    }

    public func cancelUpNext() { userTouched(); upNext = nil; upNextDeadline = nil; upNextDismissed = true }

    public func playNextNow() async { userTouched(); await advance(auto: false)?.value }

    public func confirmStillWatching() async {
        userTouched(); stillWatchingPrompt = false
        await advance(auto: false)?.value
    }

    /// Pasa al siguiente episodio. Es una sola transición a la vez (un «Ver ahora» y la cuenta atrás no la duplican) y corre aparte:
    /// quien la pide (el escucha del motor) no se queda esperando mientras se buscan las fuentes. Se puede esperar con `waitForTransition`.

    /// Pasa al siguiente episodio. Es una sola transición a la vez (un «Ver ahora» y la cuenta atrás no la duplican) y corre aparte:
    /// quien la pide (el escucha del motor) no se queda esperando mientras se buscan las fuentes. Se puede esperar con `waitForTransition`.
    @discardableResult
    func advance(auto: Bool) -> Task<Void, Never>? {
        guard !advancing, !closing, phase != .closed, let card = upNext, let request else { return transition }
        if auto && autoAdvances >= PlaybackRules.stillWatchingAfter {
            // Tres episodios seguidos sin tocar la pantalla: se pregunta antes de seguir (y lo visto ya queda guardado).
            stillWatchingPrompt = true; upNextDeadline = nil
            let saved = Task { if !finalReported { await report(.stopped(finished: true)) }; await engine.pause() }
            transition = saved
            return saved
        }
        advancing = true
        let task = Task { [weak self] in
            guard let self else { return }
            if !finalReported { await report(.stopped(finished: true)) }
            guard !closing, phase != .closed else { advancing = false; return }
            if request.localFile != nil, StremioLibrary.finished(position: snapshot.position, duration: snapshot.duration, kind: request.kind) { onFinishedLocal?(request) }
            var next = request
            next.videoID = card.videoID; next.fromStart = true; next.binge = source?.binge
            next.episodeLabel = card.title.isEmpty ? card.label : "\(card.label) · \(card.title)"   // si no, se queda el del episodio anterior
            if request.localFile != nil, let local = nextLocal { next.localFile = local.file; next.localSubtitles = local.subtitles; next.savedSubtitles = local.saved }
            if auto { autoAdvances += 1 }
            advancing = false
            await begin(next)
        }
        transition = task
        return task
    }

    /// Espera a que termine el cambio de episodio en curso (para las pruebas y para la vista).
    public func waitForTransition() async { await transition?.value }

    /// Un «final» a más de 90 s del final de verdad es la conexión que se cortó, no el episodio visto (como `CUT_MARGIN` en la consola).
    static let cutMargin = 90.0

    var endIsReal: Bool { snapshot.duration <= 0 || snapshot.position >= snapshot.duration - Self.cutMargin }

    func finishAndAdvance() async {
        if nextEpisodeID() != nil && !upNextDismissed && !stillWatchingPrompt {
            if upNext == nil, let next = nextEpisodeID() { let (l, t) = episodeText(next); upNext = UpNext(videoID: next, label: l, title: t, secondsLeft: 0) }
            advance(auto: true)
        } else {
            if !finalReported { await report(.stopped(finished: endIsReal)) }
            phase = .closed
            await engine.stop()
        }
    }
}
