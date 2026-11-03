import Foundation

/// K1 · las llaves por aparato (AD-3; design/addons-contract.json, «devices» y «secrets»): el QR v2, emparejar, la lista de
/// aparatos de tu TV, quitar uno y la clave de Real-Debrid entre el iPhone y la TV. La llave nunca sale del llavero de este
/// aparato: ni en bitácoras, ni en direcciones, ni en los ajustes, ni en lo que se guarda en disco.

/// «od1.<device_id>.<secreto>»: `device_id` en hexadecimal (16 bytes, lo pone la TV) y el secreto en base64url (32 bytes).
public enum OrbitalDeviceKey {
    public static let prefix = "od1"

    /// ¿Tiene la forma acordada? (Lo demás no se manda: sería un token cualquiera en `Authorization`.)
    public static func isValid(_ key: String) -> Bool { deviceID(of: key) != nil }

    /// El id de este aparato en tu TV (la llave de `enabled`); nil si la llave no tiene la forma acordada.
    public static func deviceID(of key: String) -> String? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix, parts[1].count == 32, parts[1].allSatisfy(\.isHexDigit),
              parts[2].count >= 16, parts[2].allSatisfy(isBase64URL) else { return nil }
        return parts[1].lowercased()
    }

    static func isBase64URL(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_") }
}

/// Lo que trae el código de la TV.
public enum OrbitalPairing: Equatable, Sendable {
    /// v1: `orbital-ios://pair?u=<dirección>&t=<token>` (el token del túnel, el mismo de Alexa).
    case token(address: String, token: String)
    /// v2: `orbital-ios://pair?v=2&u=<dirección>&c=<código>`: un código de un solo uso (10 min) que se cambia por la llave.
    case code(address: String, code: String)

    public var address: String {
        switch self { case .token(let a, _), .code(let a, _): a }
    }
}

/// Un aparato emparejado con tu TV (Ajustes › Tu Orbital).
public struct OrbitalPairedDevice: Sendable, Equatable, Identifiable {
    public var id: String, name: String, platform: String
    public var pairedAt: Date?, seen: Date?
    /// Es este iPhone.
    public var isThis: Bool
    public init(id: String, name: String, platform: String, pairedAt: Date? = nil, seen: Date? = nil, isThis: Bool = false) {
        self.id = id; self.name = name; self.platform = platform; self.pairedAt = pairedAt; self.seen = seen; self.isThis = isThis
    }

    static func parse(_ json: JSON) -> OrbitalPairedDevice? {
        guard let id = json["device_id"]?.nonEmptyString else { return nil }
        return OrbitalPairedDevice(id: id, name: json["name"]?.nonEmptyString ?? id, platform: json["platform"]?.string ?? "",
                                   pairedAt: OrbitalRemote.date(json["paired_at"]), seen: OrbitalRemote.date(json["seen"]),
                                   isThis: json["this"]?.bool ?? false)
    }
}

/// Lo que contestó la TV al emparejar. La llave no se enseña al imprimirlo.
public struct OrbitalPairResult: Sendable, Equatable, CustomStringConvertible {
    public var deviceID: String, key: String, tvName: String
    public var description: String { "OrbitalPairResult(deviceID: \(deviceID), tvName: \(tvName), key: •••)" }
}

/// La cuenta de Real-Debrid de tu TV tras «Pasar a la TV»: nunca la clave, solo sus últimas letras («••••3F2A»).
public struct OrbitalTVDebrid: Sendable, Equatable {
    public var user: String, premium: Bool, expires: Date?, tail: String
    public init(user: String, premium: Bool, expires: Date?, tail: String) { self.user = user; self.premium = premium; self.expires = expires; self.tail = tail }
}

extension OrbitalRemote {
    /// La frase tranquila (con «Escanear»): la TV ya reparte llaves y este aparato no tiene la suya, o la TV lo quitó.
    public static let rescanLine = "Vuelve a escanear el código de tu TV"
    /// 429: la TV pidió esperar (tope por hora). En palabras, no una pantalla de error.
    public static let waitLine = "Tu Orbital pidió esperar un poco: demasiados intentos."

    /// El código de la TV, v1 o v2. nil si no es de Orbital o la dirección no sirve (`normalize`).
    public static func pairingLink(_ url: URL) -> OrbitalPairing? {
        guard url.scheme == "orbital-ios", url.host == "pair", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let address = items.first(where: { $0.name == "u" })?.value, normalize(address) != nil else { return nil }
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 } }
        switch value("v") ?? "1" {
        case "1": return value("t").map { .token(address: address, token: $0) }
        case "2":
            guard let code = value("c"), code.count >= 16, code.count <= 128, code.allSatisfy(OrbitalDeviceKey.isBase64URL) else { return nil }
            return .code(address: address, code: code)
        default: return nil   // una versión que esta app aún no conoce
        }
    }

    /// Un 401/403 de tu TV: `device_key_required` y `device_removed` piden escanear otra vez (y se avisa a `authProblem`);
    /// lo demás es el token de siempre.
    func authFailure(_ response: HTTPResponse) -> Failure {
        let failure: Failure = switch JSON.parse(response.data)?["code"]?.string ?? JSON.parse(response.data)?["detail"]?["code"]?.string {
        case "device_key_required": .needsKey
        case "device_removed": .removed
        default: .badToken
        }
        if failure != .badToken { authProblem?(failure) }
        return failure
    }

    // MARK: Emparejar (sin token: el código es la prueba)

    /// `POST /api/devices/pair` con el código del QR v2, el nombre de este aparato (≤ 60) y su plataforma.
    public func pair(code: String, name: String, platform: String) async throws -> OrbitalPairResult {
        guard let base else { throw Failure.notConfigured }
        let body = JSON.object(["code": .string(code), "name": .string(String(name.prefix(60))), "platform": .string(platform)]).serialized()
        let request = HTTPRequest(url: base.appendingPathComponent("api/devices/pair"), method: "POST",
                                  headers: ["Content-Type": "application/json", "Cache-Control": "no-store"], body: body, timeout: 12)
        let response: HTTPResponse
        do { response = try await http.send(request) } catch { throw Failure.unreachable }
        let json = JSON.parse(response.data)
        switch response.status {
        case 200..<300:
            guard let key = json?["key"]?.string, let id = OrbitalDeviceKey.deviceID(of: key) else {
                throw Failure.refused("Tu TV contestó algo que no entiendo. Vuelve a escanear el código.")
            }
            return OrbitalPairResult(deviceID: json?["device_id"]?.nonEmptyString ?? id, key: key, tvName: json?["tv_name"]?.nonEmptyString ?? "")
        case 404:
            // Cualquier falla del código (vencido, ya usado, otro) es 404. Una TV de antes tampoco tiene la ruta: mismo arreglo.
            throw Failure.refused(json?["detail"]?.string ?? "Este código ya no sirve")
        case 409: throw Failure.refused(json?["detail"]?.string ?? "Tu TV ya tiene 10 aparatos. Quita uno en Ajustes › Cuentas")
        case 429: throw Failure.refused(Self.waitLine)
        default: throw Failure.refused(json?["detail"]?.string ?? "Tu Orbital contestó con un error (\(response.status)).")
        }
    }

    // MARK: Tus aparatos (solo con llave)

    public func devices() async throws -> [OrbitalPairedDevice] {
        let json = try await send("api/devices", method: "GET", body: nil)
        return (json?.array ?? json?["devices"]?.array ?? []).compactMap(OrbitalPairedDevice.parse)
    }

    /// «Quitar»: sin deshacer. La TV borra su llave y su prendido en `enabled`.
    public func removeDevice(_ id: String) async throws {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        _ = try await send("api/devices/\(safe)", method: "DELETE", body: nil)
    }

    // MARK: Real-Debrid entre los dos (solo con llave, por el puerto público)

    /// «Pasar a la TV»: la TV la comprueba con Real-Debrid antes de guardarla (422 si no la reconoce: se queda la de antes).
    public func putRealDebrid(token: String) async throws -> OrbitalTVDebrid {
        guard hasDeviceKey else { throw Failure.needsKey }
        let json = try await send("api/realdebrid", method: "PUT", body: JSON.object(["token": .string(token)]).serialized())
        return OrbitalTVDebrid(user: json?["user"]?.string ?? json?["username"]?.string ?? "", premium: json?["premium"]?.bool ?? false,
                               expires: Self.date(json?["expires"]), tail: json?["tail"]?.string ?? "")
    }

    /// «Usar la de la TV»: la clave completa (`?full=1`). nil si la TV no tiene una.
    public func realDebridKey() async throws -> String? {
        guard hasDeviceKey else { throw Failure.needsKey }
        let json = try await send("api/realdebrid", method: "GET", query: [URLQueryItem(name: "full", value: "1")], body: nil)
        return (json?["token"]?.nonEmptyString ?? json?["key"]?.nonEmptyString)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Una fecha de la TV: segundos desde 1970 o ISO 8601.
    static func date(_ json: JSON?) -> Date? {
        if let seconds = json?.doubleValue { return Date(timeIntervalSince1970: seconds) }
        guard let text = json?.nonEmptyString else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
