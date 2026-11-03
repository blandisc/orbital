import XCTest
@testable import OrbitalAddons

/// M6: lo traído de Stremio que solo da torrents se reconoce y viene apagado en el iPhone (una vez: si lo prendes, se respeta).
final class AddonTorrentsTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)

    func testItIsRecognizedByItsAddressOrByWhatItAnswered() {
        XCTAssertTrue(AddonTorrents.byAddress("https://torrentio.strem.fun/language=latino/manifest.json"))
        XCTAssertTrue(AddonTorrents.byAddress("https://torrentio.strem.fun/debridoptions=nodownloadlinks/manifest.json"))
        XCTAssertFalse(AddonTorrents.byAddress("https://torrentio.strem.fun/realdebrid=\(token)/manifest.json"), "con Real-Debrid da enlaces")
        XCTAssertFalse(AddonTorrents.byAddress("https://anime.strem.fun/manifest.json"), "uno cualquiera se sabe por lo que contesta")
        XCTAssertTrue(AddonTorrents.onlyTorrents([(nil, "abc"), ("magnet:?xt=urn", "def")]))
        XCTAssertFalse(AddonTorrents.onlyTorrents([(nil, "abc"), ("https://rd.example/x.mkv", nil)]), "uno que abre basta")
        XCTAssertFalse(AddonTorrents.onlyTorrents([]), "sin versiones no se sabe")
        let health = AddonHealth()
        let url = "https://tpb.example.com/manifest.json"
        health.answered(url, onlyTorrents: true)
        health.ok(url, seconds: 0.5)
        XCTAssertTrue(health.onlyTorrents(url), "contestar a tiempo no lo borra")
        health.answered(url, onlyTorrents: false)
        XCTAssertFalse(health.onlyTorrents(url))
    }

    func testItComesOffOnTheIPhoneOnceAndYourChoiceStays() {
        let vault = InMemoryAddonVault()
        let list = AddonList(vault: vault)
        list.importOnce([.init(name: "Torrentio sin RD", url: "https://torrentio.strem.fun/language=latino/manifest.json", resources: ["stream"]),
                         .init(name: "Otro", url: "https://otro.strem.fun/manifest.json", resources: ["stream"])])
        XCTAssertEqual(list.installed.first { $0.name == "Torrentio sin RD" }?.enabled, false, "viene apagado")
        XCTAssertEqual(list.installed.first { $0.name == "Otro" }?.enabled, true)
        let id = list.installed.first { $0.name == "Torrentio sin RD" }!.id
        list.setEnabled(id, true)
        XCTAssertTrue(list.turnOffTorrentsOnly(AddonTorrents.byAddress).isEmpty, "si lo prendes, se respeta")
        XCTAssertEqual(list.installed.first { $0.id == id }?.enabled, true)
    }
}
