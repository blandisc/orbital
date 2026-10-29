import Foundation
import OrbitalCore

/// Los controles: play, pausa, saltar, velocidad, cambiar de versión y lo que cada uno le dice a Stremio y a Trakt.
extension PlayerModel {
    // MARK: controles
    func userTouched() { autoAdvances = 0 }

    public func setRate(_ value: Float) async { rate = value; await engine.setRate(value) }

    /// Abre un video y le pone la velocidad elegida (el motor empieza cada video en 1).
    func loadVideo(_ url: URL, at start: Double) async throws {
        let src = source.map { "\($0.cached ? "en Real-Debrid" : ($0.debrid ? "Real-Debrid aún la baja" : "directa")) · \($0.qualitySummary.joined(separator: " "))" } ?? "archivo"
        Self.note("cargar desde \(url.host ?? "archivo") en \(Int(start)) s (\(src))")
        loadStartedAt = clock(); lastLoggedState = ""
        if let request {
            // Lo que ya sabes que quieres, desde el primer cuadro: el audio y los subtítulos con que lo dejaste (o tus idiomas).
            let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
            let choice = request.fromStart ? nil : titlePrefs.lastChoice(metaID: request.metaID)
            let audio = [choice?.audio?.language, settings.value.latinSpanish && langs.prefs.audio == "es" ? "es-419" : nil, langs.prefs.audio].compactMap { $0 }.filter { !$0.isEmpty }
            let subs = choice?.subtitle?.off == true ? [] : [choice?.subtitle?.language, langs.subtitles].compactMap { $0 }.filter { !$0.isEmpty }
            await engine.prepare(audioLanguages: audio, subtitleLanguages: subs, externalSubtitles: request.localSubtitles)
        }
        try await engine.load(url: url, startAt: start)
        engineOpened = true
        Self.note(String(format: "el motor abrió el archivo en %.1f s", clock().timeIntervalSince(loadStartedAt)))
        if rate != 1 { await engine.setRate(rate) }
    }

    /// Pausa si suena o si va a sonar (cargando o pediste play y aún no avanza): antes, en búfer el botón llamaba a «play» y la
    /// pausa no hacía caso.
    public var wantsToPlay: Bool { snapshot.state == .playing || snapshot.state == .buffering || playRequest != nil }

    public func togglePlay() async {
        userTouched()
        if wantsToPlay { playRequest = nil; settleStartup(); await engine.pause() } else { requestPlayback(); await engine.play() }
    }

    public func play() async { userTouched(); requestPlayback(); await engine.play() }

    public func pause() async { userTouched(); playRequest = nil; settleStartup(); await engine.pause() }

    /// Pausaste en los primeros segundos: el arranque ya no es carga (el botón dice play al momento, sin esperar al motor).
    func settleStartup() { if hasPlayed { playbackSettled = true } }

    /// Pediste que sonara y todavía no avanza (sobre todo al volver de segundo plano, con el video soltado por el motor): la
    /// pantalla enseña la carga en vez del play, y si en `foregroundStallSeconds` no avanza, el video se pide otra vez ahí mismo.
    public var awaitingPlayback: Bool { playRequest != nil }

    func requestPlayback() {
        guard hasPlayed, phase == .playing, !closing else { return }
        playRequest = (clock(), snapshot.position)
    }

    func checkPlayRequest(now: Date) {
        guard let request = playRequest else { return }
        if snapshot.state == .playing, snapshot.position > request.position + 0.3 { playRequest = nil; return }   // ya suena
        guard now.timeIntervalSince(request.at) >= Self.foregroundStallSeconds, !reconnecting, !retrying else { return }
        playRequest = nil
        startReload(at: max(request.position, snapshot.position), resume: true)
    }

    public func seek(to seconds: Double) async {
        userTouched()
        let target = max(0, min(seconds, snapshot.duration > 0 ? snapshot.duration : seconds))
        if hasPlayed, abs(target - snapshot.position) >= PlaybackRules.rescrobbleJump { rescrobbleAfterSeek = true }
        if !playbackSettled { startupPosition = target }   // un salto al arrancar: los 2 s se cuentan desde el punto nuevo
        // Al soltar la barra con un arrastre en curso: la búsqueda final va en la misma fila (nunca dos a la vez, que
        // podían terminar en desorden y dejar la escena en un punto viejo) y sin la espera entre búsquedas.
        if let running = scrubTask {
            scrubTarget = target; scrubFinishing = true
            await running.value
            return
        }
        await engine.seek(to: target)
    }

    /// Mientras arrastras la barra: la escena sigue al dedo. Se busca el último punto pedido apenas termina la búsqueda
    /// anterior (nunca dos a la vez); en una descarga es casi inmediato, en internet se espera un momento entre búsquedas
    /// para no pedir un trozo nuevo por cada punto del arrastre.
    public func scrub(to seconds: Double) {
        scrubTarget = max(0, min(seconds, snapshot.duration > 0 ? snapshot.duration : seconds))
        guard scrubTask == nil else { return }
        let local = request?.localFile != nil
        scrubTask = Task { [weak self] in
            while let self, let target = self.scrubTarget {
                self.scrubTarget = nil
                await self.engine.seek(to: target)
                if !local, !self.scrubFinishing { try? await Task.sleep(nanoseconds: PlaybackRules.streamScrubInterval) }
            }
            self?.scrubTask = nil; self?.scrubFinishing = false
        }
    }

    public func skip(_ delta: Double) async {
        await seek(to: snapshot.position + delta)
        if delta < 0 { await showSubtitlesBriefly() }
    }

    public static let briefSubtitlesSeconds = 8.0

    func showSubtitlesBriefly() async {
        guard settings.value.subtitlesOnSkipBack, let request else { return }
        if briefSubtitles == nil {
            guard snapshot.selectedSubtitle == nil else { return }
            var languages: [String] = []
            for code in [settings.value.subtitles, settings.value.uiLanguage].compactMap(SubtitleLanguage.code) where !languages.contains(code) { languages.append(code) }
            guard let best = languages.lazy.compactMap({ self.subtitleVersions(language: $0).first }).first else { return }
            await apply(best)   // sin recordarlo: es solo un momento
        }
        briefSubtitles?.cancel()
        let videoID = request.videoID, wait = UInt64(Self.briefSubtitlesSeconds * 1_000_000_000)
        briefSubtitles = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard let self, !Task.isCancelled, self.request?.videoID == videoID else { return }
            self.briefSubtitles = nil
            await self.engine.selectSubtitle(nil)
        }
    }

    func stopBriefSubtitles() { briefSubtitles?.cancel(); briefSubtitles = nil }

    /// Cambia de fuente en el mismo punto. Si la lista de fuentes es vieja (los enlaces de Real-Debrid caducan) se pide de nuevo.
    /// Cambiar de versión a mano (en la hoja, o un idioma que solo trae otra versión: `language`). Se pausa y se toma el
    /// segundo exacto; cuenta como «la elegiste tú» (ya no se ofrece cambiar otra vez); si no abre, se vuelve a la que veías
    /// en el mismo segundo (antes caía a cualquier otra); el idioma elegido sigue en los siguientes episodios.
    public func switchSource(to index: Int, language: String? = nil) async {
        guard let request, !closing else { return }
        userTouched()
        if snapshot.state == .playing { await engine.pause() }
        generation += 1
        let mine = generation
        let position = snapshot.position
        let previous = source
        notice = nil   // el aviso era de la versión que dejas
        acceptingSnapshots = false
        if clock().timeIntervalSince(choicesAt) > Self.choicesLifetime {
            let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
            if let fresh = try? await finder.find(kind: request.kind, videoID: request.videoID, prefs: prefs, fresh: true) { sourceChoices = fresh; choicesAt = clock() }
        }
        guard mine == generation, !closing, let choice = sourceChoices.first(where: { $0.index == index }) ?? sourceChoices.first(where: { $0.release == source?.release && $0.index == index }),
              let url = choice.playbackURL else { acceptingSnapshots = true; return }
        self.request?.sourceIndex = index
        let subtitlesWereOn = snapshot.selectedSubtitle != nil
        source = choice; phase = .preparing
        // Suelta lo que el motor estuviera abriendo: si la versión de antes se quedó cargando, la nueva quedaba formada detrás de
        // ella y la pantalla solo enseñaba la carga (el iPhone el 29 oct).
        await engine.stop()
        guard mine == generation, !closing else { return }
        startLoading()
        if let previous { switchBack = (previous, position) }
        forgetSubtitleSearch()   // otro archivo: «coincide con tu copia» se vuelve a calcular con su huella
        if subtitlesWereOn { askInSync = true }   // otro archivo, la sincronía empieza en 0: «¿Va a tiempo?»
        do {
            try await loadVideo(url, at: position)
            if let language { titlePrefs.remember(metaID: request.metaID, audioTrack: language) }
        } catch {
            guard mine == generation else { return }
            failedSources.insert(index)
            if !goBackAfterSwitch() { await retryWithAnotherSource()?.value }
        }
    }

    /// Vuelve a la versión que veías antes de cambiar a mano, en el mismo segundo. false si no hay a cuál volver.

    /// Vuelve a la versión que veías antes de cambiar a mano, en el mismo segundo. false si no hay a cuál volver.
    @discardableResult
    func goBackAfterSwitch() -> Bool {
        guard let back = switchBack, let url = back.source.playbackURL, !closing else { return false }
        switchBack = nil
        if let source, source.index != back.source.index { failedSources.insert(source.index) }
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

    /// El aviso corto que Real-Debrid manda en lugar de una versión que aún no tiene.
    func isPlaceholder(_ s: EngineSnapshot) -> Bool {
        guard request?.localFile == nil, s.duration > 0, s.duration < Self.placeholderMaxSeconds else { return false }
        let expected = request?.meta.map { CinemetaParsing.runtimeSeconds(CinemetaParsing.describe($0).runtime) } ?? 0
        return expected == 0 || expected >= Self.placeholderTitleMinSeconds
    }

    /// Los idiomas de audio que solo traen otras versiones, para ofrecerlos junto a los del archivo. Sin grabaciones de cine,
    /// tráileres ni otras películas (antes se colaban); de cada idioma, la versión más parecida a la que ves (misma calidad,
    /// al instante); lo comprobado o dicho por el nombre o el sitio es seguro, lo supuesto es «tal vez».
    public func otherVersionAudio(excluding inFile: Set<String>) -> [OtherVersionAudio] {
        guard let current = source else { return [] }
        var best: [String: (Source, Bool)] = [:]
        for choice in sourceChoices where choice.index != current.index && choice.playbackURL != nil && !failedSources.contains(choice.index)
            && !choice.tags.contains("CAM") && !choice.tags.contains("Tráiler") && !choice.tags.contains(Streams.otherTitleTag) {
            let checked = titlePrefs.checkedAudio(choice.key)
            let languages: [(String, Bool)] = checked.map { $0.map { ($0.code, true) } }
                ?? choice.audio.map { ($0.code, [.checked, .name, .site].contains($0.evidence)) }
            for (code, sure) in languages where !inFile.contains(code) && !inFile.contains(String(code.prefix(2))) {
                func rank(_ s: Source, _ sure: Bool) -> (Int, Int, Int) { (sure ? 1 : 0, s.resolution == current.resolution ? 1 : 0, s.cached ? 1 : 0) }
                if let have = best[code], rank(have.0, have.1) >= rank(choice, sure) { continue }
                best[code] = (choice, sure)
            }
        }
        // En el orden en que se recomiendan las fuentes (lo tuyo primero).
        return sourceChoices.compactMap { choice in best.first { $0.value.0.index == choice.index }.map { ($0.key, $0.value) } }
            .reduce(into: [OtherVersionAudio]()) { out, item in
                guard !out.contains(where: { $0.code == item.0 }) else { return }
                out.append(OtherVersionAudio(code: item.0, sourceIndex: item.1.0.index, quality: item.1.0.resolution, instant: item.1.0.cached, sure: item.1.1))
            }
    }
}
