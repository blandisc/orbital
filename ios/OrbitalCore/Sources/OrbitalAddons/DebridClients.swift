import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Lo que se le pide a tu nube para bajar algo que todavía no tiene (R12, R13), sea cual sea (DN1): agregar el torrent,
/// elegir archivos, ver cuánto lleva, el enlace para verlo, cuántos van y cancelarlo. Cada nube contesta en la forma de
/// Real-Debrid (`RDTorrent`, sus estados), así la libreta, sus avisos y sus pruebas son una sola (`client` del contrato).
public protocol DebridTorrentAPI: Sendable {
    func addMagnet(hash: String, token: String) async throws -> String
    func selectFiles(id: String, files: [Int], token: String) async throws
    func info(id: String, token: String) async throws -> RDTorrent
    func unrestrict(link: String, token: String) async throws -> URL
    func list(limit: Int, token: String) async throws -> [RDTorrent]
    func activeCount(token: String) async throws -> (active: Int, limit: Int)
    func delete(id: String, token: String) async throws
}

extension RealDebridTorrents: DebridTorrentAPI {}

/// La tabla de errores de una nube (`design/torbox-errors.json`, `design/alldebrid-errors.json`): primero manda su código; sin
/// él (o con uno que no está), el HTTP; otro 5xx es «espera», lo demás «otra cosa». Igual que `RDErrorCause`.
public struct DebridErrorTable: Sendable {
    public let codes: [String: RDErrorCause]
    public let http: [Int: RDErrorCause]
    public func cause(status: Int?, code: String?) -> RDErrorCause {
        if let code, let cause = codes[code] { return cause }
        guard let status else { return .other }
        return http[status] ?? ((500..<600).contains(status) ? .slowDown : .other)
    }

    public static let torBox = DebridErrorTable(codes: [
        "NO_AUTH": .invalidSession, "BAD_TOKEN": .invalidSession, "AUTH_ERROR": .invalidSession, "OAUTH_VERIFICATION_ERROR": .invalidSession,
        "PLAN_RESTRICTED_FEATURE": .noPremium, "ITEM_NOT_FOUND": .gone, "ACTIVE_LIMIT": .tooMany, "MONTHLY_LIMIT": .tooMany,
        "COOLDOWN_LIMIT": .slowDown, "DOWNLOAD_TOO_LARGE": .refused, "TOO_MUCH_DATA": .refused, "BOZO_TORRENT": .refused,
        "LINK_OFFLINE": .refused, "NO_SERVERS_AVAILABLE_ERROR": .slowDown, "DOWNLOAD_SERVER_ERROR": .slowDown, "DATABASE_ERROR": .slowDown,
        "VENDOR_DISABLED": .slowDown, "DUPLICATE_ITEM": .other, "INVALID_OPTION": .other, "MISSING_REQUIRED_OPTION": .other,
        "UNKNOWN_ERROR": .other, "ENDPOINT_NOT_FOUND": .other,
    ], http: [401: .invalidSession, 402: .noPremium, 403: .noPremium, 404: .gone, 429: .slowDown, 503: .slowDown])

    public static let allDebrid = DebridErrorTable(codes: [
        "AUTH_MISSING_APIKEY": .invalidSession, "AUTH_BAD_APIKEY": .invalidSession, "AUTH_BLOCKED": .noPremium, "AUTH_USER_BANNED": .noPremium,
        "MUST_BE_PREMIUM": .noPremium, "MAGNET_MUST_BE_PREMIUM": .noPremium, "FREE_TRIAL_LIMIT_REACHED": .noPremium, "NO_SERVER": .noPremium,
        "MAGNET_NO_SERVER": .noPremium, "MAGNET_TOO_MANY_ACTIVE": .tooMany, "MAGNET_INVALID_ID": .gone, "MAGNET_INVALID_URI": .refused,
        "MAGNET_INVALID_FILE": .refused, "MAGNET_FILE_UPLOAD_FAILED": .refused, "MAGNET_NO_URI": .other, "MAGNET_PROCESSING": .other,
        "LINK_DOWN": .refused, "LINK_HOST_NOT_SUPPORTED": .refused, "LINK_NOT_SUPPORTED": .refused, "LINK_TEMPORARY_UNAVAILABLE": .slowDown,
        "LINK_HOST_UNAVAILABLE": .slowDown, "LINK_HOST_FULL": .slowDown, "LINK_TOO_MANY_DOWNLOADS": .tooMany, "LINK_HOST_LIMIT_REACHED": .tooMany,
        "LINK_ERROR": .other,
    ], http: [401: .invalidSession, 403: .noPremium, 404: .gone, 429: .slowDown, 503: .slowDown])
}

/// El archivo que toca de un torrent ya bajado (`client.pick_file`): primero el que dice «S01E03» o «1x03» en su nombre (TorBox
/// y AllDebrid no siempre numeran como el torrent); si no, el de `fileIdx + 1`; si no, el video más grande.
public enum DebridFilePick {
    public static func pick(_ files: [RDFile], fileIdx: Int?, season: Int?, episode: Int?) -> RDFile? {
        let videos = files.filter(\.isVideo).isEmpty ? files : files.filter(\.isVideo)
        if let season, let episode,
           let mark = try? NSRegularExpression(pattern: "(?i)(s0*\(season)[ ._-]?e0*\(episode)(?!\\d)|(?<!\\d)0*\(season)x0*\(episode)(?!\\d))") {
            let named = videos.filter { mark.firstMatch(in: $0.path, range: NSRange($0.path.startIndex..., in: $0.path)) != nil }
            if let best = named.max(by: { $0.bytes < $1.bytes }) { return best }
        }
        if let fileIdx, let exact = files.first(where: { $0.id == fileIdx + 1 }) { return exact }
        return videos.max { $0.bytes < $1.bytes }
    }

    /// «tt0903747:1:3» → (1, 3).
    public static func episode(of videoID: String) -> (season: Int, episode: Int)? {
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return nil }
        return (s, e)
    }
}

/// Lo común de TorBox y AllDebrid: la petición con tu clave, el ritmo (`RDGate`) y la tabla de errores.
struct DebridCall: Sendable {
    let fetch: DebridFetch
    let gate: RDGate
    let table: DebridErrorTable
    let api: String

    func send(_ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil, contentType: String? = nil,
              token: String) async throws -> (status: Int, json: [String: Any]) {
        guard !token.isEmpty else { throw RDRequestError.noKey }
        try await gate.enter()
        var parts = URLComponents(string: "\(api)/\(path)")
        if !query.isEmpty { parts?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = parts?.url else { throw RDRequestError.unexpected }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = body; request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let status: Int, raw: Data
        do { (status, raw) = try await fetch(request) } catch { throw RDRequestError.network }
        let json = ((try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]) ?? [:]
        return (status, json)
    }

    func fail(status: Int?, code: String?) async -> RDRequestError {
        let error = RDRequestError.from(table.cause(status: status, code: code))
        if error == .slowDown { await gate.slowDown() }
        return error
    }

    static func form(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return Data(pairs.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init) }
}

// MARK: - TorBox

/// TorBox (API v1, `client.torbox` del contrato): no deja elegir archivos (baja el torrent entero) y no dice cuántas deja tu
/// plan. Responde `{success, error, detail, data}`. Solo habla con api.torbox.app.
public struct TorBoxTorrents: DebridTorrentAPI {
    public static let api = "https://api.torbox.app/v1/api"
    let call: DebridCall
    public init(fetch: @escaping DebridFetch, gate: RDGate = RDGate()) { call = DebridCall(fetch: fetch, gate: gate, table: .torBox, api: Self.api) }

    func data(_ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil, contentType: String? = nil, token: String) async throws -> Any? {
        let (status, json) = try await call.send(method, path, query: query, body: body, contentType: contentType, token: token)
        if !(200..<300).contains(status) || json["success"] as? Bool == false {
            throw await call.fail(status: status, code: json["error"] as? String)
        }
        return json["data"]
    }

    public func addMagnet(hash: String, token: String) async throws -> String {
        let boundary = UUID().uuidString
        let fields = [("magnet", "magnet:?xt=urn:btih:\(hash.lowercased())"), ("seed", "3"), ("allow_zip", "false")]
        let body = fields.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.0)\"\r\n\r\n\($0.1)\r\n" }.joined() + "--\(boundary)--\r\n"
        let got = try await data("POST", "torrents/createtorrent", body: Data(body.utf8), contentType: "multipart/form-data; boundary=\(boundary)", token: token)
        guard let id = (got as? [String: Any])?["torrent_id"] else { throw RDRequestError.unexpected }
        return "\(id)"
    }

    /// TorBox no pide nada antes de bajar.
    public func selectFiles(id: String, files: [Int], token: String) async throws {}

    public func info(id: String, token: String) async throws -> RDTorrent {
        let got = try await data("GET", "torrents/mylist", query: [("bypass_cache", "true"), ("id", id)], token: token)
        guard let row = got as? [String: Any], !row.isEmpty, let torrent = Self.shape(row) else { throw RDRequestError.notFound }
        return torrent
    }

    /// El «enlace» de un archivo de TorBox es «torbox:<torrent>:<archivo>»: aquí se cambia por el de verdad.
    public func unrestrict(link: String, token: String) async throws -> URL {
        let parts = link.split(separator: ":")
        guard parts.count == 3, parts[0] == "torbox" else { throw RDRequestError.unexpected }
        let got = try await data("GET", "torrents/requestdl", query: [("token", token), ("torrent_id", String(parts[1])), ("file_id", String(parts[2]))], token: token)
        guard let text = got as? String, let url = URL(string: text), url.scheme?.lowercased() == "https" else { throw RDRequestError.unexpected }
        return url
    }

    public func list(limit: Int, token: String) async throws -> [RDTorrent] {
        let got = try await data("GET", "torrents/mylist", query: [("bypass_cache", "true"), ("limit", String(limit))], token: token)
        return ((got as? [[String: Any]]) ?? []).compactMap(Self.shape)
    }

    /// TorBox no dice el límite de tu plan.
    public func activeCount(token: String) async throws -> (active: Int, limit: Int) { throw RDRequestError.unexpected }

    public func delete(id: String, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["torrent_id": Int(id) ?? 0, "operation": "delete"] as [String: Any])
        do { _ = try await data("POST", "torrents/controltorrent", body: body, contentType: "application/json", token: token) } catch RDRequestError.notFound { return }
    }

    /// `status_map`: presente o terminado (cached, completed, uploading, seeding) = bajado; con «error» o «fail» = error;
    /// metaDL, checkingResumeData, queued, paused = en cola; lo demás, bajando. `progress` viene de 0 a 1.
    static func status(_ row: [String: Any]) -> String {
        let state = row["download_state"] as? String ?? ""
        if row["download_present"] as? Bool == true
            || (row["download_finished"] as? Bool == true && ["cached", "completed", "uploading", "seeding"].contains(state)) { return "downloaded" }
        if state.lowercased().contains("error") || state.lowercased().contains("fail") { return "error" }
        if ["metaDL", "checkingResumeData", "queued", "paused"].contains(state) { return "queued" }
        return "downloading"
    }

    static func shape(_ row: [String: Any]) -> RDTorrent? {
        guard let rawID = row["id"] else { return nil }
        let id = "\(rawID)", status = status(row)
        let files = ((row["files"] as? [[String: Any]]) ?? []).enumerated().map { i, f in
            (RDFile(id: i + 1, path: (f["name"] as? String) ?? (f["short_name"] as? String) ?? "",
                    bytes: Int64(DebridCall.number(f["size"]) ?? 0), selected: true), f["id"].map { "\($0)" })
        }
        let progress = DebridCall.number(row["progress"]) ?? 0
        let percent = status == "downloaded" ? 100 : max(0, min(100, Int((progress <= 1 ? progress * 100 : progress).rounded())))
        let links = status == "downloaded" ? files.map { "torbox:\(id):\($0.1 ?? "")" } : []
        return RDTorrent(id: id, hash: row["hash"] as? String ?? "", filename: row["name"] as? String ?? "", status: status, progress: percent,
                         seeders: (row["seeds"] as? NSNumber)?.intValue, files: files.map(\.0), links: links)
    }
}

/// Tu cuenta de TorBox (`GET /user/me`): Premium si `plan` > 0; vence en `premium_expires_at`.
public struct TorBox: DebridProvider {
    public let name = "TorBox"
    public let renewURL = DebridService.torBox.renewURL
    public let tokenURL = DebridService.torBox.keyURL
    let fetch: DebridFetch
    private let clock: @Sendable () -> Date
    public init(fetch: @escaping DebridFetch, clock: @escaping @Sendable () -> Date = { Date() }) { self.fetch = fetch; self.clock = clock }

    public func status(token: String) async throws -> DebridStatus {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DebridService.torBox.looksLikeKey(token) else { throw DebridError.malformedToken }
        let client = TorBoxTorrents(fetch: fetch)
        let got: Any?
        do { got = try await client.data("GET", "user/me", token: token) }
        catch RDRequestError.invalidKey { throw DebridError.invalidToken }
        catch RDRequestError.network { throw DebridError.network("TorBox") }
        catch { throw DebridError.unexpected }
        guard let user = got as? [String: Any] else { throw DebridError.unexpected }
        let plan = (user["plan"] as? NSNumber)?.intValue ?? 0
        let expires = (user["premium_expires_at"] as? String).flatMap(RealDebrid.date)
        return DebridStatus(service: name, username: user["email"] as? String ?? "", isPremium: plan > 0, expires: expires, checkedAt: clock(),
                            userID: user["id"].map { "\($0)" })
    }
}

// MARK: - AllDebrid

/// AllDebrid (API v4 / v4.1, `client.alldebrid`): no deja elegir archivos y deja 30 a la vez. Responde `{status: success, data}`
/// o `{status: error, error: {code, message}}` con HTTP 200. Solo habla con api.alldebrid.com.
public struct AllDebridTorrents: DebridTorrentAPI {
    public static let api = "https://api.alldebrid.com"
    public static let activeLimit = 30
    let call: DebridCall
    let pause: @Sendable () async -> Void
    public init(fetch: @escaping DebridFetch, gate: RDGate = RDGate(), pause: @escaping @Sendable () async -> Void = { try? await Task.sleep(nanoseconds: 1_000_000_000) }) {
        call = DebridCall(fetch: fetch, gate: gate, table: .allDebrid, api: Self.api); self.pause = pause
    }

    func data(_ method: String, _ path: String, _ form: [(String, String)]? = nil, token: String) async throws -> [String: Any] {
        let (status, json) = try await call.send(method, path, body: form.map(DebridCall.form), contentType: "application/x-www-form-urlencoded", token: token)
        if json["status"] as? String == "error" || !(200..<300).contains(status) {
            throw await call.fail(status: status, code: (json["error"] as? [String: Any])?["code"] as? String)
        }
        return json["data"] as? [String: Any] ?? [:]
    }

    /// Un error que viene dentro de un magnet (`data.magnets[0].error`).
    private func firstMagnet(_ data: [String: Any]) async throws -> [String: Any] {
        let first = (data["magnets"] as? [[String: Any]])?.first ?? [:]
        if let error = first["error"] as? [String: Any] { throw await call.fail(status: nil, code: error["code"] as? String) }
        return first
    }

    public func addMagnet(hash: String, token: String) async throws -> String {
        let first = try await firstMagnet(try await data("POST", "v4/magnet/upload", [("magnets[]", hash.lowercased())], token: token))
        guard let id = first["id"] else { throw RDRequestError.unexpected }
        return "\(id)"
    }

    /// AllDebrid no pide nada antes de bajar.
    public func selectFiles(id: String, files: [Int], token: String) async throws {}

    private func magnets(_ form: [(String, String)], token: String) async throws -> [[String: Any]] {
        let got = try await data("POST", "v4.1/magnet/status", form, token: token)
        if let one = got["magnets"] as? [String: Any] { return [one] }   // con «id» llega uno solo
        return got["magnets"] as? [[String: Any]] ?? []
    }

    public func info(id: String, token: String) async throws -> RDTorrent {
        guard let row = try await magnets([("id", id)], token: token).first else { throw RDRequestError.notFound }
        var files: [(path: String, bytes: Int64, link: String)] = []
        if (row["statusCode"] as? NSNumber)?.intValue == 4 {
            let first = try await firstMagnet(try await data("POST", "v4/magnet/files", [("id[]", id)], token: token))
            files = Self.flatten(first["files"] as? [[String: Any]] ?? [])
        }
        guard let torrent = Self.shape(row, files: files) else { throw RDRequestError.unexpected }
        return torrent
    }

    public func unrestrict(link: String, token: String) async throws -> URL {
        let got = try await data("POST", "v4/link/unlock", [("link", link)], token: token)
        var text = got["link"] as? String ?? ""
        if text.isEmpty, let delayed = got["delayed"] {
            for _ in 0..<5 {   // AllDebrid a veces arma el enlace aparte
                await pause()
                let wait = try await data("POST", "v4/link/delayed", [("id", "\(delayed)")], token: token)
                let state = (wait["status"] as? NSNumber)?.intValue
                if state == 2 { text = wait["link"] as? String ?? ""; break }
                if state == 3 { break }
            }
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else { throw RDRequestError.unexpected }
        return url
    }

    public func list(limit: Int, token: String) async throws -> [RDTorrent] {
        Array(try await magnets([], token: token).compactMap { Self.shape($0, files: []) }.prefix(limit))
    }

    /// Los de `status=active` contra los 30 que deja.
    public func activeCount(token: String) async throws -> (active: Int, limit: Int) {
        (try await magnets([("status", "active")], token: token).count, Self.activeLimit)
    }

    public func delete(id: String, token: String) async throws {
        do { _ = try await data("POST", "v4/magnet/delete", [("id", id)], token: token) } catch RDRequestError.notFound { return }
    }

    /// `status_map`: 4 bajado · 0 en cola · 1 bajando · 2 y 3 subiendo (cuenta como bajando) · 7 y 15 nadie lo comparte ·
    /// del 5 al 14, error.
    static func status(_ code: Int?) -> String {
        switch code {
        case 4: "downloaded"
        case 0: "queued"
        case 1: "downloading"
        case 2, 3: "uploading"
        case 7, 15: "dead"
        case .some: "error"
        case nil: "queued"
        }
    }

    /// El árbol de archivos («n» nombre, «e» carpeta, «s» tamaño, «l» enlace) en una lista, en su orden.
    static func flatten(_ nodes: [[String: Any]], prefix: String = "") -> [(path: String, bytes: Int64, link: String)] {
        nodes.flatMap { node -> [(path: String, bytes: Int64, link: String)] in
            let path = prefix + (node["n"] as? String ?? "")
            if let children = node["e"] as? [[String: Any]] { return flatten(children, prefix: path + "/") }
            guard let link = node["l"] as? String else { return [] }
            return [(path, Int64(DebridCall.number(node["s"]) ?? 0), link)]
        }
    }

    static func shape(_ row: [String: Any], files: [(path: String, bytes: Int64, link: String)]) -> RDTorrent? {
        guard let rawID = row["id"] else { return nil }
        let status = status((row["statusCode"] as? NSNumber)?.intValue)
        let size = DebridCall.number(row["size"]) ?? 0, done = DebridCall.number(row["downloaded"]) ?? 0
        let percent = status == "downloaded" ? 100 : (size > 0 ? max(0, min(100, Int((done * 100 / size).rounded()))) : 0)
        return RDTorrent(id: "\(rawID)", hash: row["hash"] as? String ?? "", filename: row["filename"] as? String ?? "", status: status,
                         progress: percent, seeders: (row["seeders"] as? NSNumber)?.intValue,
                         files: files.enumerated().map { RDFile(id: $0.offset + 1, path: $0.element.path, bytes: $0.element.bytes, selected: true) },
                         links: files.map(\.link))
    }
}

/// Tu cuenta de AllDebrid (`GET /v4/user`): no da número de cuenta, su nombre de usuario hace de id.
public struct AllDebrid: DebridProvider {
    public let name = "AllDebrid"
    public let renewURL = DebridService.allDebrid.renewURL
    public let tokenURL = DebridService.allDebrid.keyURL
    let fetch: DebridFetch
    private let clock: @Sendable () -> Date
    public init(fetch: @escaping DebridFetch, clock: @escaping @Sendable () -> Date = { Date() }) { self.fetch = fetch; self.clock = clock }

    public func status(token: String) async throws -> DebridStatus {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DebridService.allDebrid.looksLikeKey(token) else { throw DebridError.malformedToken }
        let got: [String: Any]
        do { got = try await AllDebridTorrents(fetch: fetch).data("GET", "v4/user", token: token) }
        catch RDRequestError.invalidKey { throw DebridError.invalidToken }
        catch RDRequestError.network { throw DebridError.network("AllDebrid") }
        catch { throw DebridError.unexpected }
        guard let user = got["user"] as? [String: Any], let name = user["username"] as? String else { throw DebridError.unexpected }
        let until = DebridCall.number(user["premiumUntil"]) ?? 0
        return DebridStatus(service: self.name, username: name, isPremium: user["isPremium"] as? Bool == true,
                            expires: until > 0 ? Date(timeIntervalSince1970: until) : nil, checkedAt: clock(), userID: name)
    }
}

// MARK: - La que usas

/// Las tres nubes, y la que usas en cada momento (la del llavero: cambiarla en «Tu nube» cambia a quién se le pregunta,
/// sin rearmar nada).
public struct DebridClients: Sendable {
    public let providers: @Sendable (DebridService) -> DebridProvider
    public let torrents: @Sendable (DebridService) -> any DebridTorrentAPI

    public init(providers: @escaping @Sendable (DebridService) -> DebridProvider, torrents: @escaping @Sendable (DebridService) -> any DebridTorrentAPI) {
        self.providers = providers; self.torrents = torrents
    }

    /// Las de verdad, por una red (`fetch`). Cada nube con su propio ritmo.
    public static func live(fetch: @escaping DebridFetch, clock: @escaping @Sendable () -> Date = { Date() }) -> DebridClients {
        let rd = RealDebridTorrents(fetch: fetch, gate: RDGate()), tb = TorBoxTorrents(fetch: fetch, gate: RDGate()), ad = AllDebridTorrents(fetch: fetch, gate: RDGate())
        return DebridClients(providers: { service in
            switch service {
            case .realDebrid: RealDebrid(fetch: fetch, clock: clock)
            case .torBox: TorBox(fetch: fetch, clock: clock)
            case .allDebrid: AllDebrid(fetch: fetch, clock: clock)
            }
        }, torrents: { service in
            switch service { case .realDebrid: rd; case .torBox: tb; case .allDebrid: ad }
        })
    }
}

/// Los torrents de la nube que usas ahora (la del llavero): el `DebridRequester` habla con esta.
public struct ActiveDebridTorrents: DebridTorrentAPI {
    let vault: AddonVault
    let clients: DebridClients
    public init(vault: AddonVault, clients: DebridClients) { self.vault = vault; self.clients = clients }
    var current: any DebridTorrentAPI { clients.torrents(vault.debridService) }

    public func addMagnet(hash: String, token: String) async throws -> String { try await current.addMagnet(hash: hash, token: token) }
    public func selectFiles(id: String, files: [Int], token: String) async throws { try await current.selectFiles(id: id, files: files, token: token) }
    public func info(id: String, token: String) async throws -> RDTorrent { try await current.info(id: id, token: token) }
    public func unrestrict(link: String, token: String) async throws -> URL { try await current.unrestrict(link: link, token: token) }
    public func list(limit: Int, token: String) async throws -> [RDTorrent] { try await current.list(limit: limit, token: token) }
    public func activeCount(token: String) async throws -> (active: Int, limit: Int) { try await current.activeCount(token: token) }
    public func delete(id: String, token: String) async throws { try await current.delete(id: id, token: token) }
}
