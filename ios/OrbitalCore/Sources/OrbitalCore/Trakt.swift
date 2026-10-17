import Foundation

public enum TraktError: Error, Sendable, CustomStringConvertible {
    case network(String), http(Int), invalid(String)
    /// Trakt ya no acepta la sesión: hay que volver a conectar la cuenta.
    case auth(String)
    public var description: String {
        switch self {
        case .network(let reason): return "No pude conectar con Trakt: \(reason)"
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

/// Un episodio que sale de una serie que sigues («Próximos estrenos»): la serie, cuál episodio, cuándo (la hora
/// exacta; la interfaz la pone en la de aquí) y dónde sale.
public struct TraktAiring: Sendable, Equatable {
    public var show: TraktEntry
    public var season: Int
    public var episode: Int
    public var episodeTitle: String
    public var aired: Date
    public var network: String
    public init(show: TraktEntry, season: Int, episode: Int, episodeTitle: String = "", aired: Date, network: String = "") {
        self.show = show; self.season = season; self.episode = episode; self.episodeTitle = episodeTitle; self.aired = aired; self.network = network
    }
}

public struct DeviceCode: Sendable, Equatable {
    public var deviceCode: String, userCode: String, verificationURL: String
    public var interval: TimeInterval, expiresAt: Date
}

/// Una sesión de Trakt que presta tu Orbital (sin refresh token).
public struct BorrowedSession: Sendable, Equatable {
    public var accessToken: String, expiresAt: Double
    public init(accessToken: String, expiresAt: Double) { self.accessToken = accessToken; self.expiresAt = expiresAt }
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
              let title = raw["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        func positive(_ j: JSON?) -> Int? { j?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        func isInt(_ j: JSON?) -> Int? { if case .int(let i)? = j { return i }; return nil }
        return TraktEntry(kind: kind, imdb: imdb, title: title, year: isInt(raw["year"]), runtime: positive(raw["runtime"]),
                          episodes: positive(raw["aired_episodes"]), overview: (raw["overview"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                          traktID: isInt(ids["trakt"]))
    }

    /// Una fila del calendario de Trakt («first_aired» en hora universal). Sin IMDb, fecha o número de episodio: nada.
    public static func airing(_ row: JSON) -> TraktAiring? {
        guard var show = entry(row["show"], kind: "series"), let ep = row["episode"], ep.object != nil,
              let season = ep["season"]?.intValue, let number = ep["number"]?.intValue,
              let stamp = row["first_aired"]?.string, let aired = date(stamp) else { return nil }
        if let minutes = ep["runtime"]?.intValue, minutes > 0 { show.runtime = minutes }
        return TraktAiring(show: show, season: season, episode: number,
                           episodeTitle: (ep["title"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines), aired: aired,
                           network: (row["show"]?["network"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// «2025-10-16T01:00:00.000Z» (con o sin milésimas).
    static func date(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
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
    /// La sesión prestada por tu Orbital: cuando caduca se le pide otra (la renueva la consola, no el iPhone).
    private let borrow: (@Sendable () async -> BorrowedSession?)?

    public init(http: HTTPClient, secrets: SecretsStore, clientID: String, clientSecret: String = "",
                clock: @escaping @Sendable () -> Date = { Date() },
                pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                borrow: (@Sendable () async -> BorrowedSession?)? = nil) {
        self.http = http; self.secrets = secrets; self.clientID = clientID; self.clientSecret = clientSecret; self.clock = clock; self.pause = pause
        self.borrow = borrow
    }

    static func isIMDb(_ id: String) -> Bool { id.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil }

    // MARK: cuenta
    public nonisolated var configured: Bool { !clientID.isEmpty }
    public nonisolated var linked: Bool { tokens() != nil }

    private struct Tokens: Codable { var access_token: String; var refresh_token: String?; var expires_at: Double }

    /// La sesión es la de tu Orbital (sin la parte que la renueva): desconectar aquí no la toca en la consola.
    public nonisolated var borrowed: Bool { tokens().map { ($0.refresh_token ?? "").isEmpty } ?? false }

    /// Usa la sesión de Trakt de tu Orbital (sin conectar nada en el iPhone).
    public nonisolated func adopt(_ session: BorrowedSession) {
        let tokens = Tokens(access_token: session.accessToken, refresh_token: nil, expires_at: session.expiresAt)
        secrets.set(SecretKey.traktTokens, (try? JSONEncoder().encode(tokens)).flatMap { String(data: $0, encoding: .utf8) })
    }

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
        // Prestada por tu Orbital: solo se olvida aquí (revocarla desconectaría también la consola).
        if (tokens.refresh_token ?? "").isEmpty { return }
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

    private var refreshing: Task<Tokens, Error>?

    /// Renueva la sesión UNA sola vez aunque varias peticiones la pidan a la vez (el refresh token es de un solo uso:
    /// una segunda petición con el mismo recibiría un error y desconectaría la cuenta).
    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        if let refreshing { return try await refreshing.value }
        let task = Task<Tokens, Error> {
            let body = obj(["refresh_token": .string(tokens.refresh_token ?? ""), "client_id": .string(clientID), "redirect_uri": .string(Trakt.redirect),
                            "grant_type": "refresh_token"], secretField())
            let (status, data) = try await call("POST", "/oauth/token", body: body, auth: false)
            guard status == 200, let data else {
                // Solo un rechazo del refresh token (400/401/403) desconecta; un error del servidor o un 429 son pasajeros.
                if [400, 401, 403].contains(status) {
                    secrets.set(SecretKey.traktTokens, nil)
                    throw TraktError.auth("Tu sesión de Trakt caducó: vuelve a conectarla en Ajustes.")
                }
                throw TraktError.http(status)
            }
            try save(data)  // siempre se guarda el refresh token nuevo
            return self.tokens() ?? tokens
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func access() async throws -> String {
        guard var tokens = tokens() else { throw TraktError.auth("Conecta tu cuenta de Trakt en Ajustes.") }
        let expiring = clock().timeIntervalSince1970 > tokens.expires_at - 3600
        if !(tokens.refresh_token ?? "").isEmpty, expiring { tokens = try await refresh(tokens) }
        else if expiring, let borrow, let fresh = await borrow(), fresh.expiresAt > tokens.expires_at || fresh.accessToken != tokens.access_token {
            adopt(fresh); tokens = self.tokens() ?? tokens   // tu Orbital ya la renovó
        }
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
        // El turno se reserva ANTES de esperar: dos escrituras a la vez salen con un segundo de diferencia, en orden.
        let now = clock()
        let slot = max(now, lastWrite.addingTimeInterval(1))
        lastWrite = slot
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { await pause(wait) }
        var result = try await call("POST", path, body: body)
        if result.0 == 401 {
            // Un 401 no siempre es el final: se pide una sesión nueva UNA vez (se renueva, o se la pide a tu Orbital) y se reintenta.
            try await renewAfterRejection()
            result = try await call("POST", path, body: body)
            if result.0 == 401 { secrets.set(SecretKey.traktTokens, nil); throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.") }
        }
        return result
    }

    /// Trakt rechazó la sesión (401). Con refresh token se renueva (ya limpia la sesión si Trakt también lo rechaza); si es la
    /// prestada por tu Orbital se le pide otra a la consola. Si la consola no contesta o tiene la misma, lanza SIN olvidar la sesión
    /// (puede ser la TV apagada): el aviso queda para reintentarse y la sesión sigue ahí.
    private func renewAfterRejection() async throws {
        guard let old = tokens() else { throw TraktError.auth("Conecta tu cuenta de Trakt en Ajustes.") }
        if !(old.refresh_token ?? "").isEmpty { _ = try await refresh(old); return }
        guard let borrow else {
            secrets.set(SecretKey.traktTokens, nil)
            throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.")
        }
        guard let fresh = await borrow(), fresh.accessToken != old.access_token else {
            throw TraktError.auth("Trakt no acepta la sesión de tu Orbital: reconecta Trakt en la TV (Ajustes › Cuentas).")
        }
        adopt(fresh)
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

    /// Los episodios que salen de las series que sigues desde `start` (AAAA-MM-DD, en hora universal) y `days` días, en orden.
    public func calendar(start: String, days: Int = 16) async throws -> [TraktAiring] {
        guard start.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { throw TraktError.invalid("Fecha inválida") }
        let rows = try await get("/calendars/my/shows/\(start)/\(max(1, min(days, 31)))", [("extended", "full")])
        return (rows?.array ?? []).compactMap(TraktParsing.airing).sorted { $0.aired < $1.aired }
    }

    /// Las series que estás viendo (lo más reciente primero) con el episodio que sigue; las terminadas no.
    public func watching(limit: Int = 12) async throws -> [TraktEntry] {
        let rows = try await get("/sync/history/episodes", [("limit", "100")])
        var shows: [TraktEntry] = [], seen = Set<String>()
        for row in rows?.array ?? [] {
            if let show = TraktParsing.entry(row["show"], kind: "series"), show.traktID != nil, seen.insert(show.imdb).inserted { shows.append(show) }
            if shows.count >= limit { break }
        }
        // El avance de cada serie, todas a la vez (una tras otra eran ~12 viajes seguidos: el mosaico esperaba segundos).
        let results = try await withThrowingTaskGroup(of: (Int, TraktEntry?).self) { group in
            for (i, show) in shows.enumerated() {
                group.addTask {
                    do {
                        let progress = try await self.get("/shows/\(show.traktID!)/progress/watched", [("hidden", "false"), ("specials", "false")])
                        guard let next = progress?["next_episode"], let s = next["season"]?.intValue, let n = next["number"]?.intValue else { return (i, nil) }
                        var found = show
                        found.next = (s, n)
                        return (i, found)
                    } catch let error as TraktError {
                        if case .auth = error { throw error }  // una serie que falla no tumba las demás
                        return (i, nil)
                    }
                }
            }
            var out = [TraktEntry?](repeating: nil, count: shows.count)
            for try await (i, entry) in group { out[i] = entry }
            return out
        }
        return results.compactMap { $0 }
    }

    // MARK: escritura
    public func setWatchlist(imdb: String, series: Bool, add: Bool) async throws {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        let body: JSON = series ? ["shows": [["ids": ["imdb": .string(imdb)]]]] : ["movies": [["ids": ["imdb": .string(imdb)]]]]
        let (status, _) = try await write(add ? "/sync/watchlist" : "/sync/watchlist/remove", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Avisa a Trakt de lo que reproduces. `progress` va de 0 a 100; por encima de ~80 % al parar, Trakt lo marca visto.
    @discardableResult
    public func scrobble(_ action: ScrobbleAction, _ target: TraktTarget, progress: Double) async throws -> ScrobbleResult {
        guard Self.isIMDb(target.imdb) else { throw TraktError.invalid("Título inválido") }
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
        guard Self.isIMDb(target.imdb) else { throw TraktError.invalid("Título inválido") }
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
        guard Self.isIMDb(target.imdb) else { return false }
        guard let found = try await get("/search/imdb/\(target.imdb)", [("type", kind == "movie" ? "movie" : "show")])?.array?.first,
              let id = found[kind == "movie" ? "movie" : "show"]?["ids"]?["trakt"]?.intValue else { return false }
        let params = [("start_at", StremioLibrary.iso(date.addingTimeInterval(-window).timeIntervalSince1970)),
                      ("end_at", StremioLibrary.iso(date.addingTimeInterval(window).timeIntervalSince1970)), ("limit", "100")]
        // En Trakt `episodes/{id}` espera el id de un EPISODIO; el de una serie va en `shows/{id}`.
        let rows = try await get("/sync/history/\(kind == "movie" ? "movies" : "shows")/\(id)", params)?.array ?? []
        if !target.isEpisode { return !rows.isEmpty }
        return rows.contains { $0["episode"]?["season"]?.intValue == target.season && $0["episode"]?["number"]?.intValue == target.episode }
    }
}
