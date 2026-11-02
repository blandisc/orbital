import Foundation

/// Tus listas de Letterboxd en Explorar › Tus listas (Fernando, 1 nov 2026): las públicas de tu perfil y las que solo
/// venían en tu archivo de exportación (también las privadas). Cada película se cruza con su IMDb (su página en
/// Letterboxd, una vez: se recuerda).
extension ForYou {
    /// Dónde se guarda tu usuario (lo pone Ajustes › Cuentas) y las listas que trajo tu archivo.
    public static let letterboxdUserKey = "letterboxd-user", letterboxdArchiveListsKey = "letterboxd-archive-lists"
    /// El origen que dice el estante.
    public static let letterboxdSource = "Letterboxd"
    /// Cuántas películas de una lista se cruzan con su IMDb (cada una es una página la primera vez).
    static let letterboxdShelfLimit = 120, letterboxdConcurrency = 6

    /// Una lista guardada del archivo, con sus películas.
    public struct LetterboxdSavedList: Codable, Sendable, Equatable {
        public var list: LetterboxdList, films: [LetterboxdFilm]
        public init(list: LetterboxdList, films: [LetterboxdFilm]) { self.list = list; self.films = films }
    }

    var letterboxdUser: String? { kv.data(Self.letterboxdUserKey).map { String(decoding: $0, as: UTF8.self) }.flatMap { $0.isEmpty ? nil : $0 } }

    var archiveLists: [LetterboxdSavedList] {
        kv.data(Self.letterboxdArchiveListsKey).flatMap { try? JSONDecoder().decode([LetterboxdSavedList].self, from: $0) } ?? []
    }

    /// Los estantes de tus listas de Letterboxd (vacío sin conectar). Las públicas primero, como en tu perfil.
    public func letterboxdLists() async -> [ForYouList] {
        guard let user = letterboxdUser, let http else { return archiveLists.map { shelf($0.list) } }
        let letterboxd = Letterboxd(http: http, kv: kv)
        let published = (try? await remember("letterboxd:lists:\(user)", ttl: Self.mineTTL) { try await letterboxd.lists(user: user) }) ?? []
        let onlyInArchive = archiveLists.map(\.list).filter { saved in !published.contains { $0.slug == saved.slug } }
        return (published + onlyInArchive).map(shelf)
    }

    private func shelf(_ list: LetterboxdList) -> ForYouList {
        ForYouList(id: "lb:\(list.slug)", title: list.name, group: .mine, splitsKinds: false, source: Self.letterboxdSource,
                   // Solo se cruzan las primeras `letterboxdShelfLimit`: si la lista es más larga, se dice («120 de 300»).
                   meta: list.count.map { $0 > Self.letterboxdShelfLimit ? "\(Self.letterboxdShelfLimit) de \($0)" : "\($0)" } ?? "")
    }

    /// Las películas de una lista, ya con su IMDb y en su orden.
    func letterboxdItems(slug: String) async throws -> [Suggestion] {
        guard let http else { return [] }
        let letterboxd = Letterboxd(http: http, kv: kv)
        // La de tu perfil (en vivo) gana a la de tu archivo: antes, si la lista venía en el archivo, se quedaba esa copia aunque
        // la hubieras cambiado. El archivo es el respaldo (las privadas, o si Letterboxd no contesta).
        var films: [LetterboxdFilm] = []
        var liveError: Error?
        if let user = letterboxdUser {
            do { films = try await remember("letterboxd:list:\(user):\(slug)", ttl: Self.recsTTL) { try await letterboxd.listFilms(user: user, slug: slug) } }
            catch { liveError = error }
        }
        if films.isEmpty, let saved = archiveLists.first(where: { $0.list.slug == slug }) { films = saved.films }
        if films.isEmpty, let liveError { throw liveError }
        let wanted = Array(films.filter { !$0.slug.isEmpty }.prefix(Self.letterboxdShelfLimit))
        let reason = SuggestionReason.inList(Self.letterboxdSource)
        let matches = await withTaskGroup(of: (Int, LetterboxdMatch?).self) { group in
            var next = 0, out = [LetterboxdMatch?](repeating: nil, count: wanted.count)
            func add() { guard next < wanted.count else { return }; let i = next; next += 1; group.addTask { (i, await letterboxd.resolve(slug: wanted[i].slug)) } }
            for _ in 0..<Self.letterboxdConcurrency { add() }
            for await (i, m) in group { out[i] = m; add() }
            return out
        }
        var seen = Set<String>()
        return zip(wanted, matches).compactMap { film, match in
            guard let match, seen.insert(match.imdb).inserted else { return nil }
            return Suggestion(kind: match.kind, imdb: match.imdb, title: film.title, year: film.year,
                              poster: String(format: Self.metahubPoster, match.imdb), wide: String(format: Self.metahubBackground, match.imdb),
                              logo: String(format: Self.metahubLogo, match.imdb), reason: reason)
        }
    }
}

/// Las series que dejaste de seguir (Fernando, 1 nov 2026): no salen en tus estrenos ni te avisan. Se guardan aquí (al momento)
/// y en Trakt (oculta del calendario y del progreso).
extension ForYou {
    public static let unfollowedKey = "unfollowed-shows"
    public static func unfollowed(_ kv: KeyValueStore) -> Set<String> {
        Set(kv.data(unfollowedKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }
    public static func setUnfollowed(_ ids: Set<String>, kv: KeyValueStore) { kv.set(unfollowedKey, data: try? JSONEncoder().encode(ids.sorted())) }
}
