import Foundation

/// Vaciar la cola única de Trakt (F4): lo visto, lo que quitaste, las fechas cambiadas, tu avance y lo de tus listas,
/// calificaciones, notas y series escondidas. Todo con la misma política (`TraktQueue.retry`, `expiry`) y lo descartado, a la
/// bitácora.
extension TraktQueue {
    /// Manda lo que espera. Uno a la vez: si ya va otro, regresa lo que hay (lo nuevo sale en esa vuelta o en la siguiente).
    /// `checkpoint`: cómo se manda tu avance (lo sabe `WatchService`); sin él, tu avance espera en la cola.
    @discardableResult
    public func flush(_ trakt: Trakt?, checkpoint: Checkpoint? = nil) async -> PendingWork {
        guard let trakt, trakt.linked else { return store.load() }
        // Ya va otro: lo de quien llega sale en una vuelta más al terminar esa (nunca se queda esperando otro aviso).
        guard enter() else { again = (trakt, checkpoint ?? again?.checkpoint); return store.load() }
        defer { leave() }
        var result = await pass(trakt, checkpoint)
        while let next = again {
            again = nil
            result = await pass(next.trakt, next.checkpoint ?? checkpoint)
        }
        return result
    }

    /// Una vuelta por toda la cola.
    private func pass(_ trakt: Trakt, _ checkpoint: Checkpoint?) async -> PendingWork {
        // Lo que llega por primera vez a la cola anota desde cuándo espera (para que venza a su tiempo).
        let now = clock().timeIntervalSince1970
        let snapshot = store.update { work in
            for i in work.traktWatched.indices where work.traktWatched[i].queuedAt == nil { work.traktWatched[i].queuedAt = now }
            for i in work.traktRewatched.indices where work.traktRewatched[i].queuedAt == nil { work.traktRewatched[i].queuedAt = now }
            for i in work.playbackRemovals.indices where work.playbackRemovals[i].queuedAt == nil { work.playbackRemovals[i].queuedAt = now }
        }
        guard snapshot.hasTraktWork else { return snapshot }
        var retry = PendingWork()
        retry.traktUnwatched = await attempt(snapshot.traktUnwatched, what: { "No vista · \(Self.label($0))" }, age: { _ in nil }) {
            try await trakt.removeFromHistory($0)
        }.retry
        // Pocos, uno por uno (sin duplicar lo que ya está en Trakt); muchos (una temporada, una serie), de 100 en 100.
        let watched = { (w: PendingWork.TraktWatched) in "Visto · \(Self.label(w.target))" }
        if snapshot.traktWatched.count < WatchService.batchFrom {
            retry.traktWatched = await attempt(snapshot.traktWatched, what: watched, age: { $0.queuedAt }) {
                try await trakt.addToHistory($0.target, watchedAt: Date(timeIntervalSince1970: $0.at))
            }.retry
        } else {
            let chunks = stride(from: 0, to: snapshot.traktWatched.count, by: 100).map { Array(snapshot.traktWatched[$0..<min($0 + 100, snapshot.traktWatched.count)]) }
            retry.traktWatched = await attempt(chunks, what: { "\($0.count) vistos · \($0.first.map(watched) ?? "")" }, age: { $0.compactMap(\.queuedAt).min() }) { chunk in
                try await trakt.addToHistory(chunk.map { ($0.target, Date(timeIntervalSince1970: $0.at)) })
            }.retry.flatMap { $0 }
        }
        // Primero lo nuevo, una por una; la vieja de una fecha cambiada se borra solo si la nueva llegó de verdad (si Trakt la
        // rechazó, la vieja se queda: nunca se pierde la vista).
        var replaced: [Int] = []
        for item in snapshot.traktRewatched {
            let (again, dropped) = await attempt([item], what: { "Otra vista · \(Self.label($0.target))" }, age: { $0.queuedAt }) {
                try await trakt.addToHistory([($0.target, Date(timeIntervalSince1970: $0.at))])
            }
            if again.isEmpty, dropped.isEmpty, let old = item.replaces, await Self.landed(item, in: trakt) { replaced.append(old) }
            retry.traktRewatched += again
        }
        let removals = snapshot.traktViewingRemovals + replaced
        if !removals.isEmpty {
            retry.traktViewingRemovals = await attempt([removals], what: { "Borrar \($0.count) vistas" }, age: { _ in nil }) {
                try await trakt.removeViewings($0)
            }.retry.flatMap { $0 }
        }
        retry.playbackRemovals = await attempt(snapshot.playbackRemovals, what: { "Quitar de Seguir viendo · \($0.target.imdb)" }, age: { $0.queuedAt }) { removal in
            let stale = try await trakt.playback(fresh: true).filter { $0.target.imdb == removal.target.imdb && $0.pausedAt.timeIntervalSince1970 <= removal.at + 1 }
            for item in stale { try await trakt.removePlayback(id: item.id) }
        }.retry
        if let checkpoint {
            retry.traktProgress = await attempt(snapshot.traktProgress, what: { "Tu avance · \($0.metaID)" }, age: { $0.at }) { event in
                guard let target = TraktTarget(videoID: event.videoID, kind: event.kind) else { return }
                // Lo viste en otro aparato mientras tanto (Trakt tiene uno más nuevo): el de aquí ya es viejo, se descarta.
                if let remote = await trakt.paused(target), remote.pausedAt.timeIntervalSince1970 > event.at { return }
                try await checkpoint(event, target)
            }.retry
        } else {
            retry.traktProgress = snapshot.traktProgress
        }
        let outboxDone = await flushOutbox(snapshot.outbox, trakt)
        // Lo que se subió sale; lo que falló se queda; lo que llegó mientras tanto (de este u otro `WatchService`) también:
        // todo en una sola escritura sobre lo último del archivo, nunca sobre una copia vieja. Lo que falló se queda SOLO si
        // sigue en la cola: si mientras se mandaba marcaste lo contrario (no vista, visto otra vez) o lo quitaste, gana lo último
        // que hiciste (revisión del 11 nov 2026: antes se volvía a sumar y Trakt terminaba en «visto» tras un «no visto»).
        return store.update { current in
            current.traktWatched = Self.remaining(current.traktWatched, tried: snapshot.traktWatched, retry: retry.traktWatched)
            current.traktUnwatched = Self.remaining(current.traktUnwatched, tried: snapshot.traktUnwatched, retry: retry.traktUnwatched)
            current.traktProgress = Self.remaining(current.traktProgress, tried: snapshot.traktProgress, retry: retry.traktProgress)
            current.playbackRemovals = Self.remaining(current.playbackRemovals, tried: snapshot.playbackRemovals, retry: retry.playbackRemovals)
            // Las vistas viejas de una fecha cambiada que ya llegó no estaban en la cola: si su borrado falló, entran ahora.
            let replacedLeft = retry.traktViewingRemovals.filter { replaced.contains($0) && !current.traktViewingRemovals.contains($0) }
            current.traktViewingRemovals = Self.remaining(current.traktViewingRemovals, tried: snapshot.traktViewingRemovals, retry: retry.traktViewingRemovals) + replacedLeft
            current.traktRewatched = Self.remaining(current.traktRewatched, tried: snapshot.traktRewatched, retry: retry.traktRewatched)
            for item in outboxDone { if let i = current.outbox.firstIndex(of: item) { current.outbox.remove(at: i) } }
        }
    }

    /// Tus listas, calificaciones, notas y series escondidas, en orden. Se detiene al primer error que se puede reintentar
    /// (sigue sin conexión: lo demás espera). Devuelve lo que ya salió (mandado, rechazado o vencido).
    private func flushOutbox(_ items: [TraktOutbox.Item], _ trakt: Trakt) async -> [TraktOutbox.Item] {
        var done: [TraktOutbox.Item] = []
        var queue = items[...]
        while let item = queue.first {
            // Varios seguidos a la misma lista (o a Mi lista), todos para poner o todos para quitar: un solo envío (G3-A).
            var run = [item]
            if !TraktOutbox.singles.contains(item.target) { run = Array(queue.prefix { $0.target == item.target && $0.add == item.add }) }
            let (again, dropped) = await attempt([run], what: { "\(TraktOutbox.label($0[0].target)) · \($0.count == 1 ? $0[0].imdb : "\($0.count) títulos")" },
                                           age: { $0.compactMap(\.queuedAt).min() }) { run in
                if run.count > 1 { try await trakt.setItems(target: item.target, run.map { ($0.imdb, $0.series) }, add: item.add) }
                else { try await TraktOutbox.send(item, trakt) }
            }
            if !again.isEmpty { break }
            if dropped.isEmpty { countSent(run.count) }
            done += run
            queue = queue.dropFirst(run.count)
        }
        return done
    }

    /// Lo que queda en la cola tras una vuelta, en el orden en que lo hiciste: sale lo intentado que llegó o se descartó; lo que
    /// se reintenta se queda solo si sigue en `current` (la última intención del usuario por título manda: marcar lo contrario
    /// lo sacó de la cola y no se resucita); lo que llegó durante la vuelta, también. Nunca hay a la vez «visto» y «no visto»
    /// del mismo título: cada acción quita la opuesta al anotarse (`WatchService.markWatched`, `unmarkWatched`, `addViewing`).
    static func remaining<T: Equatable>(_ current: [T], tried: [T], retry: [T]) -> [T] {
        current.filter { !tried.contains($0) || retry.contains($0) }
    }

    /// ¿La vista nueva ya está en Trakt? Sin cómo saberlo (Trakt no dice), se confía en que la aceptó (contestó 2xx).
    static func landed(_ item: PendingWork.TraktWatched, in trakt: Trakt) async -> Bool {
        guard let all = try? await trakt.viewings(item.target) else { return true }
        return all.contains { abs($0.at.timeIntervalSince1970 - item.at) < 2 }
    }

    static func label(_ t: TraktTarget) -> String {
        guard let s = t.season, let e = t.episode else { return t.imdb }
        return "\(t.imdb) T\(s) E\(e)"
    }
}
