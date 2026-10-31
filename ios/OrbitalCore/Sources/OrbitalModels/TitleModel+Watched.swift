import Foundation
import OrbitalCore

/// Cuándo la viste (la hoja «¿Cuándo la viste?», como Trakt): ahora mismo, el día que salió, otro día o no sé cuándo.
public enum WatchedWhen: Equatable, Sendable {
    case now, release, day(Date), unknown
}

/// Qué marcas como visto desde la ficha: la película, un episodio, una temporada o la serie completa.
public enum WatchedScope: Hashable, Sendable, Identifiable {
    case movie, episode(String), season(Int), series
    public var id: String {
        switch self { case .movie: "movie"; case .episode(let v): "episode:\(v)"; case .season(let s): "season:\(s)"; case .series: "series" }
    }
}

extension TitleModel {
    /// Los videos que cubre (de una serie, solo los que ya salieron y sin los especiales al marcar la serie).
    public func videos(in scope: WatchedScope, now: Date = Date()) -> [String] {
        switch scope {
        case .movie: return [metaID]
        case .episode(let id): return [id]
        case .season(let s): return released(seasons.first { $0.season == s }?.episodes ?? [], now: now).map(\.id)
        case .series: return released(seasons.filter { !$0.isSpecials }.flatMap(\.episodes), now: now).map(\.id)
        }
    }

    private func released(_ episodes: [Episode], now: Date) -> [Episode] {
        episodes.filter { ($0.released.flatMap(Self.day) ?? .distantPast) <= now }
    }

    /// Ya está vista (la película, el episodio o todos los que ya salieron de la temporada o la serie).
    public func isWatched(_ scope: WatchedScope) -> Bool {
        let ids = videos(in: scope)
        return !ids.isEmpty && ids.allSatisfy(watched.contains)
    }

    /// El día que salió: el de la película o el de un episodio (nil si no se sabe).
    public func releaseDate(of videoID: String) -> Date? {
        if kind == "movie" { return Self.day(credits.released) }
        return seasons.lazy.flatMap(\.episodes).first { $0.id == videoID }?.released.flatMap(Self.day)
    }

    /// El rango de estrenos de lo que cubre («20 sep 2005» o, para varios, el primero y el último).
    public func releaseSpan(_ scope: WatchedScope) -> (first: Date, last: Date)? {
        let dates = videos(in: scope).compactMap(releaseDate(of:)).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return (first, last)
    }

    /// Los episodios anteriores a este que ya salieron y no has visto (Trakt pregunta si los marcas también).
    public func earlierUnwatched(than videoID: String) -> [String] {
        let all = seasons.filter { !$0.isSpecials }.flatMap(\.episodes)
        guard let at = all.firstIndex(where: { $0.id == videoID }) else { return [] }
        return released(Array(all[..<at]), now: Date()).map(\.id).filter { !watched.contains($0) }
    }

    /// Marca como visto lo que cubre `scope`, con la fecha elegida; `alsoEarlier`: también los episodios anteriores sin ver.
    /// «El día que salió» usa la fecha de cada uno (si no se sabe, ahora).
    public func markWatched(_ scope: WatchedScope, when: WatchedWhen, alsoEarlier: Bool = false) async {
        let all = videos(in: scope)
        var ids = all.count > 1 ? all.filter { !watched.contains($0) } : all   // de una temporada o serie, solo lo que falta
        if alsoEarlier, case .episode(let id) = scope { ids = earlierUnwatched(than: id) + ids }
        let now = Date()
        let dated = ids.map { id -> (id: String, at: Date) in
            switch when {
            case .now: (id, now)
            case .day(let d): (id, d)
            case .unknown: (id, Trakt.unknownDate)
            case .release: (id, min(releaseDate(of: id) ?? now, now))
            }
        }
        await services.watch.markWatched(kind: kind, metaID: metaID, videos: dated, name: originalTitle)
        await refreshState()
    }

    /// «La vi otra vez»: otra vista ahora (en Trakt queda una más).
    public func markWatchedAgain(_ scope: WatchedScope) async {
        let now = Date()
        await services.watch.markWatched(kind: kind, metaID: metaID, videos: videos(in: scope).map { ($0, now) }, name: originalTitle)
        await refreshState()
    }

    /// «Quitar de vistas»: sale de lo visto aquí y en Trakt.
    public func unmarkWatched(_ scope: WatchedScope) async {
        await services.watch.unmarkWatched(kind: kind, metaID: metaID, videoIDs: videos(in: scope).filter(watched.contains))
        await refreshState()
    }

    /// «2005-10-18» o «2005-10-18T00:00:00.000Z» → la fecha (nil si no se entiende).
    static func day(_ text: String) -> Date? {
        guard text.count >= 10 else { return nil }
        return try? Date(String(text.prefix(10)), strategy: .iso8601.year().month().day())
    }
}
