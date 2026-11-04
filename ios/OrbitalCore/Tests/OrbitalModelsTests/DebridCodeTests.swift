import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// RC1 · conectar Real-Debrid con un código (como Trakt) y la llave que se renueva sola.
@MainActor
final class DebridCodeTests: XCTestCase {
    let oauth = "https://api.real-debrid.com/oauth/v2/"
    let user = "https://api.real-debrid.com/rest/1.0/user"
    let first = String(repeating: "A1B2C3D4E5", count: 5) + "FG"
    let second = String(repeating: "Z9Y8X7W6V5", count: 5) + "HI"

    func rig() throws -> ServicesRig {
        let rig = try ServicesRig(signedIn: false)
        rig.http.json[oauth + "device/code?client_id=X245A4XAIBGVM&new_credentials=yes"] =
            ["device_code": "DEVICE", "user_code": "4IHFKYGV", "interval": 0, "expires_in": 600, "verification_url": "https://real-debrid.com/device"]
        rig.http.json[oauth + "device/credentials?client_id=X245A4XAIBGVM&code=DEVICE"] = ["client_id": "MINE", "client_secret": "SECRET"]
        rig.http.json[oauth + "token"] = ["access_token": .string(first), "refresh_token": "REFRESH", "expires_in": 3600, "token_type": "Bearer"]
        rig.http.json[user] = ["username": "fernando", "type": "premium", "premium": .int(143 * 86400), "id": 7]
        return rig
    }

    func wait(_ model: DebridModel, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where model.codeFlow != .idle || model.check == .idle { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testTheCodeConnectsWithoutPastingAndArmsTheRecommended() async throws {
        let rig = try rig()
        let model = DebridModel(rig.services)
        model.connectWithCode()
        await wait(model)
        guard case .ok(let status) = model.check else { return XCTFail("conectada: \(model.check) \(model.codeFlow)") }
        XCTAssertEqual(status.username, "fernando")
        XCTAssertTrue(model.connectedByCode)
        XCTAssertEqual(rig.services.addonList.debridToken, first, "Torrentio se arma con la llave nueva")
        XCTAssertTrue(rig.services.addonList.enabledURLs().first?.contains("realdebrid=\(first)") == true)
        let form = String(data: rig.http.bodies(oauth + "token").first ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(form.contains("code=DEVICE") && form.contains("client_id=MINE"), "el código se cambia por la llave con sus credenciales")
    }

    func testTheKeyRenewsBeforeItExpiresAndEverythingUsesTheNewOne() async throws {
        let rig = try rig()
        let model = DebridModel(rig.services)
        model.connectWithCode()
        await wait(model)
        await rig.services.freshenDebrid()
        XCTAssertEqual(rig.services.addonList.debridToken, first, "con tiempo de sobra no se renueva")
        rig.http.json[oauth + "token"] = ["access_token": .string(second), "refresh_token": "REFRESH2", "expires_in": 3600]
        rig.clock.advance(3600 - 60)
        await rig.services.freshenDebrid()
        XCTAssertEqual(rig.services.addonList.debridToken, second, "a un minuto de vencer, la nueva")
        XCTAssertTrue(rig.services.addonList.enabledURLs().first?.contains("realdebrid=\(second)") == true, "Torrentio, al día")
        let form = String(data: rig.http.bodies(oauth + "token").last ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(form.contains("code=REFRESH"), "se renueva con la llave de renovar")
    }

    func testPastingAKeyForgetsTheCodeConnection() async throws {
        let rig = try rig()
        let model = DebridModel(rig.services)
        model.connectWithCode()
        await wait(model)
        XCTAssertTrue(model.connectedByCode)
        model.token = second
        await model.verify()
        XCTAssertFalse(model.connectedByCode, "una pegada no se renueva")
        rig.clock.advance(7200)
        await rig.services.freshenDebrid()
        XCTAssertEqual(rig.services.addonList.debridToken, second)
    }

    func testAnExpiredCodeSaysSo() async throws {
        let rig = try rig()
        rig.http.json[oauth + "device/code?client_id=X245A4XAIBGVM&new_credentials=yes"] =
            ["device_code": "DEVICE", "user_code": "4IHFKYGV", "interval": 0, "expires_in": 0, "verification_url": "https://real-debrid.com/device"]
        let model = DebridModel(rig.services)
        model.connectWithCode()
        for _ in 0..<200 { if case .failed = model.codeFlow { break }; try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(model.codeFlow, .failed("El código venció. Pide otro."))
        XCTAssertFalse(rig.services.debrid.hasToken)
    }
}
