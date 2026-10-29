import Foundation

/// «Para ti» tomado de tu Orbital (la consola), por el puerto público: misma curaduría, misma caché que ve la TV.
/// Convierte lo que contesta `/api/foryou*` en los mismos tipos que usa `ForYou` (local), para que la pantalla
/// no tenga que saber de dónde vino cada sugerencia. Si la consola no contesta, quien llama decide caer a `ForYou`.
public actor RemoteForYou {
    private let remote: @Sendable () -> OrbitalRemote
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, value: Any)] = [:]
    /// Título y marca de cada lista del último `lists()`, para ponerle nombre a sus sugerencias (watchlist de Trakt,
    /// plataforma…) sin tener que volver a pedir el overview.
    private var listInfo: [String: (title: String, brand: String?)] = [:]

    public init(remote: @escaping @Sendable () -> OrbitalRemote, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.remote = remote; self.clock = clock
    }

    public func clearCache() { cache.removeAll() }

    /// Lo que ya se está pidiendo: el mosaico y las listas salen del mismo overview y se piden a la vez; sin esto salían
    /// dos peticiones idénticas a la consola (y bastaba que una tardara para caer a las listas del iPhone).
    private var inFlight: [String: Task<JSON, Error>] = [:]

    private func remember(_ key: String, ttl: TimeInterval, _ load: @escaping @Sendable () async throws -> JSON) async throws -> JSON {
        if let hit = cache[key], clock() < hit.expires, let value = hit.value as? JSON { return value }
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await load() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let value = try await task.value
        cache[key] = (clock().addingTimeInterval(ttl), value)
        return value
    }

    // MARK: listas disponibles
    public func lists() async throws -> [ForYouList] {
        let overview = try await remember("overview", ttl: ForYou.mineTTL) { try await self.fetchOverview() }
        let rows = overview["lists"]?.array ?? []
        var out: [ForYouList] = []
        for row in rows {
            // Las listas de juegos (tus juegos, RAWG) son de la consola: en el iPhone no se piden.
            guard let id = row["id"]?.string, row["group"]?.string != "games" else { continue }
            let title = row["title"]?.string ?? ""
            let brand = row["brand"]?.string
            listInfo[id] = (title, brand)
            // La consola todavía dice «Stremio» en lo popular de Cinemeta y en los catálogos de complementos: en el iPhone
            // lo primero va sin sello y lo segundo es «Complemento».
            var source = row["source"]?.string ?? ""
            if source == "Stremio" { source = id == "cinemeta" ? "" : ForYouList.addonSource }
            out.append(ForYouList(id: id, title: title, group: Self.group(id: id, brand: brand), brand: brand,
                                   logo: row["logo"]?.string, splitsKinds: row["split"]?.bool ?? false,
                                   source: source, meta: row["meta"]?.string ?? ""))
        }
        return out
    }

    private static func group(id: String, brand: String?) -> ForYouGroup {
        if brand != nil { return .platforms }
        if id == "watchlist" || id == "mine" || id == "mylist" || id == "continue" || id.hasPrefix("list:") { return .mine }
        return .discover
    }

    // MARK: contenido de una lista
    public func items(listID: String, kind: String? = nil) async throws -> [Suggestion] {
        let kind = kind == "movie" ? "movie" : "series"
        let json = try await fetch(listID: listID, kind: kind)
        let rows = json["items"]?.array ?? []
        return rows.compactMap { suggestion($0, listID: listID) }
    }

    private func fetch(listID: String, kind: String) async throws -> JSON {
        try await remember("list:\(listID):\(kind)", ttl: ForYou.recsTTL) {
            guard let json = try await self.remote().foryouList(id: listID, kind: kind) else { throw OrbitalRemote.Failure.unreachable }
            return json
        }
    }

    private func fetchOverview() async throws -> JSON {
        guard let json = try await remote().foryouOverview() else { throw OrbitalRemote.Failure.unreachable }
        return json
    }

    private func suggestion(_ row: JSON, listID: String) -> Suggestion? {
        guard let kind = row["kind"]?.string, kind == "movie" || kind == "series",
              let imdb = row["meta_id"]?.string, !imdb.isEmpty, let title = row["title"]?.string else { return nil }
        var s = Suggestion(kind: kind, imdb: imdb, title: title, year: row["year"]?.intValue, runtime: nil,
                           overview: row["overview"]?.string ?? "", poster: row["image"]?.string ?? "", wide: row["hero"]?.string ?? "",
                           logo: row["logo"]?.string.flatMap { $0.isEmpty ? nil : $0 }, reason: reason(listID: listID, why: row["why"]?.string), next: Self.nextFrom(row),
                           rank: row["rank"]?.intValue)
        // El Top 10 real de la TV (`chart:*`, `jw:*`): cuánto se movió y si es nuevo.
        // Género y duración (minutos), si la consola los manda: «Decide por mí» no tiene que pedirlos a Cinemeta.
        s.genres = (row["genres"]?.array ?? []).compactMap(\.string)
        s.runtime = row["runtime"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
        s.traktRating = row["rating"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
        s.movement = row["movement"]?.intValue
        s.isNew = row["new"]?.bool ?? false
        return s
    }

    /// La consola ya manda el motivo en español («Recomendada», «En tendencia», «En Netflix»…): se traduce de
    /// vuelta al `SuggestionReason` que usa la pantalla, para que se vea igual venga de donde venga.
    private func reason(listID: String, why: String?) -> SuggestionReason {
        switch why {
        case "Sigues viéndola": return .watching
        case "En tu watchlist", "En tu lista": return .inWatchlist   // «En tu lista» es el nombre de antes en la TV
        case "Recomendada": return .recommended
        case "En tendencia": return .trending
        case "Popular": return .popular
        default: break
        }
        if let why {
            if why.hasPrefix("En «"), why.hasSuffix("»") { return .inList(String(why.dropFirst(4).dropLast())) }
            if why == "En una de tus listas" { return .inList(listInfo[listID]?.title ?? "") }
            if why.hasPrefix("En ") { return .onPlatform(String(why.dropFirst(3))) }
            return .console(why)   // «Seguir viendo», «Sale hoy», «En tu watchlist»…: tal cual, como en la TV
        }
        return .popular
    }

    /// `video_id` trae «tt0386676:2:5» cuando hay episodio en curso (si no, la consola no manda «episode»).
    private static func nextFrom(_ row: JSON) -> (season: Int, episode: Int)? {
        guard row["episode"]?.string != nil, let videoID = row["video_id"]?.string else { return nil }
        let parts = videoID.split(separator: ":")
        guard parts.count == 3, let season = Int(parts[1]), let episode = Int(parts[2]) else { return nil }
        return (season, episode)
    }

    // MARK: mosaico
    public func mosaic() async throws -> [Suggestion] {
        let overview = try await remember("overview", ttl: ForYou.mineTTL) { try await self.fetchOverview() }
        let rows = overview["mosaic"]?.array ?? []
        // El mosaico ya llega sin juegos (filtrado en la consola); por si acaso, se vuelve a filtrar aquí.
        return rows.compactMap { $0["kind"]?.string == "game" ? nil : suggestion($0, listID: "") }
    }

    // MARK: watchlist (para la etiqueta «En tu lista»)
    public func watchlistKeys() async throws -> Set<String> {
        Set(try await items(listID: "watchlist").map(\.imdb))
    }

    // MARK: «No me interesa»
    public func dismiss(_ imdb: String) async {
        try? await remote().foryouDismiss(key: "video:\(imdb)")
    }
}
