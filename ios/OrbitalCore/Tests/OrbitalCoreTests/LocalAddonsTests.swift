import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// Corte B: con la lista del teléfono armada, los complementos salen de ahí (en tu orden, sin los apagados).
final class LocalAddonsTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)

    func testWithTheLocalListOrderAndOffAreRespected() async throws {
        let http = FakeHTTP()
        http.json["https://propio.example/manifest.json"] = ["name": "Propio", "resources": ["stream"], "types": ["movie"]]
        let vault = InMemoryAddonVault()
        vault.setSecret(AddonKeys.realDebridToken, token)
        let list = AddonList(vault: vault)
        let registry = AddonRegistry(http: http, own: { ["https://propio.example"] }, local: list)
        let before = try await registry.addons()
        XCTAssertEqual(before.map(\.name), ["Propio"], "sin lista del teléfono: los que pegaste en Ajustes")

        let torrentio = try XCTUnwrap(AddonCatalog.torrentio.manifestURL(token: token))
        // `URL` escribe la «|» de Torrentio como %7C (Torrentio entiende las dos).
        http.json[try XCTUnwrap(URL(string: torrentio)).absoluteString] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"]]
        http.json["https://opensubtitles-v3.strem.io/manifest.json"] = ["name": "OpenSubtitles v3", "resources": ["subtitles"], "types": ["movie"]]
        http.json["https://listas.example/manifest.json"] = ["name": "Listas", "resources": ["catalog"], "types": ["movie"]]
        list.startWithRecommended([AddonCatalog.torrentio, AddonCatalog.openSubtitles])
        let listas = list.add(url: "https://listas.example/manifest.json", name: "Listas", resources: ["catalog"])
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        list.setEnabled(AddonCatalog.openSubtitles.id, false)
        await registry.invalidate()
        let calls = http.calls.count
        let after = try await registry.addons()
        XCTAssertEqual(after.map(\.name), ["Listas", "Torrentio"], "en tu orden y sin el apagado")
        XCTAssertFalse(http.calls.dropFirst(calls).contains { $0.contains("propio.example") }, "lo pegado en Ajustes ya no cuenta")
        XCTAssertFalse(after.isEmpty)
        list.remove(listas)
        let reordered = try await registry.addons()
        XCTAssertEqual(reordered.map(\.name), ["Torrentio"], "un cambio en la lista se ve sin esperar a la caché")
    }

    func testImportBringsYourPastedOnesOnce() {
        let found = AddonImport.addons(own: ["https://propio.example", "https://torrentio.strem.fun/realdebrid=OLD", "https://propio.example"])
        XCTAssertEqual(found.map(\.url), ["https://propio.example/manifest.json", "https://torrentio.strem.fun/realdebrid=OLD/manifest.json"])
    }

    func testRealDebridGoesThroughTheAppsNetwork() async throws {
        let http = FakeHTTP()
        http.json["https://api.real-debrid.com/rest/1.0/user"] = ["username": "fernando", "type": "premium", "premium": 864_000]
        let status = try await RealDebrid(http: http).status(token: token)
        XCTAssertEqual(status.username, "fernando")
        XCTAssertTrue(status.isPremium)
    }
}
