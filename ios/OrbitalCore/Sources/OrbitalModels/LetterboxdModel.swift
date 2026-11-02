import Foundation
import OrbitalCore

/// Letterboxd en Orbital (Fernando, 1 nov 2026; propuesta en docs/producto/letterboxd/propuesta.html): solo leer.
/// Se conecta con tu usuario (tu diario público: lo más reciente) y, una vez, con tu archivo de exportación (todo). Lo que
/// llega se cruza con su IMDb y se guarda en el iPhone: «Tus reseñas» en Lo que ves, tu reseña en la ficha y «Pasarlas a
/// Trakt» para lo que solo anotaste en Letterboxd. Tus listas van en Explorar (`ForYou+Letterboxd`).
@MainActor
public final class LetterboxdModel: ObservableModel {
    public private(set) var user: String? { didSet { if oldValue != user { changed() } } }
    /// Todo lo que viste o calificaste, lo más reciente primero (el diario y el archivo juntos, sin repetir).
    public private(set) var entries: [LetterboxdEntry] = [] { didSet { if oldValue != entries { changed() } } }
    public private(set) var importedAt: Date? { didSet { if oldValue != importedAt { changed() } } }
    public private(set) var loading = false { didSet { if oldValue != loading { changed() } } }
    public private(set) var error: String? { didSet { if oldValue != error { changed() } } }

    private let services: Services
    private var refreshedAt: Date?
    static let cacheKey = "letterboxd-entries.v1", importedKey = "letterboxd-imported"
    /// El diario se vuelve a leer si pasó esto (al abrir Lo que ves o la app).
    static let ttl: TimeInterval = 30 * 60
    static let matchConcurrency = 6

    public init(_ services: Services) {
        self.services = services
        super.init()
        user = services.kv.data(ForYou.letterboxdUserKey).map { String(decoding: $0, as: UTF8.self) }.flatMap { $0.isEmpty ? nil : $0 }
        if let data = services.caches.data(Self.cacheKey), let saved = try? JSONDecoder().decode([LetterboxdEntry].self, from: data) { entries = saved }
        importedAt = services.kv.data(Self.importedKey).flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
    }

    public var connected: Bool { user != nil || importedAt != nil }
    private var letterboxd: Letterboxd { Letterboxd(http: services.http, kv: services.kv) }

    // MARK: lo que se enseña

    /// «Tus reseñas»: lo que calificaste o reseñaste, lo más reciente primero.
    public var reviews: [LetterboxdEntry] { entries.filter { $0.review != nil || $0.rating != nil } }
    /// Tu promedio de estrellas (0.5–5).
    public var averageRating: Double? {
        let all = entries.compactMap(\.rating)
        return all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
    }
    /// Lo tuyo de un título (para su ficha): la entrada más reciente con reseña o estrellas.
    public func entry(imdb: String) -> LetterboxdEntry? { entries.first { $0.imdb == imdb && ($0.review != nil || $0.rating != nil) } }

    // MARK: conectar

    /// Conecta con tu usuario: revisa que exista leyendo tu diario. Devuelve el motivo si no se pudo.
    public func connect(_ raw: String) async -> String? {
        guard let clean = Letterboxd.cleanUser(raw) else { return "Escribe tu usuario de Letterboxd (como aparece en tu perfil)" }
        loading = true
        defer { loading = false }
        do {
            let diary = try await letterboxd.diary(user: clean)
            user = clean
            services.kv.set(ForYou.letterboxdUserKey, data: Data(clean.utf8))
            await absorb(diary)
            refreshedAt = services.now()
            await services.forYou.clearCache(["letterboxd:"])
            return nil
        } catch let e as LetterboxdError { return e.description }
        catch { return "Letterboxd no contestó. Intenta de nuevo en un momento." }
    }

    /// Se olvida todo: el usuario, lo del archivo y lo guardado.
    public func disconnect() {
        user = nil; entries = []; importedAt = nil; error = nil
        for key in [ForYou.letterboxdUserKey, ForYou.letterboxdArchiveListsKey, Self.importedKey] { services.kv.set(key, data: nil) }
        services.caches.set(Self.cacheKey, data: nil)
        Task { await services.forYou.clearCache(["letterboxd:"]) }
    }

    /// Lo nuevo de tu diario (si pasó un rato) y lo que falte cruzar con su IMDb.
    public func load(force: Bool = false) async {
        guard let user else { return }
        if !force, let refreshedAt, services.now().timeIntervalSince(refreshedAt) < Self.ttl { return }
        do {
            let diary = try await letterboxd.diary(user: user)
            refreshedAt = services.now()
            error = nil
            await absorb(diary)
        } catch {
            if Task.isCancelled { return }
            self.error = entries.isEmpty ? "No pude leer tu diario de Letterboxd" : nil   // con algo guardado, eso se enseña
        }
    }

    /// Tu archivo de exportación (el .zip o sus CSV). Devuelve el motivo si no se pudo.
    public func importArchive(_ files: [(name: String, data: Data)]) async -> String? {
        loading = true
        defer { loading = false }
        let archive: LetterboxdArchive
        do { archive = try LetterboxdArchive.read(files: files) } catch { return "\(error)" }
        let lists = archive.lists.map { ForYou.LetterboxdSavedList(list: $0.list, films: $0.films) }
        services.kv.set(ForYou.letterboxdArchiveListsKey, data: try? JSONEncoder().encode(lists))
        let now = services.now()
        importedAt = now
        services.kv.set(Self.importedKey, data: try? JSONEncoder().encode(now))
        await absorb(archive.entries)
        await services.forYou.clearCache(["letterboxd:"])
        return nil
    }

    /// Junta lo que llegó con lo guardado (lo del diario gana: trae el código de TMDB) y lo cruza con su IMDb.
    private func absorb(_ found: [LetterboxdEntry]) async {
        var merged = entries
        for entry in found {
            if let i = merged.firstIndex(where: { $0.id == entry.id || Self.same($0, entry) }) {
                var kept = merged[i]
                kept.tmdbID = kept.tmdbID ?? entry.tmdbID; kept.slug = kept.slug ?? entry.slug
                kept.rating = entry.rating ?? kept.rating; kept.review = entry.review ?? kept.review
                kept.liked = kept.liked || entry.liked; kept.rewatch = kept.rewatch || entry.rewatch
                kept.watched = kept.watched ?? entry.watched
                merged[i] = kept
            } else { merged.append(entry) }
        }
        merged.sort { ($0.watched ?? .distantPast) > ($1.watched ?? .distantPast) }
        entries = merged
        await matchIMDb()
        save()
    }

    /// La misma película el mismo día (o, sin fecha en alguna, la misma película).
    static func same(_ a: LetterboxdEntry, _ b: LetterboxdEntry) -> Bool {
        guard a.title.caseInsensitiveCompare(b.title) == .orderedSame, a.year == b.year else { return false }
        guard let da = a.watched, let db = b.watched else { return a.watched == nil && b.watched == nil }
        return Calendar(identifier: .gregorian).isDate(da, inSameDayAs: db)
    }

    /// El IMDb de lo que aún no lo tiene: por su código de TMDB (el diario), su página en Letterboxd o su título y año.
    private func matchIMDb() async {
        let missing = entries.indices.filter { entries[$0].imdb == nil }
        guard !missing.isEmpty else { return }
        let tmdb = services.tmdb, letterboxd = letterboxd, kv = services.kv
        let pending = missing.map { entries[$0] }
        let found = await withTaskGroup(of: (Int, LetterboxdMatch?).self) { group in
            var next = 0, out: [Int: LetterboxdMatch] = [:]
            func add() {
                guard next < pending.count else { return }
                let i = next, e = pending[i]
                next += 1
                group.addTask { (i, await Self.match(e, tmdb: tmdb, letterboxd: letterboxd, kv: kv)) }
            }
            for _ in 0..<Self.matchConcurrency { add() }
            for await (i, m) in group { if let m { out[i] = m }; add() }
            return out
        }
        for (i, match) in found {
            let index = missing[i]
            guard entries.indices.contains(index), entries[index].imdb == nil else { continue }
            entries[index].imdb = match.imdb; entries[index].kind = match.kind; entries[index].tmdbID = entries[index].tmdbID ?? match.tmdbID
        }
    }

    nonisolated static func match(_ e: LetterboxdEntry, tmdb: Tmdb, letterboxd: Letterboxd, kv: KeyValueStore) async -> LetterboxdMatch? {
        let key = "lb-match.\(e.title.lowercased())|\(e.year ?? 0)"
        if let saved = kv.data(key), let m = try? JSONDecoder().decode(LetterboxdMatch.self, from: saved) { return m }
        var found: LetterboxdMatch?
        if tmdb.configured, let id = e.tmdbID, let imdb = try? await tmdb.details(kind: "movie", tmdbID: id).imdb {
            found = LetterboxdMatch(imdb: imdb, kind: "movie", tmdbID: id)
        }
        if found == nil, let slug = e.slug { found = await letterboxd.resolve(slug: slug) }
        if found == nil, tmdb.configured, let id = try? await tmdb.searchMovieID(title: e.title, year: e.year),
           let imdb = try? await tmdb.details(kind: "movie", tmdbID: id).imdb {
            found = LetterboxdMatch(imdb: imdb, kind: "movie", tmdbID: id)
        }
        if let found { kv.set(key, data: try? JSONEncoder().encode(found)) }
        return found
    }

    private func save() {
        let saved = entries
        services.caches.set(Self.cacheKey) { try? JSONEncoder().encode(saved) }
    }

    // MARK: pasar a Trakt

    /// Lo que viste en Letterboxd y Trakt no tiene (películas, con su IMDb). `watched`: lo visto en Trakt.
    public func missingInTrakt(watched: Set<String>) -> [LetterboxdEntry] {
        var seen = Set<String>()
        return entries.filter { e in
            guard let imdb = e.imdb, e.kind == "movie", !watched.contains(imdb), seen.insert(imdb).inserted else { return false }
            return true
        }
    }

    /// Las pasa a Trakt: al historial con el día que las viste («no sé cuándo» si no lo dice) y con tus estrellas.
    /// Devuelve cuántas pasaron (nil si Trakt no aceptó).
    public func passToTrakt(_ items: [LetterboxdEntry]) async -> Int? {
        guard let trakt = services.trakt, trakt.linked else { return nil }
        let valid = items.filter { $0.imdb != nil }
        do {
            try await trakt.addToHistory(valid.map { (TraktTarget(imdb: $0.imdb!), $0.watched ?? Trakt.unknownDate) })
            for e in valid where e.traktRating != nil { try? await trakt.setRating(imdb: e.imdb!, series: false, rating: e.traktRating) }
            return valid.count
        } catch { return nil }
    }
}
