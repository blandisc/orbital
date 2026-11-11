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

    func testRegistryReadsYourAddonsAndCaches() async throws {
        let http = FakeHTTP()
        http.json["https://propio.example/manifest.json"] = ["name": "Propio", "resources": ["stream"], "types": ["movie"]]
        http.json["https://subs.example/manifest.json"] = ["name": "Subs", "resources": ["subtitles"], "types": ["movie"]]
        let registry = AddonRegistry(http: http, own: { ["https://propio.example", "https://subs.example"] })
        let first = try await registry.addons()
        XCTAssertEqual(first.map(\.name), ["Propio", "Subs"])
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("manifest.json") }.count, 2, "la lista se recuerda")
        let serving = try await registry.serving("stream", kind: "movie", itemID: "tt1")
        XCTAssertEqual(serving.map(\.name), ["Propio"])
    }

    func testRegistrySharesInFlightAndOpensFromDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let http = FakeHTTP(), url = "https://propio.example/manifest.json"
        http.json[url] = ["name": "Propio", "resources": ["stream"], "types": ["movie"]]
        http.delays[url] = 50
        let registry = AddonRegistry(http: http, own: { ["https://propio.example"] }, disk: dir)
        async let a = registry.addons()
        async let b = registry.addons()
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.map(\.name), ["Propio"]); XCTAssertEqual(second.map(\.name), ["Propio"])
        XCTAssertEqual(http.calls.filter { $0 == url }.count, 1, "a la vez: una sola petición")

        // Otra apertura: la lista guardada sale sin esperar a la red y se revalida aparte.
        http.delays[url] = 2000
        let reopened = AddonRegistry(http: http, own: { ["https://propio.example"] }, disk: dir)
        let saved = try await reopened.addons()
        XCTAssertEqual(saved.map(\.name), ["Propio"])
        for _ in 0..<200 where http.calls.filter({ $0 == url }).count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(http.calls.filter { $0 == url }.count, 2, "revalidando en segundo plano")
    }

    func testTheSavedListDoesNotKeepYourKeyOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("addons-0123abcd.json")
        try Data(#"[{"transportUrl":"https://torrentio.strem.fun/realdebrid=VIEJACLAVE1234/manifest.json"}]"#.utf8).write(to: old)
        let key = String(repeating: "K9", count: 26)
        let keyed = "https://torrentio.strem.fun/realdebrid=\(key)/manifest.json", plain = "https://subs.example/manifest.json"
        let http = FakeHTTP()
        http.json[keyed] = ["name": "Torrentio", "resources": ["stream"], "description": .string("Con realdebrid=\(key)")]
        http.json[plain] = ["name": "Subs", "resources": ["subtitles"]]
        let registry = AddonRegistry(http: http, own: { [keyed, plain] }, disk: dir)
        _ = try await registry.addons()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "el archivo de antes (con la clave) se borra")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains(key))
        let text = try String(contentsOf: dir.appendingPathComponent(files[0]), encoding: .utf8)
        XCTAssertFalse(text.contains(key), "ni la URL ni el manifiesto llevan la clave")
        XCTAssertTrue(text.contains(plain), "una URL sin clave se guarda tal cual")
        // Al abrir otra vez: la URL con clave se recupera de la lista, no del archivo.
        http.fail = true
        let reopened = AddonRegistry(http: http, own: { [keyed, plain] }, disk: dir)
        let saved = try await reopened.addons()
        XCTAssertEqual(saved.map(\.url), [keyed, plain])
    }

    func testRegistryShortCacheWhenSomethingFails() async throws {
        let http = FakeHTTP()
        http.json["https://ok.example/manifest.json"] = ["name": "Ok", "resources": ["stream"]]
        let clock = Clock()
        let registry = AddonRegistry(http: http, own: { ["https://ok.example", "https://caido.example"] }, clock: { clock.now })
        _ = try await registry.addons()
        clock.now.addTimeInterval(10)
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.contains("ok.example") }.count, 1)
        clock.now.addTimeInterval(10)  // pasaron más de 15 s: se vuelve a preguntar
        _ = try await registry.addons()
        XCTAssertEqual(http.calls.filter { $0.contains("ok.example") }.count, 2)
    }

    func testRegistryThrowsWhenNothingAnswers() async {
        let http = FakeHTTP()
        http.fail = true
        let registry = AddonRegistry(http: http, own: { ["https://propio.example"] })
        do { _ = try await registry.addons(); XCTFail("debía fallar") } catch { XCTAssertTrue(error is NetworkError, "«no responden», no «no tienes complementos»") }
    }
}
