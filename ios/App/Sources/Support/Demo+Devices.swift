#if DEBUG
import Foundation
import OrbitalCore

/// K1 · las llaves por aparato con la Orbital de mentira (`tv.demo.invalid`). Nada sale a una TV de verdad y la llave es de
/// mentira (no sirve en ningún lado):
///
/// - `-demo-keys paired`: emparejado con QR v2 (llave, sin token); Tu Orbital enseña los aparatos de la TV.
/// - `-demo-keys rescan`: la TV anuncia `pairing: 2` y este iPhone solo tiene el token: «Vuelve a escanear el código de tu TV».
/// - `-demo-keys removed`: la TV quitó este iPhone (401 `device_removed`): la llave se borra y sale la misma frase.
/// - `-demo-keys pass-ok` · `pass-422`: «Pasar a la TV» que la TV acepta o que Real-Debrid no reconoce (con `-demo-rd premium`).
/// - `-demo-keys use`: «Usar la de la TV» (la TV tiene una clave de mentira; con `-demo-rd premium` Real-Debrid la acepta).
/// - `-demo-keys other-account`: la TV usa otra cuenta de Real-Debrid («ana»): la pregunta de las tres salidas (IOS-6).
///
/// Con `-demo-scan v2`, la hoja de conectar lee un QR v2 y la TV de mentira le da su llave.
extension Demo {
    static var keys: String? { value(after: "-demo-keys") }
    /// Una llave de mentira con la forma acordada («od1.<32 hex>.<secreto>»).
    static let deviceKey = "od1." + String(repeating: "d3", count: 16) + "." + String(repeating: "DEMOkey_", count: 5)
    static let deviceKeyID = String(repeating: "d3", count: 16)

    /// Lo que guarda el llavero de mentira según `-demo-keys`.
    static func seedKeys(_ secrets: InMemorySecrets) {
        guard let mode = keys, !noTV else { return }
        if mode == "rescan" { return }   // solo el token de antes
        secrets.set(SecretKey.orbitalDeviceKey, deviceKey)
        secrets.set(SecretKey.orbitalToken, nil)
    }
}

/// La TV de mentira de K1: `pairing: 2`, la lista de aparatos, quitar, emparejar con el código v2 y la clave de Real-Debrid.
enum DemoDevices {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var removed: Set<String> = []

    static func respond(_ request: HTTPRequest) -> HTTPResponse? {
        let url = request.url, path = url.path
        guard url.host == "tv.demo.invalid", Demo.keys != nil || Demo.value(after: "-demo-scan") == "v2" else { return nil }
        func json(_ value: JSON, _ status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        let keyed = request.headers["Authorization"] == "Bearer \(Demo.deviceKey)"
        if path == "/api/devices/pair", request.method == "POST" {
            return json(["device_id": .string(Demo.deviceKeyID), "key": .string(Demo.deviceKey), "tv_name": "Orbital de la sala"])
        }
        if Demo.keys == "removed", keyed {
            return json(["code": "device_removed", "detail": "Esta TV te quitó: vuelve a escanear el QR"], 401)
        }
        if path == "/api/companion", request.method == "GET" { return json(["pairing": 2, "region": "MX"]) }
        if path == "/api/devices", request.method == "GET" {
            guard keyed else { return json(["code": "device_key_required", "detail": "Espera las llaves por aparato"], 401) }
            let now = Date().timeIntervalSince1970
            let all: [JSON] = [
                ["device_id": .string(Demo.deviceKeyID), "name": "iPhone de Fernando", "platform": "iphone", "paired_at": .double(now - 86_400), "seen": .double(now), "this": true],
                ["device_id": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", "name": "iPad de la sala", "platform": "ipad", "paired_at": .double(now - 9 * 86_400), "seen": .double(now - 3 * 3600), "this": false],
                ["device_id": "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2", "name": "iPhone de Ana", "platform": "iphone", "paired_at": .double(now - 20 * 86_400), "seen": .double(now - 6 * 86_400), "this": false],
            ]
            let gone = lock.withLock { removed }
            return json(.array(all.filter { !gone.contains($0["device_id"]?.string ?? "") }))
        }
        if path.hasPrefix("/api/devices/"), request.method == "DELETE" {
            lock.withLock { _ = removed.insert(url.lastPathComponent) }
            return json(["ok": true])
        }
        if path == "/api/realdebrid" {
            guard keyed else { return json(["code": "device_key_required", "detail": "Espera las llaves por aparato"], 401) }
            if request.method == "PUT" {
                if Demo.keys == "pass-422" { return json(["detail": "Real-Debrid no la reconoce"], 422) }
                let sent = request.body.flatMap(JSON.parse)?["token"]?.string ?? ""
                return json(["user": "demo", "premium": true, "expires": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(143 * 86_400))),
                             "tail": .string("••••" + String(sent.suffix(4)).uppercased())])
            }
            // IOS-6: `-demo-keys other-account`: la TV usa otra cuenta («ana»). La clave, solo con `?full=1` (como la TV).
            let user: JSON = Demo.keys == "other-account" ? "ana" : "demo"
            var out: JSON = ["linked": true, "user": user, "premium": true, "ends_with": "DEMO"]
            if url.query?.contains("full=1") == true { out = ["token": .string(Demo.realDebridToken), "user": user, "premium": true, "ends_with": "DEMO"] }
            return json(out)
        }
        return nil
    }
}
#endif
