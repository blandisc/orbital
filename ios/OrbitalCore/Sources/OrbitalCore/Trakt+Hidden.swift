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
    /// «La dejé» (G1-A, 9 nov 2026): además, la sección «dejadas» de Trakt (`/users/hidden/dropped`, solo series), para que
    /// trakt.tv también la vea como dejada.
    public static let droppedSections = hiddenSections + ["dropped"]

    /// Las series que escondiste en Trakt (desde cualquier aparato o desde trakt.tv).
    public func hiddenShows() async throws -> [TraktHiddenShow] {
        async let dropped = try? get("/users/hidden/dropped", [("type", "show"), ("limit", "1000")])?.array
        let hidden = try await get("/users/hidden/progress_watched", [("type", "show"), ("limit", "1000")])?.array ?? []
        // Las que dejaste en trakt.tv («Drop») también cuentan, aunque no estén escondidas del progreso.
        var seen = Set<String>()
        return (hidden + (await dropped ?? [])).compactMap { row -> TraktHiddenShow? in
            guard let show = row["show"], let imdb = show["ids"]?["imdb"]?.string, Trakt.isIMDb(imdb), seen.insert(imdb).inserted else { return nil }
            return TraktHiddenShow(imdb: imdb, traktID: show["ids"]?["trakt"]?.intValue, title: show["title"]?.string ?? "")
        }
    }

    /// Esconde una serie en esas secciones de Trakt (o la vuelve a mostrar). Lo que viste no se toca.
    public func setHidden(imdb: String, hidden: Bool, sections: [String] = Trakt.hiddenSections) async throws {
        try await setHidden(imdbs: [imdb], hidden: hidden, sections: sections)
    }

    /// Varias series a la vez (elegir varias › «Las dejé»): un envío por sección, no por serie.
    public func setHidden(imdbs: [String], hidden: Bool, sections: [String] = Trakt.hiddenSections) async throws {
        let valid = imdbs.filter(Self.isIMDb)
        guard !valid.isEmpty else { throw TraktError.invalid("Título inválido") }
        let body: JSON = ["shows": .array(valid.map { ["ids": ["imdb": .string($0)]] })]
        for section in sections {   // `write` ya las espacia un segundo (límite de Trakt)
            let (status, _) = try await write("/users/hidden/\(section)\(hidden ? "" : "/remove")", body)
            guard status == 200 || status == 201 || status == 204 else {
                if section == "dropped", status != 429, status < 500 { continue }   // «dejadas» es extra: si Trakt no la acepta, lo demás ya quedó
                throw TraktError.http(status)
            }
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
    /// `pending`: lo que escondiste o mostraste sin internet y Trakt aún no recibe (eso manda).
    public static func hiddenFrom(trakt: [String], kv: KeyValueStore, pending: [String: Bool] = [:]) -> Set<String> {
        let mine = hidden(kv)
        let switchedOff = unfollowed(kv).subtracting(mine)
        var result = Set(trakt).subtracting(switchedOff)
        for (imdb, hide) in pending { if hide { result.insert(imdb) } else { result.remove(imdb) } }
        return result
    }
}
