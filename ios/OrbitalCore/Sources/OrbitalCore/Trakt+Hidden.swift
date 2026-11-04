import Foundation

/// Una serie escondida en Trakt (`/users/hidden/progress_watched`): ya no sale en tu progreso, ni en tus estrenos, ni en
/// «Sigue viendo». Lo que viste se queda (SS1-A, Fernando, 3 nov 2026: «Vamos con SS1A»).
public struct TraktHiddenShow: Sendable, Equatable {
    public var imdb: String
    public var traktID: Int?
    public var title: String
    public init(imdb: String, traktID: Int? = nil, title: String) { self.imdb = imdb; self.traktID = traktID; self.title = title }
}

extension Trakt {
    /// Las secciones de Trakt donde se esconde una serie: «Esconder» usa las dos; el interruptor de «Series que sigues», también
    /// (por eso, para Orbital, la escondida es la que está en `progress_watched` y no la apagaste aquí: `ForYou.hiddenFrom`).
    public static let hiddenSections = ["calendar", "progress_watched"]

    /// Las series que escondiste en Trakt (desde cualquier aparato o desde trakt.tv).
    public func hiddenShows() async throws -> [TraktHiddenShow] {
        let rows = try await get("/users/hidden/progress_watched", [("type", "show"), ("limit", "1000")])?.array ?? []
        return rows.compactMap { row in
            guard let show = row["show"], let imdb = show["ids"]?["imdb"]?.string, Trakt.isIMDb(imdb) else { return nil }
            return TraktHiddenShow(imdb: imdb, traktID: show["ids"]?["trakt"]?.intValue, title: show["title"]?.string ?? "")
        }
    }

    /// Esconde una serie en esas secciones de Trakt (o la vuelve a mostrar). Lo que viste no se toca.
    public func setHidden(imdb: String, hidden: Bool, sections: [String] = Trakt.hiddenSections) async throws {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        let body: JSON = ["shows": [["ids": ["imdb": .string(imdb)]]]]
        for section in sections {
            let (status, _) = try await write("/users/hidden/\(section)\(hidden ? "" : "/remove")", body)
            guard status == 200 || status == 201 || status == 204 else { throw TraktError.http(status) }
        }
    }
}

/// Las series escondidas (SS1-A): no salen en «Series que sigues», en tus estrenos, en «Sigue viendo» ni en los avisos. Se
/// guardan aquí (al momento) y en Trakt, que es quien manda cuando contesta.
extension ForYou {
    public static let hiddenKey = "hidden-shows"
    public static func hidden(_ kv: KeyValueStore) -> Set<String> {
        Set(kv.data(hiddenKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }
    public static func setHidden(_ ids: Set<String>, kv: KeyValueStore) { kv.set(hiddenKey, data: try? JSONEncoder().encode(ids.sorted())) }

    /// Las escondidas según Trakt: lo que está en su `progress_watched`, menos las que solo apagaste con el interruptor en
    /// este iPhone (ese también las oculta allá, pero siguen en tu lista).
    public static func hiddenFrom(trakt: [String], kv: KeyValueStore) -> Set<String> {
        let mine = hidden(kv)
        let switchedOff = unfollowed(kv).subtracting(mine)
        return Set(trakt).subtracting(switchedOff)
    }
}
