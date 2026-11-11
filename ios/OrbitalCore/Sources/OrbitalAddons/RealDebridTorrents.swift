import Foundation

/// Un torrent en tu Real-Debrid (`GET /torrents`, `GET /torrents/info/{id}`): lo que Real-Debrid sabe de él. No sabe qué
/// título ni qué episodio es, ni quién lo pidió: eso lo lleva la libreta de pedidos (`DebridRequestBook`).
public struct RDTorrent: Equatable, Sendable {
    public var id: String
    /// La huella del torrent, en minúsculas (la misma `infoHash` de Torrentio).
    public var hash: String
    public var filename: String
    /// `magnet_error`, `magnet_conversion`, `waiting_files_selection`, `queued`, `downloading`, `downloaded`, `error`, `virus`,
    /// `compressing`, `uploading`, `dead`.
    public var status: String
    /// 0…100.
    public var progress: Int
    /// Solo mientras baja (`downloading`, `magnet_conversion`): cuánta gente lo comparte.
    public var seeders: Int?
    /// Los archivos (solo en `info`).
    public var files: [RDFile] = []
    /// Los enlaces de lo ya bajado (solo en `info`): uno por archivo elegido, en el orden de sus ids. Se «liberan» con
    /// `unrestrict` para verlos.
    public var links: [String] = []

    public init(id: String, hash: String, filename: String, status: String, progress: Int, seeders: Int? = nil, files: [RDFile] = [],
                links: [String] = []) {
        self.id = id; self.hash = hash.lowercased(); self.filename = filename; self.status = status; self.progress = progress
        self.seeders = seeders; self.files = files; self.links = links
    }

    /// El enlace del archivo `fileIdx` (el de Torrentio, desde 0) entre lo bajado; sin saber cuál, el del video más grande.
    /// nil si no está bajado o ese archivo no se eligió.
    public func link(fileIdx: Int?) -> String? {
        let chosen = files.filter(\.selected).sorted { $0.id < $1.id }
        guard !links.isEmpty else { return nil }
        guard !chosen.isEmpty, chosen.count == links.count else { return links.count == 1 ? links[0] : nil }
        let target = fileIdx.map { $0 + 1 } ?? chosen.filter(\.isVideo).max { $0.bytes < $1.bytes }?.id
        guard let target, let at = chosen.firstIndex(where: { $0.id == target }) else { return nil }
        return links[at]
    }

    init?(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        let progress = (json["progress"] as? NSNumber)?.doubleValue ?? 0
        let files = (json["files"] as? [[String: Any]] ?? []).compactMap(RDFile.init)
        self.init(id: id, hash: json["hash"] as? String ?? "", filename: json["filename"] as? String ?? "", status: json["status"] as? String ?? "",
                  progress: Int(progress.rounded()), seeders: (json["seeders"] as? NSNumber)?.intValue, files: files,
                  links: json["links"] as? [String] ?? [])
    }
}

/// Un archivo de un torrent de Real-Debrid (sus ids empiezan en 1: el `fileIdx` de Torrentio + 1).
public struct RDFile: Equatable, Sendable {
    public var id: Int
    public var path: String
    public var bytes: Int64
    public var selected: Bool
    public init(id: Int, path: String, bytes: Int64, selected: Bool) { self.id = id; self.path = path; self.bytes = bytes; self.selected = selected }
    init?(_ json: [String: Any]) {
        guard let id = (json["id"] as? NSNumber)?.intValue else { return nil }
        self.init(id: id, path: json["path"] as? String ?? "", bytes: (json["bytes"] as? NSNumber)?.int64Value ?? 0,
                  selected: (json["selected"] as? NSNumber)?.intValue == 1)
    }
    static let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "webm", "wmv", "mpg", "mpeg"]
    /// ¿Es un video (no un .nfo, .srt ni la muestra)?
    public var isVideo: Bool {
        let name = path.lowercased()
        return Self.videoExtensions.contains((name as NSString).pathExtension) && !name.contains("sample")
    }
}

/// A15 · qué quiere decir cada error de Real-Debrid, igual que en la TV: la tabla de `design/realdebrid-errors.json` (la TV la
/// lee en `orbital/library/realdebrid.py`). `RDErrorTableTests` comprueba que esta copia sea esa tabla y corre sus `cases`.
public enum RDErrorCause: String, Sendable, CaseIterable {
    case invalidSession = "invalid_session", noPremium = "no_premium", refused, tooMany = "too_many", slowDown = "slow_down", gone, other

    /// `codes` de la tabla: el `error_code` de Real-Debrid → la causa.
    public static let codes: [Int: RDErrorCause] = [
        -1: .other, 1: .other, 2: .other, 3: .other, 4: .other, 5: .slowDown, 6: .slowDown, 7: .gone, 8: .invalidSession,
        9: .noPremium, 10: .invalidSession, 11: .invalidSession, 12: .invalidSession, 13: .invalidSession, 14: .noPremium,
        15: .noPremium, 16: .refused, 17: .slowDown, 18: .tooMany, 19: .slowDown, 20: .noPremium, 21: .tooMany, 22: .noPremium,
        23: .tooMany, 24: .refused, 25: .slowDown, 26: .refused, 27: .refused, 28: .refused, 29: .refused, 30: .refused,
        31: .other, 32: .other, 33: .other, 34: .slowDown, 35: .refused, 36: .tooMany, 37: .other,
    ]
    /// `http` de la tabla: solo sin `error_code` (o con uno que no está en `codes`).
    public static let http: [Int: RDErrorCause] = [401: .invalidSession, 403: .noPremium, 404: .gone, 429: .slowDown, 451: .refused,
                                                   503: .slowDown, 509: .tooMany]

    /// Primero manda `error_code`; sin él (o con uno desconocido), el HTTP; otro 5xx es «espera», lo demás «otra cosa».
    public static func of(status: Int?, code: Int?) -> RDErrorCause {
        if let code, let cause = codes[code] { return cause }
        guard let status else { return .other }
        return http[status] ?? ((500..<600).contains(status) ? .slowDown : .other)
    }
}

/// Lo que Real-Debrid contestó cuando dijo que no (su `error_code`, o el código HTTP si no lo dio), en lo que importa para
/// decirlo con palabras (R13, R7). Nunca lleva la clave.
public enum RDRequestError: Error, Equatable, Sendable {
    /// No hay clave en la app.
    case noKey
    /// La clave ya no sirve (401; códigos 8, 10–13): «Vuelve a conectar Real-Debrid».
    case invalidKey
    /// Sin Premium, vencida, bloqueada o desde una IP no permitida (403; códigos 9, 14, 15, 20, 22).
    case notPremium
    /// No deja bajar ese archivo (451; códigos 16, 24, 26–30, 35): se ofrece otra versión.
    case refused
    /// Un límite de tu cuenta: descargas a la vez, tráfico o uso justo (509; códigos 18, 21, 23, 36): se reintenta.
    case tooManyActive
    /// Demasiadas preguntas o un servicio caído (429, 503 y otros 5xx; códigos 5, 6, 17, 19, 25, 34): se espera y se reintenta.
    case slowDown
    /// Ese torrent ya no está (404, código 7): lo borraste en real-debrid.com.
    case notFound
    /// No contestó.
    case network
    case unexpected

    /// Del cuerpo de la respuesta (`{"error": "…", "error_code": 35}`) y su código HTTP, con la tabla compartida.
    public static func from(status: Int, body: Data) -> RDRequestError {
        let code = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error_code"] as? Int
        return from(RDErrorCause.of(status: status, code: code))
    }

    public static func from(_ cause: RDErrorCause) -> RDRequestError {
        switch cause {
        case .invalidSession: .invalidKey
        case .noPremium: .notPremium
        case .refused: .refused
        case .tooMany: .tooManyActive
        case .slowDown: .slowDown
        case .gone: .notFound
        case .other: .unexpected
        }
    }
}

/// Lo que se le pide a Real-Debrid para bajar algo que todavía no tiene (R12, R13): agregar el torrent, elegir el archivo,
/// ver cuánto lleva, cuántos van y cancelarlo. Con tu clave fija (la de real-debrid.com/apitoken), nunca la de «conectar con
/// código». Respeta el límite de Real-Debrid (250 por minuto; tras un 429 espera un minuto).
public struct RealDebridTorrents: Sendable {
    private let fetch: DebridFetch
    private let gate: RDGate
    public init(fetch: @escaping DebridFetch, gate: RDGate = RDGate()) { self.fetch = fetch; self.gate = gate }

    /// `POST /torrents/addMagnet`: el id del torrent en tu cuenta.
    public func addMagnet(hash: String, token: String) async throws -> String {
        let body = try await call("torrents/addMagnet", method: "POST", form: ["magnet": "magnet:?xt=urn:btih:\(hash.lowercased())"], token: token)
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let id = json["id"] as? String else { throw RDRequestError.unexpected }
        return id
    }

    /// `POST /torrents/selectFiles/{id}`: los archivos (sus ids) o todos los videos si no se sabe cuál.
    public func selectFiles(id: String, files: [Int], token: String) async throws {
        _ = try await call("torrents/selectFiles/\(id)", method: "POST",
                           form: ["files": files.isEmpty ? "all" : files.map(String.init).joined(separator: ",")], token: token)
    }

    /// `GET /torrents/info/{id}`.
    public func info(id: String, token: String) async throws -> RDTorrent {
        let body = try await call("torrents/info/\(id)", token: token)
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let torrent = RDTorrent(json) else { throw RDRequestError.unexpected }
        return torrent
    }

    /// `POST /unrestrict/link`: el enlace para ver un archivo ya bajado (caduca en unas horas; no se guarda).
    public func unrestrict(link: String, token: String) async throws -> URL {
        let body = try await call("unrestrict/link", method: "POST", form: ["link": link], token: token)
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let text = json["download"] as? String,
              let url = URL(string: text), url.scheme?.lowercased() == "https" else { throw RDRequestError.unexpected }
        return url
    }

    /// `GET /torrents`: los más recientes de tu cuenta, en una sola consulta (cuánto lleva cada pedido).
    public func list(limit: Int = 100, token: String) async throws -> [RDTorrent] {
        let body = try await call("torrents?limit=\(limit)", token: token)
        guard !body.isEmpty else { return [] }   // 204: no hay ninguno
        guard let rows = (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]] else { throw RDRequestError.unexpected }
        return rows.compactMap(RDTorrent.init)
    }

    /// `GET /torrents/activeCount`: cuántos bajan a la vez y cuántos permite tu cuenta.
    public func activeCount(token: String) async throws -> (active: Int, limit: Int) {
        let body = try await call("torrents/activeCount", token: token)
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { throw RDRequestError.unexpected }
        return ((json["nb"] as? NSNumber)?.intValue ?? 0, (json["limit"] as? NSNumber)?.intValue ?? 0)
    }

    /// `DELETE /torrents/delete/{id}` («Cancelar pedido»). Si ya no estaba, también cuenta como cancelado.
    public func delete(id: String, token: String) async throws {
        do { _ = try await call("torrents/delete/\(id)", method: "DELETE", token: token) } catch RDRequestError.notFound { return }
    }

    private func call(_ path: String, method: String = "GET", form: [String: String]? = nil, token: String) async throws -> Data {
        guard !token.isEmpty else { throw RDRequestError.noKey }
        try await gate.enter()
        guard let url = URL(string: RealDebrid.api.absoluteString + "/" + path) else { throw RDRequestError.unexpected }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let form {
            var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
            let encoded = form.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
            request.httpBody = Data(encoded.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let status: Int, body: Data
        do { (status, body) = try await fetch(request) } catch { throw RDRequestError.network }
        guard (200..<300).contains(status) else {
            let error = RDRequestError.from(status: status, body: body)
            if error == .slowDown { await gate.slowDown() }
            throw error
        }
        return body
    }
}

/// El ritmo con que se le pregunta a Real-Debrid: no más de `perMinute` por minuto (su límite es 250, y los 429 también
/// cuentan) y, si dice «más despacio», un minuto sin preguntar.
public actor RDGate {
    public let perMinute: Int
    private let clock: @Sendable () -> Date
    private var recent: [Date] = []
    private var pausedUntil: Date?
    public init(perMinute: Int = 120, clock: @escaping @Sendable () -> Date = { Date() }) { self.perMinute = perMinute; self.clock = clock }

    /// Deja pasar o dice que hay que esperar (sin dormir: quien pregunta cada 20 s vuelve en la siguiente vuelta).
    func enter() throws {
        let now = clock()
        if let until = pausedUntil, now < until { throw RDRequestError.slowDown }
        recent = recent.filter { now.timeIntervalSince($0) < 60 }
        guard recent.count < perMinute else { throw RDRequestError.slowDown }
        recent.append(now)
    }
    func slowDown() { pausedUntil = clock().addingTimeInterval(60) }
}
