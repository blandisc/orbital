import Foundation

/// Guarda lo que ves. **Primero en el teléfono** (`LocalLibrary`: la pantalla responde sin red), luego en **Trakt** (lo que
/// comparten tus aparatos, con las reglas de `TraktProgressRule`) y, mientras dure la prueba, una **copia en Stremio** si lo
/// conectaste. Lo que no se pueda subir espera en una cola (`PendingWork`) y se sube al volver, sin pisar algo más nuevo.
public actor WatchService {
    let store: LocalLibrary
    let stremio: StremioAPI
    let authKey: @Sendable () -> String?
    let cinemeta: Cinemeta
    let trakt: Trakt?
    let pending: PendingStore
    let clock: @Sendable () -> Date
    let gate: FlushGate
    let scrobbleLog: ScrobbleLog?
    let sleep: @Sendable (TimeInterval) async -> Void
    /// Cuándo se le mandó a Trakt el último aviso de cada video que suena (para el respaldo cada 5 minutos).
    var lastTraktWrite: [String: Date] = [:]
    /// Videos cuyo último aviso fue un respaldo (`start` + `pause` mientras sonaba): la siguiente pausa o cierre llevan antes
    /// un `start`, o Trakt no movería `paused_at`.
    var afterBackup: Set<String> = []

    public init(library: LocalLibrary = LocalLibrary(), stremio: StremioAPI, authKey: @escaping @Sendable () -> String?, cinemeta: Cinemeta,
                trakt: Trakt? = nil, pending: PendingStore, clock: @escaping @Sendable () -> Date = { Date() }, gate: FlushGate = FlushGate(),
                scrobbleLog: ScrobbleLog? = nil,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.store = library; self.stremio = stremio; self.authKey = authKey; self.cinemeta = cinemeta; self.trakt = trakt
        self.pending = pending; self.clock = clock; self.gate = gate; self.scrobbleLog = scrobbleLog; self.sleep = sleep
    }

    /// ¿Hay copia a Stremio? Solo si lo conectaste (fases 1 y 2 de la transición).
    var copiesToStremio: Bool { authKey() != nil }

    // MARK: dónde seguir
    /// Dónde ibas en segundos (0 si no se sabe). Si de Trakt solo se sabe el porcentaje (sin la duración), lo de este teléfono
    /// (Infuse recibe segundos, no puede buscar después).
    public func resumePosition(metaID: String, videoID: String, kind: String? = nil) async -> Double {
        let point = await resumePoint(metaID: metaID, videoID: videoID, kind: kind)
        guard point.fraction != nil else { return point.seconds }
        guard let entry = store.entry(metaID), entry.videoID == videoID, !entry.nextUp, entry.fraction == nil else { return 0 }
        return entry.position
    }

    /// Dónde seguir: lo más reciente entre este teléfono y lo que Trakt guardó al pausar o cerrar en otro aparato.
    public func resumePoint(metaID: String, videoID: String, kind: String? = nil) async -> ResumePoint {
        let target = TraktTarget(videoID: videoID, kind: kind ?? (videoID == metaID ? "movie" : "series"))
        var paused: TraktPlayback?
        if let trakt, trakt.linked, let target { paused = await trakt.paused(target) }
        return ResumePoint.latest(local: store.entry(metaID), videoID: videoID, trakt: paused)
    }

    // MARK: lo que ves
    /// `scrobbleToTrakt: false` para Infuse, que ya avisa a Trakt con su propia conexión (así no se duplica).
    @discardableResult
    public func report(_ event: ProgressEvent, phase: PlaybackPhase, scrobbleToTrakt: Bool = true) async -> ReportOutcome {
        var event = event
        if case .stopped(let finished) = phase { event.finished = finished || event.finished }
        var outcome = ReportOutcome()
        let final: Bool = { if case .stopped = phase { return true }; return false }()
        // Se abrió y se cerró sin ver nada: no se toca lo tuyo (salvo que se haya dicho que se terminó).
        let trivial = final && !event.finished && event.watched < PlaybackRules.minWatchedToSave && event.position < PlaybackRules.minPositionToSave
        // Primero el teléfono (así Trakt, al contestar, ya encuentra el título y lo marca como «mandado desde aquí»).
        if phase != .started && !trivial { await saveLocally(event); outcome.saved = true }
        if scrobbleToTrakt { await scrobble(event, phase) }
        if outcome.saved && copiesToStremio { outcome.queued = await copyToStremio(event) }
        return outcome
    }

    /// El avance en el teléfono. Terminado: queda visto y la serie pasa al siguiente episodio (el de Cinemeta, ya emitido).
    func saveLocally(_ event: ProgressEvent) async {
        let position = StremioLibrary.finite(event.position), duration = StremioLibrary.finite(event.duration)
        let done = event.finished || StremioLibrary.finished(position: position, duration: duration, kind: event.kind)
        var next: String?
        if done, event.kind == "series", let info = try? await cinemeta.meta(kind: event.kind, id: event.metaID) {
            next = CinemetaParsing.nextEpisode(info, after: event.videoID, now: event.at)
        }
        store.update(event.metaID, make: { LibraryMerge.make(event.metaID, kind: event.kind, name: event.originalTitle) }) { e in
            if e.name.isEmpty { e.name = event.originalTitle }
            if done { e.finish(videoID: event.videoID, next: next, at: event.at); return }
            e.videoID = event.videoID; e.position = position; e.duration = duration; e.fraction = nil
            e.nextUp = false; e.hiddenAt = nil; e.updatedAt = event.at
        }
        announceChange()
    }

    nonisolated func announceChange() { NotificationCenter.default.post(name: LocalLibrary.changed, object: nil) }

    /// ¿Vale la pena volver a intentarlo más tarde? (sin red, servidor caído, límite de peticiones o sesión por reconectar)
    static func shouldRetry(_ error: TraktError) -> Bool {
        switch error {
        case .network, .auth: return true
        case .http(let status): return status >= 500 || status == 429 || status == 408
        case .invalid: return false
        }
    }

    // MARK: Trakt
    private func scrobble(_ event: ProgressEvent, _ phase: PlaybackPhase) async {
        guard let trakt, trakt.linked else { return }
        guard let target = TraktTarget(videoID: event.videoID, kind: event.kind) else {
            // Sin IMDb (un complemento con sus propios ids) Trakt no lo reconoce: se dice una vez, al empezar, en vez de callar.
            if case .started = phase { scrobbleLog?.recordFailure("«\(Self.scrobbleTitle(event))» no tiene ficha de IMDb: Trakt no lo puede registrar.") }
            return
        }
        guard event.duration > 0 else { return }
        let now = clock()
        switch phase {
        case .started:
            afterBackup.remove(event.videoID)
            await send(.start, event, target)
        case .tick:
            // Respaldo cada 5 minutos: `start` y, 2 s después, `pause` (una entrada nueva con la hora de ahora). Una pausa sola
            // no mueve `paused_at` y otro aparato la creería vieja.
            guard now.timeIntervalSince(lastTraktWrite[event.videoID] ?? now) >= TraktProgressRule.backupEvery else {
                if lastTraktWrite[event.videoID] == nil { lastTraktWrite[event.videoID] = now }
                return
            }
            await checkpoint(event, target)
        case .paused, .background:
            await restartAfterBackup(event, target)
            await send(.pause, event, target)
        case .stopped:
            await restartAfterBackup(event, target)
            lastTraktWrite[event.videoID] = nil
            await send(.stop, event, target)
        }
    }

    /// Después de un respaldo Trakt cree que está en pausa: un `start` (y 2 s) para que la pausa o el cierre cuenten como nuevos.
    private func restartAfterBackup(_ event: ProgressEvent, _ target: TraktTarget) async {
        guard afterBackup.remove(event.videoID) != nil else { return }
        if await send(.start, event, target) { await sleep(TraktProgressRule.backupGap) }
    }

    /// `start` + 2 s + `pause`, con el avance real (con su tope). Sin red, tu avance queda en la cola.
    func checkpoint(_ event: ProgressEvent, _ target: TraktTarget) async {
        do { try await sendCheckpoint(event, target) }
        catch let error as TraktError { scrobbleLog?.recordFailure(error.description); if Self.shouldRetry(error) { queue(progress: event) } }
        catch { scrobbleLog?.recordFailure("\(error)") }
    }

    /// Lo mismo, lanzando el error (la cola decide si lo reintenta).
    func sendCheckpoint(_ event: ProgressEvent, _ target: TraktTarget) async throws {
        guard let trakt, let percent = TraktProgressRule.percent(.pause, position: event.position, duration: event.duration, kind: event.kind, finished: event.finished) else { return }
        lastTraktWrite[event.videoID] = clock()
        try await trakt.scrobble(.start, target, progress: percent)
        await sleep(TraktProgressRule.backupGap)
        let result = try await trakt.scrobble(.pause, target, progress: percent)
        if result != .ignored { scrobbleLog?.recordSent(title: Self.scrobbleTitle(event), action: .pause, at: clock()) }
        afterBackup.insert(event.videoID)
        markPushed(event.metaID)
    }

    /// Un aviso a Trakt con las reglas de `TraktProgressRule`. Devuelve si llegó.
    @discardableResult
    private func send(_ action: ScrobbleAction, _ event: ProgressEvent, _ target: TraktTarget) async -> Bool {
        guard let trakt else { return false }
        let done = TraktProgressRule.done(position: event.position, duration: event.duration, kind: event.kind, finished: event.finished)
        guard let percent = TraktProgressRule.percent(action, position: event.position, duration: event.duration, kind: event.kind, finished: event.finished) else { return true }
        lastTraktWrite[event.videoID] = clock()
        do {
            let result = try await trakt.scrobble(action, target, progress: percent)
            // 409 = ya estaba registrado: no es un error. Menos de 1 % (422) no cuenta como aviso.
            if result != .ignored { scrobbleLog?.recordSent(title: Self.scrobbleTitle(event), action: action, at: clock()) }
            if action != .start { markPushed(event.metaID) }
            return true
        } catch let error as TraktError {
            scrobbleLog?.recordFailure(error.description)
            guard Self.shouldRetry(error), action != .start else { return false }
            // Sin conexión: lo visto se sube después con su fecha real; tu avance, solo si Trakt no tiene uno más nuevo.
            if action == .stop && done { enqueue(trakt: .init(target: target, at: event.at)) } else { queue(progress: event) }
            return false
        } catch {
            scrobbleLog?.recordFailure("\(error)")
            return false
        }
    }

    /// Este teléfono le acaba de mandar su avance a Trakt: lo que Trakt devuelva en un rato es el mismo, no algo nuevo.
    func markPushed(_ metaID: String) {
        let now = clock().timeIntervalSince1970
        guard store.entry(metaID) != nil else { return }
        store.update(metaID, make: { LibraryEntry(metaID: metaID, kind: "movie", name: "") }) { $0.pushedAt = now }
    }

    /// «The Office T2 · E5» o «Dune»: cómo se dice lo último que se mandó.
    static func scrobbleTitle(_ event: ProgressEvent) -> String {
        guard event.kind == "series", let target = TraktTarget(videoID: event.videoID, kind: "series"),
              let season = target.season, let episode = target.episode else { return event.originalTitle }
        return "\(event.originalTitle) T\(season) · E\(episode)"
    }

    func enqueue(trakt item: PendingWork.TraktWatched) {
        var work = pending.load()
        // El mismo título cerrado dos veces sin red es UN visionado, no dos.
        work.traktWatched.removeAll { $0.target == item.target && abs($0.at - item.at) < 12 * 3600 }
        work.traktWatched.append(item)
        pending.save(work)
    }

    /// Tu avance para Trakt, en la cola: solo el último de cada video cuenta.
    func queue(progress event: ProgressEvent) {
        var work = pending.load()
        work.traktProgress.removeAll { $0.videoID == event.videoID }
        work.traktProgress.append(event)
        pending.save(work)
    }
}
