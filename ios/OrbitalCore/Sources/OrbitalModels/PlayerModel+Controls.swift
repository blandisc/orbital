import Foundation
import OrbitalCore

/// Los controles: play, pausa, saltar, velocidad, cambiar de versión y lo que cada uno le dice a Stremio y a Trakt.
extension PlayerModel {
    // MARK: controles
    func userTouched() { autoAdvances = 0 }

    public func setRate(_ value: Float) async { rate = value; await engine.setRate(value) }

    /// Abre un video y le pone la velocidad elegida (el motor empieza cada video en 1).
    func loadVideo(_ url: URL, at start: Double) async throws {
        let src = source.map { "\($0.cached ? "en la nube" : ($0.debrid ? "la nube aún la baja" : "directa")) · \($0.qualitySummary.joined(separator: " "))" } ?? "archivo"
        Self.note("cargar desde \(url.host ?? "archivo") en \(Int(start)) s (\(src))")
        loadStartedAt = clock(); lastLoggedState = ""
        loadTarget = start; pendingAudio = nil; pendingAudioAt = nil   // otro archivo: sus pistas son otras
        if rd.shortDuration != nil { rd.shortDuration = nil }   // otra carga: la duración corta era de la anterior
        await resumeSync?.value
        // La dirección final del complemento, si ya se resolvió (`StreamLinks`): el motor no vuelve a pasar por Torrentio.
        let target = await openable(url)
        markStartup(.link)
        if source?.resolution == "4K" { ParallelPlayback.want(target); ParallelPlayback.want(url) }   // varias conexiones solo en 4K
        if let request {
            // Lo que ya sabes que quieres, desde el primer cuadro: el audio y los subtítulos con que lo dejaste (o tus idiomas).
            let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
            let choice = request.fromStart ? nil : titlePrefs.lastChoice(metaID: request.metaID)
            // Y si no trae ninguno de esos, «Tus idiomas» en su orden (N4-A): «original» es el idioma original de esta versión.
            let order = langs.prefs.order.compactMap { $0 == "original" ? source?.originalLanguage : $0 }
            var audio: [String] = []
            // Lo de «Continuar» con su variante («spa» + «Latino» → «es-419»); un español que no dice cuál, el de Ajustes.
            let resumed = choice?.audio.flatMap { TrackChooser.audioCode(MediaTrack(id: -1, kind: .audio, language: $0.language, title: $0.title)) }
                .map { $0 == "es" && !langs.prefs.spanish.isEmpty ? langs.prefs.spanish : $0 }
            // Luego tu español (latino o castellano, lo de Ajustes o lo que elegiste en este título); nada fijo.
            for code in [resumed ?? choice?.audio?.language, langs.prefs.audio == "es" && !langs.prefs.spanish.isEmpty ? langs.prefs.spanish : nil, langs.prefs.audio].compactMap({ $0 }) + order
            where !code.isEmpty && !audio.contains(code) { audio.append(code) }
            let subs = choice?.subtitle?.off == true ? [] : [choice?.subtitle?.language, langs.subtitles].compactMap { $0 }.filter { !$0.isEmpty }
            await engine.prepare(audioLanguages: audio, subtitleLanguages: subs, externalSubtitles: request.localSubtitles)
            await engine.prepare(titleKey: request.metaID)
        }
        let mine = generation
        do { try await engine.load(url: target, startAt: start) }
        catch where target != url && !(error is CancellationError) && mine == generation && !closing {
            // La dirección final no abrió (venció, la nube la movió): la del complemento, como antes.
            links.forget(url)
            Self.note("la dirección resuelta no abrió: con la del complemento")
            try await engine.load(url: url, startAt: start)
        }
        // Mientras abría se pidió otra carga (cambiaste de versión dos veces seguidas): lo que diga el motor ya no es de esta.
        guard mine == generation else { return }
        engineOpened = true
        markStartup(.opened)
        Self.note(String(format: "el motor abrió el archivo en %.1f s", clock().timeIntervalSince(loadStartedAt)))
        if rate != 1 { await engine.setRate(rate) }
    }

    /// Pausa si suena o si va a sonar (cargando o pediste play y aún no avanza): antes, en búfer el botón llamaba a «play» y la
    /// pausa no hacía caso.
    /// Rearmando en pausa al volver a la app, lo que diga el motor a media carga no cuenta: el botón enseña play y tocarlo es
    /// play (antes, si el motor pasaba un instante por «búfer», el toque se tomaba como pausa y se perdía).
    public var wantsToPlay: Bool {
        if restoringQuietly { return playRequest != nil }
        return snapshot.state == .playing || snapshot.state == .buffering || playRequest != nil
    }

    public func togglePlay() async {
        userTouched()
        if wantsToPlay { playRequest = nil; settleStartup(); await engine.pause() } else { requestPlayback(); await engine.play() }
    }

    public func play() async { userTouched(); requestPlayback(); await engine.play() }

    public func pause() async { userTouched(); playRequest = nil; settleStartup(); await engine.pause() }

    /// Pausaste en los primeros segundos: el arranque ya no es carga (el botón dice play al momento, sin esperar al motor).
    func settleStartup() { playWantedWhileRestoring = false; if hasPlayed { playbackSettled = true } }

    /// Pediste que sonara y todavía no avanza (sobre todo al volver de segundo plano, con el video soltado por el motor): la
    /// pantalla enseña la carga en vez del play, y si en `foregroundStallSeconds` no avanza, el video se pide otra vez ahí mismo.
    public var awaitingPlayback: Bool { playRequest != nil }

    func requestPlayback() {
        guard hasPlayed, phase == .playing, !closing else { return }
        // A media rearmada el motor dice 0: el punto de verdad es donde lo dejaste.
        if restoringQuietly { playWantedWhileRestoring = true }
        playRequest = (clock(), restoringQuietly ? max(snapshot.position, backgroundPosition) : snapshot.position)
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
        lastGoodPosition = target   // lo pediste tú (también el principio): eso sí se guarda
        skipAnchor = nil   // lo buscaste tú: la posición nueva sí vale para «Saltar intro»
        if hasPlayed, abs(target - snapshot.position) >= PlaybackRules.rescrobbleJump { rescrobbleAfterSeek = true }
        if !playbackSettled { startupPosition = target }   // un salto al arrancar: el medio segundo se cuenta desde el punto nuevo
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

    // Cambiar de versión a mano y volver a la de antes: `PlayerModel+Switching.swift`.

    /// El aviso corto que Real-Debrid manda en lugar de una versión que aún no tiene.
    func isPlaceholder(_ s: EngineSnapshot) -> Bool {
        guard request?.localFile == nil, s.duration > 0 else { return false }
        let expected = request?.meta.map { CinemetaParsing.runtimeSeconds(CinemetaParsing.describe($0).runtime) } ?? 0
        if s.duration < Self.placeholderMaxSeconds { return expected == 0 || expected >= Self.placeholderTitleMinSeconds }
        // Los avisos de ElfHosted («Not ready yet», MEDIA_NOT_CACHED_YET) duran más de 2 min: un video de menos del 15 % de
        // lo que dura el título tampoco es el título.
        return expected >= Self.placeholderTitleMinSeconds && s.duration < expected * 0.15
    }

    /// Los idiomas de audio que solo traen otras versiones, para ofrecerlos junto a los del archivo. Sin grabaciones de cine,
    /// tráileres ni otras películas (antes se colaban); de cada idioma, la versión más parecida a la que ves (misma calidad,
    /// al instante); lo comprobado o dicho por el nombre o el sitio es seguro, lo supuesto es «tal vez».
    public func otherVersionAudio(excluding inFile: Set<String>) -> [OtherVersionAudio] {
        guard let current = source else { return [] }
        var best: [String: (Source, Bool)] = [:]
        for choice in sourceChoices where choice.index != current.index && choice.playbackURL != nil && !failedSources.contains(choice.index)
            && !choice.tags.contains("CAM") && !choice.tags.contains("Tráiler") && !choice.tags.contains(Streams.otherTitleTag) && !choice.tags.contains(Streams.otherEpisodeTag) {
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
