import Foundation

/// RC1 (Fernando, 4 nov 2026: «vamos con tu recomendación»): conectar Real-Debrid con un código, como Trakt, en lugar de copiar
/// y pegar la clave de 52 letras. Es el inicio de sesión por aparato de Real-Debrid para apps de código abierto:
/// 1. `deviceCode()` pide un código corto («4IHF KYGV») que tú escribes en real-debrid.com/device.
/// 2. `deviceCredentials(_:)` se pregunta cada `interval` segundos hasta que lo apruebas (nil mientras no).
/// 3. `token(...)` cambia el código por una llave de acceso y otra para renovarla.
/// La llave de acceso vence (unas horas): `token(..., refresh:)` pide otra sin que hagas nada. La llave vive solo en el llavero
/// de este aparato; nunca se enseña ni sale en la bitácora.
public struct DebridDeviceCode: Sendable, Equatable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: URL
    public var interval: TimeInterval
    public var expiresIn: TimeInterval
}

/// Las credenciales propias de esta conexión (Real-Debrid las da al aprobar) y la llave para renovar.
public struct DebridOAuth: Codable, Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String
    public var refreshToken: String
    /// Cuándo vence la llave de acceso guardada.
    public var expiresAt: Date
}

public struct DebridOAuthToken: Sendable, Equatable {
    public var access: String
    public var refresh: String
    public var expiresIn: TimeInterval
}

extension RealDebrid {
    /// El identificador público de Real-Debrid para apps de código abierto (el mismo que usan Kodi y Stremio).
    public static let openSourceClientID = "X245A4XAIBGVM"
    static let oauth = URL(string: "https://api.real-debrid.com/oauth/v2")!
    static let deviceGrant = "http://oauth.net/grant_type/device/1.0"

    public func deviceCode() async throws -> DebridDeviceCode {
        var url = URLComponents(url: Self.oauth.appendingPathComponent("device/code"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: Self.openSourceClientID), URLQueryItem(name: "new_credentials", value: "yes")]
        let json = try await call(URLRequest(url: url.url!, timeoutInterval: 12))
        guard let device = json["device_code"] as? String, let user = json["user_code"] as? String else { throw DebridError.unexpected }
        let verify = (json["verification_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://real-debrid.com/device")!
        return DebridDeviceCode(deviceCode: device, userCode: user, verificationURL: verify,
                                interval: (json["interval"] as? NSNumber)?.doubleValue ?? 5, expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue ?? 600)
    }

    /// Las credenciales de esta conexión, en cuanto apruebas el código; nil mientras no lo apruebas.
    public func deviceCredentials(_ code: DebridDeviceCode) async throws -> (clientID: String, clientSecret: String)? {
        var url = URLComponents(url: Self.oauth.appendingPathComponent("device/credentials"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: Self.openSourceClientID), URLQueryItem(name: "code", value: code.deviceCode)]
        let (status, body): (Int, Data)
        do { (status, body) = try await fetch(URLRequest(url: url.url!, timeoutInterval: 12)) } catch { throw DebridError.network("\(error)") }
        guard status == 200 else { return nil }   // todavía no lo apruebas (Real-Debrid contesta 403)
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = json["client_id"] as? String, let secret = json["client_secret"] as? String else { return nil }
        return (id, secret)
    }

    /// La llave de acceso: la primera vez con el código del aparato; después, renovándola con la llave de renovar.
    public func token(clientID: String, clientSecret: String, code: String) async throws -> DebridOAuthToken {
        var request = URLRequest(url: Self.oauth.appendingPathComponent("token"), timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "client_secret", value: clientSecret),
                           URLQueryItem(name: "code", value: code), URLQueryItem(name: "grant_type", value: Self.deviceGrant)]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let json = try await call(request)
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else { throw DebridError.unexpected }
        return DebridOAuthToken(access: access, refresh: refresh, expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
    }

    private func call(_ request: URLRequest) async throws -> [String: Any] {
        let (status, body): (Int, Data)
        do { (status, body) = try await fetch(request) } catch { throw DebridError.network("\(error)") }
        if status == 401 || status == 403 { throw DebridError.invalidToken }
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw DebridError.network("HTTP \(status)") }
        return json
    }
}

extension DebridAccount {
    /// Renueva la llave cuando le queda menos de esto.
    public static let renewBefore: TimeInterval = 15 * 60

    /// ¿La conexión de este aparato fue con código (se renueva sola)?
    public nonisolated var connectedByCode: Bool { oauth != nil }

    nonisolated var oauth: DebridOAuth? {
        vaultRef.secret(AddonKeys.realDebridOAuth).flatMap { try? Self.decoder.decode(DebridOAuth.self, from: Data($0.utf8)) }
    }

    private func storeOAuth(_ value: DebridOAuth?) {
        let text = value.flatMap { try? Self.encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        vaultRef.setSecret(AddonKeys.realDebridOAuth, text)
    }

    /// Aprobaste el código: se cambia por la llave, se comprueba con Real-Debrid y se guarda como si la hubieras pegado (los
    /// recomendados se arman con ella). No se comparte con tus otros aparatos Apple: vence y cada uno conecta el suyo.
    public func connect(code: DebridDeviceCode, clientID: String, clientSecret: String) async throws -> DebridStatus {
        guard let rd = provider as? RealDebrid else { throw DebridError.unexpected }
        let token = try await rd.token(clientID: clientID, clientSecret: clientSecret, code: code.deviceCode)
        let status = try await rd.status(token: token.access)
        guard status.isPremium else { return status }
        guard save(token: token.access, status: status, share: false) else { throw DebridError.unexpected }
        storeOAuth(DebridOAuth(clientID: clientID, clientSecret: clientSecret, refreshToken: token.refresh,
                               expiresAt: now().addingTimeInterval(token.expiresIn)))
        return status
    }

    /// Si la llave está por vencer (o ya venció), pide otra. true si la cambió (hay que poner al día lo que la usa).
    @discardableResult
    public func renewIfNeeded() async -> Bool {
        guard let session = oauth, let rd = provider as? RealDebrid, session.expiresAt.timeIntervalSince(now()) < Self.renewBefore else { return false }
        guard let fresh = try? await rd.token(clientID: session.clientID, clientSecret: session.clientSecret, code: session.refreshToken) else { return false }
        guard vaultRef.storeSecret(AddonKeys.realDebridToken, fresh.access) else { return false }
        storeOAuth(DebridOAuth(clientID: session.clientID, clientSecret: session.clientSecret, refreshToken: fresh.refresh,
                               expiresAt: now().addingTimeInterval(fresh.expiresIn)))
        return true
    }

    /// Al pegar una clave a mano o quitarla, la conexión con código se olvida.
    public func forgetCodeConnection() { storeOAuth(nil) }
}
