import Foundation
import OrbitalCore

#if DEBUG   // solo la demo: DemoHTTPClient no existe en la versión del iPhone

/// Tu historial de Trakt de mentira (`-demo-trakt`, gestor ola 3, O3-B): cada vez que viste algo, con su id para borrarla;
/// Dune vista dos veces el mismo día (la tele y el iPhone a la vez: una «repetida»), las notas (con `-demo-vip`, en Trakt) y
/// las estrellas de temporada. Lo que borras, agregas o escribes se recuerda mientras la app siga abierta.
extension DemoHTTPClient {
    struct DemoViewing { var id: Int; var imdb: String; var hoursAgo: Double; var season: Int? = nil; var episode: Int? = nil }

    nonisolated(unsafe) static var demoHistory: [DemoViewing] = [
        .init(id: 9001, imdb: "tt1160419", hoursAgo: 100), .init(id: 9002, imdb: "tt1160419", hoursAgo: 99.8),   // la repetida
        .init(id: 9003, imdb: "tt1160419", hoursAgo: 24 * 400), .init(id: 9004, imdb: "tt1375666", hoursAgo: 100),
        .init(id: 9005, imdb: "tt0386676", hoursAgo: 2, season: 1, episode: 2), .init(id: 9006, imdb: "tt0386676", hoursAgo: 26, season: 1, episode: 1),
        .init(id: 9007, imdb: "tt7366338", hoursAgo: 900, season: 1, episode: 5),
    ]
    nonisolated(unsafe) static var demoNextViewing = 9100
    nonisolated(unsafe) static var demoNotes: [String: (id: Int, text: String, show: Bool)] = [:]
    static let historyLock = NSLock()

    static let historyNames = ["tt1160419": "Dune", "tt1375666": "Inception", "tt0386676": "The Office", "tt7366338": "Chernobyl",
                               "tt0816692": "Interstellar", "tt15239678": "Dune: Part Two", "tt0133093": "The Matrix", "tt0068646": "The Godfather"]

    func historyDemo(_ request: HTTPRequest) -> HTTPResponse? {
        let path = request.url.path, method = request.method
        let body = request.body.flatMap(JSON.parse)
        func json(_ value: JSON, status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        func iso(_ hoursAgo: Double) -> JSON { .string(StremioLibrary.iso(Date().timeIntervalSince1970 - hoursAgo * 3600)) }
        func ids(_ imdb: String) -> JSON { ["imdb": .string(imdb), "trakt": .int(Int(imdb.dropFirst(2)) ?? 0)] }
        func row(_ v: DemoViewing) -> JSON {
            let name = JSON.string(Self.historyNames[v.imdb] ?? v.imdb)
            if let s = v.season, let e = v.episode {
                return ["id": .int(v.id), "watched_at": iso(v.hoursAgo), "type": "episode",
                        "episode": ["season": .int(s), "number": .int(e), "title": .string("Capítulo \(e)")], "show": ["title": name, "year": 2005, "ids": ids(v.imdb)]]
            }
            return ["id": .int(v.id), "watched_at": iso(v.hoursAgo), "type": "movie", "movie": ["title": name, "year": 2021, "ids": ids(v.imdb)]]
        }
        func hours(_ stamp: String?) -> Double {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let stamp, let d = f.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) else { return 0 }
            return Date().timeIntervalSince(d) / 3600
        }
        return Self.historyLock.withLock { () -> HTTPResponse? in
            if path.hasPrefix("/search/imdb/") {
                let imdb = String(path.dropFirst("/search/imdb/".count))
                let type = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "type" }?.value ?? "movie"
                return json(.array([.object(["type": .string(type), type: ["title": .string(Self.historyNames[imdb] ?? imdb), "ids": ids(imdb)]])]))
            }
            if path.hasPrefix("/sync/history/movies/") || path.hasPrefix("/sync/history/shows/"), method == "GET" {
                let trakt = Int(path.split(separator: "/").last ?? "") ?? 0
                return json(.array(Self.demoHistory.filter { (Int($0.imdb.dropFirst(2)) ?? 0) == trakt }.sorted { $0.hoursAgo < $1.hoursAgo }.map(row)))
            }
            if path == "/sync/history", method == "GET" {
                let page = Int(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
                return json(page > 1 ? [] : .array(Self.demoHistory.sorted { $0.hoursAgo < $1.hoursAgo }.map(row)))
            }
            if path == "/sync/history/remove" {
                let gone = body?["ids"]?.array?.compactMap(\.intValue) ?? []
                Self.demoHistory.removeAll { gone.contains($0.id) }
                return json(["deleted": ["movies": .int(gone.count)]])
            }
            if path == "/sync/history", method == "POST" {
                for m in body?["movies"]?.array ?? [] {
                    guard let imdb = m["ids"]?["imdb"]?.string else { continue }
                    Self.demoHistory.append(.init(id: Self.demoNextViewing, imdb: imdb, hoursAgo: hours(m["watched_at"]?.string))); Self.demoNextViewing += 1
                }
                for s in body?["shows"]?.array ?? [] {
                    guard let imdb = s["ids"]?["imdb"]?.string else { continue }
                    for season in s["seasons"]?.array ?? [] {
                        for e in season["episodes"]?.array ?? [] {
                            Self.demoHistory.append(.init(id: Self.demoNextViewing, imdb: imdb, hoursAgo: hours(e["watched_at"]?.string),
                                                          season: season["number"]?.intValue, episode: e["number"]?.intValue))
                            Self.demoNextViewing += 1
                        }
                    }
                }
                return json(["added": ["movies": 1]], status: 201)
            }
            // VIP (`-demo-vip`): las notas viven en Trakt; sin él, la app las guarda en el iPhone.
            if path == "/users/settings" { return json(["user": ["username": "demo", "vip": .bool(Demo.vip)]]) }
            if path == "/users/me/notes/movies" || path == "/users/me/notes/shows" {
                let shows = path.hasSuffix("shows")
                return json(.array(Self.demoNotes.filter { $0.value.show == shows }.map { imdb, n in
                    [shows ? "show" : "movie": ["ids": ids(imdb)], "note": ["id": .int(n.id), "notes": .string(n.text), "privacy": "private"]]
                }))
            }
            if path == "/notes", method == "POST", Demo.vip {
                let show = body?["show"] != nil
                guard let imdb = (body?["show"] ?? body?["movie"])?["ids"]?["imdb"]?.string, let text = body?["notes"]?.string else { return json([:], status: 422) }
                Self.demoNextViewing += 1
                Self.demoNotes[imdb] = (Self.demoNextViewing, text, show)
                return json(["id": .int(Self.demoNextViewing), "notes": .string(text)], status: 201)
            }
            if path.hasPrefix("/notes/"), let id = Int(path.dropFirst("/notes/".count)),
               let imdb = Self.demoNotes.first(where: { $0.value.id == id })?.key {
                if method == "DELETE" { Self.demoNotes[imdb] = nil; return json([:], status: 204) }
                Self.demoNotes[imdb]?.text = body?["notes"]?.string ?? ""
                return json(["id": .int(id)])
            }
            if path == "/sync/ratings/seasons" { return json([]) }
            return nil
        }
    }
}
#endif
