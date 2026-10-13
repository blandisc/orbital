import Foundation

public enum TraktError: Error, Sendable, CustomStringConvertible {
    case network(String), http(Int), invalid(String)
    /// Trakt ya no acepta la sesión: hay que volver a conectar la cuenta.
    case auth(String)
    public var description: String {
        switch self {
        case .network(let m): return "No pude conectar con Trakt: \(m)"
        case .http(let s): return "Trakt respondió HTTP \(s)"
        case .invalid(let m), .auth(let m): return m
        }
    }
}

/// Una película o serie de Trakt, con su id de IMDb (sin él no se podría ver).
public struct TraktEntry: Sendable, Equatable, Identifiable {
    public var kind: String          // movie | series
    public var imdb: String
    public var title: String
    public var year: Int?
    public var runtime: Int?
    public var episodes: Int?
    public var overview: String
    public var traktID: Int?
    public var next: (season: Int, episode: Int)?
    public var id: String { imdb }

    public static func == (a: TraktEntry, b: TraktEntry) -> Bool {
        a.kind == b.kind && a.imdb == b.imdb && a.title == b.title && a.year == b.year && a.runtime == b.runtime
            && a.episodes == b.episodes && a.overview == b.overview && a.traktID == b.traktID
            && a.next?.season == b.next?.season && a.next?.episode == b.next?.episode
    }
}

public struct DeviceCode: Sendable, Equatable {
    public var deviceCode: String, userCode: String, verificationURL: String
    public var interval: TimeInterval, expiresAt: Date
}

public enum DeviceStatus: Sendable, Equatable { case linked, pending, slow, expired, denied, invalid }

/// Lo que se avisa a Trakt de lo que reproduces.
public enum ScrobbleAction: String, Sendable { case start, pause, stop }
public enum ScrobbleResult: Sendable, Equatable {
    case sent
    /// 409: ya estaba registrado (dos dispositivos, o el mismo reproductor dos veces).
    case duplicate
    /// Menos de 1 % o respuesta que se ignora.
    case ignored
}

/// Cuál título se está viendo, para el scrobble: una película, o un episodio de una serie (por IMDb de la serie).
public struct TraktTarget: Sendable, Equatable, Codable {
    public var imdb: String
    public var season: Int?
    public var episode: Int?
    public init(imdb: String, season: Int? = nil, episode: Int? = nil) { self.imdb = imdb; self.season = season; self.episode = episode }
    public var isEpisode: Bool { season != nil && episode != nil }

    /// «tt0944947:1:5» → serie 1×5; «tt1160419» → película.
    public init?(videoID: String, kind: String) {
        let parts = videoID.split(separator: ":").map(String.init)
        guard let imdb = parts.first, imdb.hasPrefix("tt") else { return nil }
        if kind == "movie" { self.init(imdb: imdb); return }
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return nil }
        self.init(imdb: imdb, season: s, episode: e)
    }

    var body: JSON {
        isEpisode ? ["show": ["ids": ["imdb": .string(imdb)]], "episode": ["season": .int(season!), "number": .int(episode!)]]
                  : ["movie": ["ids": ["imdb": .string(imdb)]]]
    }
}

public enum TraktParsing {
    static let kinds = ["movie": "movies", "series": "shows"]

    public static func entry(_ raw: JSON?, kind: String) -> TraktEntry? {
        guard let raw, raw.object != nil, let ids = raw["ids"], let imdb = ids["imdb"]?.string, imdb.hasPrefix("tt"),
              let title = raw["title"]?.string?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
        func positive(_ j: JSON?) -> Int? { j?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        func isInt(_ j: JSON?) -> Int? { if case .int(let i)? = j { return i }; return nil }
        return TraktEntry(kind: kind, imdb: imdb, title: title, year: isInt(raw["year"]), runtime: positive(raw["runtime"]),
                          episodes: positive(raw["aired_episodes"]), overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                          traktID: isInt(ids["trakt"]))
    }

    /// Filas mezcladas («type»: movie/show) → solo películas y series con IMDb, sin repetir.
    public static func typed(_ rows: [JSON]?) -> [TraktEntry] {
        var found: [TraktEntry] = [], seen = Set<String>()
        for row in rows ?? [] {
            guard let typeName = row["type"]?.string, let kind = ["movie": "movie", "show": "series"][typeName],
                  let item = entry(row[typeName], kind: kind), seen.insert(item.imdb).inserted else { continue }
            found.append(item)
        }
        return found
    }
}

/// Cliente de Trakt. Hay que registrar una aplicación de la API de Trakt (client id). Las cuentas gratuitas
/// tienen un tope de apps conectadas: si Trakt no deja conectar, se avisa (`TraktError.auth`/`.http`) y el
/// resto de la app sigue funcionando.
public actor Trakt {
    public static let api = URL(string: "https://api.trakt.tv")!
    public static let redirect = "urn:ietf:wg:oauth:2.0:oob"

    private let http: HTTPClient
    private let secrets: SecretsStore
    private let clientID: String
    private let clientSecret: String
    private let clock: @Sendable () -> Date
    private let pause: @Sendable (TimeInterval) async -> Void
    private var lastWrite = Date.distantPast

    public init(http: HTTPClient, secrets: SecretsStore, clientID: String, clientSecret: String = "",
                clock: @escaping @Sendable () -> Date = { Date() },
                pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.http = http; self.secrets = secrets; self.clientID = clientID; self.clientSecret = clientSecret; self.clock = clock; self.pause = pause
    }

    // MARK: cuenta
    public nonisolated var configured: Bool { !clientID.isEmpty }
    public nonisolated var linked: Bool { tokens() != nil }

    private struct Tokens: Codable { var access_token: String; var refresh_token: String?; var expires_at: Double }

    private nonisolated func tokens() -> Tokens? {
        guard let raw = secrets.get(SecretKey.traktTokens), let data = raw.data(using: .utf8),
              let t = try? JSONDecoder().decode(Tokens.self, from: data), !t.access_token.isEmpty else { return nil }
        return t
    }

    private func save(_ data: JSON) throws {
        guard let access = data["access_token"]?.nonEmptyString else { throw TraktError.invalid("Trakt no devolvió una sesión") }
        let created = number(data["created_at"]) ?? clock().timeIntervalSince1970
        let tokens = Tokens(access_token: access, refresh_token: data["refresh_token"]?.string, expires_at: created + (number(data["expires_in"]) ?? 0))
        secrets.set(SecretKey.traktTokens, String(data: try JSONEncoder().encode(tokens), encoding: .utf8))
    }

    private func number(_ j: JSON?) -> Double? {
        switch j { case .int(let i)?: return Double(i); case .double(let d)?: return d; default: return nil }
    }

    public func unlink() async {
        guard let tokens = tokens() else { return }
        secrets.set(SecretKey.traktTokens, nil)
        // Que la sesión deje de servir también en Trakt (si no hay internet, da igual).
        _ = try? await call("POST", "/oauth/revoke", body: obj(["token": .string(tokens.access_token), "client_id": .string(clientID)], secretField()), auth: false)
    }

    private nonisolated func obj(_ a: [String: JSON], _ b: [String: JSON] = [:]) -> JSON { .object(a.merging(b) { $1 }) }
    private func secretField() -> [String: JSON] { clientSecret.isEmpty ? [:] : ["client_secret": .string(clientSecret)] }

    public func deviceCode() async throws -> DeviceCode {
        let (status, data) = try await call("POST", "/oauth/device/code", body: ["client_id": .string(clientID)], auth: false)
        guard status == 200, let device = data?["device_code"]?.nonEmptyString, let user = data?["user_code"]?.nonEmptyString else {
            throw TraktError.invalid("Trakt no dio un código. Revisa la aplicación de Trakt.")
        }
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: data?["verification_url"]?.nonEmptyString ?? "https://trakt.tv/activate",
                          interval: number(data?["interval"]) ?? 5, expiresAt: clock().addingTimeInterval(number(data?["expires_in"]) ?? 600))
    }

    /// Una consulta: `.linked`, `.pending`, `.slow` (más despacio) o `.expired`/`.denied`/`.invalid`.
    public func pollDevice(_ code: DeviceCode) async throws -> DeviceStatus {
        let (status, data) = try await call("POST", "/oauth/device/token", body: obj(["code": .string(code.deviceCode), "client_id": .string(clientID)], secretField()), auth: false)
        if status == 200, let data { try save(data); return .linked }
        return [400: .pending, 429: .slow, 404: .invalid, 409: .invalid, 410: .expired, 418: .denied][status] ?? .pending
    }

    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        let body = obj(["refresh_token": .string(tokens.refresh_token ?? ""), "client_id": .string(clientID), "redirect_uri": .string(Trakt.redirect),
                        "grant_type": "refresh_token"], secretField())
        let (status, data) = try await call("POST", "/oauth/token", body: body, auth: false)
        guard status == 200, let data else {
            secrets.set(SecretKey.traktTokens, nil)
            throw TraktError.auth("Tu sesión de Trakt caducó: vuelve a conectarla en Ajustes.")
        }
        try save(data)  // el refresh token podría ser de un solo uso: siempre se guarda el nuevo
        return self.tokens()!
    }

    private func access() async throws -> String {
        guard var tokens = tokens() else { throw TraktError.auth("Conecta tu cuenta de Trakt en Ajustes.") }
        if tokens.refresh_token != nil, clock().timeIntervalSince1970 > tokens.expires_at - 3600 { tokens = try await refresh(tokens) }
        return tokens.access_token
    }

    // MARK: peticiones
    private func call(_ method: String, _ path: String, body: JSON? = nil, auth: Bool = true, params: [(String, String)] = []) async throws -> (Int, JSON?) {
        var headers = ["trakt-api-version": "2", "trakt-api-key": clientID, "Content-Type": "application/json"]
        if auth { headers["Authorization"] = "Bearer \(try await access())" }
        var components = URLComponents(url: Trakt.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !params.isEmpty { components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) } }
        do {
            let response = try await http.send(HTTPRequest(url: components.url!, method: method, headers: headers, body: body?.serialized(), timeout: 10))
            return (response.status, JSON.parse(response.data))
        } catch let error as NetworkError { throw TraktError.network("\(error)") }
    }

    private func get(_ path: String, auth: Bool = true, _ params: [(String, String)] = []) async throws -> JSON? {
        let (status, data) = try await call("GET", path, auth: auth, params: params)
        if status == 401 && auth {
            secrets.set(SecretKey.traktTokens, nil)
            throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.")
        }
        guard status == 200 else { throw TraktError.http(status) }
        return data
    }

    /// Una escritura a la vez y como máximo una por segundo (límite de Trakt).
    private func write(_ path: String, _ body: JSON) async throws -> (Int, JSON?) {
        let wait = 1.0 - clock().timeIntervalSince(lastWrite)
        if wait > 0 { await pause(wait) }
        defer { lastWrite = clock() }
        let result = try await call("POST", path, body: body)
        if result.0 == 401 { secrets.set(SecretKey.traktTokens, nil); throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.") }
        return result
    }

    // MARK: listas (lectura)
    public func username() async throws -> String {
        let user = try await get("/users/settings")?["user"]
        return user?["name"]?.nonEmptyString ?? user?["username"]?.nonEmptyString ?? ""
    }

    public func recommendations(kind: String, limit: Int = 30) async throws -> [TraktEntry] {
        let rows = try await get("/recommendations/\(TraktParsing.kinds[kind]!)", [("limit", String(limit)), ("ignore_collected", "true"), ("ignore_watchlisted", "true"), ("extended", "full")])
        return (rows?.array ?? []).compactMap { TraktParsing.entry($0, kind: kind) }
    }

    public func watchlist() async throws -> [TraktEntry] {
        let rows = try await get("/sync/watchlist", [("extended", "full"), ("sort_by", "added"), ("sort_how", "desc")])
        let sorted = (rows?.array ?? []).filter { $0.object != nil }.sorted { ($0["listed_at"]?.string ?? "") > ($1["listed_at"]?.string ?? "") }
        return TraktParsing.typed(sorted)
    }

    public func lists() async throws -> [(id: String, name: String)] {
        let rows = try await get("/users/me/lists")
        return (rows?.array ?? []).compactMap { row in
            guard let name = row["name"]?.string?.trimmingCharacters(in: .whitespaces), !name.isEmpty, let id = row["ids"]?["trakt"]?.intValue else { return nil }
            return (String(id), name)
        }
    }

    public func listItems(_ id: String) async throws -> [TraktEntry] {
        guard !id.isEmpty, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else { throw TraktError.invalid("Lista inválida") }
        return TraktParsing.typed(try await get("/users/me/lists/\(id)/items", [("extended", "full")])?.array)
    }

    public func trending(kind: String, limit: Int = 30) async throws -> [TraktEntry] {
        let rows = try await get("/\(TraktParsing.kinds[kind]!)/trending", auth: false, [("limit", String(limit)), ("extended", "full")])
        let key = kind == "movie" ? "movie" : "show"
        return (rows?.array ?? []).compactMap { TraktParsing.entry($0[key], kind: kind) }
    }

    public func popular(kind: String, limit: Int = 30) async throws -> [TraktEntry] {
        let rows = try await get("/\(TraktParsing.kinds[kind]!)/popular", auth: false, [("limit", String(limit)), ("extended", "full")])
        return (rows?.array ?? []).compactMap { TraktParsing.entry($0, kind: kind) }
    }

    /// Las series que estás viendo (lo más reciente primero) con el episodio que sigue; las terminadas no.
    public func watching(limit: Int = 12) async throws -> [TraktEntry] {
        let rows = try await get("/sync/history/episodes", [("limit", "100")])
        var shows: [TraktEntry] = [], seen = Set<String>()
        for row in rows?.array ?? [] {
            if let show = TraktParsing.entry(row["show"], kind: "series"), show.traktID != nil, seen.insert(show.imdb).inserted { shows.append(show) }
            if shows.count >= limit { break }
        }
        var found: [TraktEntry] = []
        for var show in shows {
            do {
                let progress = try await get("/shows/\(show.traktID!)/progress/watched", [("hidden", "false"), ("specials", "false")])
                if let next = progress?["next_episode"], let s = next["season"]?.intValue, let n = next["number"]?.intValue { show.next = (s, n); found.append(show) }
            } catch let error as TraktError {
                if case .auth = error { throw error }  // una serie que falla no tumba las demás
            }
        }
        return found
    }

    // MARK: escritura
    public func setWatchlist(_ target: TraktTarget, add: Bool) async throws {
        let body: JSON = target.isEpisode ? ["shows": [["ids": ["imdb": .string(target.imdb)]]]] : ["movies": [["ids": ["imdb": .string(target.imdb)]]]]
        let (status, _) = try await write(add ? "/sync/watchlist" : "/sync/watchlist/remove", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Avisa a Trakt de lo que reproduces. `progress` va de 0 a 100; por encima de ~80 % al parar, Trakt lo marca visto.
    @discardableResult
    public func scrobble(_ action: ScrobbleAction, _ target: TraktTarget, progress: Double) async throws -> ScrobbleResult {
        var body = target.body.object ?? [:]
        body["progress"] = .double(min(100, max(0, progress)))
        let (status, _) = try await write("/scrobble/\(action.rawValue)", .object(body))
        switch status {
        case 200, 201: return .sent
        case 409: return .duplicate
        case 422: return .ignored
        default: throw TraktError.http(status)
        }
    }

    /// Sube lo visto sin conexión con su fecha real, sin repetir lo que ya está en el historial de Trakt.
    @discardableResult
    public func addToHistory(_ target: TraktTarget, watchedAt: Date) async throws -> Bool {
        if try await alreadyWatched(target, near: watchedAt) { return false }
        let stamp = StremioLibrary.iso(watchedAt.timeIntervalSince1970)
        let body: JSON = target.isEpisode
            ? ["shows": [["ids": ["imdb": .string(target.imdb)], "seasons": [["number": .int(target.season!), "episodes": [["number": .int(target.episode!), "watched_at": .string(stamp)]]]]]]]
            : ["movies": [["ids": ["imdb": .string(target.imdb)], "watched_at": .string(stamp)]]]
        let (status, _) = try await write("/sync/history", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
        return true
    }

    /// ¿Ya hay un visionado de este título cerca de esa hora? (Trakt no comprueba duplicados en `/sync/history`.)
    func alreadyWatched(_ target: TraktTarget, near date: Date, window: TimeInterval = 12 * 3600) async throws -> Bool {
        let kind = target.isEpisode ? "series" : "movie"
        guard let found = try await get("/search/imdb/\(target.imdb)", [("type", kind == "movie" ? "movie" : "show")])?.array?.first,
              let id = found[kind == "movie" ? "movie" : "show"]?["ids"]?["trakt"]?.intValue else { return false }
        let params = [("start_at", StremioLibrary.iso(date.addingTimeInterval(-window).timeIntervalSince1970)),
                      ("end_at", StremioLibrary.iso(date.addingTimeInterval(window).timeIntervalSince1970)), ("limit", "100")]
        let rows = try await get("/sync/history/\(kind == "movie" ? "movies" : "episodes")/\(id)", params)?.array ?? []
        if !target.isEpisode { return !rows.isEmpty }
        return rows.contains { $0["episode"]?["season"]?.intValue == target.season && $0["episode"]?["number"]?.intValue == target.episode }
    }
}
