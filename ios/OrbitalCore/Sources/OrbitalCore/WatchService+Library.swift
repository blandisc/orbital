import Foundation

/// Lo tuyo en el teléfono: «Seguir viendo», Mi lista y lo visto. Cada cambio se guarda aquí al instante y viaja después a
/// Trakt (lo que comparten tus aparatos).
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
        let candidates = Array(all.filter { $0.mayReturn(now: now) }.prefix(LibraryRules.returnChecks))
        guard !candidates.isEmpty else { return all }
        let cinemeta = self.cinemeta
        let found = await withTaskGroup(of: (String, Watchable?).self) { group in
            for w in candidates {
                group.addTask {
                    guard let videoID = w.videoID, let info = try? await cinemeta.meta(kind: "series", id: w.id) else { return (w.id, nil) }
                    // lo quitaste a medias de Seguir viendo: no se terminó, no vuelve
                    let seen = w.seen ?? LibraryRules.parseWatched(w.watched, videoIDs: CinemetaParsing.seasonVideoIDs(info))
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

    /// Mi lista: aquí al instante; a tu watchlist de Trakt por la cola (`outbox`, que ya sabe esperar a la red).
    /// `flush: false`: varios seguidos (elegir varios); quien llama manda la cola una vez al final.
    public func setInLibrary(kind: String, metaID: String, title: String, poster: String?, add: Bool, outbox: TraktOutbox? = nil, flush: Bool = true) async {
        let now = clock().timeIntervalSince1970
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: title) }) { e in
            e.inList = add; e.listedAt = add ? now : nil
            if e.name.isEmpty { e.name = title }
            if e.poster == nil { e.poster = poster }
        }
        announceChange()
        if let outbox, metaID.hasPrefix("tt") {
            outbox.enqueue(.init(target: TraktOutbox.watchlist, imdb: metaID, series: kind == "series", add: add))
            if flush { await flushPending() }
        }
    }

    /// «Marcar como visto» (un episodio o la película): aquí al instante y a Trakt (`/sync/history`).
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
            pending.update { $0.traktUnwatched.removeAll { $0 == target } }
            enqueue(trakt: .init(target: target, at: at))
        }
        await flushPending()
    }

    /// Varios a la vez (una temporada, la serie completa, «también los anteriores»), cada uno con su fecha: aquí en una sola
    /// escritura y a Trakt juntos. Lo de «Seguir viendo» lo mueve solo el más nuevo de la serie.
    public func markWatched(kind: String, metaID: String, videos: [(id: String, at: Date)], name: String = "") async {
        guard let latest = videos.max(by: { $0.at < $1.at }) else { return }
        if videos.count == 1 { return await markWatched(kind: kind, metaID: metaID, videoID: latest.id, name: name, at: latest.at) }
        let info = try? await cinemeta.meta(kind: kind, id: metaID)
        // En orden de temporada y episodio («tt…:2:5»): el último marca dónde vas.
        let rank = { (id: String) -> Int in let p = id.split(separator: ":").compactMap { Int($0) }; return p.count >= 2 ? p[p.count - 2] * 10_000 + p[p.count - 1] : 0 }
        let order = videos.map(\.id).sorted { rank($0) < rank($1) }
        let last = order.last ?? latest.id
        let now = clock().timeIntervalSince1970
        let next = info.flatMap { CinemetaParsing.nextEpisode($0, after: last, now: now) }
        let title = info?["name"]?.nonEmptyString ?? name
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: title) }) { e in
            if e.name.isEmpty { e.name = title }
            e.seen.formUnion(videos.map(\.id))
            if e.videoID == nil || order.contains(e.videoID ?? "") { e.finish(videoID: last, next: next, at: max(latest.at.timeIntervalSince1970, 1)) }
        }
        announceChange()
        let targets = videos.compactMap { v in TraktTarget(videoID: v.id, kind: kind).map { ($0, v.at) } }
        pending.update { work in work.traktUnwatched.removeAll { t in targets.contains { $0.0 == t } } }
        for (target, at) in targets { enqueue(trakt: .init(target: target, at: at.timeIntervalSince1970)) }
        await flushPending()
    }

    /// Varios fuera de lo visto a la vez (quitar una temporada o la serie).
    public func unmarkWatched(kind: String, metaID: String, videoIDs: [String]) async {
        for id in videoIDs { await unmarkWatched(kind: kind, metaID: metaID, videoID: id) }
    }

    /// «Marcar como no visto»: sale de lo visto aquí y viaja a Trakt (`/sync/history/remove`). Una sincronización no lo regresa
    /// mientras no llegue.
    public func unmarkWatched(kind: String, metaID: String, videoID: String) async {
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: "") }) { $0.seen.remove(videoID) }
        announceChange()
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return }
        pending.update { work in
            work.traktWatched.removeAll { $0.target == target }
            work.traktRewatched.removeAll { $0.target == target }   // «La vi otra vez» sin red no lo regresa
            if !work.traktUnwatched.contains(target) { work.traktUnwatched.append(target) }
        }
        await flushPending()
    }

    /// «Quitar de Seguir viendo»: aquí al instante; en Trakt se borra lo que estaba a medias (`DELETE /sync/playback/{id}`).
    /// Con `newEpisode` (la serie había vuelto con ese episodio), no vuelve otra vez.
    public func dismissContinue(metaID: String, newEpisode: String? = nil) async {
        let now = clock().timeIntervalSince1970
        guard let current = store.entry(metaID) else { return }
        store.update(metaID, make: { current }) { e in
            e.dismissDetour()   // un episodio del canal a medias: tu orden de antes, fuera de la fila
            e.hiddenAt = now
            if let newEpisode { e.videoID = newEpisode; e.nextUp = false; e.position = 0 }
        }
        announceChange()
        if metaID.hasPrefix("tt") {
            pending.update { work in
                work.playbackRemovals.removeAll { $0.target.imdb == metaID }
                work.playbackRemovals.append(.init(target: TraktTarget(imdb: metaID), at: now))
            }
        }
        await flushPending()
    }
}

extension CinemetaParsing {
    /// Los ids de todos los videos en el orden del catálogo (para el bitfield de «visto» del formato `libraryItem`).
    public static func seasonVideoIDs(_ meta: JSON) -> [String] {
        (meta["videos"]?.array ?? []).compactMap { $0["id"]?.nonEmptyString }
    }
}
