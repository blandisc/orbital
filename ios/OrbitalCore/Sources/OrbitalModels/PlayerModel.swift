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
    /// El segundo exacto donde empezar («Seguir en el iPhone» desde la TV); sin él, donde te quedaste.
    public var startPosition: Double?
    public var localFile: URL?             // una descarga: se reproduce sin red
    public var localSubtitles: [URL] = []
    public var binge: String?              // el grupo de la fuente anterior (misma calidad e idioma)
    public var sourceIndex: Int?           // una fuente elegida en la lista
    /// Desde Mi media: primero tu copia de OneDrive (también para el siguiente episodio); si falla, Real-Debrid.
    public var ownCopy = false

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

/// El siguiente episodio ya descargado (para seguir viendo sin conexión).
public struct LocalEpisode: Sendable, Equatable {
    public var file: URL
    public var subtitles: [URL]
    public init(file: URL, subtitles: [URL] = []) { self.file = file; self.subtitles = subtitles }
}

/// Orquesta una reproducción: elige la fuente, reanuda donde ibas, pone el audio y los subtítulos que quieres,
/// guarda el avance (cada minuto, al pausar y al cerrar), ofrece «Siguiente episodio» y cambia de fuente si una falla.
/// No conoce SwiftUI ni el motor concreto: `PlayerEngine` y los relojes se inyectan, así se prueba entero.
///
/// Concurrencia: todo ocurre en el hilo principal, pero hay `await` en medio (red); por eso cada cambio de video lleva un número
/// (`generation`) y se revisa tras cada espera, y las instantáneas del motor se ignoran mientras se carga otra fuente.
@MainActor
public final class PlayerModel: ObservableModel {
    public enum Phase: Equatable { case idle, preparing, playing, failed(String), closed }

    public private(set) var phase: Phase = .idle { didSet { changed() } }
    public private(set) var snapshot = EngineSnapshot() { didSet { changed() } }
    /// Un episodio descargado que viste hasta el final y del que el reproductor pasó solo al siguiente (para «Borrar al
    /// terminar de verlo»: el último lo atiende quien cierra el reproductor).
    public var onFinishedLocal: (@MainActor (PlayRequest) -> Void)?
    public private(set) var request: PlayRequest? { didSet { changed() } }
    public private(set) var source: Source? { didSet { changed() } }
    public private(set) var sourceChoices: [Source] = [] { didSet { changed() } }
    public private(set) var upNext: UpNext? { didSet { changed() } }
    public private(set) var skipIntroTo: Double? { didSet { changed() } }
    /// Qué se salta con el botón: la intro o el resumen («Anteriormente en…»).
    public enum SkipKind: Sendable, Equatable { case intro, recap }
    public private(set) var skipKind: SkipKind = .intro { didSet { changed() } }
    /// Las marcas de la comunidad (IntroDB) del video que suena: intro, resumen y créditos.
    public private(set) var segments: SkipSegments? { didSet { changed() } }
    private var segmentsFor: String?
    public private(set) var stillWatchingPrompt = false { didSet { changed() } }
    public private(set) var notice: PlayerNotice? { didSet { changed() } }
    /// Sincronía de los subtítulos (s): positivo los atrasa, negativo los adelanta (como Infuse). Vuelve a 0 con cada video.
    public private(set) var subtitleDelay: Double = 0 { didSet { changed() } }
    public static let subtitleStep = 0.5, subtitleMaxDelay = 10.0
    public func nudgeSubtitles(by seconds: Double) {
        subtitleDelay = max(-Self.subtitleMaxDelay, min(Self.subtitleMaxDelay, (subtitleDelay + seconds).rounded(toPlaces: 1)))
    }
    public func resetSubtitleDelay() { subtitleDelay = 0 }
    /// Velocidad de reproducción elegida (sigue igual en el siguiente episodio y al cambiar de fuente).
    public private(set) var rate: Float = 1 { didSet { changed() } }
    public static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    public private(set) var attempts = 0 { didSet { changed() } }

    private let engine: PlayerEngine
    private let finder: StreamFinder
    private let watch: WatchService
    private let titlePrefs: TitlePreferences
    private let settings: SettingsStore
    private let clock: @Sendable () -> Date
    private let onCellular: @Sendable () -> Bool
    private let episodeLabel: @Sendable (Int, Int) -> String
    private let localEpisode: @Sendable (_ metaID: String, _ videoID: String) async -> LocalEpisode?

    private var consuming: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var failedSources = Set<Int>()
    private var hasPlayed = false
    private var startupDeadline: Date?
    private var lastSnapshotAt: Date?
    private var lastSave: Date
    private var watchedUnsaved = 0.0
    private var tracksApplied = false
    private var addedExternalSubtitle = false
    private var rescrobbleAfterSeek = false
    /// Trakt ya sabe que empezó este video (el `start` sale cuando el motor suena Y se sabe la duración).
    private var scrobbleStarted = false
    /// Lo último que Trakt sabe: ¿está sonando (`start`) o en pausa (`pause`)?
    private var scrobblePlaying = false
    private var knownSubtitleIDs = Set<Int>()
    private var preloadedNext = false
    private var upNextDeadline: Date?
    private var lastTick: Date?
    /// El panel de ajustes del video está abierto (la tarjeta de «Siguiente» no se ve).
    public var panelOpen = false
    private var upNextDismissed = false
    private var autoAdvances = 0
    private var reachedEnd = false
    private var finalReported = false
    private var generation = 0
    private var acceptingSnapshots = false     // false mientras se elige y se carga una fuente (lo que el motor diga entonces es del video anterior)
    private var retrying = false
    private var advancing = false
    private var closing = false
    private var choicesAt = Date.distantPast
    private var nextLocal: LocalEpisode?
    private let skipSegments: @Sendable (String) async -> SkipSegments?
    private let scareMap: @Sendable (String, String) async -> [JumpScare]?
    /// Tu copia de un video (Mi media), si la hay: se usa antes que las fuentes cuando `request.ownCopy`.
    public var ownSource: (@Sendable (_ videoID: String, _ preferred: Int?) async -> Source?)?
    /// Cuántas veces se pidió tu copia en este video: dos (su enlace dura ~1 h; si se venció a media película se pide otro), luego Real-Debrid.
    private var ownAttempts = 0
    static let maxOwnAttempts = 2
    static let choicesLifetime: TimeInterval = StreamFinder.cacheSeconds   // los enlaces de Real-Debrid caducan

    public init(engine: PlayerEngine, finder: StreamFinder, watch: WatchService, titlePrefs: TitlePreferences, settings: SettingsStore,
                clock: @escaping @Sendable () -> Date = { Date() }, onCellular: @escaping @Sendable () -> Bool = { false },
                episodeLabel: @escaping @Sendable (Int, Int) -> String = { "T\($0) · E\($1)" },
                localEpisode: @escaping @Sendable (String, String) async -> LocalEpisode? = { _, _ in nil },
                skipSegments: @escaping @Sendable (String) async -> SkipSegments? = { _ in nil },
                scareMap: @escaping @Sendable (_ imdb: String, _ title: String) async -> [JumpScare]? = { _, _ in nil }) {
        self.engine = engine; self.finder = finder; self.watch = watch; self.titlePrefs = titlePrefs; self.settings = settings
        self.clock = clock; self.onCellular = onCellular; self.episodeLabel = episodeLabel; self.localEpisode = localEpisode; self.skipSegments = skipSegments; self.scareMap = scareMap; self.lastSave = clock()
        super.init()
    }

    // MARK: arranque
    /// Empieza a reproducir. Devuelve cuando el motor ya recibió la fuente (el video puede tardar unos segundos).
    public func begin(_ request: PlayRequest) async {
        subtitleDelay = 0
        ownAttempts = 0
        guard !closing, phase != .closed else { return }
        generation += 1
        let mine = generation
        self.request = request
        resetForNewVideo()
        phase = .preparing
        startConsuming()
        if request.localFile != nil, request.kind == "series", let next = nextEpisodeIDIgnoringLocal() { nextLocal = await localEpisode(request.metaID, next) }
        guard mine == generation, !closing else { return }
        await prepare(startAt: nil, generation: mine)
    }

    /// Una sola tarea escucha al motor durante toda la reproducción (también entre episodios).
    private func startConsuming() {
        guard consuming == nil else { return }
        let stream = engine.snapshots
        consuming = Task { [weak self] in for await s in stream { await self?.handle(s) } }
    }

    private func resetForNewVideo() {
        failedSources = []; hasPlayed = false; startupDeadline = nil; lastSnapshotAt = nil; watchedUnsaved = 0
        scrobbleStarted = false; scrobblePlaying = false; rescrobbleAfterSeek = false
        tracksApplied = false; addedExternalSubtitle = false; knownSubtitleIDs = []; preloadedNext = false
        upNext = nil; upNextDeadline = nil; upNextDismissed = false; skipIntroTo = nil; reachedEnd = false; finalReported = false
        notice = nil; attempts = 0; lastSave = clock(); snapshot = EngineSnapshot(state: .loading); source = nil; sourceChoices = []
        acceptingSnapshots = false; retrying = false; nextLocal = nil; choicesAt = .distantPast
        // Lo encontrado «En internet» y el mapa de sustos eran del video anterior.
        foundSubtitles = nil; addedSubtitleURLs = []; subtitleSearchFailed = false; scares = nil
        Task { [weak self] in await self?.loadScares() }
    }

    /// Justo antes de cargar: de aquí en adelante lo que diga el motor es del video nuevo.
    private func startLoading() {
        loadSegmentsIfNeeded()
        acceptingSnapshots = true; retrying = false; hasPlayed = false; tracksApplied = false
        // Otra fuente: el subtítulo externo (OpenSubtitles) se vuelve a sumar; antes se perdía al cambiar de fuente.
        addedExternalSubtitle = false; knownSubtitleIDs = []
        scrobbleStarted = false   // otra carga (otra fuente, otro episodio): cuando suene, Trakt recibe el avance donde va
        startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
    }

    /// Elige fuente y la carga. `startAt` solo se pasa al reintentar con otra fuente (se sigue en el mismo punto).
    private func prepare(startAt: Double?, generation mine: Int) async {
        guard let request else { return }
        if let file = request.localFile {
            var start = startAt ?? 0
            if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await watch.resumePosition(metaID: request.metaID, videoID: request.videoID) } }
            guard mine == generation, !closing else { return }
            startLoading()
            do { try await loadVideo(file, at: start) } catch { fail("No pude abrir el archivo descargado.") }
            return
        }
        let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
        while true {
            let found: Source?
            if request.ownCopy, ownAttempts < Self.maxOwnAttempts, let own = await ownSource?(request.videoID, request.sourceIndex) {
                ownAttempts += 1
                guard mine == generation, !closing else { return }
                source = own
                var start = startAt ?? 0
                if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await watch.resumePosition(metaID: request.metaID, videoID: request.videoID) } }
                guard mine == generation, !closing, let url = own.playbackURL else { failedSources.insert(own.index); continue }
                startLoading()
                do { try await loadVideo(url, at: start); return }
                catch { guard mine == generation else { return }; failedSources.insert(own.index); notice = .triedAnotherSource(attempt: 1); acceptingSnapshots = false; continue }
            }
            do {
                sourceChoices = try await finder.find(kind: request.kind, videoID: request.videoID, prefs: langs.prefs)
                choicesAt = clock()
                guard mine == generation, !closing else { return }
                if let chosen = request.sourceIndex, failedSources.isEmpty, let pick = sourceChoices.first(where: { $0.index == chosen }) { found = pick }
                // «Continuar»: la fuente con la que lo dejaste, si sigue ahí (como en la TV).
                else if failedSources.isEmpty, !request.fromStart, let key = titlePrefs.resumeChoice(metaID: request.metaID, videoID: request.videoID)?.source,
                        let pick = sourceChoices.first(where: { $0.key == key }) { found = pick }
                else { found = try await finder.best(kind: request.kind, videoID: request.videoID, prefs: langs.prefs, binge: request.binge, skip: failedSources) }
            } catch { guard mine == generation else { return }; return fail("No pude pedir las fuentes: \(error)") }
            guard mine == generation, !closing else { return }
            guard let found else { return fail(failedSources.isEmpty ? "No hay fuentes de Real-Debrid para este título." : "Ninguna fuente funcionó.") }
            source = found
            var start = startAt ?? 0
            if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await watch.resumePosition(metaID: request.metaID, videoID: request.videoID) } }
            guard mine == generation, !closing else { return }
            guard let url = found.playbackURL else { failedSources.insert(found.index); continue }
            startLoading()
            do { try await loadVideo(url, at: start); return }
            catch {
                guard mine == generation else { return }
                failedSources.insert(found.index)
                attempts = failedSources.count
                if failedSources.count > PlaybackRules.maxSourceRetries { return fail("Ninguna fuente funcionó.") }
                notice = .triedAnotherSource(attempt: failedSources.count)
                acceptingSnapshots = false
            }
        }
    }

    /// Los mensajes de los motores pueden traer la dirección del video (con tu clave): nunca llegan a la pantalla.
    private func fail(_ message: String) { phase = .failed(stripURLs(message)); startupDeadline = nil }

    // MARK: lo que dice el motor
    func handle(_ raw: EngineSnapshot) async {
        guard phase != .closed, acceptingSnapshots, !retrying else { return }
        var s = raw
        s.position = StremioLibrary.finite(s.position); s.duration = StremioLibrary.finite(s.duration)   // NaN o infinito (en vivo) no valen
        let now = clock()
        let previous = snapshot
        // Segundos vistos: solo cuenta el tiempo en que estuvo reproduciendo (y sin saltos raros).
        if previous.state == .playing, let last = lastSnapshotAt { watchedUnsaved += min(max(0, now.timeIntervalSince(last)), 5) }
        lastSnapshotAt = now
        snapshot = s

        if case .failed(let message) = s.state {
            // Una fuente que se corta (antes o después de empezar) se cambia por otra en el mismo punto, como en Orbital.
            // El cambio corre aparte: así los avisos repetidos del mismo fallo, que ya están en cola, se descartan mientras se carga la otra.
            _ = message
            retryWithAnotherSource()
            return
        }
        if s.state == .playing && !hasPlayed { hasPlayed = true; startupDeadline = nil; phase = .playing }
        if hasPlayed {
            await applyTracksOnce(s)                 // primero el audio y los subtítulos; el aviso a Trakt no los retrasa
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
    private func scrobbleIfNeeded(_ s: EngineSnapshot) async {
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
        if let deadline = startupDeadline, now >= deadline, !hasPlayed, phase == .preparing, !retrying { return await retryWithAnotherSource()?.value ?? () }
        if snapshot.state == .playing {
            if now.timeIntervalSince(lastSave) >= PlaybackRules.saveEvery { await report(.tick) }
            if var card = upNext, let deadline = upNextDeadline {
                // Con el panel de ajustes abierto la tarjeta no se ve: la cuenta se detiene (no cambia de episodio a escondidas).
                if panelOpen { upNextDeadline = deadline.addingTimeInterval(now.timeIntervalSince(lastTick ?? now)); lastTick = now; return }
                card.secondsLeft = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
                upNext = card
                if now >= deadline { await advance(auto: true)?.value }
            }
        }
    }

    /// Cambia a otra fuente en el mismo punto. Marca el cambio de forma síncrona (lo que el motor diga ahora se ignora) y carga aparte.
    @discardableResult
    private func retryWithAnotherSource() -> Task<Void, Never>? {
        guard !retrying, !closing else { return transition }
        guard request?.localFile == nil else { fail("No pude abrir el archivo descargado."); return nil }
        retrying = true; acceptingSnapshots = false; startupDeadline = nil
        if let source { failedSources.insert(source.index) }
        attempts = failedSources.count
        guard failedSources.count <= PlaybackRules.maxSourceRetries else { retrying = false; fail("Ninguna fuente funcionó."); return nil }
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

    // MARK: guardado
    private func event() -> ProgressEvent? {
        guard let r = request else { return nil }
        let known = snapshot.duration > 0 ? snapshot.duration : CinemetaParsing.runtimeSeconds(r.meta.map { CinemetaParsing.describe($0).runtime } ?? "")
        return ProgressEvent(kind: r.kind, metaID: r.metaID, videoID: r.videoID, originalTitle: r.originalTitle, position: StremioLibrary.finite(snapshot.position),
                             duration: StremioLibrary.finite(known), watched: 0, at: clock().timeIntervalSince1970)
    }

    /// Cada aviso reserva los segundos vistos que le tocan (dos avisos a la vez no cuentan los mismos segundos dos veces) y los
    /// devuelve si no se pudieron guardar ni encolar.
    private func report(_ phase: PlaybackPhase) async {
        // Un archivo que te pasaron y no se reconoció («file:…»): no es un título de Stremio, no se guarda nada allá.
        guard var event = event(), !event.metaID.hasPrefix("file:") else { return }
        let reserved: Double
        if case .started = phase { reserved = 0 } else { reserved = watchedUnsaved; watchedUnsaved -= reserved }
        event.watched = reserved
        if case .stopped = phase { finalReported = true }
        if case .started = phase {} else { rememberChoice() }
        let outcome = await watch.report(event, phase: phase)
        if case .started = phase { return }
        if outcome.savedToStremio || outcome.queued { lastSave = clock() } else { watchedUnsaved += reserved }
    }

    // MARK: pistas
    private func applyTracksOnce(_ s: EngineSnapshot) async {
        guard !tracksApplied, !s.audioTracks.isEmpty || !s.subtitleTracks.isEmpty, let request else { return }
        tracksApplied = true
        // «Continuar»: las mismas pistas con que lo dejaste; lo que no se encuentre, con la regla de siempre.
        // También en el siguiente episodio de la serie (antes solo en el mismo episodio exacto).
        if !request.fromStart, let choice = titlePrefs.lastChoice(metaID: request.metaID), await applyResumeTracks(choice, s) { return }
        let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
        let audio = TrackChooser.audio(s.audioTracks, language: langs.prefs.audio, latin: settings.value.latinSpanish)
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

    /// Las pistas guardadas, si están en este video. true si los subtítulos quedaron como los dejaste (el audio, si se
    /// encuentra, también); false para elegir con la regla de siempre.
    private func applyResumeTracks(_ choice: ResumeChoice, _ s: EngineSnapshot) async -> Bool {
        // La misma pista (idioma y nombre); si en este archivo se llama distinto (otro episodio, otra fuente), la del mismo idioma.
        func find(_ tracks: [MediaTrack], _ saved: ResumeChoice.Track) -> MediaTrack? {
            tracks.first { $0.language == saved.language && $0.title == saved.title }
                ?? tracks.first { PlaybackRules.languageCode($0.language) != nil && PlaybackRules.languageCode($0.language) == PlaybackRules.languageCode(saved.language) && !$0.isForced }
        }
        guard let sub = choice.subtitle else { return false }
        if let audio = choice.audio, let track = find(s.audioTracks, audio), track.id != s.selectedAudio { await engine.selectAudio(track.id) }
        knownSubtitleIDs = Set(s.subtitleTracks.map(\.id))
        if sub.off { await engine.selectSubtitle(nil); return true }
        guard let track = find(s.subtitleTracks, sub) else { return false }
        await engine.selectSubtitle(track.id)
        return true
    }

    /// Junto a «dónde ibas»: la fuente y las pistas que tienes puestas (para «Continuar»).
    private func rememberChoice() {
        guard let request, snapshot.position >= PlaybackRules.rememberChoiceAfter else { return }
        func pick(_ tracks: [MediaTrack], _ selected: Int?) -> ResumeChoice.Track? {
            guard !tracks.isEmpty else { return nil }
            guard let selected, let t = tracks.first(where: { $0.id == selected }) else { return ResumeChoice.Track(off: true) }
            return ResumeChoice.Track(language: t.language, title: t.title)
        }
        let audio = pick(snapshot.audioTracks, snapshot.selectedAudio).flatMap { $0.off ? nil : $0 }
        titlePrefs.remember(metaID: request.metaID, choice: ResumeChoice(videoID: request.videoID, source: source?.key, audio: audio,
                                                                        subtitle: pick(snapshot.subtitleTracks, snapshot.selectedSubtitle)))
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
        if let url { await engine.addSubtitle(url: url, language: language) }
    }

    /// «Buscar en internet» (Subtítulos del reproductor): todo lo que hay en OpenSubtitles y tus complementos, por idioma.
    public private(set) var foundSubtitles: [SubtitleOption]? { didSet { changed() } }
    /// Los sustos de la película que suena (Where's The Jump), marcados en la barra; nil: no hay mapa.
    public private(set) var scares: [JumpScare]? { didSet { changed() } }

    public func loadScares() async {
        guard let r = request, r.kind == "movie", r.metaID.hasPrefix("tt") else { scares = nil; return }
        let id = r.metaID
        let found = await scareMap(id, r.originalTitle)
        guard request?.metaID == id else { return }
        scares = found
    }
    public private(set) var searchingSubtitles = false { didSet { changed() } }

    public func searchSubtitles() async {
        guard let request, !searchingSubtitles else { return }
        let mine = generation
        searchingSubtitles = true
        defer { searchingSubtitles = false }
        let file = request.localFile.flatMap(FileFingerprint.of)
        let found = await finder.subtitleOptions(kind: request.kind, videoID: request.videoID, file: file)
        guard generation == mine else { return }   // ya es otro video: no se le cuelgan los de este
        // Nada (o sin red): se queda el botón para volver a intentar, con el aviso.
        foundSubtitles = found.isEmpty ? nil : found
        subtitleSearchFailed = found.isEmpty
    }

    /// No se encontró nada en la última búsqueda (o no había red).
    public private(set) var subtitleSearchFailed = false { didSet { changed() } }
    /// Los que ya se sumaron (no se suma dos veces el mismo).
    public private(set) var addedSubtitleURLs: Set<URL> = [] { didSet { changed() } }

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
        if let id {
            // Una pista sin etiqueta de idioma no se recuerda (y desde luego no apaga los subtítulos de la serie).
            if let track = snapshot.subtitleTracks.first(where: { $0.id == id }), let language = track.language, !language.isEmpty {
                titlePrefs.remember(metaID: request.metaID, subtitleTrack: language)
            }
        } else { titlePrefs.remember(metaID: request.metaID, subtitleTrack: "") }
    }

    // MARK: controles
    private func userTouched() { autoAdvances = 0 }

    public func setRate(_ value: Float) async { rate = value; await engine.setRate(value) }

    /// Abre un video y le pone la velocidad elegida (el motor empieza cada video en 1).
    private func loadVideo(_ url: URL, at start: Double) async throws {
        if let request {
            // Lo que ya sabes que quieres, desde el primer cuadro: el audio y los subtítulos con que lo dejaste (o tus idiomas).
            let langs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular())
            let choice = request.fromStart ? nil : titlePrefs.lastChoice(metaID: request.metaID)
            let audio = [choice?.audio?.language, settings.value.latinSpanish && langs.prefs.audio == "es" ? "es-419" : nil, langs.prefs.audio].compactMap { $0 }.filter { !$0.isEmpty }
            let subs = choice?.subtitle?.off == true ? [] : [choice?.subtitle?.language, langs.subtitles].compactMap { $0 }.filter { !$0.isEmpty }
            await engine.prepare(audioLanguages: audio, subtitleLanguages: subs, externalSubtitles: request.localSubtitles)
        }
        try await engine.load(url: url, startAt: start)
        if rate != 1 { await engine.setRate(rate) }
    }

    public func togglePlay() async { userTouched(); snapshot.state == .playing ? await engine.pause() : await engine.play() }
    public func play() async { userTouched(); await engine.play() }
    public func pause() async { userTouched(); await engine.pause() }
    public func seek(to seconds: Double) async {
        userTouched()
        let target = max(0, min(seconds, snapshot.duration > 0 ? snapshot.duration : seconds))
        if hasPlayed, abs(target - snapshot.position) >= PlaybackRules.rescrobbleJump { rescrobbleAfterSeek = true }
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
                if !local { try? await Task.sleep(nanoseconds: PlaybackRules.streamScrubInterval) }
            }
            self?.scrubTask = nil
        }
    }
    private var scrubTarget: Double?
    private var scrubTask: Task<Void, Never>?

    public func skip(_ delta: Double) async { await seek(to: snapshot.position + delta) }

    /// Cambia de fuente en el mismo punto. Si la lista de fuentes es vieja (los enlaces de Real-Debrid caducan) se pide de nuevo.
    public func switchSource(to index: Int) async {
        guard let request, !closing else { return }
        userTouched()
        generation += 1
        let mine = generation
        let position = snapshot.position
        acceptingSnapshots = false
        if clock().timeIntervalSince(choicesAt) > Self.choicesLifetime {
            let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
            if let fresh = try? await finder.find(kind: request.kind, videoID: request.videoID, prefs: prefs, fresh: true) { sourceChoices = fresh; choicesAt = clock() }
        }
        guard mine == generation, !closing, let choice = sourceChoices.first(where: { $0.index == index }) ?? sourceChoices.first(where: { $0.release == source?.release && $0.index == index }),
              let url = choice.playbackURL else { acceptingSnapshots = true; return }
        source = choice; phase = .preparing
        startLoading()
        do { try await loadVideo(url, at: position) } catch { guard mine == generation else { return }; failedSources.insert(index); await retryWithAnotherSource()?.value }
    }

    // MARK: intro y siguiente episodio
    /// Las marcas de IntroDB del video que va a sonar (una vez por video; otra fuente del mismo no las vuelve a pedir).
    private func loadSegmentsIfNeeded() {
        guard let videoID = request?.videoID, segmentsFor != videoID else { return }
        segmentsFor = videoID
        segments = nil
        let fetch = skipSegments
        Task { [weak self] in
            let found = await fetch(videoID)
            guard let self, self.request?.videoID == videoID else { return }
            self.segments = found
        }
    }

    /// «Saltar intro» / «Saltar resumen»: primero los capítulos del archivo; si no los trae, las marcas de la comunidad.
    private func updateSkipIntro(_ s: EngineSnapshot) {
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

    public func skipIntro() async { if let target = skipIntroTo { await seek(to: target) } }

    private func nextEpisodeIDIgnoringLocal() -> String? {
        guard let request, request.kind == "series", let meta = request.meta else { return nil }
        return CinemetaParsing.nextEpisode(meta, after: request.videoID)
    }

    /// El siguiente episodio. Viendo un archivo descargado solo cuenta si el siguiente también está descargado.
    private func nextEpisodeID() -> String? {
        guard let next = nextEpisodeIDIgnoringLocal() else { return nil }
        if request?.localFile != nil && nextLocal == nil { return nil }
        return next
    }

    private func evaluateUpNext(_ s: EngineSnapshot, now: Date) async {
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
            upNext = UpNext(videoID: next, label: label, title: title, secondsLeft: Int(PlaybackRules.upNextCountdown))
        } else if upNext != nil && !near && remaining > PlaybackRules.upNextAt + 5 {
            upNext = nil; upNextDeadline = nil          // retrocediste lejos del final: la tarjeta ya no aplica
        }
    }

    private func episodeText(_ videoID: String) -> (String, String) {
        guard let meta = request?.meta else { return ("", "") }
        for season in CinemetaParsing.seasons(meta) {
            if let ep = season.episodes.first(where: { $0.id == videoID }) { return (episodeLabel(season.season, ep.episode), ep.title) }
        }
        return ("", "")
    }

    public func cancelUpNext() { userTouched(); upNext = nil; upNextDeadline = nil; upNextDismissed = true }
    public func playNextNow() async { userTouched(); await advance(auto: false)?.value }

    public func confirmStillWatching() async {
        userTouched(); stillWatchingPrompt = false
        await advance(auto: false)?.value
    }

    /// Pasa al siguiente episodio. Es una sola transición a la vez (un «Ver ahora» y la cuenta atrás no la duplican) y corre aparte:
    /// quien la pide (el escucha del motor) no se queda esperando mientras se buscan las fuentes. Se puede esperar con `waitForTransition`.
    @discardableResult
    private func advance(auto: Bool) -> Task<Void, Never>? {
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
            if request.localFile != nil, snapshot.duration > 0, snapshot.position >= snapshot.duration * StremioLibrary.watchedAt { onFinishedLocal?(request) }
            var next = request
            next.videoID = card.videoID; next.fromStart = true; next.binge = source?.binge
            next.episodeLabel = card.title.isEmpty ? card.label : "\(card.label) · \(card.title)"   // si no, se queda el del episodio anterior
            if request.localFile != nil, let local = nextLocal { next.localFile = local.file; next.localSubtitles = local.subtitles }
            if auto { autoAdvances += 1 }
            advancing = false
            await begin(next)
        }
        transition = task
        return task
    }

    /// Espera a que termine el cambio de episodio en curso (para las pruebas y para la vista).
    public func waitForTransition() async { await transition?.value }

    private func finishAndAdvance() async {
        if nextEpisodeID() != nil && !upNextDismissed && !stillWatchingPrompt {
            if upNext == nil, let next = nextEpisodeID() { let (l, t) = episodeText(next); upNext = UpNext(videoID: next, label: l, title: t, secondsLeft: 0) }
            advance(auto: true)
        } else {
            if !finalReported { await report(.stopped(finished: true)) }
            phase = .closed
            await engine.stop()
        }
    }

    // MARK: cierre
    /// Cierra el reproductor y guarda dónde te quedaste. Se puede llamar varias veces: solo la primera hace algo.
    public func close() async {
        guard !closing, phase != .closed else { return }
        closing = true
        generation += 1                       // cualquier carga o cambio de episodio en curso queda sin efecto
        consuming?.cancel(); consuming = nil
        let finished = reachedEnd || (snapshot.duration > 0 && snapshot.position >= snapshot.duration * StremioLibrary.watchedAt)
        // Primero se calla (la pantalla ya se fue); guardar en la red puede tardar.
        await engine.pause()
        if !finalReported { await report(.stopped(finished: finished)) }
        phase = .closed
        await engine.stop()
    }

    /// Al pasar a segundo plano: se guarda ya (iOS puede suspender la app).
    public func appDidEnterBackground() async { if hasPlayed, phase != .closed, !closing { await report(.tick) } }
}

extension Double {
    /// Redondeo a décimas (los pasos de la sincronía no acumulan 0.30000000000000004).
    func rounded(toPlaces places: Int) -> Double { let f = pow(10, Double(places)); return (self * f).rounded() / f }
}
