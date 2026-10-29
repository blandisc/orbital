import Foundation
import OrbitalCore
import os

/// Orquesta una reproducción: elige la fuente, reanuda donde ibas, pone el audio y los subtítulos que quieres,
/// guarda el avance (cada minuto, al pausar y al cerrar), ofrece «Siguiente episodio» y cambia de fuente si una falla.
/// No conoce SwiftUI ni el motor concreto: `PlayerEngine` y los relojes se inyectan, así se prueba entero.
///
/// Concurrencia: todo ocurre en el hilo principal, pero hay `await` en medio (red); por eso cada cambio de video lleva un número
/// (`generation`) y se revisa tras cada espera, y las instantáneas del motor se ignoran mientras se carga otra fuente.
@MainActor
public final class PlayerModel: ObservableModel {
    // Lo de pistas y versiones de subtítulos vive en `PlayerModel+Tracks.swift` y `PlayerModel+Subtitles.swift`: lo que esas
    // extensiones tocan es interno al módulo (no `private`), no público.
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

    public internal(set) var phase: Phase = .idle { didSet { changed() } }
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
    public internal(set) var snapshot = EngineSnapshot() { didSet { changed() } }
    /// Un episodio descargado que viste hasta el final y del que el reproductor pasó solo al siguiente (para «Borrar al
    /// terminar de verlo»: el último lo atiende quien cierra el reproductor).
    public var onFinishedLocal: (@MainActor (PlayRequest) -> Void)?
    public internal(set) var request: PlayRequest? { didSet { changed() } }
    public internal(set) var source: Source? { didSet { changed() } }
    public internal(set) var sourceChoices: [Source] = [] { didSet { changed() } }
    public internal(set) var upNext: UpNext? { didSet { changed() } }
    public internal(set) var skipIntroTo: Double? { didSet { changed() } }
    /// Qué se salta con el botón: la intro o el resumen («Anteriormente en…»).
    public enum SkipKind: Sendable, Equatable { case intro, recap }
    public internal(set) var skipKind: SkipKind = .intro { didSet { changed() } }
    /// Las marcas de la comunidad (IntroDB) del video que suena: intro, resumen y créditos.
    public internal(set) var segments: SkipSegments? { didSet { changed() } }
    var segmentsFor: String?
    public internal(set) var stillWatchingPrompt = false { didSet { changed() } }
    public internal(set) var notice: PlayerNotice? { didSet { changed() } }
    /// Sincronía de los subtítulos (s): positivo los atrasa, negativo los adelanta (como Infuse). Se recuerda por versión
    /// (`SubtitleOffsets`): al volver a esa versión de ese título, se pone sola.
    public internal(set) var subtitleDelay: Double = 0 { didSet { changed() } }
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
    public internal(set) var restoredDelay: Double? { didSet { changed() } }
    public var subtitleOffsets: SubtitleOffsets?
    /// La versión a la que ya se le puso su ajuste (las que pone el arranque solo, sin pasar por `apply`, también).
    var offsetVersionID: String?
    private func restoreOffsetIfVersionChanged() {
        let id = selectedVersionID
        guard id != offsetVersionID else { return }
        offsetVersionID = id
        guard let id, let request else { return }
        let saved = subtitleOffsets?.offset(metaID: request.metaID, versionID: offsetKey(id)) ?? 0
        if saved != subtitleDelay { subtitleDelay = saved; restoredDelay = saved == 0 ? nil : saved }
    }

    /// Las versiones que ya probaste en este video (para no volver a las que no iban).
    public internal(set) var triedVersionIDs: Set<String> = [] { didSet { changed() } }
    /// Elegiste otra versión: se pregunta un momento «¿Va a tiempo?».
    public internal(set) var askInSync = false { didSet { changed() } }
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
    public internal(set) var rate: Float = 1 { didSet { changed() } }
    public static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    public private(set) var attempts = 0 { didSet { changed() } }

    let engine: PlayerEngine
    let finder: StreamFinder
    private let watch: WatchService
    let titlePrefs: TitlePreferences
    let settings: SettingsStore
    let clock: @Sendable () -> Date
    let onCellular: @Sendable () -> Bool
    let episodeLabel: @Sendable (Int, Int) -> String
    let localEpisode: @Sendable (_ metaID: String, _ videoID: String) async -> LocalEpisode?

    private var consuming: Task<Void, Never>?
    var transition: Task<Void, Never>?
    var failedSources = Set<Int>()
    /// Ya sonó este video (el motor llegó a reproducir): hasta entonces la pantalla enseña la carga, no el play.
    public internal(set) var hasPlayed = false { didSet { if oldValue != hasPlayed { changed() } } }
    /// Ya corre de verdad: desde que sonó avanzó `startupSettleSeconds` (o lo pausaste). El motor dice «suena» con casi nada en
    /// el búfer y enseguida se detiene a llenarlo, o recarga todo para cambiar la pista de audio: hasta que corre, la pantalla sigue
    /// enseñando la carga. Antes el botón hacía carga → pausa → carga → pausa en cada video.
    public internal(set) var playbackSettled = false { didSet { if oldValue != playbackSettled { changed() } } }
    static let startupSettleSeconds: Double = 2
    var startupPosition: Double = 0
    private var startupDeadline: Date?
    /// El motor ya abrió el archivo de la carga en curso (desde ahí, lo que diga es de este video).
    var engineOpened = true
    private var lastSnapshotAt: Date?
    private var lastSave: Date
    private var watchedUnsaved = 0.0
    var tracksApplied = false
    /// Rearmando el mismo video en pausa al volver de segundo plano (en pausa ya cuenta como «está»).
    private var restoringInPlace = false
    /// Cambiaste de versión a mano: a cuál y a qué segundo volver si la nueva no llega a sonar (falla después de abrir, se
    /// acaba el plazo o es el aviso de Real-Debrid). Antes caía a cualquier otra fuente.
    var switchBack: (source: Source, position: Double)?
    /// Lo más que dura el video de aviso de Real-Debrid («la estamos bajando»): uno así en un título largo no es el título.
    static let placeholderMaxSeconds: Double = 120, placeholderTitleMinSeconds: Double = 600
    /// Lo más que el reproductor espera a que se pongan el audio y los subtítulos antes de seguir atendiendo al video.
    static let trackSetupWait: Double = 1
    /// Cuántas versiones de subtítulos se han pedido: si eliges otra antes de que llegue la anterior, la anterior ya no se recuerda.
    var subtitleTicket = 0

    /// Espera una tarea hasta `seconds`; si tarda más, se sigue (la tarea termina sola).
    static func waitBriefly(_ task: Task<Void, Never>, seconds: Double) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let once = Once()
            Task { await task.value; if once.claim() { done.resume() } }
            Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); if once.claim() { done.resume() } }
        }
    }

    /// Otro archivo: lo encontrado en internet se vuelve a buscar con su huella.
    func forgetSubtitleSearch() {
        foundSubtitles = nil; subtitleSearchFailed = false; subtitlesOffline = false; searchTask = nil
    }
    var addedExternalSubtitle = false
    var rescrobbleAfterSeek = false
    /// Trakt ya sabe que empezó este video (el `start` sale cuando el motor suena Y se sabe la duración).
    private var scrobbleStarted = false
    /// Lo último que Trakt sabe: ¿está sonando (`start`) o en pausa (`pause`)?
    private var scrobblePlaying = false
    var knownSubtitleIDs = Set<Int>()
    var preloadedNext = false
    var upNextDeadline: Date?
    private var lastTick: Date?
    /// «Audio y subtítulos» está abierto (la tarjeta de «Siguiente» no se ve y su cuenta se detiene).
    public var panelOpen = false
    var upNextDismissed = false
    /// Modo demostración: el estado puesto a mano no lo recalcula el avance.
    var demoPinned = false
    var autoAdvances = 0
    private var reachedEnd = false
    var finalReported = false
    /// Dónde seguir según Trakt cuando solo se sabe el porcentaje (sin la duración): se busca en cuanto el motor la dice.
    private var pendingResumeFraction: Double?
    var generation = 0
    var acceptingSnapshots = false     // false mientras se elige y se carga una fuente (lo que el motor diga entonces es del video anterior)
    var retrying = false
    var advancing = false
    var closing = false
    var choicesAt = Date.distantPast
    var nextLocal: LocalEpisode?
    let skipSegments: @Sendable (String) async -> SkipSegments?
    let scareMap: @Sendable (String, String) async -> [JumpScare]?
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
    nonisolated static let log = Logger(subsystem: "mx.iracheta.orbital", category: "player")

    /// La misma bitácora en un archivo de la app (`player-log.txt`, las últimas `logKeep` líneas), para leerla desde la Mac con
    /// `devicectl` cuando algo no carga en el iPhone (el registro del sistema pide la clave de administrador).
    nonisolated static let logFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Orbital", isDirectory: true).appendingPathComponent("player-log.txt")
    nonisolated static let logKeep = 400
    nonisolated private static let logLock = NSLock()
    nonisolated public static func note(_ text: String) {
        log.notice("\(text, privacy: .public)")
        guard NSClassFromString("XCTestCase") == nil else { return }   // las pruebas no escriben en la Mac
        let line = ISO8601DateFormatter().string(from: Date()) + " " + text
        logLock.withLock {
            let old = (try? String(contentsOf: logFile, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            let kept = (old + [line]).suffix(logKeep).joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? kept.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    public func begin(_ request: PlayRequest) async {
        Self.note("abrir \(request.kind) \(request.videoID) local=\(request.localFile != nil)")
        subtitleDelay = 0
        ownAttempts = 0
        backgroundPosition = 0
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
        failedSources = []; hasPlayed = false; playbackSettled = false; startupDeadline = nil; lastSnapshotAt = nil; watchedUnsaved = 0
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
    func startLoading() {
        loadSegmentsIfNeeded()
        acceptingSnapshots = true; retrying = false; hasPlayed = false; playbackSettled = false; tracksApplied = false; restoringInPlace = false; playRequest = nil
        engineOpened = false
        // Toda carga tiene su plazo (abrir, volver a pedirla al regresar a la app, cambiar de versión): antes solo la primera; si el
        // motor se quedaba abriendo el archivo al volver a la app, la pantalla cargaba para siempre (3 min en el iPhone el 29 oct).
        startupDeadline = clock().addingTimeInterval(PlaybackRules.startupTimeout)
        // Otra fuente: el subtítulo externo (OpenSubtitles) se vuelve a sumar; antes se perdía al cambiar de fuente.
        addedExternalSubtitle = false; knownSubtitleIDs = []; addedTracks = [:]; pendingSubtitleURL = nil; addedSubtitleURLs = []
        scrobbleStarted = false   // otra carga (otra fuente, otro episodio): cuando suene, Trakt recibe el avance donde va
    }

    /// Elige fuente y la carga. `startAt` solo se pasa al reintentar con otra fuente (se sigue en el mismo punto).
    func prepare(startAt: Double?, generation mine: Int) async {
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
                Self.note("versiones encontradas: \(sourceChoices.count)")
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
                Self.note("no abrió en \(Int(clock().timeIntervalSince(loadStartedAt))) s (\(String(describing: error).prefix(80))): otra versión")
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
        if !playbackSettled { startupPosition = target }   // los 2 s de arranque se cuentan desde donde va a seguir
        await engine.seek(to: target)
        snapshot.position = target
    }

    /// Los mensajes de los motores pueden traer la dirección del video (con tu clave): nunca llegan a la pantalla.
    func fail(_ message: String, _ kind: Failure) {
        Self.note("falló \(String(describing: kind)): \(stripURLs(message))")
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
        // Hasta que el motor abre el archivo nuevo, lo que diga es del video anterior (avisos que se quedaron formados): antes un
        // «suena» viejo daba por arrancada una versión que no había abierto, se quitaba su plazo y cargaba para siempre.
        if !engineOpened, raw.state != .loading, raw.state != .idle { return }
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
        if !hasPlayed, acceptingSnapshots, "\(s.state)" != lastLoggedState {   // antes de sonar: cada cambio del motor, con su tiempo
            lastLoggedState = "\(s.state)"
            Self.note(String(format: "motor: %@ (%.1f s)", lastLoggedState, clock().timeIntervalSince(loadStartedAt)))
        }
        if s.state == .playing && !hasPlayed { Self.note(String(format: "suena en %d s (%.1f s desde que empezó a cargar)", Int(s.position), clock().timeIntervalSince(loadStartedAt))); hasPlayed = true; startupPosition = s.position; startupDeadline = nil; phase = .playing; switchBack = nil }
        if let request = playRequest, s.state == .playing, s.position > request.position + 0.3 { playRequest = nil }   // ya avanza
        // Rearmando el mismo video en pausa (al volver de segundo plano): en pausa también es «ya está». Antes se esperaba a que
        // sonara, se quedaba en «preparando» sin botones y a los 45 s cambiaba de fuente y arrancaba solo.
        if restoringInPlace, !hasPlayed, s.state == .paused, s.duration > 0 {
            hasPlayed = true; startupDeadline = nil; phase = .playing; restoringInPlace = false
        }
        if hasPlayed, !playbackSettled, s.state == .paused || s.state == .ended || (s.state == .playing && s.position >= startupPosition + Self.startupSettleSeconds) {
            playbackSettled = true
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
        // El reloj nunca se queda esperando una carga: si el motor se colgaba abriendo el archivo, `tick` no volvía, nadie revisaba
        // el plazo y la pantalla cargaba para siempre (44 min en el iPhone el 29 oct). Lo largo corre aparte (`transition`).
        if foregroundCheck != nil { checkForegroundStall(now: now) }
        if playRequest != nil { checkPlayRequest(now: now) }
        checkBufferingStall(now: now)
        if foregroundPending, acceptingSnapshots, !retrying {
            foregroundPending = false
            transition = Task { [weak self] in await self?.appDidBecomeActive() }
        }
        if let deadline = startupDeadline, now >= deadline, !hasPlayed, phase == .preparing, !retrying {
            Self.note("no arrancó en \(Int(PlaybackRules.startupTimeout)) s")
            if goBackAfterSwitch() { return }
            _ = retryWithAnotherSource()   // corre aparte: el reloj sigue revisando
            return
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
                // Sin esperar: si el siguiente episodio se colgaba al abrir, el reloj se quedaba ahí y nadie revisaba su plazo.
                if now >= deadline { _ = advance(auto: true) }
            }
        }
    }

    /// Cambia a otra fuente en el mismo punto. Marca el cambio de forma síncrona (lo que el motor diga ahora se ignora) y carga aparte.
    @discardableResult
    func retryWithAnotherSource() -> Task<Void, Never>? {
        guard !retrying, !closing else { return transition }
        guard request?.localFile == nil else { fail("No pude abrir el archivo descargado.", .localFile); return nil }
        retrying = true; acceptingSnapshots = false; startupDeadline = nil
        Self.note("otra versión (ya fallaron \(failedSources.count + 1))")
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
    func report(_ phase: PlaybackPhase) async {
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

    /// «Buscar en internet» (Subtítulos del reproductor): todo lo que hay en OpenSubtitles y tus complementos, por idioma.
    public internal(set) var foundSubtitles: [SubtitleOption]? { didSet { changed() } }
    /// Los sustos de la película que suena (Where's The Jump), marcados en la barra; nil: no hay mapa.
    public internal(set) var scares: [JumpScare]? { didSet { changed() } }

    public internal(set) var searchingSubtitles = false { didSet { changed() } }

    var searchTask: Task<Void, Never>?

    /// No se encontró nada en la última búsqueda (o no había red).
    public internal(set) var subtitleSearchFailed = false { didSet { changed() } }
    /// La última búsqueda no llegó a internet (modo avión, sin señal): solo hay los del video y los guardados con la descarga.
    public internal(set) var subtitlesOffline = false { didSet { if oldValue != subtitlesOffline { changed() } } }

    /// Los que ya se sumaron (no se suma dos veces el mismo).
    public internal(set) var addedSubtitleURLs: Set<URL> = [] { didSet { changed() } }

    // MARK: versiones de subtítulos («Subtítulos» del panel)
    /// Las elecciones de «Este va bien» por serie (las pone quien arma el reproductor).
    public var subtitlePicks: SubtitlePicks?
    /// Los subtítulos de internet ya sumados al video → su pista en el motor.
    public internal(set) var addedTracks: [URL: Int] = [:] { didSet { changed() } }
    var pendingSubtitleURL: URL? { didSet { changed() } }
    /// La tira para probar versiones sobre el video (el idioma que se está probando); nil: no se ve.
    public internal(set) var tryingSubtitles: String? { didSet { changed() } }

    /// La versión que tenías antes de apagarlos (para prenderlos otra vez igual).
    var versionBeforeOff: SubtitleVersion?

    // MARK: controles

    var playRequest: (at: Date, position: Double)? { didSet { if (oldValue == nil) != (playRequest == nil) { changed() } } }
    var scrubFinishing = false
    var scrubTarget: Double?
    var scrubTask: Task<Void, Never>?

    /// Regresaste con los subtítulos apagados: se ven unos segundos («¿qué dijo?», como en Apple TV) y se vuelven a apagar.
    var briefSubtitles: Task<Void, Never>?

    // MARK: intro y siguiente episodio
    /// Las marcas de IntroDB del video que va a sonar (una vez por video; otra fuente del mismo no las vuelve a pedir).
    /// Esperas entre reintentos de las marcas de IntroDB cuando no responde.
    /// Antes eran dos (2 y 5 s) y luego se rendía por toda la reproducción: con la red floja al empezar, el episodio se quedaba
    /// sin botón aunque la intro llegara minutos después (las de Game of Thrones empiezan pasados los 7 min).
    var segmentRetryDelays: [Double] = [2, 5, 15, 30, 60, 120]

    /// La ficha traducida a tu idioma (la pide la pantalla con el traductor de la app): los nombres de los episodios en
    /// «Siguiente episodio» salen igual que en la ficha de la serie, no en inglés. Sin ella, la original.
    public internal(set) var localizedMeta: JSON?

    /// El siguiente episodio y su «T5 E3», calculados al abrir (para el botón «Siguiente» de los controles).
    public private(set) var nextUp: (videoID: String, label: String)? { didSet { changed() } }

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
    public internal(set) var reconnecting = false { didSet { changed() } }
    var backgrounded = false
    private var foregroundPending = false
    private var backgroundPosition = 0.0
    var loadStartedAt = Date.distantPast
    var lastLoggedState = ""
    private var resumeOnForeground = false
    /// Tras volver: si iba sonando y en este plazo no avanzó, el video se pide otra vez en el mismo punto.
    private var foregroundCheck: (deadline: Date, position: Double)?
    static let foregroundStallSeconds: TimeInterval = 8
    /// Ya sonaba y se detuvo a esperar datos (Real-Debrid o la red se atoraron): pasado este tiempo se pide otra vez en el mismo
    /// punto. Antes se quedaba cargando para siempre; si la nueva petición tampoco arranca, su plazo prueba otra versión.
    static let bufferingStallSeconds: TimeInterval = 20
    private var bufferingSince: Date?
    private func checkBufferingStall(now: Date) {
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
        let restored = await engine.restoreAfterBackground(resume: resume)
        guard mine == generation, !closing else { return }
        if !restored { foregroundCheck = nil; return await reloadCurrentSource(at: position, resume: resume) }
    }

    /// El plazo tras volver: el video tenía que avanzar y no lo hizo (negro o congelado) → se pide de nuevo.
    private func checkForegroundStall(now: Date) {
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

extension Double {
    /// Redondeo a décimas (los pasos de la sincronía no acumulan 0.30000000000000004).
    func rounded(toPlaces places: Int) -> Double { let f = pow(10, Double(places)); return (self * f).rounded() / f }
}
