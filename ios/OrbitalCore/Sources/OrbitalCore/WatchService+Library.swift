import Foundation

/// Lo tuyo en el teléfono: «Seguir viendo», Mi lista y lo visto. Cada cambio se guarda aquí al instante y viaja después:
/// a Trakt (lo que comparten tus aparatos) y, si lo conectaste, una copia a Stremio.
extension WatchService {
    /// Lo tuyo de un título (dónde ibas, lo visto, si está en Mi lista); nil si nunca lo tocaste.
    public func entry(metaID: String) -> LibraryEntry? { store.entry(metaID) }

    /// Tu biblioteca del teléfono, lo último que viste (o guardaste) primero.
    public func library() -> [Watchable] {
        store.all.map(\.watchable).sorted { ($0.lastWatched ?? 0) > ($1.lastWatched ?? 0) }
    }

    /// Las series que ibas al día y ya tienen episodio nuevo, de vuelta en Seguir viendo («Nuevo»), en su lugar según cuándo
    /// salió. Como en la consola (`_returning` de watch.py); Cinemeta tiene caché, así que la segunda vez es al instante.
    public func withReturning(_ all: [Watchable]) async -> [Watchable] {
        let now = clock().timeIntervalSince1970
        let candidates = Array(all.filter { $0.mayReturn(now: now) }.prefix(StremioLibrary.returnChecks))
        guard !candidates.isEmpty else { return all }
        let cinemeta = self.cinemeta
        let found = await withTaskGroup(of: (String, Watchable?).self) { group in
            for w in candidates {
                group.addTask {
                    guard let videoID = w.videoID, let info = try? await cinemeta.meta(kind: "series", id: w.id) else { return (w.id, nil) }
                    // lo quitaste a medias de Seguir viendo: no se terminó, no vuelve
                    let seen = w.seen ?? StremioLibrary.parseWatched(w.watched, videoIDs: CinemetaParsing.seasonVideoIDs(info))
                    guard seen.contains(videoID), let new = CinemetaParsing.newEpisode(info, after: videoID, since: w.lastWatched ?? now, now: now)
                    else { return (w.id, nil) }
                    return (w.id, w.returning(videoID: new.id, released: new.released))
                }
            }
            var out: [String: Watchable] = [:]
            for await (id, w) in group { if let w { out[id] = w } }
            return out
        }
        guard !found.isEmpty else { return all }
        return all.map { found[$0.id] ?? $0 }.sorted { ($0.lastWatched ?? 0) > ($1.lastWatched ?? 0) }
    }

    /// «Seguir viendo»: lo que dejaste a medias (o el siguiente episodio), sin lo que abriste un momento.
    public func continueWatching() async -> [Watchable] {
        await withReturning(library()).filter { w in
            guard w.inContinue else { return false }
            let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.episode.episode != nil
            return nextUp || (w.progress ?? 1) >= PlaybackRules.continueMinProgress
        }
    }

    /// Mi lista: aquí al instante; a tu watchlist de Trakt por la cola (`outbox`, que ya sabe esperar a la red) y, si lo
    /// conectaste, una copia a la biblioteca de Stremio.
    public func setInLibrary(kind: String, metaID: String, title: String, poster: String?, add: Bool, outbox: TraktOutbox? = nil) async {
        let now = clock().timeIntervalSince1970
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: title) }) { e in
            e.inList = add; e.listedAt = add ? now : nil
            if e.name.isEmpty { e.name = title }
            if e.poster == nil { e.poster = poster }
        }
        announceChange()
        if let outbox, metaID.hasPrefix("tt") {
            outbox.enqueue(.init(target: TraktOutbox.watchlist, imdb: metaID, series: kind == "series", add: add))
            await outbox.flush(trakt)
        }
        if copiesToStremio { try? await copyLibrary(kind: kind, metaID: metaID, poster: poster, add: add) }
    }

    /// «Marcar como visto» (un episodio o la película): aquí al instante, a Trakt (`/sync/history`) y la copia a Stremio.
    /// Marcar un episodio anterior no mueve tu punto de «Seguir viendo».
    public func markWatched(kind: String, metaID: String, videoID: String, name: String = "", at date: Date? = nil) async {
        let at = (date ?? clock()).timeIntervalSince1970
        let info = try? await cinemeta.meta(kind: kind, id: metaID)
        let next = kind == "series" ? info.flatMap { CinemetaParsing.nextEpisode($0, after: videoID, now: at) } : nil
        let title = info?["name"]?.nonEmptyString ?? name
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: title) }) { e in
            if e.name.isEmpty { e.name = title }
            if e.videoID == nil || e.videoID == videoID || kind == "movie" { e.finish(videoID: videoID, next: next, at: at) } else { e.seen.insert(videoID) }
        }
        announceChange()
        if let target = TraktTarget(videoID: videoID, kind: kind) {
            var work = pending.load()
            work.traktUnwatched.removeAll { $0 == target }
            pending.save(work)
            enqueue(trakt: .init(target: target, at: at))
        }
        if copiesToStremio { try? await copyWatched(kind: kind, metaID: metaID, videoID: videoID) }
        await flushPending()
    }

    /// «Marcar como no visto»: sale de lo visto aquí y viaja a Trakt (`/sync/history/remove`). Una sincronización no lo regresa
    /// mientras no llegue.
    public func unmarkWatched(kind: String, metaID: String, videoID: String) async {
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: "") }) { $0.seen.remove(videoID) }
        announceChange()
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return }
        var work = pending.load()
        work.traktWatched.removeAll { $0.target == target }
        if !work.traktUnwatched.contains(target) { work.traktUnwatched.append(target) }
        pending.save(work)
        await flushPending()
    }

    /// «Quitar de Seguir viendo»: aquí al instante; en Trakt se borra lo que estaba a medias (`DELETE /sync/playback/{id}`).
    /// Con `newEpisode` (la serie había vuelto con ese episodio), no vuelve otra vez.
    public func dismissContinue(metaID: String, newEpisode: String? = nil) async {
        let now = clock().timeIntervalSince1970
        guard let current = store.entry(metaID) else { return }
        store.update(metaID, make: { current }) { e in
            e.hiddenAt = now
            if let newEpisode { e.videoID = newEpisode; e.nextUp = false; e.position = 0 }
        }
        announceChange()
        if metaID.hasPrefix("tt") {
            var work = pending.load()
            work.playbackRemovals.removeAll { $0.target.imdb == metaID }
            work.playbackRemovals.append(.init(target: TraktTarget(imdb: metaID), at: now))
            pending.save(work)
        }
        if copiesToStremio { try? await copyDismiss(metaID: metaID, newEpisode: newEpisode) }
        await flushPending()
    }

    /// Una sola vez: lo que tenías en Stremio (dónde ibas y lo visto) pasa al teléfono. Mi lista de Stremio no se trae: Mi lista
    /// es tu watchlist de Trakt (decisión de Fernando, 29 oct). Devuelve cuántos títulos se trajeron.
    @discardableResult
    public func importFromStremio(kv: KeyValueStore) async -> Int {
        guard kv.data(Self.importedKey) == nil, let key = authKey(), let raws = try? await stremio.library(authKey: key) else { return 0 }
        let items = StremioLibrary.parseLibrary(raws).filter { ["movie", "series"].contains($0.type) && $0.lastWatched != nil }
        // Los episodios vistos de las series más recientes (el resto los trae Trakt): hace falta su lista de Cinemeta.
        let cinemeta = self.cinemeta
        let recent = Array(items.filter { $0.type == "series" && $0.watched != nil }.prefix(40))
        let seen: [String: Set<String>] = await withTaskGroup(of: (String, Set<String>).self) { group in
            for w in recent {
                group.addTask {
                    guard let info = try? await cinemeta.meta(kind: "series", id: w.id) else { return (w.id, []) }
                    return (w.id, StremioLibrary.parseWatched(w.watched, videoIDs: CinemetaParsing.seasonVideoIDs(info)))
                }
            }
            var out: [String: Set<String>] = [:]
            for await (id, s) in group { out[id] = s }
            return out
        }
        store.batch { entries in
            for w in items where entries[w.id] == nil { entries[w.id] = Self.imported(w, seen: seen[w.id] ?? []) }
        }
        kv.set(Self.importedKey, data: Data("1".utf8))
        announceChange()
        return items.count
    }

    public static let importedKey = "library-imported-stremio"

    /// Un título de Stremio como queda en el teléfono.
    static func imported(_ w: Watchable, seen: Set<String>) -> LibraryEntry {
        var e = LibraryEntry(metaID: w.id, kind: w.type, name: w.name, poster: w.poster)
        e.videoID = w.videoID; e.updatedAt = w.lastWatched ?? 0; e.seen = seen
        let nextUp = w.type == "series" && w.timeOffset <= 1 && w.duration == 0 && w.videoID != nil
        if nextUp { e.nextUp = true }
        else if w.timeOffset > 0 { e.position = Double(w.timeOffset) / 1000; e.duration = Double(w.duration) / 1000 }
        return e
    }
}

extension CinemetaParsing {
    /// Los ids de todos los videos en el orden del catálogo (para el bitfield de «visto» de Stremio).
    public static func seasonVideoIDs(_ meta: JSON) -> [String] {
        (meta["videos"]?.array ?? []).compactMap { $0["id"]?.nonEmptyString }
    }
}
