import XCTest
#if canImport(Security)
import Security
#endif
@testable import OrbitalCore

/// K1 · llaves por aparato (contrato «devices» y «secrets»), con una TV de mentira: nada sale a una TV ni a una cuenta de verdad.
private final class ScriptedTV: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    var requests: [HTTPRequest] { lock.withLock { _requests } }
    let answer: @Sendable (HTTPRequest) -> (Int, JSON)
    init(_ answer: @escaping @Sendable (HTTPRequest) -> (Int, JSON)) { self.answer = answer }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _requests.append(request) }
        let (status, json) = answer(request)
        return HTTPResponse(status: status, data: json.serialized())
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}

final class OrbitalDeviceKeyTests: XCTestCase {
    static let id = String(repeating: "ab", count: 16)
    static let key = "od1.\(id).\(String(repeating: "Zx9_-", count: 9))"

    func testQRv1AndV2() throws {
        let v1 = try XCTUnwrap(URL(string: "orbital-ios://pair?u=https%3A%2F%2Ftv.example&t=TOKEN"))
        XCTAssertEqual(OrbitalRemote.pairingLink(v1), .token(address: "https://tv.example", token: "TOKEN"))
        XCTAssertEqual(OrbitalRemote.pairing(v1)?.token, "TOKEN", "el v1 sigue sirviendo")
        let code = String(repeating: "c0De-_", count: 7) + "x"   // 43, como 32 bytes en base64url
        let v2 = try XCTUnwrap(URL(string: "orbital-ios://pair?v=2&u=https%3A%2F%2Ftv.example&c=\(code)"))
        XCTAssertEqual(OrbitalRemote.pairingLink(v2), .code(address: "https://tv.example", code: code))
        XCTAssertNil(OrbitalRemote.pairing(v2), "el v2 no trae token")
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=2&u=https%3A%2F%2Ftv.example&t=TOKEN")!), "v2 sin código")
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=2&u=https%3A%2F%2Ftv.example&c=corto")!))
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=2&u=https%3A%2F%2Ftv.example&c=\(code)%2B%2F")!), "solo base64url")
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=2&u=http%3A%2F%2Fevil.example&c=\(code)")!), "http fuera de Tailscale")
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=3&u=https%3A%2F%2Ftv.example&c=\(code)")!), "una versión que no conoce")
        XCTAssertNil(OrbitalRemote.pairingLink(URL(string: "https://tv.example/pair?v=2&c=\(code)")!))
    }

    func testDeviceKeyShape() {
        XCTAssertEqual(OrbitalDeviceKey.deviceID(of: Self.key), Self.id)
        XCTAssertNil(OrbitalDeviceKey.deviceID(of: "od2.\(Self.id).\(String(repeating: "a", count: 43))"))
        XCTAssertNil(OrbitalDeviceKey.deviceID(of: "od1.xyz.\(String(repeating: "a", count: 43))"))
        XCTAssertNil(OrbitalDeviceKey.deviceID(of: "od1.\(Self.id)."))
        XCTAssertNil(OrbitalDeviceKey.deviceID(of: "TOKEN"))
        let remote = OrbitalRemote(http: ScriptedTV { _ in (200, [:]) }, address: "tv.example", token: "", deviceKey: "od1.malformada")
        XCTAssertFalse(remote.hasDeviceKey, "una llave sin la forma acordada no se manda")
        XCTAssertFalse(remote.isConfigured)
    }

    #if canImport(Security)
    func testKeychainKeepsItOnThisDeviceAndOutOfICloud() {
        let attributes = KeychainSecrets.addAttributes
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(SecretKey.orbitalDeviceKey, "orbital_device_key")
    }
    #endif

    func testEveryRequestUsesTheKeyInsteadOfTheToken() async throws {
        let tv = ScriptedTV { _ in (200, ["ok": true]) }
        let device = OrbitalRemote.Device(name: "iPhone", kind: "iphone", id: "INSTALL-1")
        try await OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN", device: device, deviceKey: Self.key).check()
        let keyed = try XCTUnwrap(tv.requests.last)
        XCTAssertEqual(keyed.headers["Authorization"], "Bearer \(Self.key)")
        XCTAssertNil(keyed.headers["X-Orbital-Device-Id"], "con llave la TV lo ignora: ya no va")
        XCTAssertFalse(keyed.url.absoluteString.contains("od1"), "la llave nunca en la dirección")
        try await OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN", device: device).check()
        XCTAssertEqual(tv.requests.last?.headers["Authorization"], "Bearer TOKEN")
        XCTAssertEqual(tv.requests.last?.headers["X-Orbital-Device-Id"], "INSTALL-1")
        XCTAssertTrue(OrbitalRemote(http: tv, address: "tv.example", token: "", deviceKey: Self.key).isConfigured, "con llave y sin token")
    }

    func testTheTwo401CodesAskToScanAgain() async {
        let code = Box("device_key_required")
        let reported = Box<[OrbitalRemote.Failure]>([])
        let tv = ScriptedTV { _ in (401, ["code": .string(code.value), "detail": "Espera las llaves por aparato"]) }
        var remote = OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN")
        remote.authProblem = { reported.value.append($0) }
        do { try await remote.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .needsKey) }
        code.value = "device_removed"
        do { try await remote.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .removed) }
        code.value = "otro"
        do { try await remote.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .badToken) }
        XCTAssertEqual(reported.value, [.needsKey, .removed], "el token malo de siempre no pide escanear")
        XCTAssertEqual(OrbitalRemote.Failure.removed.description, "Vuelve a escanear el código de tu TV")
        XCTAssertEqual(OrbitalRemote.Failure.needsKey.description, OrbitalRemote.rescanLine)
    }

    func testPairSendsTheCodeWithoutAnyTokenAndKeepsTheKeyOutOfDescriptions() async throws {
        let tv = ScriptedTV { _ in (200, ["device_id": .string(Self.id), "key": .string(Self.key), "tv_name": "Orbital de la sala"]) }
        let remote = OrbitalRemote(http: tv, address: "tv.example", token: "")
        let name = String(repeating: "Ñ", count: 80)
        let paired = try await remote.pair(code: "CODE", name: name, platform: "ipad")
        XCTAssertEqual(paired.deviceID, Self.id)
        XCTAssertEqual(paired.tvName, "Orbital de la sala")
        XCTAssertFalse("\(paired)".contains(Self.key), "imprimirlo no enseña la llave")
        let sent = try XCTUnwrap(tv.requests.first)
        XCTAssertEqual(sent.url.absoluteString, "https://tv.example/api/devices/pair")
        XCTAssertNil(sent.headers["Authorization"])
        let body = try XCTUnwrap(JSON.parse(try XCTUnwrap(sent.body)))
        XCTAssertEqual(body["code"]?.string, "CODE")
        XCTAssertEqual(body["platform"]?.string, "ipad")
        XCTAssertEqual(body["name"]?.string?.count, 60)
    }

    func testPairFailuresInWords() async {
        let status = Box(404)
        let tv = ScriptedTV { _ in (status.value, [:]) }
        let remote = OrbitalRemote(http: tv, address: "tv.example", token: "")
        for (code, words) in [(404, "Este código ya no sirve"), (409, "Tu TV ya tiene 10 aparatos. Quita uno en Ajustes › Cuentas"), (429, OrbitalRemote.waitLine)] {
            status.value = code
            do { _ = try await remote.pair(code: "C", name: "iPhone", platform: "iphone"); XCTFail() }
            catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused(words)) }
        }
    }

    func testDevicesAndRemove() async throws {
        let tv = ScriptedTV { request in
            if request.method == "DELETE" { return (200, ["ok": true]) }
            return (200, [["device_id": .string(Self.id), "name": "iPhone de Fernando", "platform": "iphone", "paired_at": 1_760_000_000, "seen": "2026-11-03T10:00:00Z", "this": true],
                          ["device_id": "ff", "name": "iPad", "platform": "ipad", "this": false]])
        }
        let remote = OrbitalRemote(http: tv, address: "tv.example", token: "", deviceKey: Self.key)
        let devices = try await remote.devices()
        XCTAssertEqual(devices.map(\.name), ["iPhone de Fernando", "iPad"])
        XCTAssertEqual(devices.first?.isThis, true)
        XCTAssertNotNil(devices.first?.seen)
        try await remote.removeDevice("ff")
        XCTAssertEqual(tv.requests.last?.method, "DELETE")
        XCTAssertEqual(tv.requests.last?.url.path, "/api/devices/ff")
    }

    func testRealDebridBothWays() async throws {
        let status = Box(200)
        let tv = ScriptedTV { request in
            if request.method == "PUT" {
                return status.value == 200 ? (200, ["user": "fer", "premium": true, "expires": "2027-03-01T00:00:00Z", "tail": "••••3F2A"])
                                           : (status.value, ["detail": "Real-Debrid no la reconoce"])
            }
            return (200, ["token": "RDKEYFROMTHETV", "tail": "••••ETV"])
        }
        let noKey = OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN")
        do { _ = try await noKey.putRealDebrid(token: "X"); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .needsKey) }
        do { _ = try await noKey.realDebridKey(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .needsKey) }
        XCTAssertTrue(tv.requests.isEmpty, "sin llave ni se pregunta: nunca con el token del túnel")

        let remote = OrbitalRemote(http: tv, address: "tv.example", token: "", deviceKey: Self.key)
        let passed = try await remote.putRealDebrid(token: "MYRDKEY")
        XCTAssertEqual(passed, OrbitalTVDebrid(user: "fer", premium: true, expires: OrbitalRemote.date("2027-03-01T00:00:00Z"), tail: "••••3F2A"))
        let put = try XCTUnwrap(tv.requests.last)
        XCTAssertFalse(put.url.absoluteString.contains("MYRDKEY"), "la clave va en el cuerpo, nunca en la dirección")
        XCTAssertEqual(JSON.parse(try XCTUnwrap(put.body))?["token"]?.string, "MYRDKEY")
        status.value = 422
        do { _ = try await remote.putRealDebrid(token: "MALA"); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused("Real-Debrid no la reconoce")) }
        status.value = 429
        do { _ = try await remote.putRealDebrid(token: "MYRDKEY"); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .refused(OrbitalRemote.waitLine)) }

        let key = try await remote.realDebridKey()
        XCTAssertEqual(key, "RDKEYFROMTHETV")
        XCTAssertEqual(tv.requests.last?.url.query, "full=1")
    }

    func testAddonListAsksForFullAddressesOnlyWithAKey() async {
        let tv = ScriptedTV { _ in (200, ["revision": 1, "addons": []]) }
        _ = await AddonListRemote(remote: { OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN") }).get(full: true)
        XCTAssertNil(tv.requests.last?.url.query, "con el token del túnel nunca ?full=1")
        _ = await AddonListRemote(remote: { OrbitalRemote(http: tv, address: "tv.example", token: "", deviceKey: Self.key) }).get(full: true)
        XCTAssertEqual(tv.requests.last?.url.query, "full=1")
        let removed = ScriptedTV { _ in (401, ["code": "device_removed"]) }
        let reply = await AddonListRemote(remote: { OrbitalRemote(http: removed, address: "tv.example", token: "", deviceKey: Self.key) }).get()
        XCTAssertEqual(reply, .refused(OrbitalRemote.rescanLine))
    }

    func testCompanionAnnouncesPairing() async throws {
        let tv = ScriptedTV { _ in (200, ["pairing": 2, "region": "MX"]) }
        let keys = try await OrbitalRemote(http: tv, address: "tv.example", token: "TOKEN").keys()
        XCTAssertEqual(keys.pairing, 2)
        let old = ScriptedTV { _ in (200, ["region": "MX"]) }
        let oldKeys = try await OrbitalRemote(http: old, address: "tv.example", token: "TOKEN").keys()
        XCTAssertEqual(oldKeys.pairing, 1, "una TV de antes no dice nada: v1")
    }
}
