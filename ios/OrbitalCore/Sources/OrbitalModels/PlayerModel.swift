import Foundation
import OrbitalCore

/// Qué se va a reproducir. `originalTitle` es el nombre de Cinemeta (lo que se guarda en Stremio);
/// `displayTitle` es el de tu idioma (lo que se muestra).
public struct PlayRequest: Sendable {
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var originalTitle: String
    public var displayTitle: String
    public var episodeLabel: String
    public var poster: String?
    public var year: String?
    public var meta: JSON?                 // la ficha original: de ahí salen el siguiente episodio y las duraciones
    public var fromStart = false
    public var localFile: URL?             // una descarga: se reproduce sin red
    public var localSubtitles: [URL] = []
    public var binge: String?              // el grupo de la fuente anterior (misma calidad e idioma)
    public var sourceIndex: Int?           // una fuente elegida en la lista

    public init(kind: String, metaID: String, videoID: String, originalTitle: String, displayTitle: String, episodeLabel: String = "", poster: String? = nil,
                year: String? = nil, meta: JSON? = nil, fromStart: Bool = false, localFile: URL? = nil, localSubtitles: [URL] = [], binge: String? = nil, sourceIndex: Int? = nil) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.originalTitle = originalTitle; self.displayTitle = displayTitle
        self.episodeLabel = episodeLabel; self.poster = poster; self.year = year; self.meta = meta; self.fromStart = fromStart
        self.localFile = localFile; self.localSubtitles = localSubtitles; self.binge = binge; self.sourceIndex = sourceIndex
    }
}

public struct UpNext: Sendable, Equatable {
    public var videoID: String
    public var label: String           // «T2 · E6»
    public var title: String
    public var secondsLeft: Int
}

public enum PlayerNotice: Sendable, Equatable {
    case triedAnotherSource(attempt: Int)
    case audioNotInYourLanguage
}

/// Orquesta una reproducción: elige la fuente, reanuda donde ibas, pone el audio y los subtítulos que quieres,
/// guarda el avance (cada minuto, al pausar y al cerrar), ofrece «Siguiente episodio» y cambia de fuente si una falla.
/// No conoce SwiftUI ni el motor concreto: `PlayerEngine` y los relojes se inyectan, así se prueba entero.
@MainActor
public final class PlayerModel: ObservableModel {
    public enum Phase: Equatable { case idle, preparing, playing, failed(String), closed }

    public private(set) var phase: Phase = .idle { didSet { changed() } }
    public private(set) var snapshot = EngineSnapshot() { didSet { changed() } }
    public private(set) var request: PlayRequest? { didSet { changed() } }
    public private(set) var source: Source? { didSet { changed() } }
    public private(set) var sourceChoices: [Source] = [] { didSet { changed() } }
    public private(set) var upNext: UpNext? { didSet { changed() } }
    public private(set) var skipIntroTo: Double? { didSet { changed() } }
    public private(set) var stillWatchingPrompt = false { didSet { changed() } }
    public private(set) var notice: PlayerNotice? { didSet { changed() } }
    public private(set) var attempts = 0 { didSet { changed() } }

    private let engine: PlayerEngine
    private let finder: StreamFinder
    private let watch: WatchService
    private let titlePrefs: TitlePreferences
    private let settings: SettingsStore
    private let clock: @Sendable () -> Date
    private let onCellular: @Sendable () -> Bool
    private let episodeLabel: @Sendable (Int, Int) -> String

    private var consuming: Task<Void, Never>?
    private var failedSources = Set<Int>()
    private var hasPlayed = false
    private var startupDeadline: Date?
    private var lastSnapshotAt: Date?
    private var lastSave: Date
    private var watchedUnsaved = 0.0
    private var tracksApplied = false
    private var addedExternalSubtitle = false
    private var knownSubtitleIDs = Set<Int>()
    private var preloadedNext = false
    private var upNextDeadline: Date?
    private var upNextDismissed = false
    private var autoAdvances = 0
    private var reachedEnd = false
    private var generation = 0

    public init(engine: PlayerEngine, finder: StreamFinder, watch: WatchService, titlePrefs: TitlePreferences, settings: SettingsStore,
                clock: @escaping @Sendable () -> Date = { Date() }, onCellular: @escaping @Sendable () -> Bool = { false },
                episodeLabel: @escaping @Sendable (Int, Int) -> String = { "T\($0) · E\($1)" }) {
        self.engine = engine; self.finder = finder; self.watch = watch; self.titlePrefs = titlePrefs; self.settings = settings
        self.clock = clock; self.onCellular = onCellular; self.episodeLabel = episodeLabel; self.lastSave = clock()
        super.init()
    }

    // MARK: arranque
    /// Empieza a reproducir. Devuelve cuando el motor ya recibió la fuente (el video puede tardar unos segundos).
    public func begin(_ request: PlayRequest) async {
        generation += 1
        self.request = request
        resetForNewVideo()
        phase = .preparing
        consuming?.cancel()
        let stream = engine.snapshots
        consuming = Task { [weak self] in for await s in stream { await self?.handle(s) } }
        await prepare(startAt: nil)
    }

    private func resetForNewVideo() {
        failedSources = []; hasPlayed = false; startupDeadline = nil; lastSnapshotAt = nil; watchedUnsaved = 0
        tracksApplied = false; addedExternalSubtitle = false; knownSubtitleIDs = []; preloadedNext = false
        upNext = nil; upNextDeadline = nil; upNextDismissed = false; skipIntroTo = nil; reachedEnd = false
        notice = nil; attempts = 0; lastSave = clock(); snapshot = EngineSnapshot(state: .loading); source = nil; sourceChoices = []
    }

    /// Elige fuente y la carga. `startAt` solo se pasa al reintentar con otra fuente (se sigue en el mismo punto).
    private func prepare(startAt: Double?) async {
        guard let request else { return }
        let myGeneration = generation
        if let file = request.localFile {
            var start = startAt ?? 0
            if startAt == nil && !request.fromStart { start = await watch.resumePosition(metaID: request.metaID, videoID: request.videoID) }
            startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
            do { try await engine.load(url: file, startAt: start) } catch { fail("No pude abrir el archivo descargado.") }
            return
        }
        let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
        while true {
            let found: Source?
            do {
                sourceChoices = try await finder.find(kind: request.kind, videoID: request.videoID, prefs: langs.prefs)
                if let chosen = request.sourceIndex, failedSources.isEmpty, let pick = sourceChoices.first(where: { $0.index == chosen }) { found = pick }
                else { found = try await finder.best(kind: request.kind, videoID: request.videoID, prefs: langs.prefs, binge: request.binge, skip: failedSources) }
            } catch { return fail("No pude pedir las fuentes: \(error)") }
            guard myGeneration == generation else { return }
            guard let found else { return fail(failedSources.isEmpty ? "No hay fuentes de Real-Debrid para este título." : "Ninguna fuente funcionó.") }
            source = found
            let start: Double
            if let startAt { start = startAt } else if request.fromStart { start = 0 } else { start = await watch.resumePosition(metaID: request.metaID, videoID: request.videoID) }
            startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
            guard let url = found.playbackURL else { failedSources.insert(found.index); continue }
            do { try await engine.load(url: url, startAt: start); return }
            catch {
                failedSources.insert(found.index)
                attempts = failedSources.count
                if failedSources.count > PlaybackRules.maxSourceRetries { return fail("Ninguna fuente funcionó.") }
                notice = .triedAnotherSource(attempt: failedSources.count)
            }
        }
    }

    private func fail(_ message: String) { phase = .failed(message); startupDeadline = nil }

    // MARK: lo que dice el motor
    func handle(_ s: EngineSnapshot) async {
        guard phase != .closed else { return }
        let now = clock()
        let previous = snapshot
        // Segundos vistos: solo cuenta el tiempo en que estuvo reproduciendo (y sin saltos raros).
        if previous.state == .playing, let last = lastSnapshotAt { watchedUnsaved += min(max(0, now.timeIntervalSince(last)), 5) }
        lastSnapshotAt = now
        snapshot = s

        if case .failed(let message) = s.state {
            if hasPlayed { return fail(message) }
            return await retryWithAnotherSource()
        }
        if s.state == .playing && !hasPlayed {
            hasPlayed = true; startupDeadline = nil; phase = .playing
            await report(.started)
        } else if hasPlayed {
            if previous.state == .playing && s.state == .paused { await report(.paused) }
            else if previous.state == .paused && s.state == .playing { await report(.started) }
        }
        if hasPlayed { await applyTracksOnce(s); updateSkipIntro(s); await evaluateUpNext(s, now: now) }
        if s.state == .ended && !reachedEnd { reachedEnd = true; await finishAndAdvance() }
    }

    /// Cada segundo desde la vista: guardado cada minuto, plazo de arranque y cuenta atrás.
    public func tick() async {
        let now = clock()
        if let deadline = startupDeadline, now >= deadline, !hasPlayed, phase == .preparing { return await retryWithAnotherSource() }
        if snapshot.state == .playing {
            if now.timeIntervalSince(lastSave) >= PlaybackRules.saveEvery { await report(.tick) }
            if var card = upNext, let deadline = upNextDeadline {
                card.secondsLeft = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
                upNext = card
                if now >= deadline { await advance(auto: true) }
            }
        }
    }

    private func retryWithAnotherSource() async {
        guard request?.localFile == nil else { return fail("No pude abrir el archivo descargado.") }
        if let source { failedSources.insert(source.index) }
        attempts = failedSources.count
        guard failedSources.count <= PlaybackRules.maxSourceRetries else { return fail("Ninguna fuente funcionó.") }
        notice = .triedAnotherSource(attempt: failedSources.count)
        let position = snapshot.position
        await engine.stop()
        generation += 1
        phase = .preparing
        await prepare(startAt: position > 5 ? position : nil)
    }

    // MARK: guardado
    private func event() -> ProgressEvent? {
        guard let r = request else { return nil }
        return ProgressEvent(kind: r.kind, metaID: r.metaID, videoID: r.videoID, originalTitle: r.originalTitle, position: snapshot.position,
                             duration: snapshot.duration > 0 ? snapshot.duration : CinemetaParsing.runtimeSeconds(r.meta.map { CinemetaParsing.describe($0).runtime } ?? ""),
                             watched: watchedUnsaved, at: clock().timeIntervalSince1970)
    }

    private func report(_ phase: PlaybackPhase) async {
        guard let event = event() else { return }
        let outcome = await watch.report(event, phase: phase)
        if phase != .started { lastSave = clock() }
        if outcome.savedToStremio || outcome.queued { watchedUnsaved = 0 }
    }

    // MARK: pistas
    private func applyTracksOnce(_ s: EngineSnapshot) async {
        guard !tracksApplied, !s.audioTracks.isEmpty || !s.subtitleTracks.isEmpty, let request else { return }
        tracksApplied = true
        let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
        let audio = TrackChooser.audio(s.audioTracks, language: langs.prefs.audio)
        if let audio, audio.id != s.selectedAudio { await engine.selectAudio(audio.id) }
        if TrackChooser.wrongAudio(s.audioTracks, language: langs.prefs.audio) { notice = .audioNotInYourLanguage }
        let audioLanguage = PlaybackRules.languageCode(audio?.language) ?? langs.prefs.audio
        let mode: SubtitleMode = settings.value.onlyForcedSubtitles ? .forced : SubtitleMode(settings: langs.subtitles, onlyForced: false)
        let sub = TrackChooser.subtitle(s.subtitleTracks, mode: mode, audioLanguage: audioLanguage)
        knownSubtitleIDs = Set(s.subtitleTracks.map(\.id))
        if let sub { await engine.selectSubtitle(sub.id) }
        else if case .language(let language) = mode, !(audio.map { TrackChooser.matches($0, language) } ?? false) {
            // El video no trae subtítulos en tu idioma: se piden a tus complementos (OpenSubtitles…) o a la descarga.
            await addExternalSubtitle(language: language)
        }
    }

    private func addExternalSubtitle(language: String) async {
        guard let request, !addedExternalSubtitle else { return }
        addedExternalSubtitle = true
        var url = request.localSubtitles.first { $0.lastPathComponent.hasPrefix(language) }
        if url == nil && request.localFile == nil { url = await finder.subtitles(kind: request.kind, videoID: request.videoID, language: language).first }
        if let url { await engine.addSubtitle(url: url, language: language) }
    }

    /// El motor ya sumó el subtítulo externo: se activa.
    private func selectNewSubtitleIfAny(_ s: EngineSnapshot) async {
        guard addedExternalSubtitle else { return }
        let new = s.subtitleTracks.filter { !knownSubtitleIDs.contains($0.id) }
        if let track = new.first { knownSubtitleIDs.insert(track.id); await engine.selectSubtitle(track.id) }
    }

    public func selectAudio(_ id: Int?) async {
        userTouched()
        await engine.selectAudio(id)
        if let id, let track = snapshot.audioTracks.first(where: { $0.id == id }), let request {
            titlePrefs.remember(metaID: request.metaID, audioTrack: track.language)
        }
    }

    public func selectSubtitle(_ id: Int?) async {
        userTouched()
        await engine.selectSubtitle(id)
        guard let request else { return }
        if let id, let track = snapshot.subtitleTracks.first(where: { $0.id == id }) { titlePrefs.remember(metaID: request.metaID, subtitleTrack: track.language ?? "") }
        else if id == nil { titlePrefs.remember(metaID: request.metaID, subtitleTrack: "") }
    }

    // MARK: controles
    private func userTouched() { autoAdvances = 0 }

    public func togglePlay() async { userTouched(); snapshot.state == .playing ? await engine.pause() : await engine.play() }
    public func play() async { userTouched(); await engine.play() }
    public func pause() async { userTouched(); await engine.pause() }
    public func seek(to seconds: Double) async { userTouched(); await engine.seek(to: max(0, min(seconds, snapshot.duration > 0 ? snapshot.duration : seconds))) }
    public func skip(_ delta: Double) async { await seek(to: snapshot.position + delta) }

    /// Cambia de fuente en el mismo punto.
    public func switchSource(to index: Int) async {
        guard let request, let choice = sourceChoices.first(where: { $0.index == index }), let url = choice.playbackURL else { return }
        userTouched()
        let position = snapshot.position
        source = choice; hasPlayed = false; tracksApplied = false; phase = .preparing
        startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
        do { try await engine.load(url: url, startAt: position) } catch { failedSources.insert(index); await retryWithAnotherSource() }
        _ = request
    }

    // MARK: intro y siguiente episodio
    private func updateSkipIntro(_ s: EngineSnapshot) {
        let sorted = s.chapters.sorted { $0.time < $1.time }
        for (i, chapter) in sorted.enumerated() where PlaybackRules.chapterKind(chapter.title) == .intro {
            let end = i + 1 < sorted.count ? sorted[i + 1].time : s.duration
            if s.position >= chapter.time && s.position < end - 1 { skipIntroTo = end; return }
        }
        skipIntroTo = nil
    }

    public func skipIntro() async { if let target = skipIntroTo { await seek(to: target) } }

    private func nextEpisodeID() -> String? {
        guard let request, request.kind == "series", let meta = request.meta else { return nil }
        return CinemetaParsing.nextEpisode(meta, after: request.videoID)
    }

    private func evaluateUpNext(_ s: EngineSnapshot, now: Date) async {
        guard let next = nextEpisodeID(), s.duration > 0, let request else { return }
        let remaining = s.duration - s.position
        if remaining <= PlaybackRules.upNextLookahead && !preloadedNext {
            preloadedNext = true  // que al llegar el momento ya esté buscada la fuente
            let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
            Task { _ = try? await finder.find(kind: request.kind, videoID: next, prefs: prefs) }
        }
        let inCredits = s.chapters.sorted { $0.time < $1.time }.last { $0.time <= s.position }.map { PlaybackRules.chapterKind($0.title) == .credits } ?? false
        if upNext == nil && !upNextDismissed && PlaybackRules.shouldShowUpNext(position: s.position, duration: s.duration, inCredits: inCredits) {
            upNextDeadline = now.addingTimeInterval(PlaybackRules.upNextCountdown)
            let (label, title) = episodeText(next)
            upNext = UpNext(videoID: next, label: label, title: title, secondsLeft: Int(PlaybackRules.upNextCountdown))
        }
        await selectNewSubtitleIfAny(s)
    }

    private func episodeText(_ videoID: String) -> (String, String) {
        guard let meta = request?.meta else { return ("", "") }
        for season in CinemetaParsing.seasons(meta) {
            if let ep = season.episodes.first(where: { $0.id == videoID }) { return (episodeLabel(season.season, ep.episode), ep.title) }
        }
        return ("", "")
    }

    public func cancelUpNext() { userTouched(); upNext = nil; upNextDeadline = nil; upNextDismissed = true }
    public func playNextNow() async { userTouched(); await advance(auto: false) }

    public func confirmStillWatching() async {
        userTouched(); stillWatchingPrompt = false
        await advance(auto: false)
    }

    private func advance(auto: Bool) async {
        guard let card = upNext, let request else { return }
        if auto && autoAdvances >= PlaybackRules.stillWatchingAfter {
            // Tres episodios seguidos sin tocar la pantalla: se pregunta antes de seguir.
            stillWatchingPrompt = true; upNextDeadline = nil; await engine.pause(); return
        }
        await report(.stopped(finished: true))
        var next = request
        next.videoID = card.videoID; next.fromStart = true; next.binge = source?.binge
        if auto { autoAdvances += 1 }
        let kept = autoAdvances
        await begin(next)
        autoAdvances = kept
    }

    private func finishAndAdvance() async {
        if nextEpisodeID() != nil && !upNextDismissed && !stillWatchingPrompt {
            if upNext == nil, let next = nextEpisodeID() { let (l, t) = episodeText(next); upNext = UpNext(videoID: next, label: l, title: t, secondsLeft: 0) }
            await advance(auto: true)
        } else { await report(.stopped(finished: true)); phase = .closed; await engine.stop() }
    }

    // MARK: cierre
    /// Cierra el reproductor y guarda dónde te quedaste.
    public func close() async {
        guard phase != .closed else { return }
        consuming?.cancel()
        let finished = reachedEnd || (snapshot.duration > 0 && snapshot.position >= snapshot.duration * StremioLibrary.watchedAt)
        await report(.stopped(finished: finished))
        phase = .closed
        await engine.stop()
    }

    /// Al pasar a segundo plano: se guarda ya (iOS puede suspender la app).
    public func appDidEnterBackground() async { if hasPlayed { await report(.tick) } }
}
