import Foundation
import OrbitalAddons

/// `GET/PUT /api/addons` contra tu Orbital (corte S6 de la TV; design/addons-contract.json, `routes`), solo por https o por
/// Tailscale (`OrbitalRemote.normalize`). Con la llave de este aparato (K1) va ella; sin llave, el token del túnel. Las
/// direcciones llegan tapadas; `?full=1` (las completas) solo con llave, y cuenta para el tope de 20 lecturas por hora.
public struct AddonListRemote: Sendable {
    public static let path = "api/addons"

    public enum Reply: Equatable, Sendable {
        /// 200: la lista (la guardada, en un PUT).
        case list(SharedAddonList)
        /// 409: partiste de otra revisión; va la actual para juntar y reintentar.
        case conflict(SharedAddonList)
        /// 422: algo no cuadra (con su motivo, tal cual lo dice la TV).
        case refused(String)
        /// 404: tu Orbital es de antes del corte S6.
        case outdated
        /// No contestó (apagada, otra red) o no aceptó el token.
        case unreachable
    }

    private let remote: @Sendable () -> OrbitalRemote
    public init(remote: @escaping @Sendable () -> OrbitalRemote) { self.remote = remote }

    public var isConfigured: Bool { remote().isConfigured }

    /// ¿Habla con la llave de este aparato? Sin ella no se pide `?full=1` ni viaja una dirección con clave.
    public var hasDeviceKey: Bool { remote().hasDeviceKey }

    /// `full`: las direcciones completas (solo con llave; si no, se pide la tapada).
    public func get(full: Bool = false) async -> Reply {
        await send("GET", query: full && hasDeviceKey ? [URLQueryItem(name: "full", value: "1")] : [], body: nil)
    }

    public func put(_ body: StoredJSON) async -> Reply {
        guard let data = try? JSONEncoder().encode(body) else { return .refused("La lista no tiene la forma acordada") }
        return await send("PUT", body: data)
    }

    private func send(_ method: String, query: [URLQueryItem] = [], body: Data?) async -> Reply {
        let remote = remote()
        guard let request = try? remote.request(Self.path, method: method, query: query, body: body, timeout: 12),
              let response = try? await remote.http.send(request) else { return .unreachable }
        switch response.status {
        case 200..<300: return SharedAddonList.parse(response.data).map(Reply.list) ?? .refused("La lista de tu TV no tiene la forma acordada")
        case 409: return SharedAddonList.parse(response.data).map(Reply.conflict) ?? .unreachable
        case 422: return .refused(JSON.parse(response.data)?["detail"]?.string ?? "Tu TV no aceptó la lista")
        case 404: return .outdated
        case 401, 403: return .refused(remote.authFailure(response).description)
        default: return .unreachable
        }
    }
}
