import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Corte C: la guía de la primera vez y Ajustes › Cuentas y Complementos (sin interfaz).
@MainActor
final class OnboardingModelTests: XCTestCase {
    let user = "https://api.real-debrid.com/rest/1.0/user"
    let token = String(repeating: "QX7MZ2K9PL", count: 5) + "AB"

    func testTheGuideShowsOnceAndNotWhenEverythingIsAlreadyConnected() throws {
        let rig = try ServicesRig(signedIn: false)
        XCTAssertTrue(OnboardingModel.shouldShow(rig.services))
        OnboardingModel(rig.services).finish()
        XCTAssertFalse(OnboardingModel.shouldShow(rig.services), "una sola vez; se reabre desde Ajustes")
    }

    func testRealDebridBlocksUntilTheKeyIsPremiumAndThenArmsTheRecommended() async throws {
        let rig = try ServicesRig(signedIn: false)
        let guide = OnboardingModel(rig.services)
        XCTAssertFalse(guide.canContinue(.debridKey), "sin clave no se avanza")
        guide.debrid.token = "QX7MZ2K9PLA4RT8W"
        await guide.debrid.verify()
        XCTAssertEqual(guide.debrid.check, .failed(DebridError.malformedToken.description), "incompleta: dice qué hacer")
        XCTAssertFalse(guide.canContinue(.debridKey))
        rig.http.json[user] = ["username": "fernando", "type": "free", "premium": 0]
        guide.debrid.token = token
        await guide.debrid.verify()
        guard case .free = guide.debrid.check else { return XCTFail("cuenta gratuita") }
        XCTAssertFalse(guide.debrid.hasToken, "una cuenta gratuita no se guarda")
        rig.http.json[user] = ["username": "fernando", "type": "premium", "premium": .int(143 * 86400)]
        await guide.debrid.verify()
        guard case .ok(let status) = guide.debrid.check else { return XCTFail("Premium") }
        XCTAssertEqual(status.username, "fernando")
        XCTAssertTrue(guide.canContinue(.debridKey))
        XCTAssertTrue(rig.services.debrid.hasToken)
        XCTAssertEqual(rig.services.addonList.installed.map(\.id), ["torrentio", "comet", "opensubtitles"], "los recomendados, armados con tu clave")
        XCTAssertEqual(rig.services.addonList.installed.filter(\.enabled).map(\.id), ["torrentio", "opensubtitles"], "Comet, apagado")
        XCTAssertTrue(rig.services.addonList.enabledURLs().first?.contains("realdebrid=\(token)") == true)
    }

    func testTheGuideHasNoTVStepAndTraktDoneOnlyAfterLinking() throws {
        let rig = try ServicesRig(signedIn: false, traktClientID: "CID")
        let guide = OnboardingModel(rig.services)
        XCTAssertEqual(OnboardingModel.Step.allCases.last, .done)
        XCTAssertFalse(OnboardingModel.Step.allCases.map { "\($0)" }.contains("tv"), "la app es de una sola pieza: la TV se prende en Ajustes")
        XCTAssertFalse(guide.canContinue(.trakt), "Trakt es obligatorio")
        XCTAssertEqual(guide.next(after: .trakt), .done, "sin conectar no hay «Conectado como…»")
        let linked = OnboardingModel(try ServicesRig(signedIn: false, traktLinked: true, traktClientID: "CID").services)
        XCTAssertTrue(linked.canContinue(.trakt))
        XCTAssertEqual(linked.next(after: .trakt), .traktDone)
        XCTAssertNil(linked.next(after: .done))
    }

    func testAddonsCanBeReorderedSwitchedOffAndPasted() async throws {
        let rig = try ServicesRig(signedIn: false)
        rig.http.json["https://nuevo.example/KEY/manifest.json"] = ["name": "Comet", "resources": ["stream"], "types": ["movie"]]
        let addons = AddonsModel(rig.services)
        await addons.prepare()
        XCTAssertEqual(Array(addons.items.map(\.id).prefix(3)), ["torrentio", "comet", "opensubtitles"], "los recomendados primero")
        XCTAssertEqual(addons.items.last?.origin, .imported, "y lo que tenías pegado, importado una vez")
        let pasted = await addons.add(address: "stremio://nuevo.example/KEY")
        XCTAssertTrue(pasted)
        XCTAssertEqual(addons.items.last?.name, "Comet")
        let broken = await addons.add(address: "https://roto.example")
        XCTAssertFalse(broken)
        XCTAssertNotNil(addons.error)
        await addons.move(fromOffsets: [addons.items.count - 1], toOffset: 0)
        XCTAssertEqual(addons.items.first?.name, "Comet", "se pregunta primero")
        await addons.setEnabled("opensubtitles", false)
        XCTAssertEqual(addons.items.first { $0.id == "opensubtitles" }?.enabled, false)
        XCTAssertTrue(addons.missingRecommended.isEmpty)
        await addons.remove("torrentio")
        XCTAssertEqual(addons.missingRecommended.map(\.id), ["torrentio"], "se puede volver a agregar")
    }

    func testDebridSummaryInWords() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        func status(_ days: Double, premium: Bool = true) -> DebridStatus {
            DebridStatus(service: "Real-Debrid", username: "f", isPremium: premium, expires: now.addingTimeInterval(days * 86400 + 3600), checkedAt: now)
        }
        XCTAssertEqual(DebridModel.summary(status(143), now: now).state, .active(daysLeft: 143))
        XCTAssertEqual(DebridModel.summary(status(3), now: now).state, .expiringSoon(daysLeft: 3))
        XCTAssertEqual(DebridModel.summary(status(-2), now: now).state, .expired(daysAgo: 2))
    }
}
