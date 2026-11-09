import Foundation

/// La API oficial de OpenSubtitles (api.opensubtitles.com, v1), directa: muchos más subtítulos por idioma que su complemento
/// de Stremio (que da dos o tres). Dos llaves distintas:
/// - la clave de la app (`Api-Key`), registrada una vez en opensubtitles.com/consumers; vive en `Secrets.xcconfig`
///   (`ORBITAL_OPENSUBTITLES_KEY`), nunca en git. Sin ella no se usa la API y queda el complemento.
/// - tu cuenta (usuario y contraseña → un token): hace falta para bajar (cuota diaria, ~20 en las gratis). La contraseña no
///   se guarda; el token y tu usuario, en el llavero (`SecretKey.openSubtitlesAccount`).
/// Buscar no gasta cuota; bajar sí, y solo se baja el que eliges (no se adelanta ninguno). Las búsquedas se recuerdan 10 min.
public actor OpenSubtitlesAPI {
    public static let host = "https://api.opensubtitles.com/api/v1"
    public static let signUp = URL(string: "https://www.opensubtitles.com/es/users/sign_up")!
    /// Así se ven los subtítulos de la API en la lista: se bajan (con tu cuota) solo cuando eliges uno.
    public static let scheme = "opensubtitles"
    static let cacheSeconds: TimeInterval = 600

    private let http: HTTPClient
    private let apiKey: String
    private let secrets: SecretsStore
    private let userAgent: String
    private let languages: @Sendable () -> [String]
    private let clock: @Sendable () -> Date
    private var searches: [String: (expires: Date, options: [SubtitleOption])] = [:]
    private var links: [String: URL] = [:]

    public init(http: HTTPClient, apiKey: String, secrets: SecretsStore, version: String = "1.0",
                languages: @escaping @Sendable () -> [String] = { ["es", "en"] }, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines); self.secrets = secrets
        self.userAgent = "Orbital v\(version)"; self.languages = languages; self.clock = clock
    }

    /// ¿Se puede usar la API? Hace falta la clave de la app.
    public nonisolated var available: Bool { !apiKey.isEmpty }

    // MARK: tu cuenta

    public func account() -> OpenSubtitlesAccount? {
        secrets.get(SecretKey.openSubtitlesAccount).flatMap { try? JSONDecoder().decode(OpenSubtitlesAccount.self, from: Data($0.utf8)) }
    }

    private func save(_ account: OpenSubtitlesAccount?) {
        let text = account.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        secrets.set(SecretKey.openSubtitlesAccount, text)
    }

    /// Entra con tu usuario y contraseña (la contraseña no se guarda: solo el token que devuelve).
    public func login(username: String, password: String) async throws -> OpenSubtitlesAccount {
        guard available else { throw OpenSubtitlesError.noAppKey }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { throw OpenSubtitlesError.missing }
        let body = try JSONSerialization.data(withJSONObject: ["username": user, "password": password])
        let reply = try await send("/login", method: "POST", body: body, token: nil)
        guard reply.status != 401 else { throw OpenSubtitlesError.wrongPassword }
        guard reply.status < 400, let json = JSON.parse(reply.data), let token = json["token"]?.string else { throw OpenSubtitlesError.status(reply.status) }
        let info = json["user"]
        let account = OpenSubtitlesAccount(username: user, token: token, base: json["base_url"]?.string,
                                           allowed: info?["allowed_downloads"]?.intValue,
                                           remaining: info?["remaining_downloads"]?.intValue ?? info?["allowed_downloads"]?.intValue,
                                           vip: info?["vip"]?.bool ?? false)
        save(account)
        return account
    }

    /// Para pasar tu cuenta de otro aparato (la TV) sin volver a escribir la contraseña.
    public func adopt(_ account: OpenSubtitlesAccount) { save(account) }

    public func logout() { save(nil); links = [:] }

    // MARK: buscar

    /// Los subtítulos de un video (`tt123` o `tt123:1:5`), los de tu copia exacta (huella) primero y luego los más bajados.
    /// nil si la API no está, no contestó o se negó (entonces queda el complemento).
    public func search(kind: String, videoID: String, file: FileFingerprint?) async -> [SubtitleOption]? {
        guard available, let query = Self.query(videoID: videoID, file: file, languages: languages()) else { return nil }
        let key = query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        if let hit = searches[key], hit.expires > clock() { return hit.options }
        var parts = URLComponents(string: Self.host + "/subtitles")
        parts?.queryItems = query
        guard let url = parts?.url, let reply = try? await http.send(request(url, method: "GET", body: nil, token: nil)),
              reply.status < 400, let json = JSON.parse(reply.data) else { return nil }
        let options = Self.parse(json)
        searches[key] = (clock().addingTimeInterval(Self.cacheSeconds), options)
        if searches.count > 100 { searches = searches.filter { $0.value.expires > clock() } }
        return options
    }

    /// La búsqueda como la pide OpenSubtitles: parámetros en minúsculas y en orden alfabético (si no, redirige), el IMDb
    /// sin «tt» ni ceros al frente; de un episodio, el de la serie con temporada y capítulo.
    static func query(videoID: String, file: FileFingerprint?, languages: [String]) -> [URLQueryItem]? {
        let parts = videoID.split(separator: ":").map(String.init)
        guard let first = parts.first, first.hasPrefix("tt"), let number = Int(first.dropFirst(2)) else { return nil }
        var items: [String: String] = ["order_by": "download_count"]
        if parts.count >= 3, let season = Int(parts[1]), let episode = Int(parts[2]) {
            items["parent_imdb_id"] = String(number); items["season_number"] = String(season); items["episode_number"] = String(episode)
        } else {
            items["imdb_id"] = String(number)
        }
        let langs = Array(Set(languages.compactMap { SubtitleLanguage.code($0) })).sorted()
        if !langs.isEmpty { items["languages"] = langs.joined(separator: ",") }
        if let file { items["moviehash"] = file.hash }
        return items.keys.sorted().map { URLQueryItem(name: $0, value: items[$0]) }
    }

    /// La respuesta de `/subtitles` → opciones. La dirección es `opensubtitles://file/<id>`: se cambia por la de verdad
    /// (`resolve`) solo al ponerlo.
    public static func parse(_ json: JSON) -> [SubtitleOption] {
        let out: [SubtitleOption] = (json["data"]?.array ?? []).compactMap { item in
            let a = item["attributes"]
            guard let lang = a?["language"]?.string, let fileID = a?["files"]?.array?.first?["file_id"]?.intValue,
                  let url = URL(string: "\(scheme)://file/\(fileID)") else { return nil }
            return SubtitleOption(url: url, language: lang, release: a?["release"]?.string, downloads: a?["download_count"]?.intValue,
                                  hearingImpaired: a?["hearing_impaired"]?.bool ?? false, foreignOnly: a?["foreign_parts_only"]?.bool ?? false,
                                  source: "OpenSubtitles", fileID: String(fileID), exactFile: a?["moviehash_match"]?.bool ?? false)
        }
        return out.enumerated().sorted { a, b in
            if a.element.exactFile != b.element.exactFile { return a.element.exactFile }
            let da = a.element.downloads ?? -1, db = b.element.downloads ?? -1
            return da != db ? da > db : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: bajar

    /// La dirección de verdad de un subtítulo de la API (gasta una de tu cuota; la misma no se pide dos veces).
    public func resolve(_ url: URL) async throws -> URL {
        guard url.scheme == Self.scheme, let id = Int(url.lastPathComponent) else { return url }
        if let known = links[url.lastPathComponent] { return known }
        guard let account = account() else { throw OpenSubtitlesError.notConnected }
        let body = try JSONSerialization.data(withJSONObject: ["file_id": id])
        let reply = try await send("/download", method: "POST", body: body, token: account.token, base: account.base)
        if reply.status == 401 { save(nil); throw OpenSubtitlesError.notConnected }
        if reply.status == 406 || reply.status == 429 { throw OpenSubtitlesError.quota }
        guard reply.status < 400, let json = JSON.parse(reply.data), let text = json["link"]?.string, let link = URL(string: text) else {
            throw OpenSubtitlesError.status(reply.status)
        }
        var updated = account
        updated.remaining = json["remaining"]?.intValue ?? account.remaining
        save(updated)
        links[url.lastPathComponent] = link
        return link
    }

    // MARK: red

    private func request(_ url: URL, method: String, body: Data?, token: String?) -> HTTPRequest {
        var headers = ["Api-Key": apiKey, "User-Agent": userAgent, "Accept": "application/json"]
        if body != nil { headers["Content-Type"] = "application/json" }
        if let token { headers["Authorization"] = "Bearer \(token)" }
        return HTTPRequest(url: url, method: method, headers: headers, body: body, timeout: 15)
    }

    private func send(_ path: String, method: String, body: Data?, token: String?, base: String? = nil) async throws -> HTTPResponse {
        let root = base.flatMap { $0.isEmpty ? nil : "https://\($0)/api/v1" } ?? Self.host
        guard let url = URL(string: root + path) else { throw OpenSubtitlesError.status(0) }
        do { return try await http.send(request(url, method: method, body: body, token: token)) }
        catch { throw OpenSubtitlesError.offline }
    }
}

/// Tu cuenta de OpenSubtitles en este aparato: el usuario, el token y lo que queda de tu cuota de hoy. Sin contraseña.
public struct OpenSubtitlesAccount: Codable, Sendable, Equatable {
    public var username: String
    public var token: String
    /// El servidor que le tocó a tu cuenta («vip-api.opensubtitles.com» si eres VIP).
    public var base: String?
    public var allowed: Int?
    public var remaining: Int?
    public var vip = false
    public init(username: String, token: String, base: String? = nil, allowed: Int? = nil, remaining: Int? = nil, vip: Bool = false) {
        self.username = username; self.token = token; self.base = base; self.allowed = allowed; self.remaining = remaining; self.vip = vip
    }
}

public enum OpenSubtitlesError: Error, Equatable, CustomStringConvertible {
    case noAppKey, missing, wrongPassword, notConnected, quota, offline, status(Int)
    public var description: String {
        switch self {
        case .noAppKey: "Esta versión de Orbital no trae la clave de OpenSubtitles"
        case .missing: "Escribe tu usuario y tu contraseña de OpenSubtitles"
        case .wrongPassword: "El usuario o la contraseña no coinciden"
        case .notConnected: "Conecta tu cuenta de OpenSubtitles para bajar este"
        case .quota: "Ya usaste tus subtítulos de hoy en OpenSubtitles. Mañana hay más."
        case .offline: "OpenSubtitles no contestó. Intenta de nuevo en un momento."
        case .status(let code): "OpenSubtitles contestó con un error (\(code))"
        }
    }
}
