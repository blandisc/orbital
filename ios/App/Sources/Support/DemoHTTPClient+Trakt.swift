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

    /// Trakt de mentira para «Guardar en…»: la watchlist, tus listas (tardan ~1,5 s, como la red) y lo que escribes en ellas.
    func traktDemo(_ request: HTTPRequest) async -> HTTPResponse? {
        let path = request.url.path, post = request.method == "POST"
        let body = request.body.flatMap(JSON.parse)
        func iso(_ hoursAgo: Double) -> JSON { .string(StremioLibrary.iso(Date().timeIntervalSince1970 - hoursAgo * 3600)) }
        func imdbs(_ body: JSON?) -> [String] { ((body?["movies"]?.array ?? []) + (body?["shows"]?.array ?? [])).compactMap { $0["ids"]?["imdb"]?.string } }
        func json(_ value: JSON, status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        if path == "/users/me/lists", !post {
            try? await Task.sleep(for: .milliseconds(1500))   // ds-exception: demora de red simulada (solo modo demo), para ver «Guardar en…» cargando
            return lock.withLock {
                json(.array(traktLists.map { l in
                    ["name": .string(l.name), "ids": ["trakt": .int(l.id), "slug": .string(l.name.lowercased())], "privacy": "private",
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
        let parts = path.split(separator: "/").map(String.init)   // users · me · lists · {id} · items [· remove]
        if parts.count >= 5, parts[2] == "lists", parts[4] == "items", let id = Int(parts[3]) {
            return lock.withLock {
                guard let i = traktLists.firstIndex(where: { $0.id == id }) else { return json([:], status: 404) }
                if post {
                    let ids = imdbs(body)
                    if parts.count == 6 { traktLists[i].items.subtract(ids) } else { traktLists[i].items.formUnion(ids) }
                    traktLists[i].updated = 0
                    return json(["added": [:]], status: 201)
                }
                return json(.array(traktLists[i].items.sorted().map { ["type": "movie", "movie": ["ids": ["imdb": .string($0)]]] }))
            }
        }
        if path.hasPrefix("/sync/watchlist") {
            return lock.withLock {
                if post {
                    let ids = imdbs(body)
                    if path.hasSuffix("/remove") { traktWatchlist.removeAll { ids.contains($0.imdb) } }
                    else { for id in ids where !traktWatchlist.contains(where: { $0.imdb == id }) { traktWatchlist.insert((id, id, body?["shows"] != nil ? "show" : "movie", 0), at: 0) } }
                    return json(["added": [:]], status: 201)
                }
                return json(.array(traktWatchlist.map { w in
                    ["listed_at": iso(w.hoursAgo), "type": .string(w.kind),
                     w.kind: ["title": .string(w.title), "year": 2022, "ids": ["imdb": .string(w.imdb), "trakt": 1]]]
                }))
            }
        }
        return nil
    }
}
#endif
