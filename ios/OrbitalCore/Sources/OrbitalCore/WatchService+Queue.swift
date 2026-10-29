import Foundation

/// El viaje de lo tuyo: la copia a Stremio (mientras dure la prueba) y la cola de lo que espera a la red para Trakt.
/// Si Stremio falla no se avisa ni se bloquea nada: se reintenta.
extension WatchService {
    // MARK: copia a Stremio
    /// Copia el avance a Stremio; sin red, a la cola. Devuelve si quedó en la cola.
    func copyToStremio(_ event: ProgressEvent) async -> Bool {
        do { try await write(event); return false } catch {
            var work = pending.load()
            work.progress.append(event)
            pending.save(work)
            return true
        }
    }

    func write(_ event: ProgressEvent) async throws {
        guard let key = authKey() else { return }
        let info = try? await cinemeta.meta(kind: event.kind, id: event.metaID)  // la ficha ORIGINAL
        let raw = try await stremio.libraryItem(authKey: key, id: event.metaID)
        // El nombre que se escribe es el de Cinemeta (original). Sin él y sin un item previo no se inventa uno: se reintenta luego.
        let name = info?["name"]?.nonEmptyString ?? raw?["name"]?.nonEmptyString ?? (event.originalTitle.isEmpty ? nil : event.originalTitle)
        guard let name else { throw WatchError.noTitle }
        let videoIDs = info.map { CinemetaParsing.seasonVideoIDs($0) } ?? []
        let next = event.kind == "series" ? info.flatMap { CinemetaParsing.nextEpisode($0, after: event.videoID) } : nil
        var position = StremioLibrary.finite(event.position), duration = StremioLibrary.finite(event.duration)
        if event.finished {   // se dijo que se terminó: cuenta como visto aunque falte un poco o no se sepa la duración
            duration = max(duration, position, 1)
            position = duration
        }
        let item = StremioLibrary.withProgress(
            raw, metaID: event.metaID, kind: event.kind, name: name, poster: info?["poster"]?.string,
            videoID: event.videoID, position: position, duration: duration, watched: StremioLibrary.finite(event.watched), nextVideo: next,
            now: event.at, videoIDs: videoIDs.isEmpty ? nil : videoIDs)
        try await stremio.saveLibraryItem(authKey: key, item: item)
    }

    func copyLibrary(kind: String, metaID: String, poster: String?, add: Bool) async throws {
        guard let key = authKey() else { return }
        let raw = try await stremio.libraryItem(authKey: key, id: metaID)
        var name = raw?["name"]?.nonEmptyString, art = poster
        if raw == nil {
            let info = try? await cinemeta.meta(kind: kind, id: metaID)
            name = info?["name"]?.nonEmptyString
            art = info?["poster"]?.string ?? poster
        }
        guard let name else { throw WatchError.noTitle }
        try await stremio.saveLibraryItem(authKey: key, item: StremioLibrary.libraryToggled(raw, metaID: metaID, kind: kind, name: name, poster: art, add: add, now: clock().timeIntervalSince1970))
    }

    func copyWatched(kind: String, metaID: String, videoID: String) async throws {
        guard let key = authKey() else { return }
        let info = try? await cinemeta.meta(kind: kind, id: metaID)
        let raw = try await stremio.libraryItem(authKey: key, id: metaID)
        guard let name = info?["name"]?.nonEmptyString ?? raw?["name"]?.nonEmptyString else { throw WatchError.noTitle }
        let ids = info.map { CinemetaParsing.seasonVideoIDs($0) } ?? []
        let next = kind == "series" ? info.flatMap { CinemetaParsing.nextEpisode($0, after: videoID) } : nil
        let item = StremioLibrary.markWatched(raw, metaID: metaID, kind: kind, name: name, poster: info?["poster"]?.string, videoID: videoID,
                                              videoIDs: ids, nextVideo: next, now: clock().timeIntervalSince1970)
        try await stremio.saveLibraryItem(authKey: key, item: item)
    }

    func copyDismiss(metaID: String, newEpisode: String?) async throws {
        guard let key = authKey(), let raw = try await stremio.libraryItem(authKey: key, id: metaID) else { return }
        try await stremio.saveLibraryItem(authKey: key, item: StremioLibrary.dismissed(raw, now: clock().timeIntervalSince1970, videoID: newEpisode))
    }

    // MARK: la cola
    /// Sube lo que quedó esperando. Un avance viejo no pisa algo más nuevo hecho en otro aparato: Trakt no deja fechar un aviso
    /// en el pasado, así que antes de mandarlo se compara con lo que Trakt tiene. Solo uno a la vez; lo que llegue a la cola
    /// mientras tanto se conserva.
    @discardableResult
    public func flushPending() async -> PendingWork {
        guard gate.enter() else { return pending.load() }
        defer { gate.leave() }
        let snapshot = pending.load()
        guard !snapshot.isEmpty else { return snapshot }
        var retry = PendingWork()
        for event in snapshot.progress.sorted(by: { $0.at < $1.at }) {
            guard let key = authKey() else { continue }   // ya no hay Stremio: la copia sobra
            do {
                if let raw = try await stremio.libraryItem(authKey: key, id: event.metaID),
                   let newer = StremioLibrary.epoch(raw["_mtime"]), newer > event.at + 1 { continue }  // el remoto es más nuevo: no se pisa
                try await write(event)
            } catch { retry.progress.append(event) }
        }
        if let trakt, trakt.linked {
            retry.traktUnwatched = await attempt(snapshot.traktUnwatched) { try await trakt.removeFromHistory($0) }
            retry.traktWatched = await attempt(snapshot.traktWatched) { try await trakt.addToHistory($0.target, watchedAt: Date(timeIntervalSince1970: $0.at)) }
            retry.playbackRemovals = await attempt(snapshot.playbackRemovals) { removal in
                let stale = try await trakt.playback(fresh: true).filter { $0.target.imdb == removal.target.imdb && $0.pausedAt.timeIntervalSince1970 <= removal.at + 1 }
                for item in stale { try await trakt.removePlayback(id: item.id) }
            }
            retry.traktProgress = await attempt(snapshot.traktProgress) { event in
                guard let target = TraktTarget(videoID: event.videoID, kind: event.kind) else { return }
                // Lo viste en otro aparato mientras tanto (Trakt tiene uno más nuevo): el de aquí ya es viejo, se descarta.
                if let remote = await trakt.paused(target), remote.pausedAt.timeIntervalSince1970 > event.at { return }
                try await sendCheckpoint(event, target)
            }
        } else {
            retry.traktWatched = snapshot.traktWatched; retry.traktUnwatched = snapshot.traktUnwatched
            retry.traktProgress = snapshot.traktProgress; retry.playbackRemovals = snapshot.playbackRemovals
        }
        // Lo que se subió sale; lo que falló se queda; lo que llegó durante el vaciado también se queda.
        let current = pending.load()
        var next = PendingWork()
        next.progress = current.progress.filter { !snapshot.progress.contains($0) } + retry.progress
        next.traktWatched = current.traktWatched.filter { !snapshot.traktWatched.contains($0) } + retry.traktWatched
        next.traktUnwatched = current.traktUnwatched.filter { !snapshot.traktUnwatched.contains($0) } + retry.traktUnwatched
        next.traktProgress = current.traktProgress.filter { !snapshot.traktProgress.contains($0) } + retry.traktProgress
        next.playbackRemovals = current.playbackRemovals.filter { !snapshot.playbackRemovals.contains($0) } + retry.playbackRemovals
        pending.save(next)
        return next
    }

    /// Manda cada cosa; devuelve lo que vale la pena reintentar (sin red, Trakt caído). Lo que Trakt rechaza (inválido) se descarta.
    private func attempt<T: Sendable>(_ items: [T], _ send: (T) async throws -> Void) async -> [T] {
        var again: [T] = []
        for item in items {
            do { try await send(item) }
            catch let error as TraktError { if Self.shouldRetry(error) { again.append(item) } }
            catch {}
        }
        return again
    }
}
