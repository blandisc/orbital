import XCTest
@testable import OrbitalModels
@testable import OrbitalCore
@testable import OrbitalAddons

/// CX1-B…CX8-A (Fernando, 3 nov: «CX2A, CX3A, CX4A… la Mac no habla con la TV»): la clave de Real-Debrid entre tus aparatos
/// Apple, quitarla solo aquí o de todos, la invitación del iPhone al iPad, quién quita a quién, el nombre al conectar,
/// «Darle su propia conexión», «Tu TV es nueva» y que la Mac nunca le hable a la TV. Todo de mentira: nada sale a la red.
private final class FakeHouse: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var authCode: String?
    var tvID = "TV-1"
    var upgradeSteps: [(Int, JSON)] = []
    var deleteStatus = 200
    private(set) var requests: [HTTPRequest] = []
    static let id = String(repeating: "c4", count: 16)
    static let key = "od1.\(id).\(String(repeating: "S3cr3t_-", count: 5))"

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock {
            requests.append(request)
            func json(_ v: JSON, _ s: Int = 200) -> HTTPResponse { HTTPResponse(status: s, data: v.serialized()) }
            let path = request.url.path
            if request.url.host == "api.real-debrid.com" {
                let token = request.headers["Authorization"] ?? ""
                if token.contains("REVOKED") { return json(["error": "bad_token"], 401) }
                let ana = token.contains("ANA")
                return json(["id": .int(ana ? 2 : 1), "username": .string(ana ? "ana" : "fer"), "type": "premium", "premium": 3_000_000])
            }
            if path == "/api/devices/pair" { return json(["device_id": .string(Self.id), "key": .string(Self.key), "tv_name": "Sala", "tv_id": .string(tvID)]) }
            if path.hasPrefix("/api/devices/upgrade") {
                let (status, body) = upgradeSteps.isEmpty ? (404, JSON.object([:])) : upgradeSteps.removeFirst()
                return json(body, status)
            }
            if let code = authCode { return json(["code": .string(code)], 401) }
            switch path {
            case "/api/ping": return json(["ok": true])
            case "/api/companion": return json(["pairing": 2, "tv_id": .string(tvID)])
            case "/api/devices/invite": return json(["code": "INVITECODE", "expires": .double(Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970)])
            case _ where path.hasPrefix("/api/devices/") && request.method == "DELETE": return json(["detail": "no"], deleteStatus)
            default: return json([:], 404)
            }
        }
    }
    func last(_ path: String) -> HTTPRequest? { lock.withLock { requests.last { $0.url.path == path } } }
    var count: Int { lock.withLock { requests.count } }
}

@MainActor
final class ConnectWithOrWithoutIPhoneTests: XCTestCase {
    let fer1 = String(repeating: "FERONE", count: 8), fer2 = String(repeating: "FERTWO", count: 8)
    let ana = String(repeating: "ANAKEY", count: 8), revoked = String(repeating: "REVOKED", count: 7)

    private func rig(_ platform: String, house: FakeHouse = FakeHouse(), shared: InMemorySecrets? = nil, token: String? = nil, key: String? = nil,
                     allows: Bool = true, displayName: String = "") -> (Services, InMemorySecrets, FakeHouse) {
        let secrets = InMemorySecrets(), kv = InMemoryKeyValueStore()
        if let token { secrets.set(SecretKey.orbitalToken, token) }
        if let key { secrets.set(SecretKey.orbitalDeviceKey, key) }
        SettingsStore(kv).update { $0.orbitalEnabled = true; $0.orbitalAddress = "tv.example"; $0.displayName = displayName }
        let services = Services(http: house, secrets: SharedSecrets(local: secrets, cloud: shared ?? InMemorySecrets()), kv: kv,
                                pending: InMemoryPendingStore(), downloadTransport: FakeDownloadTransport(),
                                downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("cx-\(UUID().uuidString)"), freeSpace: { 1 },
                                device: OrbitalRemote.Device(name: platform == "ipad" ? "iPad" : "iPhone", kind: platform == "iphone" ? "iphone" : "ipad", id: "I"),
                                platform: platform, capabilities: Capabilities(edition: .ultra, talksToOrbital: allows))
        return (services, secrets, house)
    }

    // MARK: CX2-A · la clave entre tus aparatos Apple

    func testPastingKeepsItHereAndLeavesASharedCopyWithWhoPutIt() async throws {
        let cloud = InMemorySecrets()
        let (iphone, local, _) = rig("iphone", shared: cloud)
        await iphone.debrid.save(token: fer1, status: try await iphone.debrid.verify(fer1))
        XCTAssertEqual(local.get(AddonKeys.realDebridToken), fer1)
        let copy = try XCTUnwrap(SharedDebridKey.decode(cloud.get(SecretKey.sharedRealDebrid)))
        XCTAssertEqual(copy.from, "iphone")
        XCTAssertFalse(copy.description.contains(fer1), "la clave nunca al imprimir")
    }

    func testAKeyFromAnotherAccountAsksAndKeepingTheLocalOneStopsAsking() async throws {
        let cloud = InMemorySecrets()
        let (ipad, local, _) = rig("ipad", shared: cloud)
        local.set(AddonKeys.realDebridToken, fer1)
        cloud.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: ana, from: "iphone").encoded)
        guard case .differs(let from, let theirs, _) = await ipad.debrid.checkShared() else { return XCTFail("debía preguntar") }
        XCTAssertEqual(from, "iphone"); XCTAssertEqual(theirs.username, "ana")
        XCTAssertEqual(local.get(AddonKeys.realDebridToken), fer1, "nada cambia solo")
        ipad.debrid.keepLocal()
        let again = await ipad.debrid.checkShared()
        XCTAssertEqual(again, .none)
    }

    /// IOS-11 · la copia dice quién la puso por su nombre («iPhone de Ana»), para no leer «Tu iPad cambió la clave» en el iPad.
    func testTheSharedCopyCarriesTheNameOfWhoPutIt() async throws {
        let cloud = InMemorySecrets()
        let (ipad, local, _) = rig("ipad", shared: cloud)
        local.set(AddonKeys.realDebridToken, fer1)
        cloud.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: ana, from: "ipad", name: "iPad de Ana").encoded)
        guard case .differs(let from, _, _) = await ipad.debrid.checkShared() else { return XCTFail("debía preguntar") }
        XCTAssertEqual(from, "iPad de Ana")
        XCTAssertNil(SharedDebridKey.decode(#"{"key":"X","from":"iphone"}"#)?.name, "una copia de antes se sigue leyendo")
    }

    func testSameAccountWithBothKeysWorkingDoesNotAskAndARevokedLocalOneTakesTheNew() async throws {
        let cloud = InMemorySecrets()
        let (mac, local, _) = rig("mac", shared: cloud, allows: false)
        local.set(AddonKeys.realDebridToken, fer1)
        cloud.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: fer2, from: "iphone").encoded)
        let same = await mac.debrid.checkShared()
        XCTAssertEqual(same, .none, "misma cuenta: se queda la que funciona")
        let (other, local2, _) = rig("ipad", shared: cloud)
        local2.set(AddonKeys.realDebridToken, revoked)
        await other.debrid.save(token: revoked, status: DebridStatus(service: "Real-Debrid", username: "fer", isPremium: true, expires: nil, checkedAt: Date(), userID: "1"), share: false)
        cloud.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: fer2, from: "iphone").encoded)
        let adopted = await other.debrid.checkShared()
        XCTAssertEqual(adopted, .adopted(from: "iphone"))
        XCTAssertEqual(local2.get(AddonKeys.realDebridToken), fer2)
    }

    func testADeviceWithoutAKeyIsOfferedTheSharedOneAndUsingItSavesItHere() async throws {
        let cloud = InMemorySecrets()
        cloud.set(SecretKey.sharedRealDebrid, SharedDebridKey(key: fer1, from: "ipad").encoded)
        let (mac, local, _) = rig("mac", shared: cloud, allows: false)
        guard case .offer(let from, let account) = await mac.debrid.checkShared() else { return XCTFail() }
        XCTAssertEqual(from, "ipad", "no se promete «tu iPhone» si vino del iPad (UX-19)"); XCTAssertEqual(account.username, "fer")
        XCTAssertNil(local.get(AddonKeys.realDebridToken), "solo se ofrece: no se toma sola")
        _ = try await mac.debrid.useShared()
        XCTAssertEqual(local.get(AddonKeys.realDebridToken), fer1)
    }

    func testAKeyFromBeforeIsSharedOnTheFirstCheck() async {
        let cloud = InMemorySecrets()
        let (iphone, local, _) = rig("iphone", shared: cloud)
        local.set(AddonKeys.realDebridToken, fer1)
        _ = await iphone.debrid.checkShared()
        XCTAssertEqual(SharedDebridKey.decode(cloud.get(SecretKey.sharedRealDebrid))?.key, fer1)
        XCTAssertEqual(local.get(AddonKeys.realDebridToken), fer1, "la de este aparato no se pierde")
    }

    // MARK: CX3-A · quitarla solo aquí o de todos

    func testRemovingOnlyHereKeepsTheSharedCopyAndEverywhereRemovesItOnDevicesThatUsedIt() async throws {
        let cloud = InMemorySecrets()
        let (iphone, iLocal, _) = rig("iphone", shared: cloud)
        await iphone.debrid.save(token: fer1, status: try await iphone.debrid.verify(fer1))
        let (ipad, pLocal, _) = rig("ipad", shared: cloud)
        pLocal.set(AddonKeys.realDebridToken, fer1)
        let (mac, mLocal, _) = rig("mac", shared: cloud, allows: false)
        mLocal.set(AddonKeys.realDebridToken, ana)

        await ipad.debrid.remove(everywhere: false)
        XCTAssertNil(pLocal.get(AddonKeys.realDebridToken))
        XCTAssertEqual(SharedDebridKey.decode(cloud.get(SecretKey.sharedRealDebrid))?.key, fer1, "solo de este iPad")

        pLocal.set(AddonKeys.realDebridToken, fer1)
        await iphone.debrid.remove(everywhere: true)
        XCTAssertNil(iLocal.get(AddonKeys.realDebridToken))
        let onIPad = await ipad.debrid.checkShared()
        XCTAssertEqual(onIPad, .removedEverywhere(from: "iphone"))
        XCTAssertNil(pLocal.get(AddonKeys.realDebridToken), "usaba esa misma clave")
        let onMac = await mac.debrid.checkShared()
        XCTAssertEqual(onMac, .none)
        XCTAssertEqual(mLocal.get(AddonKeys.realDebridToken), ana, "la suya era otra: se queda")
        XCTAssertFalse(cloud.get(SecretKey.sharedRealDebrid)?.contains(fer1) ?? true, "en iCloud solo la huella, nunca la clave")
    }

    // MARK: CX4-A · la invitación

    func testIPhoneInvitesAndTheIPadJoinsWithOneTapAndItsOwnName() async throws {
        let cloud = InMemorySecrets(), house = FakeHouse()
        let (iphone, _, _) = rig("iphone", house: house, shared: cloud, key: FakeHouse.key, displayName: "Fernando Iracheta")
        try await iphone.connectOrbital()
        XCTAssertTrue(iphone.canInviteIPad)
        let invite = try await iphone.inviteIPad()
        XCTAssertEqual(JSON.parse(try XCTUnwrap(house.last("/api/devices/invite")?.body))?["platform"]?.string, "ipad")
        XCTAssertEqual(invite.from, "iPhone de Fernando")
        XCTAssertFalse(invite.description.contains("INVITECODE"))

        let (ipad, iLocal, _) = rig("ipad", house: house, shared: cloud)
        let model = OrbitalInviteModel(ipad)
        XCTAssertTrue(model.inviteIsValid)
        model.name = "iPad de la sala"
        await model.accept()
        XCTAssertEqual(model.state, .joined)
        let pair = try XCTUnwrap(JSON.parse(try XCTUnwrap(house.last("/api/devices/pair")?.body)))
        XCTAssertEqual(pair["code"]?.string, "INVITECODE"); XCTAssertEqual(pair["platform"]?.string, "ipad"); XCTAssertEqual(pair["name"]?.string, "iPad de la sala")
        XCTAssertEqual(iLocal.get(SecretKey.orbitalDeviceKey), FakeHouse.key)
        XCTAssertNil(cloud.get(SecretKey.orbitalInvite), "sirve para un aparato")
        XCTAssertNil(ipad.pendingInvite)
    }

    func testAnExpiredInviteSaysSoAndTheMacNeverSeesOne() async {
        let cloud = InMemorySecrets()
        cloud.set(SecretKey.orbitalInvite, OrbitalInvite(code: "OLD", expires: Date().addingTimeInterval(-60), address: "https://tv.example",
                                                         tvName: "Sala", tvID: "TV-1", from: "iPhone").encoded)
        let (ipad, _, house) = rig("ipad", shared: cloud)
        let model = OrbitalInviteModel(ipad)
        XCTAssertNotNil(model.invite); XCTAssertFalse(model.inviteIsValid)
        await model.accept()
        XCTAssertEqual(model.state, .failed(Services.inviteExpiredLine))
        XCTAssertNil(house.last("/api/devices/pair"))
        let (mac, _, _) = rig("mac", shared: cloud, allows: false)
        XCTAssertNil(mac.pendingInvite)
        let (iphone, _, _) = rig("iphone", shared: cloud)
        XCTAssertNil(iphone.pendingInvite, "la tarjeta es solo del iPad")
    }

    // MARK: CX5 · quién quita a quién

    func testTheIPhoneRemovesAnyoneAndTheIPadOnlyItself() async {
        let other = OrbitalPairedDevice(id: "ee", name: "iPhone", platform: "iphone"), me = OrbitalPairedDevice(id: "c4", name: "iPad", platform: "ipad", isThis: true)
        let (iphone, _, _) = rig("iphone", key: FakeHouse.key)
        XCTAssertTrue(iphone.canRemove(other))
        let house = FakeHouse(); house.deleteStatus = 403
        let (ipad, _, _) = rig("ipad", house: house, key: FakeHouse.key)
        XCTAssertFalse(ipad.canRemove(other)); XCTAssertTrue(ipad.canRemove(me))
        let model = OrbitalDevicesModel(ipad)
        await model.remove(other)
        XCTAssertEqual(model.problem, OrbitalRemote.removeOthersLine, "el 403 de la TV, en palabras")
    }

    // MARK: CX7-A · el nombre

    func testTheSuggestedNameUsesYourNameAndFitsSixty() {
        XCTAssertEqual(rig("ipad", displayName: "Fernando Iracheta").0.suggestedDeviceName(), "iPad de Fernando")
        XCTAssertEqual(rig("iphone").0.suggestedDeviceName(traktName: "fer_ira"), "iPhone de fer_ira")
        XCTAssertEqual(rig("iphone").0.suggestedDeviceName(), "iPhone")
        let (s, _, _) = rig("iphone")
        XCTAssertEqual(s.rememberDeviceName(String(repeating: "x", count: 80)).count, 60)
        XCTAssertEqual(s.suggestedDeviceName(), String(repeating: "x", count: 60), "lo que escribiste se recuerda")
    }

    // MARK: CX8-A · «Darle su propia conexión»

    func testUpgradeWaitsForTheTVAndSavesTheKeyAfterTheYes() async throws {
        let house = FakeHouse()
        let (iphone, local, _) = rig("iphone", house: house, token: "TOKEN")
        try await iphone.connectOrbital()
        XCTAssertTrue(iphone.canUpgradeConnection)
        house.upgradeSteps = [(202, ["id": "R1"]), (202, [:]),
                              (200, ["device_id": .string(FakeHouse.id), "key": .string(FakeHouse.key), "tv_name": "Sala", "tv_id": "0123456789abcdef"])]
        let model = OrbitalUpgradeModel(iphone, pollEvery: .milliseconds(1))
        model.name = "iPhone de Fer"
        await model.start()
        XCTAssertEqual(model.stage, .done)
        XCTAssertEqual(local.get(SecretKey.orbitalDeviceKey), FakeHouse.key)
        XCTAssertNil(local.get(SecretKey.orbitalToken), "el token del túnel ya no le sirve")
        XCTAssertEqual(JSON.parse(try XCTUnwrap(house.last("/api/devices/upgrade")?.body))?["name"]?.string, "iPhone de Fer")
        XCTAssertEqual(house.last("/api/devices/upgrade")?.headers["Authorization"], "Bearer TOKEN")
        XCTAssertFalse(iphone.canUpgradeConnection)
        XCTAssertEqual(house.last("/api/devices/upgrade/R1")?.headers["Authorization"], "Bearer TOKEN", "se pregunta con el token")
        XCTAssertEqual(local.get(SecretKey.orbitalTVID), "0123456789abcdef")
    }

    func testUpgradeSaidNoOrNeverAnsweredKeepsTheTokenAndScanStaysAvailable() async throws {
        let house = FakeHouse()
        let (iphone, local, _) = rig("iphone", house: house, token: "TOKEN")
        try await iphone.connectOrbital()
        house.upgradeSteps = [(202, ["id": "R1"]), (403, ["detail": "No"])]
        let model = OrbitalUpgradeModel(iphone, pollEvery: .milliseconds(1))
        await model.start()
        XCTAssertEqual(model.stage, .denied)
        XCTAssertEqual(local.get(SecretKey.orbitalToken), "TOKEN")
        XCTAssertTrue(iphone.orbitalNeedsRescan, "«Escanear» sigue ahí")
        house.upgradeSteps = [(202, ["id": "R1"])] + Array(repeating: (202, JSON.object([:])), count: 50)
        let slow = OrbitalUpgradeModel(iphone, pollEvery: .milliseconds(1), giveUpAfter: 0)
        await slow.start()
        XCTAssertEqual(slow.stage, .timedOut)
    }

    // MARK: TEC-30 · «Tu TV es nueva»

    func testUnknownDeviceOrANewTVIDSaysTheTVIsNewKeepsTheKeyAndRepairSendsIt() async throws {
        let house = FakeHouse()
        let (iphone, local, _) = rig("iphone", house: house, key: FakeHouse.key)
        try await iphone.connectOrbital()
        XCTAssertEqual(local.get(SecretKey.orbitalTVID), "TV-1")
        house.tvID = "TV-2"
        try await iphone.connectOrbital()
        XCTAssertEqual(iphone.rescanReason, .newTV)
        XCTAssertEqual(OrbitalRemote.Failure.unknownTV.description, "Tu TV es nueva: vuelve a escanear su código")

        let (other, otherLocal, _) = rig("ipad", house: house, key: FakeHouse.key)
        house.authCode = "device_unknown"
        _ = try? await other.orbital.check()
        XCTAssertEqual(other.rescanReason, .newTV)
        XCTAssertEqual(otherLocal.get(SecretKey.orbitalDeviceKey), FakeHouse.key, "no «te quitó»: la llave se queda para reemplazar el renglón")
        house.authCode = nil
        try await other.pairOrbital(address: "tv.example", code: String(repeating: "c", count: 43))
        XCTAssertEqual(house.last("/api/devices/pair")?.headers["Authorization"], "Bearer \(FakeHouse.key)")
        XCTAssertNil(other.rescanReason)
    }

    // MARK: CX1-B · la Mac nunca habla con la TV

    func testTheMacNeverTalksToTheTVEvenWithEverythingInItsKeychain() async throws {
        let cloud = InMemorySecrets()
        cloud.set(SecretKey.orbitalInvite, OrbitalInvite(code: "C", expires: Date().addingTimeInterval(3600), address: "https://tv.example",
                                                         tvName: "Sala", tvID: "", from: "iPhone").encoded)
        let (mac, _, house) = rig("mac", shared: cloud, token: "TOKEN", key: FakeHouse.key, allows: false)
        XCTAssertFalse(mac.orbital.isConfigured)
        XCTAssertFalse(mac.hasOrbitalDeviceKey); XCTAssertFalse(mac.canShareKeysWithTV); XCTAssertFalse(mac.canUpgradeConnection)
        XCTAssertFalse(mac.canInviteIPad); XCTAssertNil(mac.pendingInvite); XCTAssertFalse(mac.orbitalNeedsRescan)
        _ = try await mac.connectOrbital(address: "tv.example", token: "T")
        _ = try await mac.pairOrbital(address: "tv.example", code: String(repeating: "c", count: 43))
        XCTAssertEqual(house.count, 0, "ni una petición a la TV")
    }
}

/// Un aparato: lo suyo en su llavero y lo compartido en «iCloud» (otro llavero de mentira que ven todos).
private final class SharedSecrets: SecretsStore, @unchecked Sendable {
    let local: InMemorySecrets, cloud: InMemorySecrets
    init(local: InMemorySecrets, cloud: InMemorySecrets) { self.local = local; self.cloud = cloud }
    private func pick(_ key: String) -> InMemorySecrets { SecretKey.policy(key) == .shared ? cloud : local }
    func get(_ key: String) -> String? { pick(key).get(key) }
    func set(_ key: String, _ value: String?) { pick(key).set(key, value) }
    func store(_ key: String, _ value: String?) -> Bool { pick(key).store(key, value) }
}
