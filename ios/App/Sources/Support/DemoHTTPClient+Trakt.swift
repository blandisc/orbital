import Foundation
import OrbitalCore
import OrbitalModels

#if DEBUG
/// Trakt de mentira para el modo demostración: watchlist, listas, scrobble y el calendario de estrenos.
extension DemoHTTPClient {
    /// El calendario de Trakt de mentira: tres series que salen hoy, mañana y en tres días.
    func calendarDemo() -> HTTPResponse {
        func row(_ imdb: String, _ title: String, days: Double, hour: Double, season: Int, episode: Int, network: String) -> JSON {
            let when = Calendar.current.startOfDay(for: Date()).addingTimeInterval(days * 86_400 + hour * 3600)
            return ["first_aired": .string(StremioLibrary.iso(when.timeIntervalSince1970)),
                    "episode": ["season": .int(season), "number": .int(episode), "title": "Episodio de prueba"],
                    "show": ["title": .string(title), "year": 2022, "network": .string(network), "ids": ["imdb": .string(imdb), "trakt": 1]]]
        }
        let rows: JSON = .array([row("tt14452776", "The Bear", days: 0, hour: 20, season: 3, episode: 4, network: "FX"),
                                 row("tt11280740", "Severance", days: 1, hour: 21, season: 2, episode: 7, network: "Apple TV+"),
                                 row("tt0903747", "Breaking Bad", days: 3, hour: 19, season: 1, episode: 4, network: "AMC"),
                                 // Para el calendario del mes: dos el mismo día, tres otro día y unos que ya salieron.
                                 row("tt8649186", "Only Murders in the Building", days: 0, hour: 21, season: 5, episode: 8, network: "Hulu"),
                                 row("tt5753856", "Dark", days: 6, hour: 9, season: 1, episode: 2, network: "Netflix"),
                                 row("tt2085059", "Black Mirror", days: 6, hour: 10, season: 7, episode: 1, network: "Netflix"),
                                 row("tt11280740", "Severance", days: 6, hour: 21, season: 2, episode: 8, network: "Apple TV+"),
                                 row("tt14452776", "The Bear", days: -7, hour: 20, season: 3, episode: 3, network: "FX"),
                                 row("tt11280740", "Severance", days: -6, hour: 21, season: 2, episode: 6, network: "Apple TV+")])
        return HTTPResponse(status: 200, data: rows.serialized())
    }

    /// El año de cada título de la watchlist de mentira (Guardado decía «2022» en todos; PT23, 4 nov 2026).
    static let demoYears: [String: Int] = ["tt11280740": 2022, "tt15239678": 2024, "tt0903747": 2008, "tt0386676": 2005, "tt0816692": 2014,
                                           "tt1160419": 2021, "tt14452776": 2022, "tt1375666": 2010, "tt7366338": 2019, "tt5753856": 2017,
                                           "tt0068646": 1972]

    /// Lo público de Trakt (sin sesión) y MDBList, de mentira: «Lo más popular hoy», «Por género», la búsqueda y «Aprobadas
    /// por la crítica» salen de aquí sin tocar internet. Una búsqueda sin coincidencias contesta nil (cae a Cinemeta).
    static func publicDemo(_ url: URL) -> HTTPResponse? {
        let titles: [(imdb: String, title: String, year: Int, kind: String)] = [
            ("tt1160419", "Dune", 2021, "movie"), ("tt11280740", "Severance", 2022, "series"), ("tt15239678", "Dune: Part Two", 2024, "movie"),
            ("tt0903747", "Breaking Bad", 2008, "series"), ("tt0816692", "Interstellar", 2014, "movie"), ("tt14452776", "The Bear", 2022, "series"),
            ("tt1375666", "Inception", 2010, "movie"), ("tt7366338", "Chernobyl", 2019, "series"), ("tt0133093", "The Matrix", 1999, "movie"),
            ("tt0386676", "The Office", 2005, "series"), ("tt0068646", "The Godfather", 1972, "movie"), ("tt5753856", "Dark", 2017, "series")]
        func item(_ t: (imdb: String, title: String, year: Int, kind: String)) -> JSON {
            ["title": .string(t.title), "year": .int(t.year), "runtime": t.kind == "movie" ? 140 : 50, "ids": ["trakt": 1, "imdb": .string(t.imdb)]]
        }
        func json(_ value: JSON) -> HTTPResponse { HTTPResponse(status: 200, data: value.serialized()) }
        if url.host == "mdblist.com" {
            return json(.array(titles.filter { $0.kind == "movie" }.map { ["imdb_id": .string($0.imdb), "title": .string($0.title), "mediatype": "movie", "release_year": .int($0.year)] }))
        }
        guard url.host == "api.trakt.tv" else { return nil }
        let path = url.path, kind = path.hasPrefix("/movies/") ? "movie" : "series", key = kind == "movie" ? "movie" : "show"
        if path.hasSuffix("/trending") { return json(.array(titles.filter { $0.kind == kind }.map { ["watchers": 120, key: item($0)] })) }
        if path.hasSuffix("/popular") { return json(.array(titles.filter { $0.kind == kind }.reversed().map(item))) }
        if path.hasPrefix("/users/truckclancy/lists/") { return json(.array(titles.filter { $0.kind == "series" }.map { ["type": "show", "show": item($0)] })) }
        if path == "/search/movie,show" {
            let query = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value ?? "").lowercased()
            let found = titles.filter { $0.title.lowercased().contains(query) }
            guard !found.isEmpty else { return nil }
            return json(.array(found.map { $0.kind == "movie" ? ["type": "movie", "movie": item($0)] : ["type": "show", "show": item($0)] }))
        }
        return nil
    }

    /// Real-Debrid de mentira (`-demo-rd`): `GET /rest/1.0/user` con la cuenta que se pidió.
    static func realDebridDemo(_ url: URL) -> HTTPResponse? {
        // D4: canjear puntos (`-demo-rd-points`): contesta la demo, nada sale a Real-Debrid.
        if url.host == "api.real-debrid.com", url.path.hasSuffix("/settings/convertPoints"), Demo.realDebrid != nil {
            return HTTPResponse(status: Demo.rdPoints >= 1000 ? 204 : 503, data: Data())
        }
        guard url.host == "api.real-debrid.com", url.path.hasSuffix("/user"), let state = Demo.realDebrid else { return nil }
        let days: Double = switch state { case "soon": 3; case "expired": -2; case "free": -400; default: Double(state) ?? 143 }
        // `-demo-rd unreachable`: hay clave, pero Real-Debrid no contesta (para ver «No pude ver tu cuenta»).
        guard state != "unreachable" else { return HTTPResponse(status: 503, data: Data()) }
        guard state != "invalid", state != "revoked" else { return HTTPResponse(status: 401, data: JSON.object(["error": "bad_token", "error_code": 8]).serialized()) }
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(days * 86_400))
        let premium = state == "free" || days < 0 ? 0 : Int(days * 86_400)
        let user: JSON = ["id": 1, "username": "demo", "type": premium > 0 ? "premium" : "free", "premium": .int(premium), "expiration": .string(expires),
                          "points": .int(Demo.rdPoints)]
        return HTTPResponse(status: 200, data: user.serialized())
    }

    /// Los nombres de lo que hay en tus listas de mentira, y cuáles son series.
    static let demoTitles = ["tt7366338": "Chernobyl", "tt0068646": "The Godfather", "tt0111161": "The Shawshank Redemption", "tt0386676": "The Office",
                             "tt0108778": "Friends", "tt1591095": "Insidious", "tt15239678": "Dune: Part Two"]
    static let demoShows: Set<String> = ["tt7366338", "tt0386676", "tt0108778"]

    /// Los géneros y la calificación de Trakt de lo que hay en la watchlist de mentira.
    static let watchlistFacts: [String: (genres: [String], rating: Double)] = [
        "tt11280740": (["drama", "science-fiction"], 8.6), "tt15239678": (["science-fiction", "adventure"], 8.3), "tt0903747": (["drama", "crime"], 9.2),
        "tt0386676": (["comedy"], 8.6), "tt0816692": (["science-fiction", "drama"], 8.6), "tt1160419": (["science-fiction", "adventure"], 7.9),
        "tt14452776": (["comedy", "drama"], 8.4), "tt1375666": (["science-fiction", "action"], 8.4), "tt7366338": (["drama", "history"], 9.0),
        "tt5753856": (["science-fiction", "mystery"], 8.7), "tt0068646": (["crime", "drama"], 9.2),
    ]

    /// Trakt de mentira para «Guardar en…»: la watchlist, tus listas (tardan ~1,5 s, como la red) y lo que escribes en ellas.
    /// Una lista tuya de mentira: nombre, cuándo se creó y cambió (horas atrás), qué tiene, quién la ve y el orden a mano (G4-A:
    /// lo que no está en `rank` va después, por IMDb).
    struct DemoTraktList {
        var id: Int; var name: String; var created: Double; var updated: Double; var items: Set<String>
        var privacy = "private"; var rank: [String] = []
        var ordered: [String] { items.sorted { a, b in (rank.firstIndex(of: a) ?? .max, a) < (rank.firstIndex(of: b) ?? .max, b) } }
    }

    func traktDemo(_ request: HTTPRequest) async -> HTTPResponse? {
        let path = request.url.path, post = request.method == "POST"
        if let found = historyDemo(request) { return found }   // historial, VIP, notas y temporadas (O3-B)
        let body = request.body.flatMap(JSON.parse)
        func iso(_ hoursAgo: Double) -> JSON { .string(StremioLibrary.iso(Date().timeIntervalSince1970 - hoursAgo * 3600)) }
        func imdbs(_ body: JSON?) -> [String] { ((body?["movies"]?.array ?? []) + (body?["shows"]?.array ?? [])).compactMap { $0["ids"]?["imdb"]?.string } }
        func json(_ value: JSON, status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        if path == "/users/me/lists", !post {
            try? await Task.sleep(for: .milliseconds(1500))   // ds-exception: demora de red simulada (solo modo demo), para ver «Guardar en…» cargando
            return lock.withLock {
                json(.array(traktLists.map { l in
                    ["name": .string(l.name), "ids": ["trakt": .int(l.id), "slug": .string(l.name.lowercased())], "privacy": .string(l.privacy),
                     "item_count": .int(l.items.count), "created_at": iso(l.created), "updated_at": iso(l.updated)]
                }))
            }
        }
        if path == "/users/me/lists", post {
            return lock.withLock {
                let name = body?["name"]?.string ?? "Lista"
                traktLists.append(.init(id: nextTraktList, name: name, created: 0, updated: 0, items: []))
                defer { nextTraktList += 1 }
                return json(["name": .string(name), "ids": ["trakt": .int(nextTraktList)], "created_at": iso(0), "updated_at": iso(0)], status: 201)
            }
        }
        let parts = path.split(separator: "/").map(String.init)   // users · me · lists · {id} · items [· remove | reorder]
        // El renglón de cada título (lo que pide «ordenar a mano»): sale del número de su IMDb.
        func row(_ imdb: String) -> Int { Int(imdb.dropFirst(2)) ?? 0 }
        // G4-A: cambiar nombre o quién la ve (PUT) y borrar (DELETE).
        if parts.count == 4, parts[2] == "lists", let id = Int(parts[3]), request.method == "PUT" || request.method == "DELETE" {
            return lock.withLock {
                guard let i = traktLists.firstIndex(where: { $0.id == id }) else { return json([:], status: 404) }
                if request.method == "DELETE" { traktLists.remove(at: i); return json([:], status: 204) }
                if let name = body?["name"]?.string { traktLists[i].name = name }
                if let privacy = body?["privacy"]?.string { traktLists[i].privacy = privacy }
                return json(["name": .string(traktLists[i].name), "ids": ["trakt": .int(id)], "privacy": .string(traktLists[i].privacy)])
            }
        }
        if parts.count == 6, parts[2] == "lists", parts[5] == "reorder", let id = Int(parts[3]) {
            return lock.withLock {
                guard let i = traktLists.firstIndex(where: { $0.id == id }) else { return json([:], status: 404) }
                let rows = body?["rank"]?.array?.compactMap(\.intValue) ?? []
                traktLists[i].rank = rows.compactMap { r in traktLists[i].items.first { row($0) == r } }
                return json(["updated": .int(rows.count)])
            }
        }
        if path == "/sync/watchlist/reorder" {
            return lock.withLock {
                let rows = body?["rank"]?.array?.compactMap(\.intValue) ?? []
                traktWatchlist.sort { (rows.firstIndex(of: row($0.imdb)) ?? .max) < (rows.firstIndex(of: row($1.imdb)) ?? .max) }
                return json(["updated": .int(rows.count)])
            }
        }
        if parts.count >= 5, parts[2] == "lists", parts[4] == "items", let id = Int(parts[3]) {
            return lock.withLock {
                guard let i = traktLists.firstIndex(where: { $0.id == id }) else { return json([:], status: 404) }
                if post {
                    let ids = imdbs(body)
                    if parts.count == 6 { traktLists[i].items.subtract(ids) } else { traktLists[i].items.formUnion(ids) }
                    traktLists[i].updated = 0
                    return json(["added": [:]], status: 201)
                }
                // Con su nombre y su año (Biblioteca › Guardado las enseña; «Guardar en…» solo mira los IMDb).
                return json(.array(traktLists[i].ordered.map { imdb in
                    let kind = Self.demoShows.contains(imdb) ? "show" : "movie"
                    return ["id": .int(row(imdb)), "type": .string(kind), kind: ["title": .string(Self.demoTitles[imdb] ?? imdb), "year": 2020, "ids": ["imdb": .string(imdb), "trakt": 1]]]
                }))
            }
        }
        // Las series que viste (Ajustes › Avisos › Series que sigues) y seguir o dejar de seguir una (se acepta sin más).
        let shows = [("tt0386676", "The Office", 2), ("tt11280740", "Severance", 20), ("tt0903747", "Breaking Bad", 70),
                     ("tt14452776", "The Bear", 200), ("tt5753856", "Dark", 400), ("tt7366338", "Chernobyl", 900)]
        // Cuántos capítulos han salido y cuántos viste (Biblioteca › Guardado: «A medias» con su barra, «Vistas»).
        let episodes: [String: (aired: Int, seen: Int)] = ["tt0386676": (201, 27), "tt11280740": (19, 9), "tt0903747": (62, 62),
                                                           "tt14452776": (38, 10), "tt5753856": (26, 26), "tt7366338": (5, 5)]
        if path == "/sync/watched/shows" {
            return json(.array(shows.map { show in
                let count = episodes[show.0] ?? (1, 1)
                let seen: JSON = .array((1...max(1, count.seen)).map { ["number": .int($0)] })
                return ["last_watched_at": iso(Double(show.2)), "seasons": [["number": 1, "episodes": seen]],
                        "show": ["title": .string(show.1), "year": 2020, "aired_episodes": .int(count.aired), "ids": ["imdb": .string(show.0), "trakt": 1]]]
            }))
        }
        if path == "/sync/watched/movies" {   // Dune y El origen, vistas
            return json(.array(["tt1160419", "tt1375666"].map { ["last_watched_at": iso(100), "movie": ["ids": ["imdb": .string($0), "trakt": 1]]] }))
        }
        // Esconder una serie (SS1-A): `progress_watched` se recuerda (sale en «Escondidas»); el calendario se acepta sin más.
        if path == "/users/hidden/progress_watched", !post {
            return lock.withLock {
                json(.array(shows.filter { traktHidden.contains($0.0) }.map {
                    ["hidden_at": iso(1), "type": "show", "show": ["title": .string($0.1), "year": 2020, "ids": ["imdb": .string($0.0), "trakt": 1]]]
                }))
            }
        }
        if path.hasPrefix("/users/hidden/progress_watched"), post {
            lock.withLock { if path.hasSuffix("/remove") { traktHidden.subtract(imdbs(body)) } else { traktHidden.formUnion(imdbs(body)) } }
            return json(["added": [:]], status: 201)
        }
        if path.hasPrefix("/users/hidden/") { return json(["added": [:]], status: 201) }
        if path.hasPrefix("/sync/watchlist"), !post, Demo.savedEmpty { return json([]) }   // Guardado vacío (`-demo-saved-empty`)
        if path.hasPrefix("/sync/watchlist") {
            return lock.withLock {
                if post {
                    let ids = imdbs(body)
                    if path.hasSuffix("/remove") { traktWatchlist.removeAll { ids.contains($0.imdb) } }
                    else { for id in ids where !traktWatchlist.contains(where: { $0.imdb == id }) { traktWatchlist.insert((id, id, body?["shows"] != nil ? "show" : "movie", 0), at: 0) } }
                    return json(["added": [:]], status: 201)
                }
                return json(.array(traktWatchlist.map { w in
                    // Con géneros y calificación, como Trakt (`extended=full`): «Género» y «Calificación» del filtro tienen qué usar.
                    let facts = Self.watchlistFacts[w.imdb] ?? (["drama"], 7.5)
                    return ["id": .int(row(w.imdb)), "listed_at": iso(w.hoursAgo), "type": .string(w.kind),
                            w.kind: ["title": .string(w.title), "year": .int(Self.demoYears[w.imdb] ?? 2022), "genres": .array(facts.genres.map { .string($0) }), "rating": .double(facts.rating),
                                     "ids": ["imdb": .string(w.imdb), "trakt": 1]]]
                }))
            }
        }
        return nil
    }
}
#endif
