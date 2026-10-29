import Foundation

/// Qué avance se le manda a Trakt (en %), con lo que se aprendió en la prueba del 29 oct contra la cuenta real
/// (`docs/producto/desacoplar-stremio-iphone-2026-10-29.md` §5). **Las mismas reglas que la consola** (`orbital/scrobble.py`
/// `plan`, corte E):
///
/// - Nunca menos de 1 %: Trakt contesta 422 y no guarda nada (no se manda la pausa, el cierre ni el respaldo).
/// - Hasta que se da por visto, como mucho 79.9 %: desde el 80 % Trakt lo marca visto y borra tu punto para seguir.
///   Visto = el 90 % en películas; en episodios, los últimos 45–90 s; o los créditos («Siguiente episodio»).
/// - Ya visto, el avance real (y al menos 80 %, para que Trakt lo marque y borre el punto).
/// - Respaldo cada 5 minutos mientras suena: `start` y, 2 s después, `pause` (una pausa sola no mueve `paused_at`). Tras un
///   respaldo, la siguiente pausa o cierre van precedidos de otro `start`, por lo mismo.
public enum TraktProgressRule {
    public static let minimum = 1.0
    public static let cap = 79.9
    /// Desde aquí Trakt marca visto un cierre.
    public static let traktWatched = 80.0
    public static let backupEvery: TimeInterval = 300
    public static let backupGap: TimeInterval = 2

    /// ¿Ya cuenta como visto? En los créditos (`finished`) o como Stremio: el 90 % de una película, el último tramo de un episodio.
    public static func done(position: Double, duration: Double, kind: String?, finished: Bool) -> Bool {
        finished || StremioLibrary.finished(position: position, duration: duration, kind: kind)
    }

    /// El porcentaje que se manda; nil = no se manda nada (sin duración, o menos de 1 % en una pausa o un cierre).
    public static func percent(_ action: ScrobbleAction, position: Double, duration: Double, kind: String?, finished: Bool) -> Double? {
        guard duration > 0, duration.isFinite, position.isFinite else { return nil }
        let real = min(100, max(0, position / duration * 100))
        if done(position: position, duration: duration, kind: kind, finished: finished) { return max(real, traktWatched) }
        if action != .start && real < minimum { return nil }
        return min(real, cap)
    }
}

/// Cómo se juntan lo del teléfono y lo de Trakt, una regla por cosa (§4 de la propuesta):
/// - **Avance**: gana el más reciente por título. Si gana Trakt, su porcentaje se vuelve segundos con la duración conocida.
/// - **Visto**: se suma. Desmarcar es un acto explícito que viaja aparte (`/sync/history/remove`).
/// - **Mi lista**: espejo de la watchlist de Trakt, salvo lo que este teléfono aún no le manda.
public enum LibraryMerge {
    /// Lo que Trakt devuelve hasta este rato después de que este teléfono le mandó su avance es eco de lo mismo.
    public static let echoMargin: TimeInterval = 120
    /// Sin duración del archivo ni de la ficha: una película de 2 h o un episodio de 45 min (solo para pintar la barra).
    static let fallbackRuntime = ["movie": 7200.0, "series": 2700.0]

    static func make(_ metaID: String, kind: String, name: String) -> LibraryEntry {
        var entry = LibraryEntry(metaID: metaID, kind: kind, name: name)
        if metaID.hasPrefix("tt") { entry.poster = String(format: ForYou.metahubPoster, metaID) }
        return entry
    }

    /// Un avance a medias de Trakt (`/sync/playback`). Solo cambia algo si es más nuevo que lo de aquí.
    public static func playback(_ entry: LibraryEntry?, _ p: TraktPlayback) -> LibraryEntry? {
        let kind = p.target.isEpisode ? "series" : "movie"
        let metaID = p.target.imdb
        let videoID = p.target.isEpisode ? "\(metaID):\(p.target.season!):\(p.target.episode!)" : metaID
        let fraction = p.progress / 100
        guard fraction >= PlaybackRules.continueMinProgress else { return nil }
        let at = p.pausedAt.timeIntervalSince1970
        if let entry, at <= entry.localStamp { return nil }
        var e = entry ?? make(metaID, kind: kind, name: p.title)
        if e.name.isEmpty { e.name = p.title }
        // La duración exacta del mismo archivo que tenías aquí; si no, la de Trakt (o una aproximada) y se guarda la fracción.
        if e.videoID == videoID, e.duration > 0, e.fraction == nil, !e.nextUp {
            e.position = fraction * e.duration; e.fraction = nil
        } else {
            e.duration = p.runtime.map { Double($0) * 60 } ?? fallbackRuntime[kind] ?? 3600
            e.position = fraction * e.duration; e.fraction = fraction
        }
        e.videoID = videoID; e.nextUp = false; e.hiddenAt = nil; e.updatedAt = at
        return e
    }

    /// Cómo vas en una serie según Trakt: los episodios vistos se suman (salvo los que desmarcaste aquí y aún no llegan) y, si
    /// lo último lo viste en otro aparato después de lo de aquí, la serie pasa al episodio que sigue.
    public static func show(_ entry: LibraryEntry?, _ progress: TraktShowProgress, name: String, unmarked: Set<String> = []) -> LibraryEntry {
        var e = entry ?? make(progress.imdb, kind: "series", name: name)
        if e.name.isEmpty { e.name = name }
        e.seen.formUnion(progress.completed.map(progress.videoID).filter { !unmarked.contains($0) })
        if let at = progress.lastWatchedAt?.timeIntervalSince1970, at > e.localStamp, let last = progress.last {
            e.position = 0; e.duration = 0; e.fraction = nil; e.hiddenAt = nil; e.updatedAt = at
            if let next = progress.next { e.videoID = progress.videoID(next); e.nextUp = true }
            else { e.videoID = progress.videoID(last); e.nextUp = false }
        }
        return e
    }

    /// Una película vista en Trakt: queda vista y, si fue después de lo de aquí, sale de «Seguir viendo».
    public static func movieWatched(_ entry: LibraryEntry?, imdb: String, name: String, at: Date) -> LibraryEntry {
        var e = entry ?? make(imdb, kind: "movie", name: name)
        if e.name.isEmpty { e.name = name }
        e.seen.insert(imdb)
        if at.timeIntervalSince1970 > e.localStamp { e.finish(videoID: imdb, next: nil, at: at.timeIntervalSince1970) }
        return e
    }

    /// Mi lista = tu watchlist de Trakt. Lo que este teléfono aún no le manda (`pending`: imdb → entra o sale) manda sobre Trakt.
    /// Lo que no tiene IMDb (Trakt no lo conoce) se queda como está.
    public static func watchlist(_ entries: inout [String: LibraryEntry], trakt: [TraktEntry], pending: [String: Bool], now: Double) {
        let onTrakt = Dictionary(trakt.map { ($0.imdb, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, entry) in entries where id.hasPrefix("tt") {
            let want = pending[id] ?? (onTrakt[id] != nil)
            if entry.inList != want { entries[id]?.inList = want; entries[id]?.listedAt = want ? now : nil }
        }
        // Lo nuevo de Trakt entra en su orden (el más reciente primero): una marca por puesto para que el orden se conserve.
        for (rank, item) in trakt.enumerated() where entries[item.imdb] == nil && pending[item.imdb] != false {
            var e = make(item.imdb, kind: item.kind, name: item.title)
            e.inList = true; e.listedAt = now - Double(rank)
            entries[item.imdb] = e
        }
    }
}
