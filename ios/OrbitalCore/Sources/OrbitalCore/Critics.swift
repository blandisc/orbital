import Foundation

/// «Aprobadas por la crítica» en Para ti: Rotten Tomatoes no tiene API pública, así que las películas salen de una lista
/// pública de MDBList (Certified Fresh recientes) y las series de una lista pública de Trakt (Certified Fresh, por
/// Tomatómetro). Las mismas que usa la consola (`orbital/foryou.py` `_critics`, `orbital/library/mdblist.py`). Ninguna pide
/// clave ni sesión. Un día en caché; si no contesta, la última copia buena.
///
///     GET https://mdblist.com/lists/{usuario}/{lista}/json      una lista de títulos, o {"movies": […], "shows": […]}
///     GET https://api.trakt.tv/users/{usuario}/lists/{lista}/items
public struct Critics: Sendable {
    public static let listID = "critics"
    /// Cómo se llama el origen (el sello del estante).
    public static let source = "Rotten Tomatoes"
    static let movies = (user: "tbotcotw", slug: "recent-certified-fresh")
    static let series = (user: "truckclancy", slug: "rotten-tomatoes-certified-fresh-tv-shows-ranked-by-tomatometer-score")
    /// El porqué de cada título, como lo dice la consola.
    public static func reason(kind: String) -> String { kind == "movie" ? "Certified Fresh" : "Fresh en Rotten Tomatoes" }

    let http: HTTPClient
    let trakt: Trakt?
    let kv: KeyValueStore

    public init(http: HTTPClient, trakt: Trakt?, kv: KeyValueStore) { self.http = http; self.trakt = trakt; self.kv = kv }

    /// Lo que se guarda para cuando no contesta: lo mínimo de cada título.
    private struct Saved: Codable { var kind: String, imdb: String, title: String, year: Int? }
    static func savedKey(_ kind: String) -> String { "critics-\(kind)" }

    /// Los títulos de un tipo (`movie` o `series`). Sin respuesta, la última copia; sin copia, el error.
    public func items(kind: String) async throws -> [TraktEntry] {
        do {
            let found = kind == "movie" ? try await moviesFromMDBList() : try await seriesFromTrakt()
            if !found.isEmpty {
                kv.set(Self.savedKey(kind), data: try? JSONEncoder().encode(found.map { Saved(kind: $0.kind, imdb: $0.imdb, title: $0.title, year: $0.year) }))
            }
            return found
        } catch {
            guard let data = kv.data(Self.savedKey(kind)), let saved = try? JSONDecoder().decode([Saved].self, from: data), !saved.isEmpty else { throw error }
            return saved.map { TraktEntry(kind: $0.kind, imdb: $0.imdb, title: $0.title, year: $0.year, overview: "") }
        }
    }

    private func moviesFromMDBList() async throws -> [TraktEntry] {
        guard let url = URL(string: "https://mdblist.com/lists/\(Self.movies.user)/\(Self.movies.slug)/json") else { return [] }
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": "Orbital"], timeout: 12))
        guard response.status == 200, let json = JSON.parse(response.data) else { throw NetworkError("MDBList no contestó") }
        return Self.entries(json).filter { $0.kind == "movie" }
    }

    private func seriesFromTrakt() async throws -> [TraktEntry] {
        guard let trakt, trakt.configured else { return [] }
        return try await trakt.publicListItems(user: Self.series.user, slug: Self.series.slug).filter { $0.kind == "series" }
    }

    /// Lo que contesta MDBList → títulos, sin repetir y solo con IMDb (como `mdblist.entries` en la consola).
    static func entries(_ json: JSON) -> [TraktEntry] {
        let rows = json.array ?? ((json["movies"]?.array ?? []) + (json["shows"]?.array ?? []))
        var seen = Set<String>(), out: [TraktEntry] = []
        for row in rows {
            guard let imdb = (row["imdb_id"] ?? row["imdbid"])?.string, imdb.range(of: #"^tt\d+$"#, options: .regularExpression) != nil,
                  let title = row["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let kind = ["movie": "movie", "show": "series", "tv": "series"][(row["mediatype"]?.string ?? "").lowercased()],
                  seen.insert(imdb).inserted else { continue }
            out.append(TraktEntry(kind: kind, imdb: imdb, title: title, year: (row["release_year"] ?? row["year"])?.intValue, overview: ""))
        }
        return out
    }
}
