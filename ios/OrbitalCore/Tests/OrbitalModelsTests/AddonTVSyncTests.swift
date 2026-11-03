import XCTest
@testable import OrbitalModels
@testable import OrbitalCore
@testable import OrbitalAddons

/// Una TV de mentira con las reglas del corte S6: revisión que solo sube, 409 con la actual, 422 con clave.
private final class FakeTV: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var list: SharedAddonList
    var puts: [StoredJSON] = []
    var gets = 0
    var down = false
    /// Antes del siguiente PUT, alguien cambia algo en la TV (para provocar un 409).
    var changeBeforePut: (@Sendable (inout SharedAddonList) -> Void)?

    init(_ list: SharedAddonList) { self.list = list }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            if down { throw NetworkError("sin conexión") }
            if request.method == "GET" { gets += 1; return HTTPResponse(status: 200, data: try JSONEncoder().encode(list)) }
            let body = try JSONDecoder().decode(StoredJSON.self, from: request.body ?? Data())
            puts.append(body)
            if let change = changeBeforePut { change(&list); list.revision += 1; changeBeforePut = nil }
            guard case .object(let o) = body, case .number(let base)? = o["base_revision"], case .array(let items)? = o["addons"] else {
                return HTTPResponse(status: 422, data: Data())
            }
            if Int(base) != list.revision { return HTTPResponse(status: 409, data: try JSONEncoder().encode(list)) }
            for raw in items {
                guard let got = SharedAddon(raw) else { continue }
                if got.url?.contains("realdebrid=") == true {
                    return HTTPResponse(status: 422, data: Data(#"{"detail": "Espera las llaves por aparato: esa dirección lleva una clave"}"#.utf8))
                }
                if let i = list.addons.firstIndex(where: { $0.id == got.id }) {
                    list.addons[i].enabled.merge(got.enabled.filter { $0.key != "tv" }) { _, new in new }
                    list.addons[i].order = got.order
                    if let options = got.options { list.addons[i].options = options }
                } else { list.addons.append(got) }
            }
            list.addons.sort { $0.order < $1.order }
            list.revision += 1
            return HTTPResponse(status: 200, data: try JSONEncoder().encode(list))
        }
    }
}

@MainActor
final class AddonTVSyncTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)

    private func rig(on: Bool = true) -> (AddonTVSync, AddonList, FakeTV, InMemoryAddonVault) {
        let vault = InMemoryAddonVault()
        vault.setSecret(AddonKeys.realDebridToken, token)
        let list = AddonList(vault: vault)
        list.startWithRecommended()
        let tv = FakeTV(SharedAddonList(revision: 7, changedBy: "tv", addons: [
            SharedAddon(id: "torrentio", origin: "orbital", template: "torrentio", name: "Torrentio", enabled: ["tv": true], order: 0,
                        options: AddonShare.wire(TorrentioConfig.recommended)),
            SharedAddon(id: "opensubtitles", origin: "orbital", template: "opensubtitles", name: "OpenSubtitles", enabled: ["tv": true], order: 1),
        ]))
        let remote = AddonListRemote(remote: { OrbitalRemote(http: tv, address: "https://tv.example.com", token: "t") })
        let sync = AddonTVSync(list: list, vault: vault, remote: remote, available: { on }, device: "iphone", deviceName: { "iPhone de Fernando" })
        return (sync, list, tv, vault)
    }

    func testAChangeHereGoesToTheTVWithItsBaseRevision() async {
        let (sync, list, tv, _) = rig()
        await sync.refresh()
        XCTAssertEqual(tv.puts.count, 1, "la primera vez, la TV recibe el prendido de este iPhone")
        var options = TorrentioConfig.recommended
        options.limit = 3
        list.setOptions("torrentio", options)
        await sync.refresh()
        XCTAssertEqual(tv.puts.count, 2)
        guard case .object(let o)? = tv.puts.last else { return XCTFail() }
        XCTAssertEqual(o["base_revision"], .number(8))
        XCTAssertEqual(tv.list.addons.first { $0.id == "torrentio" }?.options?["limit"], .number(3))
        XCTAssertEqual(tv.list.addons.first?.enabled["tv"], true, "el prendido de la TV no se toca")
        await sync.refresh()
        XCTAssertEqual(tv.puts.count, 2, "si ya son iguales, no se manda nada")
        if case .same = sync.status {} else { XCTFail("\(sync.status)") }
    }

    func testOn409ItMergesOptionByOptionAndRetriesOnce() async {
        let (sync, list, tv, _) = rig()
        await sync.refresh()
        var mine = TorrentioConfig.recommended
        mine.limit = 4
        list.setOptions("torrentio", mine)
        tv.changeBeforePut = { tv in   // mientras, en la TV cambiaron el orden de Torrentio
            if let i = tv.addons.firstIndex(where: { $0.id == "torrentio" }) { tv.addons[i].options?["sort"] = .string("seeders") }
        }
        await sync.refresh()
        let options = AddonShare.options(tv.list.addons.first { $0.id == "torrentio" }?.options ?? [:])
        XCTAssertEqual(options.limit, 4, "lo tuyo llegó")
        XCTAssertEqual(options.sort, "seeders", "lo de la TV se quedó")
        XCTAssertEqual(list.torrentio?.options?.sort, "seeders", "y llegó aquí")
        XCTAssertNil(sync.clash, "opciones distintas no chocan")
        if case .same = sync.status {} else { XCTFail("\(sync.status)") }
    }

    func testTVUnreachableKeepsItPendingAndOffDoesNothing() async {
        let (sync, _, tv, vault) = rig()
        tv.down = true
        await sync.refresh()
        XCTAssertEqual(sync.status, .unreachable)
        tv.down = false
        await sync.refresh()
        if case .same = sync.status {} else { XCTFail("\(sync.status)") }
        let saved = try? JSONDecoder().decode(AddonTVSync.State.self, from: vault.data(AddonTVSync.stateKey) ?? Data())
        XCTAssertNotNil(saved?.base)
        XCTAssertTrue(saved?.base?.addons.allSatisfy { $0.url == nil } ?? false, "nada de la TV se guarda como dirección")

        let (off, _, tvOff, _) = rig(on: false)
        await off.refresh()
        XCTAssertEqual(off.status, .off, "en Plus o sin TV no aparece")
        XCTAssertEqual(tvOff.gets, 0)
    }

    func testAKeyedAddonStaysHereCalmly() async {
        let (sync, list, tv, _) = rig()
        list.importOnce([.init(name: "ThePirateBay+", url: "https://tpb.strem.fun/realdebrid=\(token)/manifest.json", resources: ["stream"])])
        await sync.refresh()
        XCTAssertEqual(sync.waitingForKeys, ["ThePirateBay+"])
        XCTAssertFalse(tv.list.addons.contains { $0.name == "ThePirateBay+" })
        XCTAssertTrue(AddonTVSync.waitsForKeys("Espera las llaves por aparato: esa dirección lleva una clave"))
        XCTAssertTrue(AddonTVSync.waitsForKeys("Vuelve a escanear el código de tu TV: esa dirección lleva una clave"), "lo que dice la TV de hoy")
    }
}
