#if DEBUG
import Foundation
import OrbitalCore
import OrbitalAddons

/// CX1-B…CX8-A con todo de mentira (`-demo-cx <estado>`): nada sale a Real-Debrid ni a una TV de verdad.
///
/// - `shared-differs` (con `-demo-rd premium`): la copia de tus aparatos Apple es de otra cuenta (ana), puesta por tu iPad.
/// - `shared-offer` (sin `-demo-rd`): sin clave aquí; tus aparatos Apple tienen una («Usar la clave de tus aparatos Apple»).
/// - `remove-choice` (con `-demo-rd premium -demo-settings-page realdebrid`): «¿Quitar tu clave?» con sus dos salidas.
/// - `invite` · `invite-expired` (en el iPad, con `-demo-no-tv`): la tarjeta «¿Conectar con Orbital de la sala?».
/// - `upgrade-wait` · `upgrade-ok` · `upgrade-no` (con `-demo-settings-page orbital`): «Darle su propia conexión».
/// - `unknown-tv`: la TV no conoce este aparato: «Tu TV es nueva: vuelve a escanear su código».
/// - `ipad-list` (en el iPad): Aparatos conectados, con «Quitar» solo en este iPad.
extension Demo {
    static var cx: String? { value(after: "-demo-cx") }
    static let anaToken = String(repeating: "ANADEMO", count: 7)
    static let sharedToken = String(repeating: "FERSHARE", count: 6)

    static func seedCX(_ secrets: InMemorySecrets) {
        guard let state = cx else { return }
        switch state {
        case "shared-differs": secrets.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: anaToken, from: "ipad", name: "iPad de Ana").encoded)
        case "shared-offer": secrets.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: sharedToken, from: "iphone").encoded)
        case "invite", "invite-expired":
            let expires = Date().addingTimeInterval(state == "invite" ? 6 * 86_400 : -3600)
            secrets.set(SecretKey.orbitalInvite, OrbitalInvite(code: "DEMOinvite", expires: expires, address: "https://tv.demo.invalid",
                                                               tvName: "Orbital de la sala", tvID: "0123456789abcdef", from: "iPhone de Fernando").encoded)
        case "unknown-tv", "ipad-list":
            secrets.set(SecretKey.orbitalDeviceKey, deviceKey); secrets.set(SecretKey.orbitalToken, nil)
        default: break   // upgrade-*: solo el token de antes
        }
    }
}

enum DemoCX {
    nonisolated(unsafe) private static var polls = 0
    private static let lock = NSLock()

    /// Real-Debrid de mentira para la copia compartida: «ANA…» es la cuenta ana; lo demás, la de siempre (demo).
    static func realDebrid(_ request: HTTPRequest) -> HTTPResponse? {
        guard Demo.cx != nil, request.url.host == "api.real-debrid.com", request.url.path.hasSuffix("/user") else { return nil }
        let ana = request.headers["Authorization"]?.contains("ANADEMO") == true
        if Demo.realDebrid != nil, !ana, request.headers["Authorization"]?.contains(Demo.sharedToken) != true { return nil }
        let user: JSON = ["id": .int(ana ? 2 : 1), "username": .string(ana ? "ana" : "demo"), "type": "premium", "premium": .int(143 * 86_400),
                          "expiration": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(143 * 86_400)))]
        return HTTPResponse(status: 200, data: user.serialized())
    }

    /// La TV de mentira para lo nuevo: «Tu TV es nueva», la invitación, «Darle su propia conexión» y la lista desde el iPad.
    static func respond(_ request: HTTPRequest) -> HTTPResponse? {
        guard let state = Demo.cx, request.url.host == "tv.demo.invalid" else { return nil }
        func json(_ value: JSON, _ status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        let path = request.url.path, keyed = request.headers["Authorization"] == "Bearer \(Demo.deviceKey)"
        if state == "unknown-tv", keyed { return json(["code": "device_unknown", "detail": "Esta TV no conoce este aparato"], 401) }
        if path == "/api/devices/pair", request.method == "POST" {
            return json(["device_id": .string(Demo.deviceKeyID), "key": .string(Demo.deviceKey), "tv_name": "Orbital de la sala", "tv_id": "0123456789abcdef"])
        }
        if path == "/api/companion" { return json(["pairing": 2, "region": "MX", "tv_id": "0123456789abcdef"]) }
        if path.hasPrefix("/api/devices/upgrade") {
            let n = lock.withLock { () -> Int in polls += 1; return polls }
            switch state {   // el contrato: 202 {id}, 202 esperando, 200 con la llave una vez, 403 si dijo que no
            case "upgrade-ok" where n >= 3:
                return json(["device_id": .string(Demo.deviceKeyID), "key": .string(Demo.deviceKey), "tv_name": "Orbital de la sala", "tv_id": "0123456789abcdef"])
            case "upgrade-no" where n >= 3: return json(["detail": "Tu TV dijo que no"], 403)
            default: return json(["id": "demo"], 202)
            }
        }
        if path == "/api/devices/invite" {
            return json(["code": "DEMOinvite", "expires": .double(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970), "platform": "ipad"])
        }
        if path == "/api/devices", request.method == "GET", state == "ipad-list", keyed {
            let now = Date().timeIntervalSince1970
            return json([["device_id": .string(Demo.deviceKeyID), "name": "iPad de la sala", "platform": "ipad", "seen": .double(now), "this": true, "invited_by": "iPhone de Fernando"],
                         ["device_id": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", "name": "iPhone de Fernando", "platform": "iphone", "seen": .double(now - 3600), "this": false],
                         ["device_id": "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2", "name": "iPhone de Ana", "platform": "iphone", "seen": .double(now - 86_400), "this": false]])
        }
        if path.hasPrefix("/api/devices/"), request.method == "DELETE", state == "ipad-list", !path.hasSuffix(Demo.deviceKeyID) {
            return json(["detail": "Solo tu iPhone o la TV pueden quitar otro aparato"], 403)
        }
        return nil
    }
}
#endif
