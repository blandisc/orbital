import Foundation
import OrbitalCore

/// «Subtítulos» del panel: las versiones por idioma (las del archivo, las de internet y las que ya agregaste), elegir, recorrer,
/// apagar y prender, y el audio. El estado guardado sigue en `PlayerModel`; aquí vive lo que se hace con él.
extension PlayerModel {
    /// Se está bajando un subtítulo de internet para ponerlo (el botón de subtítulos enseña que carga).
    public var loadingSubtitle: Bool { pendingSubtitleURL != nil }

    /// El nombre de tu copia (la fuente o el archivo descargado): con él se ve qué subtítulo le va.
    public var currentRelease: String? {
        if let r = source?.release, !r.isEmpty { return r }
        return request?.localFile?.lastPathComponent
    }

    /// Las pistas que de verdad vienen en el video (sin las que se sumaron de internet).
    private var videoTracks: [MediaTrack] {
        let added = Set(addedTracks.values)
        return snapshot.subtitleTracks.filter { !added.contains($0.id) }
    }

    public var subtitleLanguages: [(code: String, count: Int)] {
        SubtitleVersions.languages(tracks: videoTracks, found: foundSubtitles ?? [])
    }

    public func subtitleVersions(language: String) -> [SubtitleVersion] {
        SubtitleVersions.ranked(language: language, tracks: videoTracks, found: foundSubtitles ?? [], release: currentRelease, playing: snapshot.selectedSubtitle,
                                saved: savedByTrack)
    }

    /// Los subtítulos guardados con la descarga, por el nombre de su pista en el motor («es-3»).
    private var savedByTrack: [String: SavedSubtitle] {
        Dictionary((request?.savedSubtitles ?? []).map { ($0.trackName, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// El video trae (sin contar SDH ni forzados) subtítulos en ese idioma.
    public func videoHasSubtitles(language: String) -> Bool {
        videoTracks.contains { !SubtitleFilter.hides($0) && SubtitleLanguage.code($0.language) == language }
    }

    /// La versión puesta ahora (su `id`), o nil sin subtítulos.
    public var selectedVersionID: String? {
        guard let id = snapshot.selectedSubtitle else { return nil }
        if let url = addedTracks.first(where: { $0.value == id })?.key { return url.absoluteString }
        return "track-\(id)"
    }

    /// Busca en internet una sola vez por video (sin tocar «Buscar»).
    public func ensureSubtitleSearch() async {
        guard foundSubtitles == nil, !subtitleSearchFailed else { return }
        await searchSubtitles()
    }

    /// Pone esa versión: la del video al momento; la de internet se baja, se suma y se activa (sin pausar).
    public func selectVersion(_ version: SubtitleVersion, trying: Bool = false) async {
        userTouched()
        stopBriefSubtitles()
        if let current = selectedVersionID, current != version.id { triedVersionIDs.insert(current) }
        askInSync = true
        if trying { tryingSubtitles = version.language }
        subtitleTicket += 1
        let ticket = subtitleTicket
        await apply(version)
        guard ticket == subtitleTicket else { return }   // ya elegiste otra mientras llegaba esta
        rememberVersion(version)
    }

    /// Lo que elijas se recuerda al momento para ese título (serie o película), sin tener que tocar «Este va bien».
    private func rememberVersion(_ version: SubtitleVersion) {
        guard let request else { return }
        titlePrefs.remember(metaID: request.metaID, subtitleTrack: version.language)
        subtitlePicks?.remember(metaID: request.metaID, SubtitlePick(version))
    }

    func apply(_ version: SubtitleVersion) async {
        // El ajuste de tiempo que ya le habías dado a esta versión (o ninguno).
        let saved = request.flatMap { subtitleOffsets?.offset(metaID: $0.metaID, versionID: offsetKey(version.id)) } ?? 0
        subtitleDelay = saved
        restoredDelay = saved == 0 ? nil : saved
        offsetVersionID = version.id
        switch version.origin {
        case .embedded(let track): await engine.selectSubtitle(track.id)
        case .internet(let option):
            if let id = addedTracks[option.url] { await engine.selectSubtitle(id); return }
            knownSubtitleIDs = Set(snapshot.subtitleTracks.map(\.id))
            addedExternalSubtitle = true
            pendingSubtitleURL = option.url
            addedSubtitleURLs.insert(option.url)
            await engine.addSubtitle(url: option.url, language: option.language)
        }
    }

    /// El botón de subtítulos de los controles (un toque): la versión siguiente del idioma puesto, sin pausar ni abrir nada;
    /// sin subtítulos, la mejor de tu idioma (`languages`: los tuyos, en orden). La primera vez busca también en internet, en
    /// segundo plano, para que haya más versiones en la vuelta. Enseña la tira (‹ anterior y «Este va bien»).
    /// Devuelve la versión puesta (nil: no hay ninguna en ese idioma).
    @discardableResult
    public func cycleSubtitle(languages: [String]) async -> SubtitleVersion? {
        userTouched(); stopBriefSubtitles()
        if foundSubtitles == nil, !searchingSubtitles, !subtitleSearchFailed { Task { await ensureSubtitleSearch() } }
        let s = snapshot
        let playing = s.selectedSubtitle.flatMap { id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) }
        let language = playing ?? languages.first { !subtitleVersions(language: $0).isEmpty } ?? languages.first
        guard let language else { return nil }
        var versions = subtitleVersions(language: language)
        if versions.isEmpty {   // el video no trae ese idioma: se espera a lo de internet
            await ensureSubtitleSearch()
            versions = subtitleVersions(language: language)
        }
        guard let next = SubtitleVersions.next(after: playing == nil ? nil : selectedVersionID, in: versions) else { return nil }
        tryingSubtitles = language
        await apply(next)
        rememberVersion(next)
        return next
    }

    /// Mantener presionado el botón: apaga los subtítulos o los vuelve a prender (lo que tenías, lo que elegiste en este
    /// título o lo mejor de tus idiomas). Devuelve la versión puesta; nil si quedaron apagados (o no hay ninguna).
    @discardableResult
    public func toggleSubtitles(languages: [String]) async -> SubtitleVersion? {
        userTouched(); stopBriefSubtitles()
        if snapshot.selectedSubtitle != nil {
            versionBeforeOff = allSubtitleVersions.first { $0.id == selectedVersionID } ?? versionBeforeOff
            await selectSubtitle(nil)
            return nil
        }
        if let back = versionBeforeOff, subtitleVersions(language: back.language).contains(where: { $0.id == back.id }) {
            await selectVersion(back); return back
        }
        if let request, let pick = subtitlePicks?.pick(metaID: request.metaID), let best = pick.best(in: subtitleVersions(language: pick.language)) {
            await selectVersion(best); return best
        }
        let language = languages.first { !subtitleVersions(language: $0).isEmpty } ?? languages.first
        guard let language else { return nil }
        return await chooseLanguage(language) ? allSubtitleVersions.first { $0.id == selectedVersionID } : nil
    }

    /// Tocar un idioma en la hoja: pone ya su mejor versión (antes había que tocar también una versión). Si el video no lo
    /// trae, lo busca en internet primero. false si no hay ninguna.
    @discardableResult
    public func chooseLanguage(_ language: String) async -> Bool {
        var versions = subtitleVersions(language: language)
        if versions.isEmpty {
            // Lo pediste tú: se busca aunque la anterior no haya encontrado nada (o se espera la que va en camino).
            if foundSubtitles == nil { await searchSubtitles() }
            versions = subtitleVersions(language: language)
        }
        guard let best = versions.first else { return false }
        await selectVersion(best)
        return true
    }

    /// Todas las versiones de todos los idiomas que hay ahora (para encontrar la puesta).
    var allSubtitleVersions: [SubtitleVersion] { subtitleLanguages.flatMap { subtitleVersions(language: $0.code) } }

    /// ‹ › de la tira: la versión anterior o la siguiente del mismo idioma.
    public func stepVersion(_ delta: Int) async {
        guard let language = tryingSubtitles else { return }
        let versions = subtitleVersions(language: language)
        guard !versions.isEmpty else { return }
        let at = versions.firstIndex { $0.id == selectedVersionID } ?? -1
        let next = ((at + delta) % versions.count + versions.count) % versions.count
        await apply(versions[next])
        rememberVersion(versions[next])
    }

    public func dismissTry() { tryingSubtitles = nil }

    /// «Este va bien»: cierra la tira y, en una serie, recuerda idioma y copia para el siguiente episodio.
    public func confirmSubtitle() {
        defer { tryingSubtitles = nil }
        guard let request, let language = tryingSubtitles,
              let version = subtitleVersions(language: language).first(where: { $0.id == selectedVersionID }) else { return }
        subtitlePicks?.remember(metaID: request.metaID, SubtitlePick(version))
    }

    /// Al empezar un episodio: lo de «Este va bien» de la serie. true si se puso un subtítulo.
    func applyRememberedPick(_ s: EngineSnapshot) async -> Bool {
        guard let request, let pick = subtitlePicks?.pick(metaID: request.metaID) else { return false }
        knownSubtitleIDs = Set(s.subtitleTracks.map(\.id))
        let embedded = subtitleVersions(language: pick.language)
        // Una pista del video igual a la elegida, o el video no trae ese idioma: se busca también en internet.
        let exact = embedded.first { (pick.name != nil && $0.name == pick.name) || (pick.group != nil && $0.traits.group == pick.group) }
        if exact == nil && (pick.group != nil || pick.name != nil || embedded.isEmpty) { await ensureSubtitleSearch() }
        guard request.videoID == self.request?.videoID, let best = pick.best(in: subtitleVersions(language: pick.language)) else { return false }
        await apply(best)
        return true
    }

    public func selectAudio(_ id: Int?) async {
        userTouched()
        await engine.selectAudio(id)
        if let id, let track = snapshot.audioTracks.first(where: { $0.id == id }), let request {
            titlePrefs.remember(metaID: request.metaID, audioTrack: track.language)
        }
    }

    public func selectSubtitle(_ id: Int?) async {
        userTouched(); stopBriefSubtitles()
        await engine.selectSubtitle(id)
        guard let request else { return }
        if let id {
            // Una pista sin etiqueta de idioma no se recuerda (y desde luego no apaga los subtítulos de la serie).
            if let track = snapshot.subtitleTracks.first(where: { $0.id == id }), let language = track.language, !language.isEmpty {
                titlePrefs.remember(metaID: request.metaID, subtitleTrack: language)
            }
        } else {
            titlePrefs.remember(metaID: request.metaID, subtitleTrack: "")
            subtitlePicks?.forget(metaID: request.metaID)
        }
    }
}
