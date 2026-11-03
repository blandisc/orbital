import XCTest
@testable import OrbitalModels
@testable import OrbitalCore
@testable import OrbitalAddons

/// K1 · con una TV y un Real-Debrid de mentira (nada sale a internet): emparejar con el QR v2, la frase de «Escanear», quitar
/// aparatos, «Pasar a la TV» / «Usar la de la TV», `enabled[<id>]` y que la llave no se guarde en ningún lado fuera del llavero.
private final class FakeK1TV: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var pairing = 2
    var rdStatus = 200
    var authCode: String?
    var tvKey = String(repeating: "TVKEY", count: 10)
    /// La cuenta de Real-Debrid de la TV (`GET /api/realdebrid`); nil: la TV no tiene.
    var tvUser: String? = "fer"
    var addons = SharedAddonList(revision: 3, addons: [])
    var fullAddons: [String: String] = [:]
    private(set) var requests: [HTTPRequest] = []
    static let id = String(repeating: "c4", count: 16)
    static let key = "od1.\(id).\(String(repeating: "S3cr3t_-", count: 5))"

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append(request)
            func json(_ v: JSON, _ s: Int = 200) -> HTTPResponse { HTTPResponse(status: s, data: v.serialized()) }
            let path = request.url.path
            if request.url.host == "api.real-debrid.com" {
                let premium = request.headers["Authorization"]?.contains("FREE") == true ? 0 : 3_000_000
                return json(["id": 9, "username": "fer", "type": premium > 0 ? "premium" : "free", "premium": .int(premium)])
            }
            if request.url.host == "addon.example" { return json(["name": "Jackett", "resources": ["stream"], "types": ["movie"]]) }
            if path == "/api/devices/pair" { return json(["device_id": .string(Self.id), "key": .string(Self.key), "tv_name": "Sala"]) }
            if let code = authCode { return json(["code": .string(code)], 401) }
            switch path {
            case "/api/ping": return json(["ok": true])
            case "/api/companion": return json(["pairing": .int(pairing)])
            case "/api/devices": return json([["device_id": .string(Self.id), "name": "iPhone", "platform": "iphone", "this": true],
                                              ["device_id": "ee", "name": "iPad", "platform": "ipad", "this": false]])
            case _ where path.hasPrefix("/api/devices/"): return json(["ok": true])
            case "/api/realdebrid":
                if request.method == "PUT" { return rdStatus == 200 ? json(["user": "fer", "premium": true, "ends_with": "••••3F2A"]) : json(["detail": "Real-Debrid no la reconoce"], rdStatus) }
                if request.url.query == "full=1" { return json(["token": .string(tvKey)]) }
                return tvUser == nil ? json(["linked": false]) : json(["linked": true, "user": .string(tvUser ?? ""), "premium": true, "ends_with": "TVKE"])
            case "/api/addons":
                if request.method == "GET" {
                    var list = addons
                    if request.url.query == "full=1" { for i in list.addons.indices { if let url = fullAddons[list.addons[i].id] { list.addons[i].url = url } } }
                    return HTTPResponse(status: 200, data: try JSONEncoder().encode(list))
                }
                let body = try JSONDecoder().decode(StoredJSON.self, from: request.body ?? Data())
                guard case .object(let o) = body, case .array(let items)? = o["addons"] else { return json([:], 422) }
                for raw in items {
                    guard let got = SharedAddon(raw) else { continue }
                    if let i = addons.addons.firstIndex(where: { $0.id == got.id }) { addons.addons[i].enabled.merge(got.enabled) { _, n in n } }
                    else { addons.addons.append(got) }
                }
                addons.revision += 1
                return HTTPResponse(status: 200, data: try JSONEncoder().encode(addons))
            default: return json([:], 404)
            }
        }
    }
}

/// Lo que se escribe en los ajustes y en disco (UserDefaults en la app), para buscar ahí la llave.
private final class RecordingKV: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func data(_ key: String) -> Data? { lock.withLock { values[key] } }
    func set(_ key: String, data: Data?) { lock.withLock { values[key] = data } }
    var everything: String { lock.withLock { values.values.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") } }
}

@MainActor
final class DeviceKeysTests: XCTestCase {
    let rdKey = String(repeating: "MYRD", count: 12)

    private func rig(tv: FakeK1TV = FakeK1TV(), token: String? = "TOKEN", key: String? = nil) -> (Services, FakeK1TV, InMemorySecrets, RecordingKV) {
        let secrets = InMemorySecrets(), kv = RecordingKV()
        if let token { secrets.set(SecretKey.orbitalToken, token) }
        if let key { secrets.set(SecretKey.orbitalDeviceKey, key) }
        SettingsStore(kv).update { $0.orbitalEnabled = true; $0.orbitalAddress = "tv.example" }
        let services = Services(http: tv, secrets: secrets, kv: kv, pending: InMemoryPendingStore(), downloadTransport: FakeDownloadTransport(),
                                downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("k1-\(UUID().uuidString)"),
                                freeSpace: { 1 }, device: OrbitalRemote.Device(name: "iPhone de Fer", kind: "iphone", id: "INSTALL"))
        return (services, tv, secrets, kv)
    }

    func testPairingV2StoresTheKeyOnlyInTheKeychainAndDropsTheToken() async throws {
        let (services, tv, secrets, kv) = rig()
        let link = try XCTUnwrap(OrbitalRemote.pairingLink(URL(string: "orbital-ios://pair?v=2&u=https%3A%2F%2Ftv.example&c=\(String(repeating: "c", count: 43))")!))
        try await services.pair(link)
        XCTAssertEqual(secrets.get(SecretKey.orbitalDeviceKey), FakeK1TV.key)
        XCTAssertNil(secrets.get(SecretKey.orbitalToken), "con v2 el token del túnel se borra")
        XCTAssertTrue(services.hasOrbitalDeviceKey)
        XCTAssertEqual(services.tvPairing, 2)
        XCTAssertFalse(services.orbitalNeedsRescan)
        XCTAssertTrue(services.canShareKeysWithTV)
        let pair = try XCTUnwrap(tv.requests.first { $0.url.path == "/api/devices/pair" })
        XCTAssertEqual(JSON.parse(try XCTUnwrap(pair.body))?["name"]?.string, "iPhone de Fer")
        XCTAssertEqual(tv.requests.last?.headers["Authorization"], "Bearer \(FakeK1TV.key)")
        XCTAssertFalse(kv.everything.contains("S3cr3t"), "la llave nunca en los ajustes")
    }

    func testV1StillWorksWithAnOldTV() async throws {
        let tv = FakeK1TV(); tv.pairing = 1
        let (services, _, secrets, _) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        try await services.pair(.token(address: "tv.example", token: "NEWTOKEN"))
        XCTAssertEqual(secrets.get(SecretKey.orbitalToken), "NEWTOKEN")
        XCTAssertNil(secrets.get(SecretKey.orbitalDeviceKey), "un QR v1: la TV es de antes")
        XCTAssertFalse(services.orbitalNeedsRescan)
        XCTAssertFalse(services.canShareKeysWithTV, "sin llave no se enseñan «Pasar a la TV» ni «Usar la de la TV»")
    }

    func testTVThatHandsOutKeysAsksATokenOnlyPhoneToScan() async throws {
        let (services, _, _, _) = rig()
        try await services.connectOrbital()
        XCTAssertEqual(services.tvPairing, 2)
        XCTAssertTrue(services.orbitalNeedsRescan, "token y sin llave: «Vuelve a escanear el código de tu TV»")
        services.turnOffOrbital()
        XCTAssertFalse(services.orbitalNeedsRescan)
    }

    func testRemovedDeviceForgetsItsKeyAndAsksToScan() async throws {
        let tv = FakeK1TV(); tv.authCode = "device_removed"
        let (services, _, secrets, _) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        do { try await services.orbital.check(); XCTFail() } catch { XCTAssertEqual(error as? OrbitalRemote.Failure, .removed) }
        XCTAssertNil(secrets.get(SecretKey.orbitalDeviceKey))
        XCTAssertEqual(services.orbitalAuth.problem, .removed)
        XCTAssertTrue(services.orbitalNeedsRescan)
        tv.authCode = "device_key_required"
        let (other, _, _, _) = rig(tv: tv)
        _ = try? await other.orbital.check()
        XCTAssertEqual(other.orbitalAuth.problem, .needsKey)
        XCTAssertTrue(other.orbitalNeedsRescan)
    }

    func testDevicesListAndRemovingThisOne() async {
        let (services, tv, secrets, _) = rig(token: nil, key: FakeK1TV.key)
        let model = OrbitalDevicesModel(services)
        XCTAssertTrue(model.isAvailable)
        await model.refresh()
        XCTAssertEqual(model.devices.map(\.name), ["iPhone", "iPad"], "este primero")
        await model.remove(model.devices[1])
        XCTAssertEqual(tv.requests.last?.method, "DELETE")
        XCTAssertNotNil(secrets.get(SecretKey.orbitalDeviceKey), "quitar otro no toca la llave de este")
        await model.remove(model.devices[0])
        XCTAssertNil(secrets.get(SecretKey.orbitalDeviceKey), "quitar este borra su llave: queda sin emparejar")
        XCTAssertFalse(services.orbital.isConfigured)
        XCTAssertFalse(model.isAvailable)
        let (tokenOnly, _, _, _) = rig()
        XCTAssertFalse(OrbitalDevicesModel(tokenOnly).isAvailable, "sin llave no hay lista")
    }

    func testPassToTVAndUseTheTVs() async throws {
        let tv = FakeK1TV()
        let (services, _, secrets, kv) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        try await services.connectOrbital()
        secrets.set(AddonKeys.realDebridToken, rdKey)
        let model = DebridModel(services)
        XCTAssertTrue(model.canShareWithTV)
        await model.passToTV()
        XCTAssertEqual(model.tvShare, .passed(OrbitalTVDebrid(user: "fer", premium: true, expires: nil, tail: "••••3F2A")))
        let put = try XCTUnwrap(tv.requests.last { $0.method == "PUT" })   // después se le pregunta su cuenta (IOS-6)
        XCTAssertEqual(JSON.parse(try XCTUnwrap(put.body))?["token"]?.string, rdKey)
        tv.rdStatus = 422
        await model.passToTV()
        XCTAssertEqual(model.tvShare, .failed("Real-Debrid no la reconoce"))
        tv.rdStatus = 429
        await model.passToTV()
        XCTAssertEqual(model.tvShare, .failed(OrbitalRemote.waitLine))

        await model.useTVKey()
        XCTAssertEqual(model.tvShare, .used)
        XCTAssertEqual(secrets.get(AddonKeys.realDebridToken), tv.tvKey, "comprobada con Real-Debrid y guardada en el llavero")
        XCTAssertEqual(model.keyCheck, .confirmed)
        tv.tvKey = String(repeating: "FREE", count: 12)
        await model.useTVKey()
        XCTAssertEqual(model.tvShare, .failed("Esa cuenta de Real-Debrid no tiene Premium: no la guardé."))
        XCTAssertNotEqual(secrets.get(AddonKeys.realDebridToken), tv.tvKey, "sin Premium no se guarda")
        XCTAssertFalse(kv.everything.contains(rdKey) || kv.everything.contains("TVKEY"), "las claves nunca en los ajustes")
    }

    func testWithoutKeyOrPairing2TheTVButtonsStayHidden() async throws {
        let tv = FakeK1TV(); tv.pairing = 1
        let (services, _, _, _) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        try await services.connectOrbital()
        XCTAssertFalse(DebridModel(services).canShareWithTV, "la TV no anuncia pairing 2")
        services.settings.update { $0.orbitalEnabled = false }
        XCTAssertFalse(services.canShareKeysWithTV, "sin TV (o en Plus) nunca")
    }

    func testEnabledReadsByIDThenPlatformAndWritesOnlyItsOwn() {
        let entry = SharedAddon(id: "x", origin: "stremio", name: "X", enabled: ["tv": false, "iphone": true, FakeK1TV.id: false], order: 0)
        XCTAssertEqual(entry.isEnabled(device: FakeK1TV.id, platform: "iphone"), false, "el id gana")
        XCTAssertEqual(entry.isEnabled(device: "otro", platform: "iphone"), true, "si no, la plataforma")
        XCTAssertNil(entry.isEnabled(device: "otro", platform: "ipad"), "si no, lo de fábrica")
        XCTAssertEqual(AddonDevice(platform: "iphone", id: FakeK1TV.id).key, FakeK1TV.id)
        XCTAssertEqual(AddonDevice(platform: "ipad").key, "ipad")
    }

    func testKeyedSyncWritesOnlyItsIDAndKeyedAddonsTravel() async throws {
        let tv = FakeK1TV()
        tv.addons = SharedAddonList(revision: 3, addons: [
            SharedAddon(id: "torrentio", origin: "orbital", template: "torrentio", name: "Torrentio", enabled: ["tv": true, "iphone": true], order: 0,
                        options: AddonShare.wire(TorrentioConfig.recommended)),
            SharedAddon(id: "jack", origin: "stremio", url: "https://addon.example/realdebrid=•••/manifest.json", name: "Jackett", enabled: ["tv": true, "iphone": false], order: 1),
            SharedAddon(id: "local", origin: "stremio", url: "http://127.0.0.1/manifest.json", name: "Local", enabled: ["tv": true], order: 2, onlyOn: "tv"),
        ])
        tv.fullAddons = ["jack": "https://addon.example/realdebrid=\(rdKey)/manifest.json"]
        let (services, _, secrets, kv) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        secrets.set(AddonKeys.realDebridToken, rdKey)
        services.addonList.startWithRecommended()
        _ = services.addonList.importOnce([.init(name: "Mine", url: "https://mine.example/token=\(rdKey)/manifest.json", resources: ["stream"])])
        await services.addonSync.refresh()

        let installed = services.addonList.installed
        let jack = try XCTUnwrap(installed.first { $0.name == "Jackett" }, "el de la TV que no tenía, traído con ?full=1")
        XCTAssertFalse(jack.enabled, "con el prendido que la TV dice para este aparato (la plataforma, a falta de su id)")
        XCTAssertEqual(services.addonList.resolvedURL(jack), tv.fullAddons["jack"])
        XCTAssertNil(installed.first { $0.name == "Local" }, "lo de Archivos de la TV no se trae")
        XCTAssertEqual(tv.requests.filter { $0.url.query == "full=1" }.count, 1)

        let put = try XCTUnwrap(tv.requests.last { $0.method == "PUT" })
        let body = try XCTUnwrap(JSON.parse(try XCTUnwrap(put.body)))
        for item in body["addons"]?.array ?? [] {
            XCTAssertEqual(item["enabled"]?.object.map { Array($0.keys) }, [FakeK1TV.id], "solo enabled[<su id>], nunca «tv» ni la plataforma")
        }
        XCTAssertTrue((body["addons"]?.array ?? []).contains { $0["url"]?.string?.hasPrefix("https://mine.example/") == true }, "con llave, el que lleva clave viaja")
        XCTAssertEqual(services.addonSync.waitingForKeys, [])

        await services.addonSync.refresh()
        XCTAssertEqual(tv.requests.filter { $0.url.query == "full=1" }.count, 1, "cada uno se pide una vez (tope de 20 por hora)")
        let state = kv.everything
        XCTAssertFalse(state.contains(rdKey), "ni la clave de los complementos…")
        XCTAssertFalse(state.contains("S3cr3t"), "…ni la llave del aparato en lo que se guarda")
    }

    /// IOS-6 · «Tu TV usa la cuenta X»: se compara la cuenta (no la clave) y las tres salidas solo cuando son distintas.
    func testTheTVsRealDebridIsComparedByAccount() async throws {
        let tv = FakeK1TV()
        let (services, _, secrets, _) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        try await services.connectOrbital()
        secrets.set(AddonKeys.realDebridToken, rdKey)
        let model = DebridModel(services)
        await model.load(force: true)
        await model.compareWithTV()
        XCTAssertEqual(model.tvAccount, .same(user: "fer"), "la misma cuenta: nada que preguntar")
        tv.tvUser = "Ana"
        await model.compareWithTV()
        XCTAssertEqual(model.tvAccount, .different(tv: "Ana", mine: "fer", keptApart: false))
        model.keepAccountsApart()
        await model.compareWithTV()
        XCTAssertEqual(model.tvAccount, .different(tv: "Ana", mine: "fer", keptApart: true), "«Dejar cada una» no se vuelve a preguntar")
        tv.tvUser = nil
        await model.compareWithTV()
        XCTAssertEqual(model.tvAccount, .tvHasNone)
        XCTAssertFalse(tv.requests.contains { $0.url.path == "/api/realdebrid" && $0.url.query == "full=1" }, "para comparar no se pide la clave")
    }

    /// IOS-2 · «Conectada» solo si la TV contestó hace menos de 2 min; con un problema de «Escanear», ni «Conectada» ni «no contesta».
    func testConnectedOnlyIfTheTVJustAnswered() async throws {
        let tv = FakeK1TV()
        let (services, _, _, _) = rig(tv: tv, token: nil, key: FakeK1TV.key)
        XCTAssertEqual(services.tvLinkNow, .unknown)
        await services.checkTV()
        XCTAssertTrue(services.tvAnsweredRecently)
        if case .answered = services.tvLinkNow {} else { XCTFail("contestó: «Conectada»") }
        tv.authCode = "device_removed"
        await services.checkTV(force: true)
        XCTAssertEqual(services.tvLinkNow, .unknown, "con «Vuelve a escanear» arriba no se dice nada más")
    }

    /// IOS-11 · los pedidos llevan el nombre que escribiste al conectar, no el que da iOS.
    func testRequestsCarryTheNameYouGaveThisDevice() async throws {
        let (services, _, _, kv) = rig()
        XCTAssertEqual(services.debridRequests.requester.deviceName, "iPhone de Fer", "sin nombre propio, el de iOS")
        kv.set("orbital.device-name", data: Data("iPhone de Fernando".utf8))
        XCTAssertEqual(services.debridRequests.requester.deviceName, "iPhone de Fernando")
        XCTAssertTrue(services.debridRequests.alsoMine.contains("iPhone de Fer"), "lo de antes sigue siendo tuyo para avisar")
    }
}
