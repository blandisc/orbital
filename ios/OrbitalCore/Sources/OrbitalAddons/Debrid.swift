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

    public init(service: String, username: String, isPremium: Bool, expires: Date?, checkedAt: Date) {
        self.service = service; self.username = username; self.isPremium = isPremium; self.expires = expires; self.checkedAt = checkedAt
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

    public func state(now: Date, calendar: Calendar = .current) -> State {
        guard let days = daysLeft(now: now, calendar: calendar) else { return isPremium ? .active(daysLeft: .max) : .free }
        if days < 0 { return .expired(daysAgo: -days) }
        guard isPremium else { return .free }
        return days <= Self.soonDays ? .expiringSoon(daysLeft: days) : .active(daysLeft: days)
    }
}

public enum DebridError: Error, Equatable, Sendable, CustomStringConvertible {
    /// La clave está incompleta o mal copiada (ni se le preguntó al servicio).
    case malformedToken
    /// El servicio no la reconoce.
    case invalidToken
    case network(String)
    case unexpected
    public var description: String {
        switch self {
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
    private let fetch: DebridFetch
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

    /// `{"username": "…", "type": "premium" | "free", "premium": segundos, "expiration": "2027-03-21T12:00:00.000Z"}`.
    static func parse(_ body: Data, checkedAt: Date) throws -> DebridStatus {
        guard let user = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let name = user["username"] as? String else { throw DebridError.unexpected }
        let premiumSeconds = (user["premium"] as? NSNumber)?.doubleValue ?? 0
        let isPremium = (user["type"] as? String)?.lowercased() == "premium" && premiumSeconds > 0
        var expires = (user["expiration"] as? String).flatMap(Self.date)
        if expires == nil, premiumSeconds > 0 { expires = checkedAt.addingTimeInterval(premiumSeconds) }
        return DebridStatus(service: "Real-Debrid", username: name, isPremium: isPremium, expires: expires, checkedAt: checkedAt)
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

    public init(provider: DebridProvider, vault: AddonVault, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.vault = vault; self.clock = clock
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

    /// Comprueba una clave sin guardarla (la guía y «Cambiar clave»): el estado, o por qué no sirve.
    public func verify(_ token: String) async throws -> DebridStatus {
        try await provider.status(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Guarda una clave ya comprobada (y su estado). Los recomendados se rearman solos con ella.
    public func save(token: String, status: DebridStatus) {
        vault.setSecret(AddonKeys.realDebridToken, token.trimmingCharacters(in: .whitespacesAndNewlines))
        remember(status)
    }

    /// «Quitar»: se olvida la clave, su estado y los avisos.
    public func remove() {
        vault.setSecret(AddonKeys.realDebridToken, nil)
        vault.setData(AddonKeys.debridStatus, nil)
        vault.setData(AddonKeys.reminders, nil)
    }

    private func remember(_ status: DebridStatus) { vault.setData(AddonKeys.debridStatus, try? Self.encoder.encode(status)) }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}
