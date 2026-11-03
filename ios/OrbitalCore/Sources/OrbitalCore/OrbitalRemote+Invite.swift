import Foundation

/// CX4-A y CX8-A · la invitación de tu iPhone para tu iPad y «Darle su propia conexión» a un aparato que entró con el QR de
/// antes. Formas acordadas con la sesión de la TV (3 nov); la llave nunca se imprime ni se guarda fuera del llavero.

/// La invitación que tu iPhone deja en el llavero de iCloud para tu iPad: un aparato, 7 días, muere si se quita el iPhone.
public struct OrbitalInvite: Codable, Equatable, Sendable, CustomStringConvertible {
    public var code: String
    public var expires: Date
    /// Dónde está tu TV (la dirección del túnel) y cómo se llama; `tvID` para descartarla si la TV cambió (TEC-30).
    public var address: String, tvName: String, tvID: String
    /// Quién invitó («iPhone de Fernando»).
    public var from: String
    public init(code: String, expires: Date, address: String, tvName: String, tvID: String, from: String) {
        self.code = code; self.expires = expires; self.address = address; self.tvName = tvName; self.tvID = tvID; self.from = from
    }
    public var description: String { "OrbitalInvite(tv: \(tvName), from: \(from), expires: \(expires), code: •••)" }

    public func isValid(at now: Date) -> Bool { now < expires && !code.isEmpty && OrbitalRemote.normalize(address) != nil }
    /// TEC-16 · pasada la mitad de su vida, el iPhone la renueva al abrirse.
    public func needsRenewal(at now: Date, life: TimeInterval = OrbitalInvite.life) -> Bool { expires.timeIntervalSince(now) < life / 2 }
    public static let life: TimeInterval = 7 * 86_400

    public var encoded: String {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        return (try? e.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    public static func decode(_ raw: String?) -> OrbitalInvite? {
        guard let data = raw?.data(using: .utf8) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(OrbitalInvite.self, from: data)
    }
}

/// Cómo va «Darle su propia conexión» (CX8-A): la TV pregunta en su pantalla y el aparato espera.
public enum OrbitalUpgrade: Equatable, Sendable, CustomStringConvertible {
    case pending(request: String)
    case approved(OrbitalPairResult)
    case denied
    case expired
    public var description: String {
        switch self {
        case .pending: "pending"
        case .approved(let r): "approved(\(r))"
        case .denied: "denied"
        case .expired: "expired"
        }
    }
}

extension OrbitalRemote {
    /// `POST /api/devices/invite` (con la llave del iPhone) `{platform}` → `{code, expires}`.
    public func invite(platform: String) async throws -> (code: String, expires: Date) {
        guard hasDeviceKey else { throw Failure.needsKey }
        let json = try await send("api/devices/invite", method: "POST", body: JSON.object(["platform": .string(platform)]).serialized())
        guard let code = json?["code"]?.nonEmptyString else { throw Failure.refused("Tu TV contestó algo que no entiendo.") }
        return (code, Self.date(json?["expires"]) ?? Date().addingTimeInterval(OrbitalInvite.life))
    }

    /// `POST /api/devices/upgrade` (con el token de antes, una vez) `{name, platform}` → 202 `{id}`: la TV pregunta en su
    /// pantalla y espera hasta 3 min. 409 si este aparato ya tiene llave.
    public func upgrade(name: String, platform: String) async throws -> OrbitalUpgrade {
        let body = JSON.object(["name": .string(String(name.prefix(60))), "platform": .string(platform)]).serialized()
        return try await upgradeStep(try request("api/devices/upgrade", method: "POST", body: body, timeout: 12), id: nil)
    }

    /// `GET /api/devices/upgrade/<id>` (con el token): 202 esperando, 200 con la llave (una sola vez), 403 dijo que no, 404 ya
    /// no está.
    public func upgradeStatus(_ id: String) async throws -> OrbitalUpgrade {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return try await upgradeStep(try request("api/devices/upgrade/\(safe)", method: "GET", body: nil, timeout: 12), id: id)
    }

    private func upgradeStep(_ request: HTTPRequest, id: String?) async throws -> OrbitalUpgrade {
        var request = request
        request.headers["Cache-Control"] = "no-store"
        let response: HTTPResponse
        do { response = try await http.send(request) } catch { throw Failure.unreachable }
        let json = JSON.parse(response.data)
        switch response.status {
        case 202:
            guard let id = json?["id"]?.nonEmptyString ?? id else { return .expired }
            return .pending(request: id)
        case 200..<300:
            guard let key = json?["key"]?.string, let deviceID = OrbitalDeviceKey.deviceID(of: key) else {
                throw Failure.refused("Tu TV contestó algo que no entiendo. Vuelve a escanear el código.")
            }
            return .approved(OrbitalPairResult(deviceID: json?["device_id"]?.nonEmptyString ?? deviceID, key: key,
                                               tvName: json?["tv_name"]?.nonEmptyString ?? "", tvID: json?["tv_id"]?.nonEmptyString ?? ""))
        case 403: return .denied
        case 404, 410: return .expired
        case 401: throw authFailure(response)
        case 409: throw Failure.refused(json?["detail"]?.string ?? "Este aparato ya tiene su propia conexión.")
        case 429: throw Failure.refused(Self.waitLine)
        default: throw Failure.refused(json?["detail"]?.string ?? "Tu Orbital contestó con un error (\(response.status)).")
        }
    }
}
