import XCTest
@testable import OrbitalCore

final class AddonsTests: XCTestCase {
    func testManifestURL() {
        XCTAssertEqual(Addons.manifestURL("stremio://torrentio.strem.fun/realdebrid=KEY"), "https://torrentio.strem.fun/realdebrid=KEY/manifest.json")
        XCTAssertEqual(Addons.manifestURL(" https://x.example/a/manifest.json "), "https://x.example/a/manifest.json")
        XCTAssertEqual(Addons.manifestURL("https://x.example/a//"), "https://x.example/a/manifest.json")
        XCTAssertNil(Addons.manifestURL("file:///etc/passwd"))
        XCTAssertNil(Addons.manifestURL("javascript:alert(1)"))
    }

    func testCleanURLsDropsDuplicatesAndJunk() {
        XCTAssertEqual(Addons.cleanURLs(["https://a.example", "https://a.example/manifest.json", "ftp://x", "https://b.example/"]),
                       ["https://a.example/manifest.json", "https://b.example/manifest.json"])
    }

    func testRedactKeepsOnlyServer() {
        XCTAssertEqual(redact("https://torrentio.strem.fun/realdebrid=SECRET/manifest.json"), "torrentio.strem.fun")
    }

    func testParseManifestRules() throws {
        let manifest: JSON = ["name": "Mixto", "types": ["movie", "series"], "idPrefixes": ["tt"],
                              "resources": ["catalog", ["name": "meta", "types": ["series"], "idPrefixes": ["kitsu:"]], "stream", "raro", 3],
                              "catalogs": [["id": "x"], "no"]]
        let addon = try XCTUnwrap(Addons.parseManifest(manifest, url: "https://m.example/manifest.json"))
        XCTAssertEqual(addon.name, "Mixto")
        XCTAssertEqual(Set(addon.rules.keys), ["catalog", "meta", "stream"])
        XCTAssertTrue(addon.handles("stream", kind: "movie", itemID: "tt123"))
        XCTAssertFalse(addon.handles("stream", kind: "movie", itemID: "kitsu:1"))  // un id de kitsu no se le pide a quien solo sabe de IMDb
        XCTAssertTrue(addon.handles("meta", kind: "series", itemID: "kitsu:1"))
        XCTAssertFalse(addon.handles("meta", kind: "movie", itemID: "kitsu:1"))
        XCTAssertFalse(addon.handles("subtitles", kind: "movie"))
        XCTAssertEqual(addon.base, "https://m.example")
        XCTAssertEqual(addon.catalogs.count, 1)
    }

    func testParseManifestRejectsUseless() {
        XCTAssertNil(Addons.parseManifest(["name": "x", "resources": ["raro"]], url: "https://x/manifest.json"))
        XCTAssertNil(Addons.parseManifest(["name": "x", "resources": ["stream"]], url: "file:///x"))
        XCTAssertNil(Addons.parseManifest("texto", url: "https://x/manifest.json"))
    }

    func testRegistryMergesAccountAndOwnAndCaches() async throws {
        let http = FakeHTTP()
        http.json["https://api.strem.io/api/addonCollectionGet"] = ["result": ["addons": [
            ["transportUrl": "https://cuenta.example/manifest.json", "manifest": ["name": "Cuenta", "resources": ["stream"], "types": ["movie"]]],
            ["transportUrl": "https://roto.example/manifest.json", "manifest": "raro"]]]]
        http.json["https://propio.example/manifest.json"] = ["name": "Propio", "resources": ["subtitles"], "types": ["movie"]]
        let registry = AddonRegistry(http: http, account: StremioAPI(http: http), auth: { "KEY" }, own: { ["https://propio.example"] })
        let first = try await registry.addons()
        XCTAssertEqual(first.map(\.name), ["Cuenta", "Propio"])
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("addonCollectionGet") }.count, 1, "la lista se recuerda")
        let serving = try await registry.serving("stream", kind: "movie", itemID: "tt1")
        XCTAssertEqual(serving.map(\.name), ["Cuenta"])
    }

    func testRegistryShortCacheWhenSomethingFails() async throws {
        let http = FakeHTTP()
        http.json["https://ok.example/manifest.json"] = ["name": "Ok", "resources": ["stream"]]
        let clock = Clock()
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://ok.example", "https://caido.example"] }, clock: { clock.now })
        _ = try await registry.addons()
        clock.now.addTimeInterval(10)
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.contains("ok.example") }.count, 1)
        clock.now.addTimeInterval(10)  // pasaron más de 15 s: se vuelve a preguntar
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.contains("ok.example") }.count, 2)
    }

    func testRegistryThrowsAccountErrorWhenNothingWorks() async {
        let http = FakeHTTP()
        http.fail = true
        let registry = AddonRegistry(http: http, account: StremioAPI(http: http), auth: { "KEY" })
        do { _ = try await registry.addons(); XCTFail("debía fallar") } catch { XCTAssertTrue("\(error)".contains("Stremio")) }
    }
}
