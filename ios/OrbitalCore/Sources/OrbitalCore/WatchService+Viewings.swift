import Foundation

/// Cada vez que viste algo (gestor ola 3, O3-B, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): leerlas, cambiar
/// una fecha, borrar una sola y deshacer solo la de hoy. Lo de aquí cambia al momento; Trakt lo recibe en cuanto haya red
/// (`traktRewatched` y `traktViewingRemovals` en la cola). docs/producto/live-activity-2026-11-08/gestor-ola3.html
extension WatchService {
    /// Cada vez que viste esta película o este capítulo, la más nueva primero. Lo que espera en la cola sale ya (con id 0:
    /// aún no llega a Trakt) y lo que borraste sin red ya no sale.
    public func viewings(kind: String, videoID: String) async throws -> [TraktViewing] {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return [] }
        let work = pending.load()
        let queued = (work.traktWatched + work.traktRewatched).filter { $0.target == target }.map { TraktViewing(id: 0, at: Date(timeIntervalSince1970: $0.at)) }
        let gone = work.goneViewings
        var remote: [TraktViewing] = []
        if let trakt, trakt.linked { remote = try await trakt.viewings(target).filter { !gone.contains($0.id) } }
        return (queued + remote).sorted { $0.at > $1.at }
    }

    /// Para la hoja «Tus vistas»: primero sube lo que esperaba (así lo de la cola ya tiene su id) y, sin internet, enseña lo
    /// que espera en este aparato con `offline` (la hoja lo dice y «La vi otra vez» sigue a mano). La sesión de la TV lo
    /// encontró en su pasada del 10 nov.
    public func viewingsOrQueued(kind: String, videoID: String) async -> (viewings: [TraktViewing], offline: Bool) {
        if !pending.load().isEmpty { await flushPending() }
        if let found = try? await viewings(kind: kind, videoID: videoID) { return (found, false) }
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return ([], true) }
        let work = pending.load()
        let queued = (work.traktWatched + work.traktRewatched).filter { $0.target == target }.map { TraktViewing(id: 0, at: Date(timeIntervalSince1970: $0.at)) }
        return (queued.sorted { $0.at > $1.at }, true)
    }

    /// Borra una sola vista. Si era la única, el título (o el capítulo) deja de contar como visto aquí.
    /// `sure: false` (el Historial solo ve las páginas que cargó): antes de dejar de contarlo como visto, se pregunta a Trakt.
    public func removeViewing(_ viewing: TraktViewing, kind: String, metaID: String, videoID: String, remaining: Int, sure: Bool = true) async {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return }
        pending.update { work in
            if viewing.id == 0 {   // aún no llegaba a Trakt: sale de la cola (y si era una fecha cambiada, la vieja también se va)
                let at = viewing.at.timeIntervalSince1970
                work.traktWatched.removeAll { $0.target == target && abs($0.at - at) < 1 }
                for old in work.traktRewatched where old.target == target && abs(old.at - at) < 1 {
                    if let id = old.replaces, !work.traktViewingRemovals.contains(id) { work.traktViewingRemovals.append(id) }
                }
                work.traktRewatched.removeAll { $0.target == target && abs($0.at - at) < 1 }
            } else if !work.traktViewingRemovals.contains(viewing.id) {
                work.traktViewingRemovals.append(viewing.id)
            }
        }
        var none = remaining == 0
        if none, !sure {
            let left = try? await viewings(kind: kind, videoID: videoID).filter { $0.id != viewing.id }
            none = left?.isEmpty == true   // sin red no se sabe: se queda como visto
        }
        if none {
            store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: "") }) { $0.seen.remove(videoID) }
            announceChange()
        }
        await flushPending()
    }

    /// Cambia la fecha de una vista: la nueva entra y la vieja sale (en Trakt no hay «cambiar»).
    public func moveViewing(_ viewing: TraktViewing, kind: String, videoID: String, to date: Date) async {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return }
        pending.update { work in
            if viewing.id == 0 {
                let at = viewing.at.timeIntervalSince1970
                let old = work.traktRewatched.first { $0.target == target && abs($0.at - at) < 1 }
                work.traktWatched.removeAll { $0.target == target && abs($0.at - at) < 1 }
                work.traktRewatched.removeAll { $0.target == target && abs($0.at - at) < 1 }
                if let old { work.traktRewatched.append(.init(target: target, at: date.timeIntervalSince1970, replaces: old.replaces)) }
                else { work.traktWatched.append(.init(target: target, at: date.timeIntervalSince1970)) }
            } else {   // la vieja se borra hasta que la nueva llegue (flushPending)
                work.traktRewatched.append(.init(target: target, at: date.timeIntervalSince1970, replaces: viewing.id))
            }
        }
        await flushPending()
    }

    /// «La vi otra vez»: una vista más (aunque haya otra cerca: la pediste tú).
    public func addViewing(kind: String, metaID: String, videoID: String, name: String = "", at date: Date) async {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return }
        store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: name) }) { e in
            if e.name.isEmpty { e.name = name }
            e.seen.insert(videoID)
        }
        announceChange()
        pending.update { work in
            work.traktUnwatched.removeAll { $0 == target }
            work.traktRewatched.append(.init(target: target, at: date.timeIntervalSince1970))
        }
        await flushPending()
    }

    /// ¿Ya contaba como visto? (antes de marcar: «Deshacer» sabe si dejarlo como visto).
    public func isSeen(metaID: String, videoID: String) -> Bool { store.entry(metaID)?.seen.contains(videoID) == true }

    /// «Deshacer» del aviso de «Vista»: quita solo la vista que se acaba de marcar (`at`); las de antes se quedan. Si no
    /// contaba como visto antes de marcarlo, vuelve a no contar. Devuelve false si no se pudo (sin red y ya estaba en Trakt).
    @discardableResult
    public func undoViewing(kind: String, metaID: String, videoID: String, at: Date, wasSeen: Bool) async -> Bool {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return false }
        let stamp = at.timeIntervalSince1970
        var queued = false
        // En un solo paso: sacarla de la cola si no había llegado o, si era la única, «Quitar de vistas».
        pending.update { work in
            queued = work.traktWatched.contains { $0.target == target && abs($0.at - stamp) < 2 }
            if queued { work.traktWatched.removeAll { $0.target == target && abs($0.at - stamp) < 2 } }
            else if !wasSeen, !work.traktUnwatched.contains(target) { work.traktUnwatched.append(target) }
        }
        var done = true
        if !queued, wasSeen {   // ya estaba en Trakt y había otras: se borra solo la de esta hora
            if let trakt, trakt.linked, let all = try? await trakt.viewings(target) {
                // Si Trakt ya tenía una cerca (la TV anoche), no se subió nada y esa se queda.
                if let mine = all.first(where: { abs($0.at.timeIntervalSince1970 - stamp) < 120 }) {
                    pending.update { $0.traktViewingRemovals.append(mine.id) }
                }
            } else {
                done = false
            }
        }
        if !wasSeen {
            store.update(metaID, make: { LibraryMerge.make(metaID, kind: kind, name: "") }) { $0.seen.remove(videoID) }
            announceChange()
        }
        await flushPending()
        return done
    }

    /// «Otra fecha» del aviso de «Vista»: la vista que se acaba de marcar (`at`) pasa a `date`. false si no se pudo.
    @discardableResult
    public func redateViewing(kind: String, videoID: String, at: Date, to date: Date) async -> Bool {
        guard let target = TraktTarget(videoID: videoID, kind: kind) else { return false }
        let stamp = at.timeIntervalSince1970
        if pending.load().traktWatched.contains(where: { $0.target == target && abs($0.at - stamp) < 2 }) {
            await moveViewing(TraktViewing(id: 0, at: at), kind: kind, videoID: videoID, to: date)
            return true
        }
        guard let trakt, trakt.linked, let all = try? await trakt.viewings(target),
              let mine = all.min(by: { abs($0.at.timeIntervalSince1970 - stamp) < abs($1.at.timeIntervalSince1970 - stamp) }),
              abs(mine.at.timeIntervalSince1970 - stamp) < 12 * 3600 else { return false }
        await moveViewing(mine, kind: kind, videoID: videoID, to: date)
        return true
    }

    /// Borra varias vistas de una vez (las repetidas del historial): un solo envío a Trakt. Lo visto aquí no cambia: siempre
    /// queda la otra vista de cada una.
    public func removeViewings(_ ids: [Int]) async {
        pending.update { work in
            for id in ids where id != 0 && !work.traktViewingRemovals.contains(id) { work.traktViewingRemovals.append(id) }
        }
        await flushPending()
    }

    /// Tu historial de Trakt (página `page`, de 100 en 100), sin lo que ya borraste aquí. `full`: la página vino llena (hay más),
    /// contada antes de quitar nada.
    public func history(page: Int) async throws -> (entries: [TraktHistoryEntry], full: Bool) {
        guard let trakt, trakt.linked else { return ([], false) }
        let gone = pending.load().goneViewings
        let found = try await trakt.history(page: page)
        return (found.entries.filter { !gone.contains($0.id) }, found.full)
    }
}
