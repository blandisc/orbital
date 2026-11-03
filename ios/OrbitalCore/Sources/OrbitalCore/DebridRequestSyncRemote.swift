import Foundation
import OrbitalAddons

/// La libreta de pedidos a Real-Debrid junto con la de tu Orbital (contrato › `requests` › `routes`, acuerdo S2):
/// `GET /api/realdebrid/requests` lee la de la TV (`{version, account, requests}`, cada entrada por separado) y `POST
/// /api/realdebrid/requests` le manda una entrada completa, sin `updated` ni lo de este aparato; la TV la junta por huella y
/// contesta con la que guardó. Va con el token del puerto del túnel (el de Alexa) porque no lleva claves ni enlaces, y solo
/// por https o por Tailscale (`OrbitalRemote.normalize`). Nunca le pide nada a Real-Debrid.
public struct OrbitalRemoteDebridRequestSync: DebridRequestSync {
    public static let path = "api/realdebrid/requests"
    /// El tope del contrato para el cuerpo de un POST (`limits.post_body_bytes`); el GET devuelve todo lo guardado.
    public static let maxPostBytes = 16_384

    private let remote: @Sendable () -> OrbitalRemote
    public init(remote: @escaping @Sendable () -> OrbitalRemote) { self.remote = remote }

    public func pull() async -> DebridRequestPull? {
        let remote = remote()
        guard remote.isConfigured, let data = try? await remote.raw(Self.path, method: "GET", body: nil) else { return nil }
        return DebridRequestPull.parse(data)
    }

    public func push(_ request: DebridRequest) async -> DebridRequest? {
        let remote = remote()
        guard remote.isConfigured, let body = try? DebridRequestBook.wireEncoder.encode(request), body.count <= Self.maxPostBytes,
              let data = try? await remote.raw(Self.path, method: "POST", body: body) else { return nil }
        return DebridRequestBook.decodeEach(Data("[".utf8) + data + Data("]".utf8)).first
    }
}

extension OrbitalRemote {
    /// El cuerpo tal cual de una ruta de tu Orbital (con el token y el aparato). Lanza si no contesta o no es un 2xx.
    func raw(_ path: String, method: String, body: Data?, timeout: TimeInterval = 12) async throws -> Data {
        let request = try request(path, method: method, body: body, timeout: timeout)
        let response: HTTPResponse
        do { response = try await http.send(request) } catch { throw Failure.unreachable }
        switch response.status {
        case 200..<300: return response.data
        case 401, 403: throw authFailure(response)
        case 404: throw Failure.outdated
        default: throw Failure.refused(JSON.parse(response.data)?["detail"]?.string ?? "Tu Orbital contestó con un error (\(response.status)).")
        }
    }
}
