import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// El estado de tu cuenta del servicio de descarga: quién eres, si es Premium y cuándo vence.
public struct DebridStatus: Codable, Equatable, Sendable {
    public var service: String
    public var username: String
    public var isPremium: Bool
    /// Cuándo vence el Premium (nil en una cuenta gratuita).
    public var expires: Date?
    /// Cuándo se le preguntó al servicio.
    public var checkedAt: Date
    /// El id de usuario (`GET /user` › `id`): la `account` de la libreta de pedidos. Nunca la clave.
    public var userID: String?
    /// Tus puntos de fidelidad (D4: se canjean por días de Premium). nil si el servicio no los dice.
    public var points: Int?

    public init(service: String, username: String, isPremium: Bool, expires: Date?, checkedAt: Date, userID: String? = nil, points: Int? = nil) {
        self.service = service; self.username = username; self.isPremium = isPremium; self.expires = expires; self.checkedAt = checkedAt
        self.userID = userID; self.points = points
    }

    /// Días que quedan, contados por días de calendario (vence mañana = 1; hoy = 0; ya venció = negativo).
    public func daysLeft(now: Date, calendar: Calendar = .current) -> Int? {
        guard let expires else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expires)).day
    }

    public enum State: Equatable, Sendable {
        /// Premium con tiempo de sobra.
        case active(daysLeft: Int)
        /// Premium que vence en `soonDays` días o menos (0 = hoy).
        case expiringSoon(daysLeft: Int)
        /// Venció hace `daysAgo` días.
        case expired(daysAgo: Int)
        /// Cuenta gratuita: sin Premium no da enlaces.
        case free
    }
    public static let soonDays = 14
    /// Cuántos días después de vencer se sigue diciendo «Venció»; después, «Cuenta gratuita».
    public static let lapsedDays = 90

    /// Vence a una hora, no a un día: el 21 a las 23:00, si venció a las 15:00, ya venció (antes decía «sin Premium» todo
    /// ese día, porque los días de calendario daban 0 y Real-Debrid ya decía «free»).
    public func state(now: Date, calendar: Calendar = .current) -> State {
        guard let expires, let days = daysLeft(now: now, calendar: calendar) else { return isPremium ? .active(daysLeft: .max) : .free }
        // IOS-1: una cuenta gratuita cuyo último Premium fue hace meses (o nunca: Real-Debrid manda una fecha vieja) no «venció»:
        // es gratuita. «Venció» solo los primeros `lapsedDays` días.
        if expires <= now { return !isPremium && -days > Self.lapsedDays ? .free : .expired(daysAgo: max(0, -days)) }
        guard isPremium else { return .free }
        return days <= Self.soonDays ? .expiringSoon(daysLeft: days) : .active(daysLeft: days)
    }
}

/// Qué se sabe ahora de tu cuenta, sin quedarse con lo guardado (cuando algo falló al reproducir).
public enum DebridHealth: Equatable, Sendable {
    /// No hay clave en la app.
    case noKey
    /// Real-Debrid contestó: este es su estado.
    case status(DebridStatus)
    /// Real-Debrid ya no reconoce tu clave: «Vuelve a conectar Real-Debrid».
    case invalidToken
    /// No contestó; lo último que se sabía (si hay).
    case unreachable(DebridStatus?)
}

public enum DebridError: Error, Equatable, Sendable, CustomStringConvertible {
    /// La clave está incompleta o mal copiada (ni se le preguntó al servicio).
    case malformedToken
    /// El servicio no la reconoce.
    case invalidToken
    case network(String)
    case unexpected
    /// D4: no te alcanzan los puntos para un canje.
    case notEnoughPoints
    public var description: String {
        switch self {
        case .notEnoughPoints: "Todavía no te alcanzan los puntos para canjear."
        case .malformedToken: "La clave está incompleta. Cópiala completa de real-debrid.com/apitoken."
        case .invalidToken: "Real-Debrid no reconoce esa clave. Revisa que sea la de real-debrid.com/apitoken."
        case .network: "No pude hablar con Real-Debrid. Revisa tu conexión."
        case .unexpected: "Real-Debrid contestó algo raro. Intenta otra vez."
        }
    }
}

/// Un servicio de descarga (Real-Debrid hoy; AllDebrid, Premiumize o TorBox caben después sin tocar lo demás).
public protocol DebridProvider: Sendable {
    var name: String { get }
    /// Dónde se renueva.
    var renewURL: URL { get }
    /// Dónde se copia la clave.
    var tokenURL: URL { get }
    /// Lee el estado de la cuenta (solo lectura).
    func status(token: String) async throws -> DebridStatus
}

/// Lo que necesita un servicio para hablar con la red: la petición y lo que contestó (código y cuerpo).
public typealias DebridFetch = @Sendable (URLRequest) async throws -> (status: Int, body: Data)

/// Real-Debrid: solo `GET /rest/1.0/user` (lectura): usuario, si es Premium y cuándo vence.
public struct RealDebrid: DebridProvider {
    public static let api = URL(string: "https://api.real-debrid.com/rest/1.0")!
    public let name = "Real-Debrid"
    public let renewURL = URL(string: "https://real-debrid.com/premium")!
    public let tokenURL = URL(string: "https://real-debrid.com/apitoken")!
    let fetch: DebridFetch
    private let clock: @Sendable () -> Date

    public init(fetch: @escaping DebridFetch, clock: @escaping @Sendable () -> Date = { Date() }) { self.fetch = fetch; self.clock = clock }

    /// Una clave de Real-Debrid es una tira de letras y números (52 hoy); más corta, se copió a medias.
    public static func looksLikeToken(_ token: String) -> Bool {
        token.count >= 40 && token.count <= 80 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public func status(token: String) async throws -> DebridStatus {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeToken(token) else { throw DebridError.malformedToken }
        var request = URLRequest(url: Self.api.appendingPathComponent("user"), timeoutInterval: 12)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (status, body): (Int, Data)
        do { (status, body) = try await fetch(request) } catch { throw DebridError.network("\(error)") }
        if status == 401 || status == 403 { throw DebridError.invalidToken }
        guard status == 200 else { throw DebridError.network("HTTP \(status)") }
        return try Self.parse(body, checkedAt: clock())
    }

    /// `{"id": 123, "username": "…", "type": "premium" | "free", "premium": segundos, "expiration": "2027-03-21T12:00:00.000Z"}`.
    static func parse(_ body: Data, checkedAt: Date) throws -> DebridStatus {
        guard let user = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let name = user["username"] as? String else { throw DebridError.unexpected }
        let premiumSeconds = (user["premium"] as? NSNumber)?.doubleValue ?? 0
        let isPremium = (user["type"] as? String)?.lowercased() == "premium" && premiumSeconds > 0
        var expires = (user["expiration"] as? String).flatMap(Self.date)
        if expires == nil, premiumSeconds > 0 { expires = checkedAt.addingTimeInterval(premiumSeconds) }
        let id = (user["id"] as? NSNumber)?.stringValue ?? (user["id"] as? String)
        return DebridStatus(service: "Real-Debrid", username: name, isPremium: isPremium, expires: expires, checkedAt: checkedAt,
                            userID: id?.isEmpty == false ? id : nil, points: (user["points"] as? NSNumber)?.intValue)
    }

    /// D4: canjea tus puntos por días de Premium (`POST /settings/convertPoints`). No se puede deshacer: la pantalla
    /// pregunta antes. 503 = no te alcanzan los puntos.
    public func convertPoints(token: String) async throws {
        var request = URLRequest(url: Self.api.appendingPathComponent("settings/convertPoints"), timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (status, _): (Int, Data)
        do { (status, _) = try await fetch(request) } catch { throw DebridError.network("\(error)") }
        if status == 401 || status == 403 { throw DebridError.invalidToken }
        guard (200..<300).contains(status) else { throw status == 503 ? DebridError.notEnoughPoints : DebridError.network("HTTP \(status)") }
    }

    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

/// Tu cuenta de Real-Debrid en la app: la clave (en el llavero), su estado guardado un día y refrescado al abrir Ajustes.
/// Nada se bloquea si no se puede leer el estado: la clave sigue en las URLs de tus complementos.
public actor DebridAccount {
    public static let statusTTL: TimeInterval = 24 * 3600
    public nonisolated let provider: DebridProvider
    private let vault: AddonVault
    private let clock: @Sendable () -> Date

    /// Quién es este aparato («iphone», «ipad», «mac»): se anota en la copia compartida de tu clave (CX2-A).
    public nonisolated let platform: String
    /// IOS-11 · el nombre de este aparato («iPad de Fernando», el de CX7-A), también en la copia compartida: «iPad de Fernando
    /// cambió la clave» en vez de «Tu iPad…» leído en el mismo iPad.
    nonisolated let deviceName: @Sendable () -> String?
    let vaultRef: AddonVault

    public init(provider: DebridProvider, vault: AddonVault, platform: String = "iphone", deviceName: @escaping @Sendable () -> String? = { nil },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.vault = vault; self.vaultRef = vault; self.platform = platform; self.clock = clock
        self.deviceName = deviceName
    }

    public nonisolated var hasToken: Bool { !(vault.secret(AddonKeys.realDebridToken) ?? "").isEmpty }

    /// Lo último que se supo (sin preguntar).
    public nonisolated var saved: DebridStatus? {
        vault.data(AddonKeys.debridStatus).flatMap { try? Self.decoder.decode(DebridStatus.self, from: $0) }
    }

    /// El estado: el guardado si es de hoy; si no (o con `force`), se le pregunta al servicio. Sin respuesta, el guardado.
    public func status(force: Bool = false) async -> DebridStatus? {
        guard let token = vault.secret(AddonKeys.realDebridToken), !token.isEmpty else { return nil }
        if !force, let saved, clock().timeIntervalSince(saved.checkedAt) < Self.statusTTL { return saved }
        guard let fresh = try? await provider.status(token: token) else { return saved }
        remember(fresh)
        return fresh
    }

    /// El id de usuario de tu Real-Debrid (la `account` de la libreta de pedidos): el guardado; si el guardado es de antes de
    /// saberlo, se le pregunta una vez. nil sin clave o si no contesta.
    public func accountID() async -> String? {
        if let id = saved?.userID { return id }
        return await status(force: saved != nil)?.userID
    }

    /// Algo falló al reproducir (Torrentio mandó su «RD error» o su video de «sin acceso»): lo guardado puede tener hasta un
    /// día y decir «Premium» el día que vence. Se le pregunta ya, a lo más una vez cada `troubleEvery` (varios intentos
    /// seguidos no son varias consultas).
    public func refreshAfterTrouble() async -> DebridHealth {
        if hasToken, let last = lastTrouble, clock().timeIntervalSince(last.at) < Self.troubleEvery { return last.health }
        let health = await checkNow()
        if hasToken { lastTrouble = (clock(), health) }
        return health
    }

    /// P6-A · al abrir tu cuenta: se le pregunta ya a Real-Debrid si tu clave sirve (lo que dice la pantalla es verdad al
    /// abrirla). Sin esperar a nadie ni recordar la respuesta.
    public func checkNow() async -> DebridHealth {
        guard let token = vault.secret(AddonKeys.realDebridToken), !token.isEmpty else { return .noKey }
        do {
            let fresh = try await provider.status(token: token)
            remember(fresh)
            return .status(fresh)
        } catch DebridError.invalidToken {
            return .invalidToken
        } catch {
            return .unreachable(saved)
        }
    }

    /// La demostración (`-demo-rd revoked`): una cuenta que ya se había confirmado antes.
    public nonisolated func rememberForDemo(_ status: DebridStatus) { vault.setData(AddonKeys.debridStatus, try? Self.encoder.encode(status)) }
    public static let troubleEvery: TimeInterval = 5 * 60
    private var lastTrouble: (at: Date, health: DebridHealth)?

    /// Si no tienes clave en la app pero tu Torrentio importado de Stremio la trae en su URL (`realdebrid=…`), se toma de
    /// ahí (como la TV, AD-2): se comprueba con Real-Debrid, se guarda en el llavero y se anota de dónde salió. Devuelve
    /// true si la tomó.
    @discardableResult
    public func adoptKey(fromAddonURLs urls: [String]) async -> Bool {
        guard !hasToken, keySource != Self.removedByYou else { return false }
        let candidates = urls.flatMap(Self.realDebridKeys(in:))
        for key in Array(Set(candidates)).sorted() where RealDebrid.looksLikeToken(key) {
            guard let status = try? await provider.status(token: key) else { continue }
            vault.setSecret(AddonKeys.realDebridToken, key)
            vault.setData(AddonKeys.debridKeySource, Data(Self.fromImportedTorrentio.utf8))
            remember(status)
            return true
        }
        return false
    }
    public static let fromImportedTorrentio = "imported-torrentio"
    static let removedByYou = "removed"

    /// De dónde salió la clave guardada: `fromImportedTorrentio` si se tomó de tu Torrentio importado; nil si la pegaste.
    public nonisolated var keyCameFromImport: Bool { hasToken && keySource == Self.fromImportedTorrentio }
    nonisolated var keySource: String? { vault.data(AddonKeys.debridKeySource).flatMap { String(data: $0, encoding: .utf8) } }

    /// Las claves de Real-Debrid que trae la URL de un complemento con la forma de Torrentio (`…|realdebrid=CLAVE|…`).
    static func realDebridKeys(in url: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)realdebrid=([A-Za-z0-9]+)") else { return [] }
        return regex.matches(in: url, range: NSRange(url.startIndex..., in: url)).compactMap { Range($0.range(at: 1), in: url).map { String(url[$0]) } }
    }

    /// Lo que se enseña de tu clave (D1): sus últimas 4 letras («3F2A»); nunca completa. nil sin clave.
    public nonisolated var keyTail: String? {
        guard let token = vault.secret(AddonKeys.realDebridToken), token.count >= 4 else { return nil }
        return String(token.suffix(4)).uppercased()
    }

    /// D4: canjea tus puntos por días de Premium y vuelve a leer tu cuenta. Solo Real-Debrid lo tiene.
    public func redeemPoints() async throws -> DebridStatus? {
        guard let token = vault.secret(AddonKeys.realDebridToken), !token.isEmpty, let rd = provider as? RealDebrid else { throw DebridError.unexpected }
        try await rd.convertPoints(token: token)
        return await status(force: true)
    }

    /// Comprueba una clave sin guardarla (la guía y «Cambiar clave»): el estado, o por qué no sirve.
    public func verify(_ token: String) async throws -> DebridStatus {
        try await provider.status(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Guarda una clave ya comprobada (y su estado) en este aparato y deja la copia para tus aparatos Apple (CX2-A). Los
    /// recomendados se rearman solos con ella. false si el llavero no la aceptó: entonces nada cambia (TEC-5).
    @discardableResult
    public func save(token: String, status: DebridStatus, share: Bool = true) -> Bool {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard vault.storeSecret(AddonKeys.realDebridToken, clean) else { return false }
        vault.setData(AddonKeys.debridKeySource, nil)   // la pegaste tú
        vault.setSecret(AddonKeys.realDebridOAuth, nil)  // una pegada no se renueva (la de código vuelve a anotar su conexión)
        lastTrouble = nil
        remember(status)
        if share { publishShared(clean) }
        markSharedSeen(clean)
        return true
    }

    /// «Quitar»: se olvida la clave, su estado y los avisos. `everywhere` (CX3-A, «De todos tus aparatos Apple»): también la
    /// copia compartida, y tus otros aparatos que usaban esa misma clave la quitan al abrir Orbital.
    public func remove(everywhere: Bool = false) {
        let old = vault.secret(AddonKeys.realDebridToken) ?? ""
        if everywhere { retireShared(old) } else if let shared = sharedKey, !shared.key.isEmpty { markSharedSeen(shared.key) }
        vault.setSecret(AddonKeys.realDebridToken, nil)
        vault.setSecret(AddonKeys.realDebridOAuth, nil)
        vault.setData(AddonKeys.debridStatus, nil)
        vault.setData(AddonKeys.reminders, nil)
        // La quitaste tú: no se vuelve a tomar sola de tu Torrentio importado.
        vault.setData(AddonKeys.debridKeySource, Data(Self.removedByYou.utf8))
        lastTrouble = nil
    }

    func now() -> Date { clock() }

    private func remember(_ status: DebridStatus) { vault.setData(AddonKeys.debridStatus, try? Self.encoder.encode(status)) }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}
