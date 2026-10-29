import Foundation

/// Cliente de Trakt. Hay que registrar una aplicación de la API de Trakt (client id). Las cuentas gratuitas
/// tienen un tope de apps conectadas: si Trakt no deja conectar, se avisa (`TraktError.auth`/`.http`) y el
/// resto de la app sigue funcionando.
public actor Trakt {
    /// Trakt cerró la sesión (no la red): la app lo avisa una vez, con un botón para conectarla otra vez (antes se desconectaba
    /// en silencio y Para ti se volvía genérico).
    public static let sessionLost = Notification.Name("orbital.trakt.session-lost")
    static func announceSessionLost() { NotificationCenter.default.post(name: sessionLost, object: nil) }

    public static let api = URL(string: "https://api.trakt.tv")!
    public static let redirect = "urn:ietf:wg:oauth:2.0:oob"

    private let http: HTTPClient
    private let secrets: SecretsStore
    private let clientID: String
    private let clientSecret: String
    private let clock: @Sendable () -> Date
    private let pause: @Sendable (TimeInterval) async -> Void
    private var lastWrite = Date.distantPast
    /// Lo que dejaste a medias (`/sync/playback`), guardado un momento: abrir varios títulos seguidos no pregunta cada vez.
    private var playbackCache: (at: Date, items: [TraktPlayback])?
    static let playbackCacheFor: TimeInterval = 60
    /// Tus favoritos, guardados un momento con la marca de cuándo cambiaron en Trakt (`favorites.updated_at` de
    /// `/sync/last_activities`): pasado el rato, si la marca no cambió no se vuelven a bajar las dos listas.
    private var favoritesCache: (at: Date, stamp: String?, items: [TraktEntry])?
    static let favoritesCacheFor: TimeInterval = 60
    /// Trakt guarda hasta 100 favoritos (entre películas y series); al pasarse responde 420.
    public static let favoritesLimit = 100
    public static let favoritesFullMessage = "Llegaste a 100 favoritos en Trakt: quita uno para agregar otro."

    public init(http: HTTPClient, secrets: SecretsStore, clientID: String, clientSecret: String = "",
                clock: @escaping @Sendable () -> Date = { Date() },
                pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.http = http; self.secrets = secrets; self.clientID = clientID; self.clientSecret = clientSecret; self.clock = clock; self.pause = pause
    }

    static func isIMDb(_ id: String) -> Bool { id.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil }

    // MARK: cuenta
    public nonisolated var configured: Bool { !clientID.isEmpty }
    public nonisolated var linked: Bool { tokens() != nil }

    private struct Tokens: Codable { var access_token: String; var refresh_token: String?; var expires_at: Double }

    /// La sesión es la que antes prestaba tu Orbital (sin la parte que la renueva). Ya no se usa: cada dispositivo tiene la suya.
    public nonisolated var borrowed: Bool { tokens().map { ($0.refresh_token ?? "").isEmpty } ?? false }

    /// Olvida aquí la sesión prestada de antes, SIN revocarla (revocarla desconectaría también la consola). Devuelve si había una.
    @discardableResult
    public nonisolated func forgetBorrowedSession() -> Bool {
        guard borrowed else { return false }
        secrets.set(SecretKey.traktTokens, nil)
        return true
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
                    secrets.set(SecretKey.traktTokens, nil); Trakt.announceSessionLost()
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
        var (status, data) = try await call("GET", path, auth: auth, params: params)
        if status == 401 && auth {
            // Como en las escrituras: se renueva la sesión UNA vez antes de darla por perdida.
            try await renewAfterRejection()
            (status, data) = try await call("GET", path, auth: auth, params: params)
            if status == 401 { secrets.set(SecretKey.traktTokens, nil); Trakt.announceSessionLost(); throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.") }
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
            // Un 401 no siempre es el final: se renueva la sesión UNA vez y se reintenta.
            try await renewAfterRejection()
            result = try await call("POST", path, body: body)
            if result.0 == 401 { secrets.set(SecretKey.traktTokens, nil); Trakt.announceSessionLost(); throw TraktError.auth("Trakt cerró tu sesión: vuelve a conectarla en Ajustes.") }
        }
        return result
    }

    /// Trakt rechazó la sesión (401). Con refresh token se renueva (ya limpia la sesión si Trakt también lo rechaza); una sin él
    /// (la prestada de antes) no se puede renovar: se olvida aquí y se avisa para conectar Trakt en este iPhone.
    private func renewAfterRejection() async throws {
        guard let old = tokens() else { throw TraktError.auth("Conecta tu cuenta de Trakt en Ajustes.") }
        if !(old.refresh_token ?? "").isEmpty { _ = try await refresh(old); return }
        secrets.set(SecretKey.traktTokens, nil); Trakt.announceSessionLost()
        throw TraktError.auth("Conecta Trakt en este iPhone (Ajustes › Trakt).")
    }

    /// La calificación de la comunidad de Trakt (0–10) y cuántos votaron; nil si nadie ha votado.
    public func rating(kind: String, imdb: String) async throws -> (rating: Double, votes: Int)? {
        let path = "/\(kind == "movie" ? "movies" : "shows")/\(imdb)/ratings"
        guard let row = try await get(path, auth: false), let rating = row["rating"]?.doubleValue, rating > 0 else { return nil }
        return (rating, row["votes"]?.intValue ?? 0)
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

    /// Tus favoritos de Trakt (películas y series, lo último que marcaste primero), guardados `favoritesCacheFor` segundos.
    /// Pasado ese rato se pregunta primero si cambiaron (una respuesta chiquita) y solo entonces se bajan otra vez.
    public func favorites(fresh: Bool = false) async throws -> [TraktEntry] {
        if !fresh, let cache = favoritesCache {
            if clock().timeIntervalSince(cache.at) < Self.favoritesCacheFor { return cache.items }
            if let stamp = cache.stamp, let now = try? await favoritesStamp(), now == stamp {
                favoritesCache = (clock(), stamp, cache.items)   // no cambiaron: otro rato con los mismos
                return cache.items
            }
        }
        // La marca, las películas y las series, las tres a la vez. Sin marca (Trakt no la dio) se guardan igual, solo que la
        // próxima vez se bajan completas.
        async let stamp = try? favoritesStamp()
        async let movies = get("/sync/favorites/movies", [("extended", "full")])
        async let shows = get("/sync/favorites/shows", [("extended", "full")])
        let items = TraktParsing.favorites((try await movies?.array ?? []) + (try await shows?.array ?? []))
        favoritesCache = (clock(), await stamp ?? nil, items)
        return items
    }

    /// Cuándo cambiaron tus favoritos por última vez en Trakt (cualquier dispositivo): `favorites.updated_at`.
    func favoritesStamp() async throws -> String? {
        try await get("/sync/last_activities")?["favorites"]?["updated_at"]?.nonEmptyString
    }

    public func lists() async throws -> [(id: String, name: String)] {
        try await ownLists().map { ($0.id, $0.name) }
    }

    /// Una de tus listas, con cuándo cambió por última vez («Guardar en…» pone arriba las recientes).
    public struct OwnList: Equatable, Sendable {
        public var id: String
        public var name: String
        public var updatedAt: Date?
        public init(id: String, name: String, updatedAt: Date? = nil) { self.id = id; self.name = name; self.updatedAt = updatedAt }
    }

    /// Tus listas tal como las acomodaste en Trakt, con su fecha de cambio (`updated_at`, o `created_at` si no viene).
    public func ownLists() async throws -> [OwnList] {
        let rows = try await get("/users/me/lists")
        return (rows?.array ?? []).compactMap { row in
            guard let name = row["name"]?.string?.trimmingCharacters(in: .whitespaces), !name.isEmpty, let id = row["ids"]?["trakt"]?.intValue else { return nil }
            return OwnList(id: String(id), name: name, updatedAt: (row["updated_at"]?.string ?? row["created_at"]?.string).flatMap(TraktParsing.date))
        }
    }

    /// Qué títulos (IMDb) tiene una de tus listas: para marcar ✓ en «Guardar en…» (sin datos extra: es rápido).
    public func listMembers(_ id: String) async throws -> Set<String> {
        guard Self.isListID(id) else { throw TraktError.invalid("Lista inválida") }
        let rows = try await get("/users/me/lists/\(id)/items")?.array ?? []
        return Set(rows.compactMap { ($0["movie"] ?? $0["show"])?["ids"]?["imdb"]?.string })
    }

    /// Todo lo que ya viste (películas y series con al menos un episodio), por IMDb: «Decide por mí» no te propone eso.
    public func watchedIDs() async throws -> Set<String> {
        async let movies = get("/sync/watched/movies")
        async let shows = get("/sync/watched/shows", [("extended", "noseasons")])
        let rows = (try await movies?.array ?? []) + (try await shows?.array ?? [])
        return Set(rows.compactMap { ($0["movie"] ?? $0["show"])?["ids"]?["imdb"]?.string })
    }

    static func isListID(_ id: String) -> Bool { !id.isEmpty && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber) }

    public func listItems(_ id: String) async throws -> [TraktEntry] {
        guard !id.isEmpty, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else { throw TraktError.invalid("Lista inválida") }
        return TraktParsing.typed(try await get("/users/me/lists/\(id)/items", [("extended", "full")])?.array)
    }

    /// Los títulos de una lista pública de otra persona (sin tu sesión): las series de «Aprobadas por la crítica».
    public func publicListItems(user: String, slug: String) async throws -> [TraktEntry] {
        let safe = { (part: String) in !part.isEmpty && part.range(of: #"^[\w.-]+$"#, options: .regularExpression) != nil }
        guard safe(user), safe(slug) else { throw TraktError.invalid("Lista inválida") }
        return TraktParsing.typed(try await get("/users/\(user)/lists/\(slug)/items", auth: false, [("extended", "full")])?.array)
    }

    /// Lo que más se está viendo ahora; con `genres` («science-fiction»), solo de ese género («Por género» en Buscar).
    public func trending(kind: String, limit: Int = 30, genres: String? = nil) async throws -> [TraktEntry] {
        var params = [("limit", String(limit)), ("extended", "full")]
        if let genres { params.append(("genres", genres)) }
        let rows = try await get("/\(TraktParsing.kinds[kind]!)/trending", auth: false, params)
        let key = kind == "movie" ? "movie" : "show"
        return (rows?.array ?? []).compactMap { TraktParsing.entry($0[key], kind: kind) }
    }

    /// Lo más popular; con `years` («2024» o «1990-1999»), solo de esos años («Por año» en Colecciones), y con `genres`, de ese género.
    public func popular(kind: String, limit: Int = 30, years: String? = nil, genres: String? = nil) async throws -> [TraktEntry] {
        var params = [("limit", String(limit)), ("extended", "full")]
        if let years { params.append(("years", years)) }
        if let genres { params.append(("genres", genres)) }
        let rows = try await get("/\(TraktParsing.kinds[kind]!)/popular", auth: false, params)
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

    /// Lo que viste entre dos fechas (cada película y cada episodio con su día y hora), por páginas: «Tu año» y «Porque viste».
    public func plays(since: Date, until: Date, maxPages: Int = 20) async throws -> [TraktPlay] {
        let f = ISO8601DateFormatter()
        var out: [TraktPlay] = []
        for page in 1...max(1, maxPages) {
            let rows = try await get("/sync/history", [("start_at", f.string(from: since)), ("end_at", f.string(from: until)),
                                                       ("extended", "full"), ("limit", String(Self.historyPage)), ("page", String(page))])?.array ?? []
            out += rows.compactMap(TraktParsing.play)
            if rows.count < Self.historyPage { break }
        }
        return out
    }

    static let historyPage = 250

    /// Lo último que viste (película o serie), lo más reciente primero, sin repetir.
    public func recentlyWatched(limit: Int = 5) async throws -> [TraktEntry] {
        let rows = try await get("/sync/history", [("limit", "40"), ("extended", "full")])?.array ?? []
        var seen = Set<String>(), out: [TraktEntry] = []
        for row in rows {
            var entry = row["type"]?.string == "movie" ? TraktParsing.entry(row["movie"], kind: "movie") : TraktParsing.entry(row["show"], kind: "series")
            entry?.watchedAt = row["watched_at"]?.string.flatMap(TraktParsing.date)   // el historial viene del más nuevo al más viejo
            if let entry, seen.insert(entry.imdb).inserted { out.append(entry) }
            if out.count >= limit { break }
        }
        return out
    }

    /// Buscar películas y series por nombre (lo primero que pregunta Buscar; Cinemeta es el respaldo). No pide tu sesión.
    public func search(_ query: String, limit: Int = 20) async throws -> [TraktEntry] {
        let rows = try await get("/search/movie,show", auth: false, [("query", query), ("limit", String(limit)), ("extended", "full")])?.array ?? []
        return rows.compactMap { row in
            row["type"]?.string == "movie" ? TraktParsing.entry(row["movie"], kind: "movie") : TraktParsing.entry(row["show"], kind: "series")
        }
    }

    /// Los títulos que Trakt relaciona con uno («Porque viste X»).
    public func related(kind: String, imdb: String, limit: Int = 15) async throws -> [TraktEntry] {
        guard Self.isIMDb(imdb) else { return [] }
        let rows = try await get("/\(kind == "movie" ? "movies" : "shows")/\(imdb)/related", auth: false, [("limit", String(limit)), ("extended", "full")])
        return (rows?.array ?? []).compactMap { TraktParsing.entry($0, kind: kind) }
    }

    /// Lo que dejaste a medias en cualquier dispositivo (películas y episodios), guardado `playbackCacheFor` segundos.
    public func playback(fresh: Bool = false) async throws -> [TraktPlayback] {
        if !fresh, let cache = playbackCache, clock().timeIntervalSince(cache.at) < Self.playbackCacheFor { return cache.items }
        let items = (try await get("/sync/playback")?.array ?? []).compactMap(TraktParsing.playback)
        playbackCache = (clock(), items)
        return items
    }

    /// Dónde lo dejaste según Trakt (la pausa más reciente de esa película o ese episodio); nil sin sesión o si no hay.
    public func paused(_ target: TraktTarget) async -> TraktPlayback? {
        guard linked, let items = try? await playback() else { return nil }
        return items.filter { $0.target == target }.max { $0.pausedAt < $1.pausedAt }
    }

    // MARK: escritura
    public func setWatchlist(imdb: String, series: Bool, add: Bool) async throws {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        let body: JSON = series ? ["shows": [["ids": ["imdb": .string(imdb)]]]] : ["movies": [["ids": ["imdb": .string(imdb)]]]]
        let (status, _) = try await write(add ? "/sync/watchlist" : "/sync/watchlist/remove", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Pone o quita un título de tus favoritos de Trakt (el corazón). Con 100 ya no cabe otro: Trakt responde 420 y se dice
    /// claro qué hacer (`favoritesFullMessage`).
    public func setFavorite(imdb: String, series: Bool, add: Bool) async throws {
        guard Self.isIMDb(imdb) else { throw TraktError.invalid("Título inválido") }
        let (status, _) = try await write(add ? "/sync/favorites" : "/sync/favorites/remove", Self.itemBody(imdb: imdb, series: series))
        favoritesCache = nil   // la próxima lectura ya trae el cambio
        if status == 420 { throw TraktError.invalid(Self.favoritesFullMessage) }
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// `{"movies":[{"ids":{"imdb":…}}]}` o `{"shows":[…]}`: el cuerpo de la watchlist, las listas y los favoritos.
    static func itemBody(imdb: String, series: Bool) -> JSON {
        series ? ["shows": [["ids": ["imdb": .string(imdb)]]]] : ["movies": [["ids": ["imdb": .string(imdb)]]]]
    }

    /// Pone o quita un título de una de tus listas.
    public func setListItem(listID: String, imdb: String, series: Bool, add: Bool) async throws {
        guard Self.isIMDb(imdb), Self.isListID(listID) else { throw TraktError.invalid("Título inválido") }
        let body: JSON = series ? ["shows": [["ids": ["imdb": .string(imdb)]]]] : ["movies": [["ids": ["imdb": .string(imdb)]]]]
        let (status, _) = try await write("/users/me/lists/\(listID)/items\(add ? "" : "/remove")", body)
        guard status == 200 || status == 201 else { throw TraktError.http(status) }
    }

    /// Una lista nueva (privada); devuelve su id.
    public func createList(name: String) async throws -> (id: String, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TraktError.invalid("Ponle nombre a la lista") }
        let (status, json) = try await write("/users/me/lists", ["name": .string(clean), "privacy": "private"])
        guard status == 200 || status == 201, let id = json?["ids"]?["trakt"]?.intValue else { throw TraktError.http(status) }
        return (String(id), clean)
    }

    /// Avisa a Trakt de lo que reproduces. `progress` va de 0 a 100; por encima de ~80 % al parar, Trakt lo marca visto.
    @discardableResult
    public func scrobble(_ action: ScrobbleAction, _ target: TraktTarget, progress: Double) async throws -> ScrobbleResult {
        guard Self.isIMDb(target.imdb) else { throw TraktError.invalid("Título inválido") }
        var body = target.body.object ?? [:]
        body["progress"] = .double(min(100, max(0, progress)))
        let (status, _) = try await write("/scrobble/\(action.rawValue)", .object(body))
        if action != .start { playbackCache = nil }   // una pausa o un cierre cambian dónde ibas: la próxima lectura es nueva
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
