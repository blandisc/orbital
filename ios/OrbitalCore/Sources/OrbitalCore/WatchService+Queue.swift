import Foundation

/// El viaje de lo tuyo: la copia a Stremio (mientras dure la prueba) y la cola de lo que espera a la red para Trakt.
/// Si Stremio falla no se avisa ni se bloquea nada: se reintenta.
extension WatchService {
    // MARK: copia a Stremio
    /// Copia el avance a Stremio; sin red, a la cola. Devuelve si quedó en la cola.
    func copyToStremio(_ event: ProgressEvent) async -> Bool {
        do { try await write(event); return false } catch {
            pending.update { $0.progress.append(event) }
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
    /// Sube lo que quedó esperando: la copia a Stremio aquí y lo de Trakt en la cola única (`TraktQueue`, F4), que se vacía
    /// de uno en uno en toda la app aunque haya dos `WatchService` (al rearmar los servicios). Un avance viejo no pisa algo más
    /// nuevo hecho en otro aparato. Lo que llegue a la cola mientras tanto se conserva.
    @discardableResult
    public func flushPending() async -> PendingWork {
        await flushCopies()
        guard let trakt else { return pending.load() }
        return await traktQueue.flush(trakt, checkpoint: { [weak self] event, target in try await self?.sendCheckpoint(event, target) })
    }

    /// La copia a Stremio que quedó esperando (mientras dure la prueba).
    private func flushCopies() async {
        guard !copying else { return }
        copying = true
        defer { copying = false }
        let snapshot = pending.load().progress
        guard !snapshot.isEmpty else { return }
        var retry: [ProgressEvent] = []
        for event in snapshot.sorted(by: { $0.at < $1.at }) {
            guard let key = authKey() else { continue }   // ya no hay Stremio: la copia sobra
            do {
                if let raw = try await stremio.libraryItem(authKey: key, id: event.metaID),
                   let newer = StremioLibrary.epoch(raw["_mtime"]), newer > event.at + 1 { continue }  // el remoto es más nuevo: no se pisa
                try await write(event)
            } catch { retry.append(event) }
        }
        pending.update { $0.progress = $0.progress.filter { !snapshot.contains($0) } + retry }
    }

    /// Desde cuántos vistos pendientes se suben juntos.
    static let batchFrom = 4
}
