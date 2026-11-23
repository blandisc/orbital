import Foundation

/// CX8-A · «Darle su propia conexión» a un aparato que entró con el QR de antes. Formas acordadas con la sesión de la TV (3 nov);
/// la llave nunca se imprime ni se guarda fuera del llavero. (La invitación del iPad, CX4-A, se quitó con PA5-A.)

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
    /// `POST /api/devices/invite` (con la llave del iPhone) `{platform}` → `{code, expires}`. La app ya no lo llama (PA5-A: el
    /// iPad no se conecta a la TV); se queda porque es parte del contrato con la TV (`ContractFixturesTests`).
    public func invite(platform: String) async throws -> (code: String, expires: Date) {
        guard hasDeviceKey else { throw Failure.needsKey }
        let json = try await send("api/devices/invite", method: "POST", body: JSON.object(["platform": .string(platform)]).serialized())
        guard let code = json?["code"]?.nonEmptyString else { throw Failure.refused("Tu TV contestó algo que no entiendo.") }
        return (code, Self.date(json?["expires"]) ?? Date().addingTimeInterval(7 * 86_400))
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
