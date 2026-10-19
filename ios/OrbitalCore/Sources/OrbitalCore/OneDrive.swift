import Foundation

// OneDrive: tus películas y series guardadas ahí, como una fuente más (sin Jellyfin ni Real-Debrid). Lo mismo que
// `orbital/library/onedrive.py` en la TV:
//  · Conectar: el inicio de sesión oficial de Microsoft con un código (como Trakt): abres microsoft.com/link y escribes
//    el código. Hace falta el «ID de la aplicación» que registras gratis en Microsoft Entra (el mismo de la TV). Solo
//    pide leer tus archivos (Files.Read).
//  · La carpeta la eliges tú; solo se mira esa (y sus subcarpetas, hasta `depth` niveles).
//  · Cada video se reconoce por su nombre («Dune Part Two (2024).mkv», «Severance.S01E03.1080p.mkv») y se busca su ficha.
//  · Ver: Microsoft da una dirección temporal del archivo (~1 h) que el reproductor abre directo (y se puede descargar).

public enum OneDriveError: Error, Sendable, Equatable, CustomStringConvertible {
    case message(String)
    /// La sesión ya no sirve: hay que volver a conectar.
    case auth(String)
    public var description: String { switch self { case .message(let m), .auth(let m): return m } }
}

/// Qué es un archivo por su nombre.
public struct OneDriveName: Sendable, Equatable, Codable {
    public var kind: String          // movie | series
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?

    public static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "webm", "ts", "wmv"]

    /// «Dune Part Two (2024) 2160p.mkv» → película «Dune Part Two», 2024. «Severance.S01E03.1080p.mkv» → serie, T1 E3.
    /// El año es el último que sea año de verdad (no futuro): «Blade Runner 2049 (2017)» es de 2017; «2012.mkv», un título.
    public static func parse(_ name: String, now: Date = Date()) -> OneDriveName? {
        let ns = name as NSString
        guard videoExtensions.contains(ns.pathExtension.lowercased()) else { return nil }
        var stem = replace(ns.deletingPathExtension, #"[._]+"#, " ")
        stem = replace(stem, #"\[[^\]]*\]|\{[^}]*\}"#, " ")
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: now)
        if let m = first(#"\b[Ss](\d{1,2})\s*[Ee](\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b"#, stem) {
            let season = Int(group(m, 1, stem) ?? group(m, 3, stem) ?? "") ?? 0
            let episode = Int(group(m, 2, stem) ?? group(m, 4, stem) ?? "") ?? 0
            var title = String(stem[..<Range(m.range, in: stem)!.lowerBound])
            let year = first(#"\b(19|20)\d{2}\b"#, title).flatMap { group($0, 0, title) }.flatMap(Int.init)
            title = replace(title, #"\(?\b(19|20)\d{2}\b\)?"#, " ")
            return OneDriveName(kind: "series", title: clean(title), year: year, season: season, episode: episode)
        }
        var year: Int?
        let years = all(#"\(?\b((?:19|20)\d{2})\b\)?"#, stem).filter { m in
            m.range.location > 0 && (Int(group(m, 1, stem) ?? "") ?? 0) <= thisYear + 1
        }
        if let last = years.last {
            year = Int(group(last, 1, stem) ?? "")
            stem = String(stem[..<Range(last.range, in: stem)!.lowerBound])
        }
        if let cut = first(#"\b(2160p|1080p|720p|480p|4k|uhd|bluray|blu ray|web ?dl|webrip|hdrip|dvdrip|x264|x265|hevc|remux)\b"#, stem, caseless: true) {
            stem = String(stem[..<Range(cut.range, in: stem)!.lowerBound])
        }
        let title = clean(stem)
        return title.isEmpty ? nil : OneDriveName(kind: "movie", title: title, year: year)
    }

    static func clean(_ text: String) -> String {
        let trimmed = replace(replace(text, #"[()\-–]+\s*$"#, ""), #"\s+"#, " ")
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: " -–()"))
    }

    private static func regex(_ pattern: String, caseless: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseless ? [.caseInsensitive] : [])
    }
    private static func replace(_ text: String, _ pattern: String, _ with: String) -> String {
        regex(pattern).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: with)
    }
    private static func first(_ pattern: String, _ text: String, caseless: Bool = false) -> NSTextCheckingResult? {
        regex(pattern, caseless: caseless).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func all(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        regex(pattern).matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String? {
        guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }
}

/// Un video de tu carpeta de OneDrive.
public struct OneDriveFile: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var size: Int
    public var info: OneDriveName
    /// Cuándo lo subiste (para «Recién agregado»).
    public var added: Date?
    public init(id: String, name: String, path: String, size: Int, info: OneDriveName, added: Date? = nil) {
        self.id = id; self.name = name; self.path = path; self.size = size; self.info = info; self.added = added
    }
}

/// Una carpeta, para elegir dónde están tus películas.
public struct OneDriveFolder: Sendable, Equatable, Identifiable {
    public var name: String
    public var path: String
    public var count: Int
    public var id: String { path }
}

public actor OneDrive {
    public static let login = "https://login.microsoftonline.com/common/oauth2/v2.0"
    public static let graph = "https://graph.microsoft.com/v1.0"
    public static let scope = "Files.Read offline_access"
    public static let depth = 4          // subcarpetas que se recorren («Series/Adventure Time/Temporada 5»)
    public static let maxFiles = 5000

    private let http: HTTPClient
    private let secrets: SecretsStore
    private let clientIDProvider: @Sendable () -> String
    private let clock: @Sendable () -> Date
    private var refreshing: Task<Tokens, Error>?

    public init(http: HTTPClient, secrets: SecretsStore, clientID: @escaping @Sendable () -> String, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.secrets = secrets; self.clientIDProvider = clientID; self.clock = clock
    }

    // MARK: cuenta
    public nonisolated var clientID: String { clientIDProvider().trimmingCharacters(in: .whitespacesAndNewlines) }
    public nonisolated var configured: Bool { !clientID.isEmpty }
    public nonisolated var linked: Bool { tokens() != nil }

    struct Tokens: Codable { var access_token: String; var refresh_token: String?; var expires_at: Double }

    private nonisolated func tokens() -> Tokens? {
        guard let raw = secrets.get(SecretKey.oneDriveTokens), let data = raw.data(using: .utf8),
              let t = try? JSONDecoder().decode(Tokens.self, from: data), !t.access_token.isEmpty else { return nil }
        return t
    }

    private func save(_ data: JSON) {
        guard let access = data["access_token"]?.nonEmptyString else { return }
        let expires = number(data["expires_in"]) ?? 3600
        let tokens = Tokens(access_token: access, refresh_token: data["refresh_token"]?.nonEmptyString ?? self.tokens()?.refresh_token,
                            expires_at: clock().timeIntervalSince1970 + expires)
        secrets.set(SecretKey.oneDriveTokens, (try? JSONEncoder().encode(tokens)).flatMap { String(data: $0, encoding: .utf8) })
    }

    public nonisolated func unlink() { secrets.set(SecretKey.oneDriveTokens, nil) }

    private nonisolated func number(_ j: JSON?) -> Double? {
        switch j { case .int(let i)?: return Double(i); case .double(let d)?: return d; case .string(let s)?: return Double(s); default: return nil }
    }

    private func form(_ path: String, _ fields: [(String, String)]) async throws -> (Int, JSON?) {
        var c = URLComponents(); c.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        let body = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        do {
            let r = try await http.send(HTTPRequest(url: URL(string: "\(Self.login)\(path)")!, method: "POST",
                                                    headers: ["Content-Type": "application/x-www-form-urlencoded"], body: body, timeout: 15))
            return (r.status, JSON.parse(r.data))
        } catch { throw OneDriveError.message("No pude conectar con Microsoft.") }
    }

    public func deviceCode() async throws -> DeviceCode {
        guard configured else { throw OneDriveError.message("Falta el ID de la aplicación de OneDrive.") }
        let (status, data) = try await form("/devicecode", [("client_id", clientID), ("scope", Self.scope)])
        guard status == 200, let device = data?["device_code"]?.nonEmptyString, let user = data?["user_code"]?.nonEmptyString else {
            throw OneDriveError.message("Microsoft no dio un código. Revisa el ID de la aplicación.")
        }
        let interval = min(max(number(data?["interval"]) ?? 5, 1), 60)
        let expires = min(max(number(data?["expires_in"]) ?? 900, 1), 3600)
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: data?["verification_uri"]?.nonEmptyString ?? "https://www.microsoft.com/link",
                          interval: interval, expiresAt: clock().addingTimeInterval(expires))
    }

    /// Una consulta: `.linked`, `.pending`, `.slow` o `.expired`/`.denied`/`.invalid`.
    public func pollDevice(_ code: DeviceCode) async throws -> DeviceStatus {
        let (status, data) = try await form("/token", [("grant_type", "urn:ietf:params:oauth:grant-type:device_code"), ("client_id", clientID), ("device_code", code.deviceCode)])
        if status == 200, let data, data["access_token"]?.nonEmptyString != nil { save(data); return .linked }
        return ["authorization_pending": .pending, "slow_down": .slow, "expired_token": .expired, "authorization_declined": .denied,
                "bad_verification_code": .invalid][data?["error"]?.string ?? ""] ?? .pending
    }

    /// Renueva la sesión UNA sola vez aunque varias peticiones la pidan a la vez.
    private func access() async throws -> String {
        guard let tokens = tokens() else { throw OneDriveError.auth("Conecta tu OneDrive en Ajustes.") }
        guard clock().timeIntervalSince1970 > tokens.expires_at - 300 else { return tokens.access_token }
        if let refreshing { return try await refreshing.value.access_token }
        let task = Task<Tokens, Error> {
            let (status, data) = try await form("/token", [("grant_type", "refresh_token"), ("client_id", clientID),
                                                            ("refresh_token", tokens.refresh_token ?? ""), ("scope", Self.scope)])
            guard status == 200, let data, data["access_token"]?.nonEmptyString != nil else {
                // Solo un rechazo (400/401) desconecta; un error del servidor es pasajero.
                if [400, 401].contains(status) { unlink(); throw OneDriveError.auth("Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes.") }
                throw OneDriveError.message("Microsoft respondió HTTP \(status)")
            }
            save(data)
            return self.tokens() ?? tokens
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value.access_token
    }

    // MARK: archivos
    private func get(_ urlOrPath: String) async throws -> JSON {
        guard let url = URL(string: urlOrPath.hasPrefix("http") ? urlOrPath : "\(Self.graph)\(urlOrPath)") else { throw OneDriveError.message("Carpeta inválida") }
        let response: HTTPResponse
        do { response = try await http.send(HTTPRequest(url: url, headers: ["Authorization": "Bearer \(try await access())"], timeout: 15)) }
        catch let error as OneDriveError { throw error }
        catch { throw OneDriveError.message("No pude conectar con OneDrive.") }
        switch response.status {
        case 200: guard let json = JSON.parse(response.data), json.object != nil else { fallthrough }; return json
        case 401: throw OneDriveError.auth("Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes.")
        case 404: throw OneDriveError.message("Esa carpeta ya no está en tu OneDrive.")
        default: throw OneDriveError.message("OneDrive respondió HTTP \(response.status)")
        }
    }

    static func childrenPath(_ path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let select = "$select=id,name,size,folder,file,createdDateTime&$top=200"
        return clean.isEmpty ? "/me/drive/root/children?\(select)" : "/me/drive/root:/\(uriComponent(clean, safe: "/")):/children?\(select)"
    }

    /// Lo que hay en una carpeta, todas sus páginas.
    public func children(_ path: String = "") async throws -> [JSON] {
        var out: [JSON] = [], next: String? = Self.childrenPath(path)
        while let url = next, out.count < Self.maxFiles {
            let data = try await get(url)
            out += (data["value"]?.array ?? []).filter { $0.object != nil }
            next = data["@odata.nextLink"]?.nonEmptyString
        }
        return out
    }

    /// Las subcarpetas de una carpeta (para elegir dónde están tus películas).
    public func folders(_ path: String = "") async throws -> [OneDriveFolder] {
        let base = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try await children(path).compactMap { r in
            guard r["folder"]?.object != nil, let name = r["name"]?.nonEmptyString else { return nil }
            let count = r["folder"]?["childCount"]?.intValue ?? 0
            return OneDriveFolder(name: name, path: base.isEmpty ? name : "\(base)/\(name)", count: count)
        }
    }

    /// Los videos de esa carpeta y sus subcarpetas.
    public func videos(_ path: String) async throws -> [OneDriveFile] {
        var found: [OneDriveFile] = []
        func walk(_ folder: String, _ depth: Int) async throws {
            for r in try await children(folder) {
                if found.count >= Self.maxFiles { return }
                let name = r["name"]?.string ?? ""
                let child = folder.isEmpty ? name : "\(folder)/\(name)"
                if r["folder"]?.object != nil, depth < Self.depth { try await walk(child, depth + 1) }
                else if r["file"]?.object != nil, let id = r["id"]?.nonEmptyString, let info = OneDriveName.parse(name, now: clock()) {
                    let added = r["createdDateTime"]?.string.flatMap { ISO8601DateFormatter().date(from: $0.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)) }
                    found.append(OneDriveFile(id: id, name: name, path: child, size: r["size"]?.intValue ?? 0, info: info, added: added))
                }
            }
        }
        try await walk(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), 0)
        return found
    }

    /// Lo que hay en una carpeta, para verla tal cual (la vista de carpetas de Mi media): carpetas y videos.
    public func listing(_ path: String) async throws -> (folders: [OneDriveFolder], videos: [OneDriveFile]) {
        let base = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var folders: [OneDriveFolder] = [], videos: [OneDriveFile] = []
        for r in try await children(base) {
            guard let name = r["name"]?.nonEmptyString else { continue }
            let child = base.isEmpty ? name : "\(base)/\(name)"
            if r["folder"]?.object != nil { folders.append(OneDriveFolder(name: name, path: child, count: r["folder"]?["childCount"]?.intValue ?? 0)) }
            else if r["file"]?.object != nil, let id = r["id"]?.nonEmptyString, let info = OneDriveName.parse(name, now: clock()) {
                videos.append(OneDriveFile(id: id, name: name, path: child, size: r["size"]?.intValue ?? 0, info: info))
            }
        }
        return (folders, videos)
    }

    /// La dirección temporal del archivo (~1 h), para que el reproductor lo lea por partes o se descargue.
    public func streamURL(_ itemID: String) async throws -> URL {
        guard itemID.range(of: #"^[A-Za-z0-9!._-]{1,200}$"#, options: .regularExpression) != nil else { throw OneDriveError.message("Archivo inválido") }
        let data = try await get("/me/drive/items/\(itemID)?$select=id,@microsoft.graph.downloadUrl")
        guard let text = data["@microsoft.graph.downloadUrl"]?.string, text.hasPrefix("https://"), let url = URL(string: text) else {
            throw OneDriveError.message("OneDrive no dio la dirección del archivo.")
        }
        return url
    }
}
