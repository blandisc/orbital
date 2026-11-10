import Foundation

/// Corregir lo que viste (gestor ola 3, O3-B, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): cada vez que viste
/// algo con su fecha y hora, cambiar una fecha, borrar una vista repetida, sumar «La vi otra vez» y tu historial completo.
/// Trakt no deja cambiar una fecha: se agrega la nueva y se borra la vieja por su id. docs/producto/live-activity-2026-11-08/gestor-ola3.html
public struct TraktViewing: Sendable, Equatable, Identifiable, Codable {
    /// El id de esta vista en tu historial de Trakt (lo que se borra).
    public var id: Int
    public var at: Date
    public init(id: Int, at: Date) { self.id = id; self.at = at }
}

/// Un renglón de tu historial: qué (película o capítulo), cuándo y su id en Trakt.
public struct TraktHistoryEntry: Sendable, Equatable, Identifiable {
    public var id: Int
    public var at: Date
    public var target: TraktTarget
    /// El nombre de la película o de la serie.
    public var title: String
    public var year: Int?
    /// El nombre del capítulo (nil en una película).
    public var episodeTitle: String?
    public init(id: Int, at: Date, target: TraktTarget, title: String, year: Int? = nil, episodeTitle: String? = nil) {
        self.id = id; self.at = at; self.target = target; self.title = title; self.year = year; self.episodeTitle = episodeTitle
    }
    public var kind: String { target.isEpisode ? "series" : "movie" }
}

extension Trakt {
    /// Cuánto separa dos vistas del mismo título para contarlas como repetidas (la tele y el iPhone la marcaron a la vez).
    public static let repeatWindow: TimeInterval = 3600

    /// Cada vez que viste esta película o este capítulo, de la más nueva a la más vieja.
    public func viewings(_ target: TraktTarget) async throws -> [TraktViewing] {
        guard Self.isIMDb(target.imdb) else { throw TraktError.invalid("Título inválido") }
        let kind = target.isEpisode ? "show" : "movie"
        guard let found = try await get("/search/imdb/\(target.imdb)", [("type", kind)])?.array?.first,
              let id = found[kind]?["ids"]?["trakt"]?.intValue else { return [] }
        let rows = try await allPages("/sync/history/\(kind)s/\(id)")
        return rows.compactMap { row -> TraktViewing? in
            if target.isEpisode {
                guard row["episode"]?["season"]?.intValue == target.season, row["episode"]?["number"]?.intValue == target.episode else { return nil }
            }
            guard let hid = row["id"]?.intValue, let at = Self.date(row["watched_at"]) else { return nil }
            return TraktViewing(id: hid, at: at)
        }
        .sorted { $0.at > $1.at }
    }

    /// Borra esas vistas de tu historial (solo esas: las demás se quedan).
    public func removeViewings(_ ids: [Int]) async throws {
        guard !ids.isEmpty else { return }
        let (status, _) = try await write("/sync/history/remove", ["ids": .array(ids.map { .int($0) })])
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Cambia la fecha de una vista: agrega la nueva primero (si falla, no se pierde nada) y luego borra la vieja.
    public func moveViewing(_ id: Int, of target: TraktTarget, to date: Date) async throws {
        try await addToHistory([(target, date)])
        try await removeViewings([id])
    }

    /// Tu historial, lo más nuevo primero (`page` desde 1, de 100 en 100).
    public func history(page: Int = 1, limit: Int = 100) async throws -> [TraktHistoryEntry] {
        let rows = try await get("/sync/history", [("page", String(page)), ("limit", String(limit))])?.array ?? []
        return rows.compactMap(Self.historyEntry)
    }

    static func historyEntry(_ row: JSON) -> TraktHistoryEntry? {
        guard let hid = row["id"]?.intValue, let at = date(row["watched_at"]) else { return nil }
        if let movie = row["movie"], let imdb = movie["ids"]?["imdb"]?.string {
            return TraktHistoryEntry(id: hid, at: at, target: TraktTarget(imdb: imdb), title: movie["title"]?.string ?? imdb, year: movie["year"]?.intValue)
        }
        if let show = row["show"], let imdb = show["ids"]?["imdb"]?.string, let ep = row["episode"],
           let s = ep["season"]?.intValue, let n = ep["number"]?.intValue {
            return TraktHistoryEntry(id: hid, at: at, target: TraktTarget(imdb: imdb, season: s, episode: n), title: show["title"]?.string ?? imdb,
                                     year: show["year"]?.intValue, episodeTitle: ep["title"]?.string)
        }
        return nil
    }

    /// Las vistas repetidas: el mismo título o capítulo con menos de `repeatWindow` de otra más vieja (la más vieja se queda).
    public static func repeats(_ entries: [TraktHistoryEntry], window: TimeInterval = repeatWindow) -> Set<Int> {
        var out: Set<Int> = []
        let byTarget = Dictionary(grouping: entries) { e in e.target.isEpisode ? "\(e.target.imdb):\(e.target.season!):\(e.target.episode!)" : e.target.imdb }
        for group in byTarget.values {
            let sorted = group.sorted { $0.at < $1.at }
            for (a, b) in zip(sorted, sorted.dropFirst()) where b.at.timeIntervalSince(a.at) < window { out.insert(b.id) }
        }
        return out
    }

    static func date(_ value: JSON?) -> Date? {
        guard let text = value?.string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    // MARK: tu nota privada (G6): Trakt solo guarda notas con VIP

    /// ¿Tu cuenta de Trakt es VIP? (las notas viven en Trakt solo así).
    public func isVIP() async throws -> Bool {
        let user = try await get("/users/settings")?["user"]
        return user?["vip"]?.bool == true || user?["vip_ep"]?.bool == true
    }

    /// Tus notas de películas y series en Trakt: IMDb → (id de la nota, texto).
    public func myNotes() async throws -> [String: (id: Int, text: String)] {
        var out: [String: (id: Int, text: String)] = [:]
        for type in ["movies", "shows"] {
            for row in try await allPages("/users/me/notes/\(type)") {
                let item = row["movie"] ?? row["show"]
                guard let imdb = item?["ids"]?["imdb"]?.string, let note = row["note"], let id = note["id"]?.intValue,
                      let text = note["notes"]?.string else { continue }
                out[imdb] = (id, text)
            }
        }
        return out
    }

    /// Escribe (o, con texto vacío, borra) tu nota de una película o serie. Siempre privada. Devuelve el id de la nota.
    @discardableResult
    public func setNote(imdb: String, series: Bool, text: String, existing: Int?) async throws -> Int? {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.noteLimit))
        if clean.isEmpty {
            guard let existing else { return nil }
            let (status, _) = try await write("/notes/\(existing)", nil, method: "DELETE")
            guard status == 200 || status == 204 || status == 404 else { throw TraktError.http(status) }
            return nil
        }
        if let existing {
            let (status, data) = try await write("/notes/\(existing)", ["notes": .string(clean), "privacy": "private", "spoiler": false], method: "PUT")
            if status == 200 || status == 201 { return data?["id"]?.intValue ?? existing }
            guard status == 404 else { throw TraktError.http(status) }   // la borraste en trakt.tv: se hace otra
        }
        let body: JSON = [series ? "show" : "movie": ["ids": ["imdb": .string(imdb)]], "notes": .string(clean), "privacy": "private", "spoiler": false]
        let (status, data) = try await write("/notes", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
        return data?["id"]?.intValue
    }

    /// Lo más largo que Trakt guarda en una nota.
    public static let noteLimit = 500
}
