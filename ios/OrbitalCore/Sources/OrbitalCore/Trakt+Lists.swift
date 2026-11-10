import Foundation

/// Tus listas completas (G4-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»): cambiar nombre, quién la ve, borrar,
/// duplicar y ordenar a mano, sin ir a trakt.tv. Todo necesita conexión (no pasa por la cola: una lista borrada en otro
/// aparato y renombrada aquí sin red chocaría). docs/producto/live-activity-2026-11-08/gestor-ola2.html
extension Trakt {
    /// Los valores de «Quién la ve» que entiende Trakt.
    public static let privacies = ["private", "link", "friends", "public"]

    /// Cambia el nombre o quién la ve de una de tus listas.
    public func updateList(_ id: String, name: String? = nil, privacy: String? = nil) async throws {
        guard Self.isListID(id) else { throw TraktError.invalid("Lista inválida") }
        var body: [String: JSON] = [:]
        if let name {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw TraktError.invalid("Ponle nombre a la lista") }
            body["name"] = .string(clean)
        }
        if let privacy {
            guard Self.privacies.contains(privacy) else { throw TraktError.invalid("Privacidad inválida") }
            body["privacy"] = .string(privacy)
        }
        guard !body.isEmpty else { return }
        let (status, _) = try await write("/users/me/lists/\(id)", .object(body), method: "PUT")
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Borra una de tus listas (no se puede deshacer; los títulos siguen en Mi lista y en tus otras listas).
    public func deleteList(_ id: String) async throws {
        guard Self.isListID(id) else { throw TraktError.invalid("Lista inválida") }
        let (status, _) = try await write("/users/me/lists/\(id)", nil, method: "DELETE")
        guard status == 200 || status == 204 else { throw TraktError.http(status) }
    }

    /// Cada título de una lista (o de tu watchlist, con `watchlist`) con el id de su renglón: lo que pide «ordenar a mano».
    public func listRows(_ id: String) async throws -> [(row: Int, imdb: String)] {
        let path: String
        if id == "watchlist" { path = "/sync/watchlist" }
        else { guard Self.isListID(id) else { throw TraktError.invalid("Lista inválida") }; path = "/users/me/lists/\(id)/items" }
        return try await allPages(path).compactMap { row in
            guard let rowID = row["id"]?.intValue else { return nil }
            let item = row["movie"] ?? row["show"]
            guard let imdb = item?["ids"]?["imdb"]?.string else { return nil }
            return (rowID, imdb)
        }
    }

    /// Ordena a mano una lista (o tu watchlist) con los títulos (IMDb) en el orden que quieres. Lo que no venga se queda al
    /// final, como estaba.
    public func reorder(_ id: String, imdbs: [String]) async throws {
        let rows = try await listRows(id)
        let byIMDb = Dictionary(rows.map { ($0.imdb, $0.row) }, uniquingKeysWith: { a, _ in a })
        var rank = imdbs.compactMap { byIMDb[$0] }
        let placed = Set(rank)
        rank += rows.map(\.row).filter { !placed.contains($0) }
        guard !rank.isEmpty else { return }
        let path = id == "watchlist" ? "/sync/watchlist/reorder" : "/users/me/lists/\(id)/items/reorder"
        let (status, _) = try await write(path, ["rank": .array(rank.map { .int($0) })])
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// «Duplicar»: una lista nueva «Copia de…», Solo tú, con los mismos títulos en el mismo orden. Devuelve su id y nombre.
    public func duplicateList(_ id: String, name: String, items: [(imdb: String, series: Bool)]) async throws -> (id: String, name: String) {
        let made = try await createList(name: name)
        if !items.isEmpty {
            try await setItems(target: made.id, items, add: true)
            try? await reorder(made.id, imdbs: items.map(\.imdb))
        }
        return made
    }

    /// El enlace de una lista en trakt.tv (por su id: no cambia al renombrarla).
    public static func listURL(_ id: String) -> URL? { URL(string: "https://trakt.tv/lists/\(id)") }
}
