import Foundation
import OrbitalCore

/// Las pistas del video (audio y subtítulos del archivo), las elegidas y recordadas por título, y los subtítulos que se buscan
/// en internet. El estado guardado sigue en `PlayerModel`; aquí vive lo que se hace con él.
extension PlayerModel {
    /// Las pistas reales de esta versión: quedan «comprobadas» (la próxima vez se sabe su idioma sin adivinar).
    private func rememberCheckedAudio(_ s: EngineSnapshot) {
        guard let source, titlePrefs.rememberChecked(key: source.key, codes: Self.realAudio(s.audioTracks, source: source)) else { return }
        let finder = finder
        Task { await finder.forgetSorted() }
    }

    /// Lo que trae esta versión no es lo que quieres (inglés y castellano, y quieres latino) y otra versión sí lo trae seguro:
    /// se ofrece cambiar a esa, en el mismo segundo.
    /// Las pistas de audio de un archivo como idiomas de versión. Una pista «spa» sin nombre no dice si es latino o castellano:
    /// si el nombre de la versión sí lo dice, se queda esa variante (comprobar no puede empeorar el dato).
    static func realAudio(_ tracks: [MediaTrack], source: Source?) -> [String] {
        let variant = source?.audio.first { $0.base == "es" && $0.code != "es" && $0.evidence.solid }?.code
        var codes: [String] = []
        for track in tracks where track.kind == .audio {
            guard var code = TrackChooser.audioCode(track) else { continue }
            if code == "es", let variant { code = variant }
            if !codes.contains(code) { codes.append(code) }
        }
        return codes
    }

    func offerVersionInYourLanguage(_ s: EngineSnapshot, prefs: Preferences) {
        guard let current = source, let request else { return }
        // La elegiste tú en «Elegir versión»: no se te ofrece otra.
        if request.sourceIndex == current.index { return }
        let have = Self.realAudio(s.audioTracks, source: current)
        let want = prefs.wanted
        guard !have.isEmpty, !have.contains(where: { $0 == want || (want.count == 2 && $0.hasPrefix(want)) }) else { return }
        // Ni una que ya falló, ni una que ya se comprobó en otro idioma, ni una de cine, un tráiler u otra película.
        let better = sourceChoices.first { choice in
            guard choice.index != current.index, choice.playbackURL != nil, !failedSources.contains(choice.index),
                  !choice.tags.contains("CAM"), !choice.tags.contains("Tráiler"), !choice.tags.contains(Streams.otherTitleTag) else { return false }
            if let checked = titlePrefs.checkedAudio(choice.key) { return checked.contains { $0.code == want } }
            return choice.audio.contains { $0.code == want && $0.evidence.solid }
        }
        guard let better else { return }
        var unique: [String] = []
        for code in have where !unique.contains(code) { unique.append(code) }
        notice = .otherVersionHasYourLanguage(language: want, have: unique, sourceIndex: better.index)
    }

    func applyTracksOnce(_ s: EngineSnapshot) async {
        guard !tracksApplied, !s.audioTracks.isEmpty || !s.subtitleTracks.isEmpty, let request else { return }
        tracksApplied = true
        let mine = generation   // puede terminar después: si ya es otro video (u otra fuente), no se le toca
        rememberCheckedAudio(s)
        // Apagados en este título: eso gana a todo lo recordado.
        let subtitlesOff = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).subtitles.isEmpty
        // La versión que elegiste en este título: el subtítulo más parecido (gana a «Continuar» y a la regla).
        let picked = subtitlesOff ? false : await applyRememberedPick(s)
        guard mine == generation else { return }
        // «Continuar»: las mismas pistas con que lo dejaste; lo que no se encuentre, con la regla de siempre.
        // También en el siguiente episodio de la serie (antes solo en el mismo episodio exacto).
        if !picked, !request.fromStart, let choice = titlePrefs.lastChoice(metaID: request.metaID), await applyResumeTracks(choice, s) { return }
        let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
        let audio = TrackChooser.audio(s.audioTracks, language: langs.prefs.audio, latin: langs.prefs.spanish == "es-419", castilian: langs.prefs.spanish == "es-ES")
        if let audio, audio.id != s.selectedAudio { await engine.selectAudio(audio.id) }
        // (Si la elegiste tú en «Elegir versión», ya sabías qué idioma trae: no se avisa.)
        if TrackChooser.wrongAudio(s.audioTracks, language: langs.prefs.audio), request.sourceIndex == nil || request.sourceIndex != source?.index {
            notice = .audioNotInYourLanguage
        }
        offerVersionInYourLanguage(s, prefs: langs.prefs)
        let audioLanguage = PlaybackRules.languageCode(audio?.language) ?? langs.prefs.audio
        if picked { return }
        let mode: SubtitleMode = settings.value.onlyForcedSubtitles ? .forced : SubtitleMode(settings: langs.subtitles, onlyForced: false)
        var sub = TrackChooser.subtitle(s.subtitleTracks, mode: mode, audioLanguage: audioLanguage)
        knownSubtitleIDs = Set(s.subtitleTracks.map(\.id))
        // Apagados, pero el audio es de otro idioma (ni el tuyo ni inglés): los carteles en tu idioma, si el video los trae.
        if sub == nil, case .off = mode, settings.value.forcedForForeignAudio, let yours = SubtitleLanguage.code(settings.value.uiLanguage),
           let heard = SubtitleLanguage.code(audioLanguage), heard != yours, heard != "en" {
            sub = s.subtitleTracks.first { $0.isForced && TrackChooser.matches($0, yours) }
        }
        guard mine == generation else { return }
        if let sub { await engine.selectSubtitle(sub.id) }
        // El video no trae tu idioma (a lo más los carteles del audio): se busca en internet aunque haya puesto los carteles.
        if case .language(let language) = mode, !(sub.map { TrackChooser.matches($0, language) } ?? false),
           !(audio.map { TrackChooser.matches($0, language) } ?? false) {
            // El video no trae subtítulos en tu idioma: se piden a tus complementos (OpenSubtitles…) o a la descarga.
            await addExternalSubtitle(language: language)
        }
    }

    /// Las pistas guardadas, si están en este video. true si los subtítulos quedaron como los dejaste (el audio, si se
    /// encuentra, también); false para elegir con la regla de siempre.
    private func applyResumeTracks(_ choice: ResumeChoice, _ s: EngineSnapshot) async -> Bool {
        // La misma pista (idioma y nombre); si en este archivo se llama distinto (otro episodio, otra fuente), la del mismo idioma.
        func find(_ tracks: [MediaTrack], _ saved: ResumeChoice.Track) -> MediaTrack? {
            tracks.first { $0.language == saved.language && $0.title == saved.title }
                ?? tracks.first { PlaybackRules.languageCode($0.language) != nil && PlaybackRules.languageCode($0.language) == PlaybackRules.languageCode(saved.language) && !$0.isForced }
        }
        if let audio = choice.audio, let track = find(s.audioTracks, audio), track.id != s.selectedAudio { await engine.selectAudio(track.id) }
        guard let sub = choice.subtitle else { return false }
        knownSubtitleIDs = Set(s.subtitleTracks.map(\.id))
        if sub.off { await engine.selectSubtitle(nil); return true }
        if let track = find(s.subtitleTracks, sub) { await engine.selectSubtitle(track.id); return true }
        // Este archivo no los trae (otra fuente, o venían de la TV): los mismos de su complemento, o los de ese idioma.
        if let text = sub.url, let url = URL(string: text), url.scheme == "https" || url.scheme == "http" {
            addedExternalSubtitle = true
            await engine.addSubtitle(url: url, language: sub.language)
            return true
        }
        if let language = PlaybackRules.languageCode(sub.language) { await addExternalSubtitle(language: language); return true }
        return false
    }

    /// La fuente y las pistas que tienes puestas ahora: para «Continuar» y para pasarlas a la TV («Ver en la TV»).
    public func currentChoice() -> ResumeChoice? {
        guard let request else { return nil }
        func pick(_ tracks: [MediaTrack], _ selected: Int?) -> ResumeChoice.Track? {
            guard !tracks.isEmpty else { return nil }
            guard let selected, let t = tracks.first(where: { $0.id == selected }) else { return ResumeChoice.Track(off: true) }
            return ResumeChoice.Track(language: t.language, title: t.title)
        }
        let audio = pick(snapshot.audioTracks, snapshot.selectedAudio).flatMap { $0.off ? nil : $0 }
        return ResumeChoice(videoID: request.videoID, source: source?.key, audio: audio,
                            subtitle: pick(snapshot.subtitleTracks, snapshot.selectedSubtitle), binge: source?.binge)
    }

    /// Junto a «dónde ibas»: la fuente y las pistas que tienes puestas (para «Continuar»).
    func rememberChoice() {
        guard let request, snapshot.position >= PlaybackRules.rememberChoiceAfter, let choice = currentChoice() else { return }
        titlePrefs.remember(metaID: request.metaID, choice: choice)
    }

    private func addExternalSubtitle(language: String) async {
        guard let request, !addedExternalSubtitle else { return }
        addedExternalSubtitle = true
        var url = request.localSubtitles.first { $0.lastPathComponent.hasPrefix(language) }
        // También para una descarga (si hay red): con la huella del archivo, el subtítulo de esa copia exacta.
        if url == nil {
            let file = request.localFile.flatMap(FileFingerprint.of)
            url = await finder.subtitles(kind: request.kind, videoID: request.videoID, language: language, file: file).first
        }
        if let url { pendingSubtitleURL = url; await engine.addSubtitle(url: url, language: language) }
    }

    public func loadScares() async {
        guard let r = request, r.kind == "movie", r.metaID.hasPrefix("tt") else { scares = nil; return }
        let id = r.metaID
        let found = await scareMap(id, r.originalTitle)
        guard request?.metaID == id else { return }
        scares = found
    }

    /// Busca en internet. La búsqueda es del modelo, no de la vista que la pidió: antes corría en el `.task` del panel y
    /// cerrarlo la cancelaba, la búsqueda cancelada se tomaba como «no hay nada» y ya no se volvía a buscar en ese video.
    /// Si ya hay una en camino, se espera esa (antes se salía al momento y elegir un idioma no hacía nada).
    public func searchSubtitles() async {
        if let running = searchTask { return await running.value }
        let task = Task { await self.runSubtitleSearch() }
        searchTask = task
        await task.value
        if searchTask == task { searchTask = nil }
    }

    private func runSubtitleSearch() async {
        guard let request, !searchingSubtitles else { return }
        let mine = generation
        searchingSubtitles = true
        defer { searchingSubtitles = false }
        // La huella de tu copia (la descarga, o el video en línea con dos pedidos chicos): lo hecho para ella va primero.
        var file = request.localFile.flatMap(FileFingerprint.of)
        if file == nil, let url = source?.playbackURL, !url.isFileURL { file = await finder.fingerprint(of: url) }
        guard generation == mine else { return }
        let search = await finder.subtitleSearch(kind: request.kind, videoID: request.videoID, file: file)
        guard generation == mine else { return }   // ya es otro video: no se le cuelgan los de este
        // Nada (o sin red): se queda el botón para volver a intentar, con el aviso.
        let found = search ?? []
        foundSubtitles = found.isEmpty ? nil : found
        subtitleSearchFailed = found.isEmpty
        subtitlesOffline = search == nil
    }

    /// Hay subtítulos de ese idioma para poner ya (del video, guardados con la descarga o encontrados en internet).
    public func hasSubtitles(language: String) -> Bool { !subtitleVersions(language: language).isEmpty }

    /// Suma el siguiente de ese idioma que aún no se sumó y lo activa.
    public func addFoundSubtitle(language: String) async {
        guard let option = foundSubtitles?.first(where: { $0.language == language && !addedSubtitleURLs.contains($0.url) }) else { return }
        userTouched()
        knownSubtitleIDs = Set(snapshot.subtitleTracks.map(\.id))
        addedExternalSubtitle = true
        addedSubtitleURLs.insert(option.url)
        await engine.addSubtitle(url: option.url, language: option.language)
    }

    /// El motor ya sumó el subtítulo externo: se activa.
    func selectNewSubtitleIfAny(_ s: EngineSnapshot) async {
        guard addedExternalSubtitle else { return }
        let new = s.subtitleTracks.filter { !knownSubtitleIDs.contains($0.id) }
        if let track = new.first {
            knownSubtitleIDs.insert(track.id)
            // El que se sumó de internet ya es esta pista: en la lista sale como «de internet», no «del video».
            if let url = pendingSubtitleURL { addedTracks[url] = track.id; pendingSubtitleURL = nil }
            await engine.selectSubtitle(track.id)
        }
    }
}
