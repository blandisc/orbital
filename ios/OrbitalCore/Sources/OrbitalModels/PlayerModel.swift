import Foundation
import OrbitalCore
import os

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
    /// Lo que se sabe de los subtítulos guardados con la descarga (fuente, copia, si es para sordos), para nombrarlos.
    public var savedSubtitles: [SavedSubtitle] = []
    public var binge: String?              // el grupo de la fuente anterior (misma calidad e idioma)
    public var sourceIndex: Int?           // una fuente elegida en la lista
    /// Desde Mi media: primero tu copia de OneDrive (también para el siguiente episodio); si falla, Real-Debrid.
    public var ownCopy = false
    /// Empieza en vertical (la ruleta de Los Simpson: la tele ya está de pie); girar el teléfono lo acuesta igual.
    public var startPortrait = false

    public init(kind: String, metaID: String, videoID: String, originalTitle: String, displayTitle: String, episodeLabel: String = "", poster: String? = nil,
                year: String? = nil, meta: JSON? = nil, fromStart: Bool = false, localFile: URL? = nil, localSubtitles: [URL] = [], savedSubtitles: [SavedSubtitle] = [], binge: String? = nil, sourceIndex: Int? = nil) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.originalTitle = originalTitle; self.displayTitle = displayTitle
        self.episodeLabel = episodeLabel; self.poster = poster; self.year = year; self.meta = meta; self.fromStart = fromStart
        self.localFile = localFile; self.localSubtitles = localSubtitles; self.savedSubtitles = savedSubtitles; self.binge = binge; self.sourceIndex = sourceIndex
    }
}

public struct UpNext: Sendable, Equatable {
    public var videoID: String
    public var label: String           // «T2 · E6»
    public var title: String
    public var secondsLeft: Int
    /// La imagen del episodio (Cinemeta), si la trae.
    public var thumbnail: String? = nil
}

public enum PlayerNotice: Sendable, Equatable {
    case triedAnotherSource(attempt: Int)
    case audioNotInYourLanguage
    /// Esta versión no trae el idioma que quieres (o no su variante: latino) y otra sí: se ofrece cambiar sin perder el punto.
    /// `language` es el código que quieres («es-419»); `have`, lo que trae esta («en», «es-ES»).
    case otherVersionHasYourLanguage(language: String, have: [String], sourceIndex: Int)
    /// La versión que elegiste no abrió: se volvió a la que veías, en el mismo segundo.
    case switchFailedBack
    /// Real-Debrid aún no tiene esa versión (mandó su video corto de «descargando» en lugar de la película).
    case notReadyOnRealDebrid
}

/// Un idioma de audio que solo trae otra versión (otro archivo): a cuál iría y qué tan seguro es que lo trae.
public struct OtherVersionAudio: Sendable, Equatable, Identifiable {
    public let code: String          // «es-419»
    public let sourceIndex: Int
    public let quality: String       // «1080p» (vacío si no se sabe)
    public let instant: Bool         // ya está en Real-Debrid
    /// Comprobado, o lo dice el nombre o el sitio. Si no (se supone por el original, o no se sabe): «tal vez».
    public let sure: Bool
    public var id: String { code }
}

/// El siguiente episodio ya descargado (para seguir viendo sin conexión).
public struct LocalEpisode: Sendable, Equatable {
    public var file: URL
    public var subtitles: [URL]
    public var saved: [SavedSubtitle]
    public init(file: URL, subtitles: [URL] = [], saved: [SavedSubtitle] = []) { self.file = file; self.subtitles = subtitles; self.saved = saved }
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
    /// Por qué falló: cada caso tiene su pantalla y sus salidas (no un aviso rojo encima de los controles).
    public enum Failure: Equatable, Sendable {
        /// Real-Debrid no tiene nada para este video (un estreno de hoy, algo raro).
        case noSources
        /// Había fuentes y ninguna arrancó.
        case noneWorked
        /// No se pudieron pedir las fuentes (sin red, el complemento caído).
        case network
        /// Arrancó y la fuente dejó de responder.
        case sourceDied
        /// La descarga del iPhone no se puede leer.
        case localFile
    }
    public private(set) var failure: Failure? { didSet { changed() } }

    public private(set) var phase: Phase = .idle { didSet { changed() } }
    /// La búsqueda de versiones de verdad (para la órbita de «Buscando la mejor versión»): a qué complementos se les
    /// pregunta, cuántas trajo cada uno y cuántas quedaron para elegir. nil si no se buscó (tu descarga, la que elegiste).
    public struct SourceSearch: Sendable, Equatable {
        public var addons: [String] = []
        /// Lo que contestó cada complemento (versiones con enlace; nil: no contestó a tiempo).
        public var answers: [String: Int?] = [:]
        /// Las versiones con las que se quedó (ya sin las de torrent sin Real-Debrid): llega al terminar.
        public var choices: Int?
        public var found: Int { choices ?? answers.values.reduce(0) { $0 + ($1 ?? 0) } }
        public var answered: Int { answers.count }
        mutating func apply(_ event: SearchEvent) {
            switch event {
            case .asking(let names): addons = names
            case .answered(let addon, let count): answers[addon] = count
            }
        }
    }
    public private(set) var search: SourceSearch? { didSet { changed() } }
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
    /// Sincronía de los subtítulos (s): positivo los atrasa, negativo los adelanta (como Infuse). Se recuerda por versión
    /// (`SubtitleOffsets`): al volver a esa versión de ese título, se pone sola.
    public private(set) var subtitleDelay: Double = 0 { didSet { changed() } }
    public static let subtitleStep = 0.5, subtitleMaxDelay = 30.0
    public func nudgeSubtitles(by seconds: Double) { setSubtitleDelay(subtitleDelay + seconds) }
    public func resetSubtitleDelay() { setSubtitleDelay(0) }
    /// Un ajuste exacto (lo usa «Sincronizar con una línea»): se guarda para la versión puesta.
    public func setSubtitleDelay(_ value: Double) {
        subtitleDelay = max(-Self.subtitleMaxDelay, min(Self.subtitleMaxDelay, value.rounded(toPlaces: 1)))
        restoredDelay = nil
        if let request, let id = selectedVersionID { subtitleOffsets?.remember(metaID: request.metaID, versionID: offsetKey(id), subtitleDelay) }
    }
    /// La sincronía es de un subtítulo EN un archivo: la pista «track-3» de un archivo es otra en otro, y el mismo subtítulo
    /// de internet puede ir a otro ritmo con otra copia. Antes se guardaba solo por subtítulo y se llevaba mal a otra fuente.
    func offsetKey(_ versionID: String) -> String {
        let file = source?.key ?? request?.localFile?.lastPathComponent ?? ""
        return file.isEmpty ? versionID : "\(file)|\(versionID)"
    }
    /// El ajuste que se puso solo al volver a una versión (para decir «Usamos tu ajuste de +1.5 s»).
    public private(set) var restoredDelay: Double? { didSet { changed() } }
    public var subtitleOffsets: SubtitleOffsets?
    /// La versión a la que ya se le puso su ajuste (las que pone el arranque solo, sin pasar por `apply`, también).
    private var offsetVersionID: String?
    private func restoreOffsetIfVersionChanged() {
        let id = selectedVersionID
        guard id != offsetVersionID else { return }
        offsetVersionID = id
        guard let id, let request else { return }
        let saved = subtitleOffsets?.offset(metaID: request.metaID, versionID: offsetKey(id)) ?? 0
        if saved != subtitleDelay { subtitleDelay = saved; restoredDelay = saved == 0 ? nil : saved }
    }

    /// Las versiones que ya probaste en este video (para no volver a las que no iban).
    public private(set) var triedVersionIDs: Set<String> = [] { didSet { changed() } }
    /// Elegiste otra versión: se pregunta un momento «¿Va a tiempo?».
    public private(set) var askInSync = false { didSet { changed() } }
    public func confirmInSync() { askInSync = false; restoredDelay = nil }
    /// «Probar otra»: la siguiente del mismo idioma que no hayas probado (y se vuelve a preguntar).
    public func tryAnotherVersion() async {
        guard let id = selectedVersionID, let current = allSubtitleVersions.first(where: { $0.id == id }) else { return }
        let versions = subtitleVersions(language: current.language)
        let untried = versions.first { !triedVersionIDs.contains($0.id) && $0.id != id }
        guard let next = untried ?? SubtitleVersions.next(after: id, in: versions), next.id != id else { return }
        await selectVersion(next)
    }
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
    /// Ya sonó este video (el motor llegó a reproducir): hasta entonces la pantalla enseña la carga, no el play.
    public private(set) var hasPlayed = false { didSet { if oldValue != hasPlayed { changed() } } }
    private var startupDeadline: Date?
    private var lastSnapshotAt: Date?
    private var lastSave: Date
    private var watchedUnsaved = 0.0
    private var tracksApplied = false
    /// Rearmando el mismo video en pausa al volver de segundo plano (en pausa ya cuenta como «está»).
    private var restoringInPlace = false
    /// Cambiaste de versión a mano: a cuál y a qué segundo volver si la nueva no llega a sonar (falla después de abrir, se
    /// acaba el plazo o es el aviso de Real-Debrid). Antes caía a cualquier otra fuente.
    private var switchBack: (source: Source, position: Double)?
    /// Lo más que dura el video de aviso de Real-Debrid («la estamos bajando»): uno así en un título largo no es el título.
    static let placeholderMaxSeconds: Double = 120, placeholderTitleMinSeconds: Double = 600
    /// Lo más que el reproductor espera a que se pongan el audio y los subtítulos antes de seguir atendiendo al video.
    static let trackSetupWait: Double = 1
    /// Cuántas versiones de subtítulos se han pedido: si eliges otra antes de que llegue la anterior, la anterior ya no se recuerda.
    private var subtitleTicket = 0

    /// Espera una tarea hasta `seconds`; si tarda más, se sigue (la tarea termina sola).
    static func waitBriefly(_ task: Task<Void, Never>, seconds: Double) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let once = Once()
            Task { await task.value; if once.claim() { done.resume() } }
            Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); if once.claim() { done.resume() } }
        }
    }

    /// Otro archivo: lo encontrado en internet se vuelve a buscar con su huella.
    private func forgetSubtitleSearch() {
        foundSubtitles = nil; subtitleSearchFailed = false; subtitlesOffline = false; searchTask = nil
    }
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
    /// «Audio y subtítulos» está abierto (la tarjeta de «Siguiente» no se ve y su cuenta se detiene).
    public var panelOpen = false
    private var upNextDismissed = false
    /// Modo demostración: el estado puesto a mano no lo recalcula el avance.
    private var demoPinned = false
    private var autoAdvances = 0
    private var reachedEnd = false
    private var finalReported = false
    /// Dónde seguir según Trakt cuando solo se sabe el porcentaje (sin la duración): se busca en cuanto el motor la dice.
    private var pendingResumeFraction: Double?
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
    /// La bitácora del reproductor en el registro del sistema (Consola de la Mac con el iPhone conectado, categoría «player»): qué
    /// se abrió, qué versión, cuándo sonó y por qué falló. Sin enlaces ni claves: solo ids de IMDb, el servidor y el motivo.
    static let log = Logger(subsystem: "mx.iracheta.orbital", category: "player")

    public func begin(_ request: PlayRequest) async {
        Self.log.notice("abrir \(request.kind, privacy: .public) \(request.videoID, privacy: .public) local=\(request.localFile != nil, privacy: .public)")
        subtitleDelay = 0
        ownAttempts = 0
        guard !closing, phase != .closed else { return }
        generation += 1
        let mine = generation
        if self.request?.metaID != request.metaID { localizedMeta = nil }   // otra serie: su traducción llega aparte
        self.request = request
        resetForNewVideo()
        phase = .preparing
        startConsuming()
        loadSegmentsIfNeeded()   // IntroDB solo depende del video: a la vez que las fuentes, no después
        if request.localFile == nil { let finder = finder; Task { await finder.warmAddons() } }   // los complementos, ya: no después de «dónde ibas»
        if request.localFile != nil, request.kind == "series", let next = nextEpisodeIDIgnoringLocal() { nextLocal = await localEpisode(request.metaID, next) }
        nextUp = nextEpisodeID().map { ($0, episodeText($0).0) }   // para «Siguiente» (una vez: leer los episodios cuesta)
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
        failure = nil
        triedVersionIDs = []; askInSync = false; restoredDelay = nil; offsetVersionID = nil; stopBriefSubtitles()
        failedSources = []; hasPlayed = false; startupDeadline = nil; lastSnapshotAt = nil; watchedUnsaved = 0
        scrobbleStarted = false; scrobblePlaying = false; rescrobbleAfterSeek = false
        tracksApplied = false; addedExternalSubtitle = false; knownSubtitleIDs = []; preloadedNext = false
        upNext = nil; upNextDeadline = nil; upNextDismissed = false; skipIntroTo = nil; reachedEnd = false; finalReported = false
        pendingResumeFraction = nil
        notice = nil; attempts = 0; lastSave = clock(); snapshot = EngineSnapshot(state: .loading); source = nil; sourceChoices = []; search = nil
        acceptingSnapshots = false; retrying = false; nextLocal = nil; choicesAt = .distantPast
        // Lo encontrado «En internet» y el mapa de sustos eran del video anterior.
        foundSubtitles = nil; addedSubtitleURLs = []; subtitleSearchFailed = false; subtitlesOffline = false; searchTask = nil; scares = nil
        addedTracks = [:]; pendingSubtitleURL = nil; tryingSubtitles = nil
        Task { [weak self] in await self?.loadScares() }
    }

    /// Justo antes de cargar: de aquí en adelante lo que diga el motor es del video nuevo.
    private func startLoading() {
        loadSegmentsIfNeeded()
        acceptingSnapshots = true; retrying = false; hasPlayed = false; tracksApplied = false; restoringInPlace = false; playRequest = nil
        // Otra fuente: el subtítulo externo (OpenSubtitles) se vuelve a sumar; antes se perdía al cambiar de fuente.
        addedExternalSubtitle = false; knownSubtitleIDs = []; addedTracks = [:]; pendingSubtitleURL = nil; addedSubtitleURLs = []
        scrobbleStarted = false   // otra carga (otra fuente, otro episodio): cuando suene, Trakt recibe el avance donde va
        startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
    }

    /// Elige fuente y la carga. `startAt` solo se pasa al reintentar con otra fuente (se sigue en el mismo punto).
    private func prepare(startAt: Double?, generation mine: Int) async {
        guard let request else { return }
        // Dónde ibas se pregunta ya, a la vez que las fuentes (antes esperaba a que llegaran).
        let watch = watch
        // Lo más reciente entre Stremio y Trakt (lo que dejaste en la TV u otro dispositivo); sin Trakt, lo de Stremio.
        let resume: Task<ResumePoint, Never>? = startAt == nil && !request.fromStart && request.startPosition == nil
            ? Task { await watch.resumePoint(metaID: request.metaID, videoID: request.videoID, kind: request.kind) } : nil
        if let file = request.localFile {
            var start = startAt ?? 0
            if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await resumeStart(resume) } }
            guard mine == generation, !closing else { return }
            startLoading()
            do { try await loadVideo(file, at: start) } catch { fail("No pude abrir el archivo descargado.", .localFile) }
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
                if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await resumeStart(resume) } }
                guard mine == generation, !closing, let url = own.playbackURL else { failedSources.insert(own.index); continue }
                startLoading()
                do { try await loadVideo(url, at: start); return }
                catch { guard mine == generation else { return }; failedSources.insert(own.index); notice = .triedAnotherSource(attempt: 1); acceptingSnapshots = false; continue }
            }
            do {
                if search == nil { search = SourceSearch() }
                let events = await finder.events(kind: request.kind, videoID: request.videoID)
                let listening = Task { [weak self] in
                    for await event in events { guard let self, self.generation == mine else { return }; self.search?.apply(event) }
                }
                defer { listening.cancel() }
                sourceChoices = try await finder.find(kind: request.kind, videoID: request.videoID, prefs: langs.prefs)
                Self.log.notice("versiones encontradas: \(self.sourceChoices.count, privacy: .public)")
                if mine == generation { search?.choices = sourceChoices.count }
                choicesAt = clock()
                guard mine == generation, !closing else { return }
                if let chosen = request.sourceIndex, failedSources.isEmpty, let pick = sourceChoices.first(where: { $0.index == chosen }) { found = pick }
                // «Continuar»: la fuente con la que lo dejaste, si sigue ahí (como en la TV).
                else if failedSources.isEmpty, !request.fromStart, let key = titlePrefs.resumeChoice(metaID: request.metaID, videoID: request.videoID)?.source,
                        let pick = sourceChoices.first(where: { $0.key == key }) { found = pick }
                // Otro episodio: la misma familia de versión con que dejaste la serie (no solo el mismo idioma).
                else {
                    let family = request.binge ?? (request.fromStart ? nil : titlePrefs.lastChoice(metaID: request.metaID)?.binge)
                    found = try await finder.best(kind: request.kind, videoID: request.videoID, prefs: langs.prefs, binge: family, skip: failedSources)
                }
            } catch { guard mine == generation else { return }; return fail("Sin conexión: no pude buscar dónde verlo.", .network) }
            guard mine == generation, !closing else { return }
            guard let found else { return failedSources.isEmpty ? fail("No hay versiones en Real-Debrid para este título.", .noSources) : fail("Ninguna versión funcionó.", .noneWorked) }
            source = found
            var start = startAt ?? 0
            if startAt == nil && !request.fromStart { if let exact = request.startPosition { start = exact } else { start = await resumeStart(resume) } }
            guard mine == generation, !closing else { return }
            guard let url = found.playbackURL else { failedSources.insert(found.index); continue }
            startLoading()
            do { try await loadVideo(url, at: start); return }
            catch {
                guard mine == generation else { return }
                failedSources.insert(found.index)
                attempts = failedSources.count
                if failedSources.count > PlaybackRules.maxSourceRetries { return fail("Ninguna versión funcionó.", .noneWorked) }
                notice = .triedAnotherSource(attempt: failedSources.count)
                acceptingSnapshots = false
            }
        }
    }

    /// El segundo donde empezar. Si Trakt solo dio un porcentaje (sin duración conocida) se empieza en 0 y se busca ese punto
    /// cuando el motor diga cuánto dura (`seekToPendingResume`).
    private func resumeStart(_ resume: Task<ResumePoint, Never>?) async -> Double {
        guard let point = await resume?.value else { return 0 }
        pendingResumeFraction = point.fraction
        return point.seconds
    }

    /// Ya se sabe la duración: se va al punto que dio Trakt (una vez). El aviso de «Viendo» a Trakt sale ya con ese avance.
    private func seekToPendingResume(_ s: EngineSnapshot) async {
        guard let fraction = pendingResumeFraction, s.duration > 0 else { return }
        pendingResumeFraction = nil
        let target = fraction * s.duration
        guard target > 5, abs(target - s.position) > 5 else { return }
        await engine.seek(to: target)
        snapshot.position = target
    }

    /// Los mensajes de los motores pueden traer la dirección del video (con tu clave): nunca llegan a la pantalla.
    private func fail(_ message: String, _ kind: Failure) {
        Self.log.error("falló \(String(describing: kind), privacy: .public): \(stripURLs(message), privacy: .public)")
        failure = kind
        phase = .failed(stripURLs(message)); startupDeadline = nil; reconnecting = false; foregroundCheck = nil
        if source != nil { Task { await engine.pause() } }   // con un video a medio cargar: que no siga una ruedita detrás
    }

    /// Intentar otra vez desde el principio (otra búsqueda de fuentes), donde ibas.
    public func retry() async {
        guard let request else { return }
        failure = nil
        await begin(request)
    }

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
        if s.state == .playing && !hasPlayed { Self.log.notice("suena en \(Int(s.position), privacy: .public) s"); hasPlayed = true; startupDeadline = nil; phase = .playing; switchBack = nil }
        if let request = playRequest, s.state == .playing, s.position > request.position + 0.3 { playRequest = nil }   // ya avanza
        // Rearmando el mismo video en pausa (al volver de segundo plano): en pausa también es «ya está». Antes se esperaba a que
        // sonara, se quedaba en «preparando» sin botones y a los 45 s cambiaba de fuente y arrancaba solo.
        if restoringInPlace, !hasPlayed, s.state == .paused, s.duration > 0 {
            hasPlayed = true; startupDeadline = nil; phase = .playing; restoringInPlace = false
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
        if foregroundCheck != nil { await checkForegroundStall(now: now) }
        if playRequest != nil { await checkPlayRequest(now: now) }
        if foregroundPending, acceptingSnapshots, !retrying { foregroundPending = false; await appDidBecomeActive() }
        if let deadline = startupDeadline, now >= deadline, !hasPlayed, phase == .preparing, !retrying {
            if goBackAfterSwitch() { return }
            return await retryWithAnotherSource()?.value ?? ()
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
                if now >= deadline { await advance(auto: true)?.value }
            }
        }
    }

    /// Cambia a otra fuente en el mismo punto. Marca el cambio de forma síncrona (lo que el motor diga ahora se ignora) y carga aparte.
    @discardableResult
    private func retryWithAnotherSource() -> Task<Void, Never>? {
        guard !retrying, !closing else { return transition }
        guard request?.localFile == nil else { fail("No pude abrir el archivo descargado.", .localFile); return nil }
        retrying = true; acceptingSnapshots = false; startupDeadline = nil
        Self.log.notice("otra versión (ya fallaron \(self.failedSources.count + 1, privacy: .public))")
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

    private func applyTracksOnce(_ s: EngineSnapshot) async {
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
    private func rememberChoice() {
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
    private var searchTask: Task<Void, Never>?

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

    /// No se encontró nada en la última búsqueda (o no había red).
    public private(set) var subtitleSearchFailed = false { didSet { changed() } }
    /// La última búsqueda no llegó a internet (modo avión, sin señal): solo hay los del video y los guardados con la descarga.
    public private(set) var subtitlesOffline = false { didSet { if oldValue != subtitlesOffline { changed() } } }

    /// Hay subtítulos de ese idioma para poner ya (del video, guardados con la descarga o encontrados en internet).
    public func hasSubtitles(language: String) -> Bool { !subtitleVersions(language: language).isEmpty }
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
        if let track = new.first {
            knownSubtitleIDs.insert(track.id)
            // El que se sumó de internet ya es esta pista: en la lista sale como «de internet», no «del video».
            if let url = pendingSubtitleURL { addedTracks[url] = track.id; pendingSubtitleURL = nil }
            await engine.selectSubtitle(track.id)
        }
    }

    // MARK: versiones de subtítulos («Subtítulos» del panel)
    /// Las elecciones de «Este va bien» por serie (las pone quien arma el reproductor).
    public var subtitlePicks: SubtitlePicks?
    /// Los subtítulos de internet ya sumados al video → su pista en el motor.
    public private(set) var addedTracks: [URL: Int] = [:] { didSet { changed() } }
    private var pendingSubtitleURL: URL? { didSet { changed() } }
    /// Se está bajando un subtítulo de internet para ponerlo (el botón de subtítulos enseña que carga).
    public var loadingSubtitle: Bool { pendingSubtitleURL != nil }
    /// La tira para probar versiones sobre el video (el idioma que se está probando); nil: no se ve.
    public private(set) var tryingSubtitles: String? { didSet { changed() } }

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

    private func apply(_ version: SubtitleVersion) async {
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

    /// La versión que tenías antes de apagarlos (para prenderlos otra vez igual).
    private var versionBeforeOff: SubtitleVersion?

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
    private var allSubtitleVersions: [SubtitleVersion] { subtitleLanguages.flatMap { subtitleVersions(language: $0.code) } }

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
    private func applyRememberedPick(_ s: EngineSnapshot) async -> Bool {
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

    // MARK: controles
    private func userTouched() { autoAdvances = 0 }

    public func setRate(_ value: Float) async { rate = value; await engine.setRate(value) }

    /// Abre un video y le pone la velocidad elegida (el motor empieza cada video en 1).
    private func loadVideo(_ url: URL, at start: Double) async throws {
        Self.log.notice("cargar desde \(url.host ?? "archivo", privacy: .public) en \(Int(start), privacy: .public) s")
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

    /// Pausa si suena o si va a sonar (cargando o pediste play y aún no avanza): antes, en búfer el botón llamaba a «play» y la
    /// pausa no hacía caso.
    public var wantsToPlay: Bool { snapshot.state == .playing || snapshot.state == .buffering || playRequest != nil }
    public func togglePlay() async {
        userTouched()
        if wantsToPlay { playRequest = nil; await engine.pause() } else { requestPlayback(); await engine.play() }
    }
    public func play() async { userTouched(); requestPlayback(); await engine.play() }
    public func pause() async { userTouched(); playRequest = nil; await engine.pause() }

    /// Pediste que sonara y todavía no avanza (sobre todo al volver de segundo plano, con el video soltado por el motor): la
    /// pantalla enseña la carga en vez del play, y si en `foregroundStallSeconds` no avanza, el video se pide otra vez ahí mismo.
    public var awaitingPlayback: Bool { playRequest != nil }
    private var playRequest: (at: Date, position: Double)? { didSet { if (oldValue == nil) != (playRequest == nil) { changed() } } }
    private func requestPlayback() {
        guard hasPlayed, phase == .playing, !closing else { return }
        playRequest = (clock(), snapshot.position)
    }
    private func checkPlayRequest(now: Date) async {
        guard let request = playRequest else { return }
        if snapshot.state == .playing, snapshot.position > request.position + 0.3 { playRequest = nil; return }   // ya suena
        guard now.timeIntervalSince(request.at) >= Self.foregroundStallSeconds, !reconnecting, !retrying else { return }
        playRequest = nil
        await reloadCurrentSource(at: max(request.position, snapshot.position), resume: true)
    }
    public func seek(to seconds: Double) async {
        userTouched()
        let target = max(0, min(seconds, snapshot.duration > 0 ? snapshot.duration : seconds))
        if hasPlayed, abs(target - snapshot.position) >= PlaybackRules.rescrobbleJump { rescrobbleAfterSeek = true }
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
    private var scrubFinishing = false
    private var scrubTarget: Double?
    private var scrubTask: Task<Void, Never>?

    public func skip(_ delta: Double) async {
        await seek(to: snapshot.position + delta)
        if delta < 0 { await showSubtitlesBriefly() }
    }

    /// Regresaste con los subtítulos apagados: se ven unos segundos («¿qué dijo?», como en Apple TV) y se vuelven a apagar.
    private var briefSubtitles: Task<Void, Never>?
    public static let briefSubtitlesSeconds = 8.0
    private func showSubtitlesBriefly() async {
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
    private func stopBriefSubtitles() { briefSubtitles?.cancel(); briefSubtitles = nil }

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
    @discardableResult
    private func goBackAfterSwitch() -> Bool {
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
    private func isPlaceholder(_ s: EngineSnapshot) -> Bool {
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

    // MARK: intro y siguiente episodio
    /// Las marcas de IntroDB del video que va a sonar (una vez por video; otra fuente del mismo no las vuelve a pedir).
    /// Esperas entre reintentos de las marcas de IntroDB cuando no responde.
    /// Antes eran dos (2 y 5 s) y luego se rendía por toda la reproducción: con la red floja al empezar, el episodio se quedaba
    /// sin botón aunque la intro llegara minutos después (las de Game of Thrones empiezan pasados los 7 min).
    var segmentRetryDelays: [Double] = [2, 5, 15, 30, 60, 120]
    private func loadSegmentsIfNeeded() {
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
            if self.hasPlayed { self.updateSkipIntro(self.snapshot) }
        }
    }

    /// «Saltar intro» / «Saltar resumen»: primero los capítulos del archivo; si no los trae, las marcas de la comunidad.
    private func updateSkipIntro(_ s: EngineSnapshot) {
        if demoPinned { return }
        // Cargando o rearmando al volver de segundo plano, la posición pasa un momento por 0 (o por el inicio): ahí no
        // aplica (salía «Saltar intro» a media película al regresar a la app).
        if s.state == .loading || reconnecting || backgrounded { skipIntroTo = nil; return }
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

    /// La ficha traducida a tu idioma (la pide la pantalla con el traductor de la app): los nombres de los episodios en
    /// «Siguiente episodio» salen igual que en la ficha de la serie, no en inglés. Sin ella, la original.
    public private(set) var localizedMeta: JSON?
    public func useLocalizedMeta(_ meta: JSON, for videoID: String) {
        guard request?.videoID == videoID else { return }
        localizedMeta = meta
    }

    private func episodeText(_ videoID: String) -> (String, String) {
        guard let meta = localizedMeta ?? request?.meta else { return ("", "") }
        for season in CinemetaParsing.seasons(meta) {
            if let ep = season.episodes.first(where: { $0.id == videoID }) { return (episodeLabel(season.season, ep.episode), ep.title) }
        }
        return ("", "")
    }

    private func episodeThumbnail(_ videoID: String) -> String? {
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

    /// El siguiente episodio y su «T5 E3», calculados al abrir (para el botón «Siguiente» de los controles).
    public private(set) var nextUp: (videoID: String, label: String)? { didSet { changed() } }

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
    private var endIsReal: Bool { snapshot.duration <= 0 || snapshot.position >= snapshot.duration - Self.cutMargin }

    private func finishAndAdvance() async {
        if nextEpisodeID() != nil && !upNextDismissed && !stillWatchingPrompt {
            if upNext == nil, let next = nextEpisodeID() { let (l, t) = episodeText(next); upNext = UpNext(videoID: next, label: l, title: t, secondsLeft: 0) }
            advance(auto: true)
        } else {
            if !finalReported { await report(.stopped(finished: endIsReal)) }
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
        let finished = (reachedEnd && endIsReal) || StremioLibrary.finished(position: snapshot.position, duration: snapshot.duration, kind: request?.kind)
        // Primero se calla (la pantalla ya se fue); guardar en la red puede tardar.
        await engine.pause()
        if !finalReported { await report(.stopped(finished: finished)) }
        phase = .closed
        await engine.stop()
    }

    /// Al pasar a segundo plano: se guarda ya (iOS puede suspender la app).
    public func appDidEnterBackground() async { if hasPlayed, phase != .closed, !closing { await report(.tick) } }

    // MARK: volver de segundo plano
    /// Volviendo de segundo plano: «Reconectando…» en vez de una pantalla negra, hasta que el video vuelve a avanzar.
    public private(set) var reconnecting = false { didSet { changed() } }
    private var backgrounded = false
    private var foregroundPending = false
    private var resumeOnForeground = false
    /// Tras volver: si iba sonando y en este plazo no avanzó, el video se pide otra vez en el mismo punto.
    private var foregroundCheck: (deadline: Date, position: Double)?
    static let foregroundStallSeconds: TimeInterval = 8

    /// La app pasó a segundo plano de verdad (no solo el Centro de control): se recuerda si iba sonando.
    public func appDidEnterBackgroundFully() {
        guard hasPlayed, phase == .playing, !closing else { return }
        backgrounded = true
        resumeOnForeground = snapshot.state == .playing || snapshot.state == .buffering
    }

    /// De vuelta al frente: el motor rearma su video (lo soltó en segundo plano); si no puede, o si el video no vuelve a
    /// avanzar, se vuelve a pedir la misma fuente en el mismo punto (con enlace nuevo si el de Real-Debrid caducó).
    public func appDidBecomeActive() async {
        guard backgrounded else { return }
        // Volviste justo mientras se cambiaba de versión: todavía no hay qué rearmar. Se queda pendiente y se revisa en cuanto la
        // versión nueva esté lista (`tick`); antes se olvidaba y la pantalla quedaba negra con el play sin responder.
        if !closing, !acceptingSnapshots || retrying { foregroundPending = true; return }
        backgrounded = false
        guard hasPlayed, phase == .playing, !closing else { return }
        let resume = resumeOnForeground
        let position = snapshot.position
        let mine = generation
        // Sin aviso al volver: casi siempre el video sigue donde estaba. Solo si de verdad hay que pedirlo otra vez
        // (el motor no pudo rearmarlo, o no avanzó en el plazo) se dice que está cargando.
        let restored = await engine.restoreAfterBackground(resume: resume)
        guard mine == generation, !closing else { return }
        if !restored { return await reloadCurrentSource(at: position, resume: resume) }
        if resume { foregroundCheck = (clock().addingTimeInterval(Self.foregroundStallSeconds), position) }
    }

    /// El plazo tras volver: el video tenía que avanzar y no lo hizo (negro o congelado) → se pide de nuevo.
    private func checkForegroundStall(now: Date) async {
        guard let check = foregroundCheck else { return }
        if snapshot.state == .paused { foregroundCheck = nil; reconnecting = false; return }   // lo pausaste tú
        if snapshot.state == .playing, snapshot.position > check.position + 0.5 { foregroundCheck = nil; reconnecting = false; return }
        guard now >= check.deadline else { return }
        foregroundCheck = nil
        await reloadCurrentSource(at: max(check.position, snapshot.position), resume: true)
    }

    /// Vuelve a abrir la fuente que sonaba en el mismo punto: la descarga, tu copia (enlace nuevo) o la de Real-Debrid
    /// (con la lista renovada si ya caducó). Si tampoco abre, se prueba otra fuente como en cualquier corte.
    private func reloadCurrentSource(at position: Double, resume: Bool) async {
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

extension Double {
    /// Redondeo a décimas (los pasos de la sincronía no acumulan 0.30000000000000004).
    func rounded(toPlaces places: Int) -> Double { let f = pow(10, Double(places)); return (self * f).rounded() / f }
}
