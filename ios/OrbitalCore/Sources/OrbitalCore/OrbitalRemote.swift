import Foundation

/// Tu Orbital (la consola de la TV) desde el iPhone: «Ver en la TV». Entra por el puerto público de Orbital (el del túnel
/// de Alexa), siempre con su token. Orbital pone la fuente recomendada y retoma donde ibas: el avance vive en Stremio.
public struct OrbitalRemote: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notConfigured, badToken, unreachable, refused(String)
        public var description: String {
            switch self {
            case .notConfigured: "Conecta tu Orbital en Ajustes (la dirección y el token)."
            case .badToken: "Tu Orbital no aceptó el token. Revísalo en Ajustes."
            case .unreachable: "No encontré tu Orbital. ¿Está prendida la consola y el túnel?"
            case .refused(let message): message
            }
        }
    }

    private let http: HTTPClient
    public let base: URL?
    private let token: String

    /// `orbital-ios://pair?u=<dirección>&t=<token>` (el QR de «Conectar iPhone» en la TV).
    public static func pairing(_ url: URL) -> (address: String, token: String)? {
        guard url.scheme == "orbital-ios", url.host == "pair", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let address = items.first(where: { $0.name == "u" })?.value, normalize(address) != nil,
              let token = items.first(where: { $0.name == "t" })?.value, !token.isEmpty else { return nil }
        return (address, token)
    }

    public init(http: HTTPClient, address: String, token: String) {
        self.http = http; self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.base = Self.normalize(address)
    }

    public var isConfigured: Bool { base != nil && !token.isEmpty }

    /// «orbital.midominio.com», «https://orbital.midominio.com/» o con ruta: siempre https y sin la barra final.
    public static func normalize(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    /// ¿Contesta y acepta el token?
    public func check() async throws {
        _ = try await send("api/ping", method: "GET", body: nil)
    }

    /// Lo de «Para ti» que ya está en tu Orbital (para no escribirlo otra vez en el iPhone).
    public struct Keys: Sendable, Equatable {
        public var tmdbKey: String, traktClientID: String, region: String
        /// La sesión de Trakt de la consola (nil si allá no está conectado).
        public var traktSession: BorrowedSession?
    }

    public func keys() async throws -> Keys {
        let json = try await send("api/companion", method: "GET", body: nil)
        func text(_ key: String) -> String { json?[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        var session: BorrowedSession?
        if let raw = json?["trakt_session"], let access = raw["access_token"]?.nonEmptyString {
            let expires: Double = { switch raw["expires_at"] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 } }()
            session = BorrowedSession(accessToken: access, expiresAt: expires)
        }
        return Keys(tmdbKey: text("tmdb_key"), traktClientID: text("trakt_client_id"), region: text("region"), traktSession: session)
    }

    /// Pone en la TV un título de Stremio (película o el episodio `videoID`), desde donde ibas.
    public func play(kind: String, metaID: String, videoID: String?, title: String) async throws {
        var body: [String: JSON] = ["kind": .string(kind), "id": .string(metaID), "title": .string(title)]
        if let videoID { body["video_id"] = .string(videoID) }
        _ = try await send("api/stremio/play", method: "POST", body: JSON.object(body).serialized())
    }

    // MARK: «Para ti» (RemoteForYou la usa cuando el iPhone está conectado a la consola)
    public func foryouOverview() async throws -> JSON? {
        try await send("api/foryou", method: "GET", body: nil)
    }

    public func foryouList(id: String, kind: String?) async throws -> JSON? {
        var query = [URLQueryItem(name: "id", value: id)]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        return try await send("api/foryou/list", method: "GET", query: query, body: nil)
    }

    public func foryouDetails(key: String, kind: String?) async throws -> JSON? {
        var query = [URLQueryItem(name: "key", value: key)]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        return try await send("api/foryou/details", method: "GET", query: query, body: nil)
    }

    public func foryouDismiss(key: String) async throws {
        _ = try await send("api/foryou/dismiss", method: "POST", body: JSON.object(["key": .string(key)]).serialized())
    }

    /// Lo que se ve ahora en la TV, para la tarjeta «Viendo en la TV». nil si no hay nada abierto.
    public struct NowPlaying: Sendable, Equatable {
        public var kind: String, live: Bool
        public var metaID: String?, videoID: String?
        public var title: String, episodeLabel: String
        /// Temporada y episodio en números (0 = especiales); nil en películas, TV en vivo o consolas viejas (queda `episodeLabel`).
        public var season: Int?, episode: Int?
        public var poster: String?
        public var position: Double, duration: Double, paused: Bool
        public var channel: String?, number: Int?, category: String?, muted: Bool

        public init(kind: String, live: Bool, metaID: String? = nil, videoID: String? = nil, title: String,
                    episodeLabel: String = "", poster: String? = nil, position: Double = 0, duration: Double = 0,
                    paused: Bool = false, channel: String? = nil, number: Int? = nil, category: String? = nil, muted: Bool = false,
                    season: Int? = nil, episode: Int? = nil) {
            self.kind = kind; self.live = live; self.metaID = metaID; self.videoID = videoID; self.title = title
            self.season = season; self.episode = episode
            self.episodeLabel = episodeLabel; self.poster = poster; self.position = position; self.duration = duration
            self.paused = paused; self.channel = channel; self.number = number; self.category = category; self.muted = muted
        }

        static func parse(_ json: JSON) -> NowPlaying? {
            guard let title = json["title"]?.string else { return nil }
            func number(_ key: String) -> Double {
                switch json[key] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 }
            }
            return NowPlaying(kind: json["kind"]?.string ?? "movie", live: json["live"]?.bool ?? false,
                              metaID: json["meta_id"]?.string, videoID: json["video_id"]?.string, title: title,
                              episodeLabel: json["episode_label"]?.string ?? "", poster: json["poster"]?.string,
                              position: number("position"), duration: number("duration"), paused: json["paused"]?.bool ?? false,
                              channel: json["channel"]?.string, number: json["number"]?.intValue, category: json["category"]?.string,
                              muted: json["muted"]?.bool ?? false, season: json["season"]?.intValue, episode: json["episode"]?.intValue)
        }
    }

    /// Algo que la TV le dejó al iPhone («Enviar al iPhone» o «Descargar en el iPhone»), a la espera de que la app actúe.
    public struct InboxItem: Sendable, Equatable, Codable, Identifiable {
        public enum Action: String, Sendable, Codable { case open, download }
        public var id: String
        public var kind: String
        public var metaID: String
        public var videoID: String?
        public var title: String
        public var episodeLabel: String
        /// Temporada y episodio en números (0 = especiales); nil si es película o la consola es de antes (queda `episodeLabel`).
        public var season: Int?, episode: Int?
        public var poster: String?
        public var action: Action
        public var at: Double

        public init(id: String, kind: String, metaID: String, videoID: String? = nil, title: String, episodeLabel: String = "",
                    poster: String? = nil, action: Action, at: Double = 0, season: Int? = nil, episode: Int? = nil) {
            self.id = id; self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.title = title
            self.season = season; self.episode = episode
            self.episodeLabel = episodeLabel; self.poster = poster; self.action = action; self.at = at
        }

        static func parse(_ json: JSON) -> InboxItem? {
            guard let id = json["id"]?.nonEmptyString, let metaID = json["meta_id"]?.nonEmptyString,
                  let raw = json["action"]?.string, let action = Action(rawValue: raw) else { return nil }
            let at: Double = { switch json["at"] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 } }()
            return InboxItem(id: id, kind: json["kind"]?.string ?? "movie", metaID: metaID, videoID: json["video_id"]?.nonEmptyString,
                             title: json["title"]?.string ?? "", episodeLabel: json["episode_label"]?.string ?? "",
                             poster: json["poster"]?.nonEmptyString, action: action, at: at,
                             season: json["season"]?.intValue, episode: json["episode"]?.intValue)
        }

        /// «The Office T2 · E5» (o solo el título, si es una película).
        public var displayName: String { episodeLabel.isEmpty ? title : "\(title) \(episodeLabel)" }
    }

    /// Lo que contesta la consola en cada sondeo: lo que se ve ahora y lo que la TV le dejó al iPhone.
    public struct Snapshot: Sendable, Equatable {
        public var playing: NowPlaying?
        public var inbox: [InboxItem]
    }

    /// Qué se ve ahora en la TV y qué le dejó la TV al iPhone, en una sola petición.
    public func snapshot() async throws -> Snapshot {
        let json = try await send("api/companion/now", method: "GET", body: nil)
        var playing: NowPlaying?
        if let raw = json?["playing"], !raw.isNull { playing = NowPlaying.parse(raw) }
        return Snapshot(playing: playing, inbox: (json?["inbox"]?.array ?? []).compactMap(InboxItem.parse))
    }

    /// Qué se ve ahora en la TV (para la tarjeta del iPhone). nil si no hay nada abierto.
    public func now() async throws -> NowPlaying? {
        try await snapshot().playing
    }

    /// El iPhone ya actuó sobre esos pendientes: la consola los quita de la bandeja.
    public func ack(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await send("api/companion/inbox/ack", method: "POST", body: JSON.object(["ids": .array(ids.map { .string($0) })]).serialized())
    }

    /// Un botón de la tarjeta: `toggle · pause · play · skip (con delta en segundos) · next · previous · stop · mute`.
    /// Devuelve lo que quedó viendo (nil si se detuvo).
    @discardableResult
    public func control(action: String, delta: Double? = nil) async throws -> NowPlaying? {
        var body: [String: JSON] = ["action": .string(action)]
        if let delta { body["delta"] = .double(delta) }
        let json = try await send("api/companion/player", method: "POST", body: JSON.object(body).serialized())
        guard let playing = json?["playing"], !playing.isNull else { return nil }
        return NowPlaying.parse(playing)
    }

    private func send(_ path: String, method: String, query: [URLQueryItem] = [], body: Data?) async throws -> JSON? {
        guard let base, !token.isEmpty else { throw Failure.notConfigured }
        var headers = ["Authorization": "Bearer \(token)"]
        if body != nil { headers["Content-Type"] = "application/json" }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.unreachable }
        let response: HTTPResponse
        do { response = try await http.send(HTTPRequest(url: url, method: method, headers: headers, body: body, timeout: 12)) }
        catch { throw Failure.unreachable }
        switch response.status {
        case 200..<300: return JSON.parse(response.data)
        case 401, 403: throw Failure.badToken
        case 429: throw Failure.refused("Tu Orbital pidió esperar un poco: demasiados intentos.")
        case 404 where path.hasPrefix("api/stremio") || path.hasPrefix("api/companion"):
            throw Failure.refused("Tu Orbital es de una versión anterior: actualízala para «Ver en la TV».")
        default:
            let detail = JSON.parse(response.data)?["detail"]?.string
            throw Failure.refused(detail ?? "Tu Orbital contestó con un error (\(response.status)).")
        }
    }
}
