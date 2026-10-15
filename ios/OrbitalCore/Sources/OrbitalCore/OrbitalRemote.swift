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
