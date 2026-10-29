import Foundation

/// Trae de Trakt lo que cambió en tus otros aparatos y lo junta con lo del teléfono (`LibraryMerge`). Primero pregunta
/// `/sync/last_activities` (una llamada chica): si nada cambió desde la última vez, no baja nada más. Lo de aquí sube antes
/// (`WatchService.flushPending`, `TraktOutbox.flush`), así lo que acabas de hacer no regresa como estaba.
public actor LibrarySync {
    private let trakt: Trakt?
    private let library: LocalLibrary
    private let kv: KeyValueStore
    private let outbox: TraktOutbox
    private let pending: PendingStore
    private let clock: @Sendable () -> Date
    static let stampsKey = "library-sync-stamps"
    /// Cuántas series se revisan a la vez (las que viste más recientemente).
    static let showsPerPull = 30
    private var running: Task<Bool, Never>?

    public init(trakt: Trakt?, library: LocalLibrary, kv: KeyValueStore, outbox: TraktOutbox, pending: PendingStore,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.trakt = trakt; self.library = library; self.kv = kv; self.outbox = outbox; self.pending = pending; self.clock = clock
    }

    /// Lo de la última vez que se leyó de Trakt.
    var stamps: TraktActivities {
        kv.data(Self.stampsKey).flatMap { try? JSONDecoder().decode(TraktActivities.self, from: $0) } ?? TraktActivities()
    }

    /// Al conectar otra cuenta de Trakt: se vuelve a leer todo.
    public func forget() { kv.set(Self.stampsKey, data: nil) }

    /// Trae lo que cambió. `force`: todo, aunque las marcas digan que no cambió nada (deslizar hacia abajo). Devuelve si cambió
    /// algo en el teléfono. Una a la vez: la que llega mientras otra corre espera a esa.
    @discardableResult
    public func pull(force: Bool = false) async -> Bool {
        if let running { return await running.value }
        let task = Task { await self.pullOnce(force: force) }
        running = task
        defer { running = nil }
        return await task.value
    }

    private func pullOnce(force: Bool) async -> Bool {
        guard let trakt, trakt.linked, let now = try? await trakt.activities() else { return false }
        var saved = stamps
        let before = library.all
        if force || now.watched != saved.watched || now.watched == nil {
            if await pullWatched(trakt, since: force ? nil : saved.watched) { saved.watched = now.watched }
        }
        if force || now.playback != saved.playback || now.playback == nil {
            if await pullPlayback(trakt) { saved.playback = now.playback }
        }
        if force || now.watchlist != saved.watchlist || now.watchlist == nil {
            if await pullWatchlist(trakt) { saved.watchlist = now.watchlist }
        }
        kv.set(Self.stampsKey, data: try? JSONEncoder().encode(saved))
        let changed = library.all.sorted { $0.metaID < $1.metaID } != before.sorted { $0.metaID < $1.metaID }
        if changed { NotificationCenter.default.post(name: LocalLibrary.changed, object: nil) }
        return changed
    }

    /// Las series y películas vistas desde `since` (la primera vez, las recientes): episodios vistos y el que sigue.
    private func pullWatched(_ trakt: Trakt, since: String?) async -> Bool {
        guard let shows = try? await trakt.watchedTitles(kind: "series"), let movies = try? await trakt.watchedTitles(kind: "movie") else { return false }
        let from = since.flatMap(TraktParsing.date) ?? clock().addingTimeInterval(-StremioLibrary.returnDays * 86400)
        let recent = Array(shows.filter { $0.lastWatchedAt > from }.sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(Self.showsPerPull))
        let progress = await withTaskGroup(of: (TraktWatchedTitle, TraktShowProgress?).self) { group in
            for show in recent {
                group.addTask { (show, try? await trakt.showProgress(show.traktID.map(String.init) ?? show.imdb, imdb: show.imdb)) }
            }
            var out: [(TraktWatchedTitle, TraktShowProgress)] = []
            for await (show, found) in group { if let found { out.append((show, found)) } }
            return out
        }
        let unmarked = Set(pending.load().traktUnwatched.map { t in t.isEpisode ? "\(t.imdb):\(t.season!):\(t.episode!)" : t.imdb })
        library.batch { entries in
            for (show, found) in progress { entries[show.imdb] = LibraryMerge.show(entries[show.imdb], found, name: show.title, unmarked: unmarked) }
            // Las películas: todas la primera vez (solo marca de visto), luego solo las nuevas.
            for movie in movies where (since == nil || movie.lastWatchedAt > from) && !unmarked.contains(movie.imdb) {
                entries[movie.imdb] = LibraryMerge.movieWatched(entries[movie.imdb], imdb: movie.imdb, name: movie.title, at: movie.lastWatchedAt)
            }
        }
        return true
    }

    /// Lo que dejaste a medias en otro aparato (`/sync/playback`): gana lo más reciente por título.
    private func pullPlayback(_ trakt: Trakt) async -> Bool {
        guard let items = try? await trakt.playback(fresh: true) else { return false }
        library.batch { entries in
            for item in items.sorted(by: { $0.pausedAt < $1.pausedAt }) {
                if let merged = LibraryMerge.playback(entries[item.target.imdb], item) { entries[item.target.imdb] = merged }
            }
        }
        return true
    }

    /// Mi lista = tu watchlist de Trakt (lo que este teléfono aún no le manda, manda).
    private func pullWatchlist(_ trakt: Trakt) async -> Bool {
        guard let list = try? await trakt.watchlist() else { return false }
        var waiting: [String: Bool] = [:]
        for item in outbox.pending where item.target == TraktOutbox.watchlist { waiting[item.imdb] = item.add }
        let now = clock().timeIntervalSince1970
        library.batch { LibraryMerge.watchlist(&$0, trakt: list, pending: waiting, now: now) }
        return true
    }

    /// Cómo vas en una serie (al abrir su ficha): sus episodios vistos y el que sigue, aunque no esté entre las recientes.
    public func pullShow(imdb: String, name: String) async {
        guard let trakt, trakt.linked, Trakt.isIMDb(imdb), let found = try? await trakt.showProgress(imdb, imdb: imdb) else { return }
        let unmarked = Set(pending.load().traktUnwatched.map { t in t.isEpisode ? "\(t.imdb):\(t.season!):\(t.episode!)" : t.imdb })
        let before = library.entry(imdb)
        // Una serie que nunca viste no se agrega a la biblioteca.
        guard before != nil || !found.completed.isEmpty else { return }
        let after = LibraryMerge.show(before, found, name: name, unmarked: unmarked)
        guard after != before else { return }
        library.update(imdb, make: { after }) { $0 = after }
        NotificationCenter.default.post(name: LocalLibrary.changed, object: nil)
    }
}
