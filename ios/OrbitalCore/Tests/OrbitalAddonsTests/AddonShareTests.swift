import XCTest
@testable import OrbitalAddons

/// S1, S3, S6 (design/addons-contract.json): lo que viaja a tu TV, cómo se junta lo que cambió allá y que nada con clave cruce.
final class AddonShareTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)

    private func list() -> AddonList {
        let vault = InMemoryAddonVault()
        vault.setSecret(AddonKeys.realDebridToken, token)
        let list = AddonList(vault: vault)
        list.startWithRecommended()
        return list
    }

    private func tv(revision: Int = 3, addons: [SharedAddon], removed: [String] = []) -> SharedAddonList {
        SharedAddonList(revision: revision, changedAt: Date(timeIntervalSince1970: 1_762_000_000), changedBy: "tv", addons: addons, removed: removed)
    }

    private func object(_ json: StoredJSON) -> [String: StoredJSON] { if case .object(let o) = json { o } else { [:] } }
    private func entries(_ plan: AddonTVPlan) -> [[String: StoredJSON]] {
        if case .array(let a)? = object(plan.body)["addons"] { a.map(object) } else { [] }
    }

    func testTorrentioOptionsGoAndComeBackWithVerbatim() {
        let options = AddonOptions(excludedQualities: ["cam"], languages: ["latino"], sort: "seeders", limit: 5, sizeFilter: "10GB,2GB",
                                   providers: ["yts", "eztv"], debridOptions: ["nodownloadlinks"], verbatim: ["futureoption=on"])
        let wire = AddonShare.wire(options)
        XCTAssertEqual(wire["verbatim"], .array([.string("futureoption=on")]))
        XCTAssertEqual(wire["sizefilter"], .string("10GB,2GB"))
        XCTAssertEqual(AddonShare.options(wire), options, "ida y vuelta, con lo que la app no conoce")
        XCTAssertEqual(AddonShare.options(["language": .array([])]).languages, [], "lo que falta es vacío, no lo de Orbital")
        XCTAssertEqual(AddonShare.canonical(AddonOptions(sort: "quality", providers: TorrentioConfig.providers)),
                       AddonShare.canonical(AddonOptions()), "decirlo igual que no decirlo no es un cambio")
    }

    func testOnlyMyOwnEnabledKeyTravelsAndTheTVsIsNeverSent() {
        let list = list()
        list.setEnabled("opensubtitles", false)
        let theirs = tv(addons: [SharedAddon(id: "torrentio", origin: "orbital", template: "torrentio", name: "Torrentio", enabled: ["tv": false], order: 0,
                                             options: AddonShare.wire(TorrentioConfig.recommended)),
                                 SharedAddon(id: "opensubtitles", origin: "orbital", template: "opensubtitles", name: "OpenSubtitles", enabled: ["tv": true], order: 1)])
        let plan = list.plan(for: theirs, links: [:], device: "iphone", changedBy: "iPhone de Fernando", now: Date())
        XCTAssertTrue(plan.needsPut)
        for entry in entries(plan) {
            guard case .object(let enabled)? = entry["enabled"] else { return XCTFail("sin enabled") }
            XCTAssertEqual(Array(enabled.keys), ["iphone"], "solo el prendido de este aparato")
        }
        XCTAssertEqual(entries(plan).last?["enabled"], .object(["iphone": .bool(false)]))
        XCTAssertNil(entries(plan).map { $0["id"] }.firstIndex(of: .string("comet")), "Comet: la TV no lo tiene, se queda aquí")
        XCTAssertEqual(object(plan.body)["base_revision"], .number(3))
    }

    func testAKeyNeverTravelsAndMaskedAddressesAreOnlyForRecognizing() throws {
        let list = list()
        let keyed = "https://thepiratebay-plus.strem.fun/realdebrid=\(token)/manifest.json"
        let plain = "https://anime.strem.fun/manifest.json"
        list.importOnce([.init(name: "ThePirateBay+", url: keyed, resources: ["stream"]), .init(name: "Anime", url: plain, resources: ["stream"]),
                         .init(name: "Jackett", url: "https://jackett.example.com/realdebrid=\(String(token.reversed()))/manifest.json", resources: ["stream"])])
        // La TV ya tiene ThePirateBay+ (tapado) y algo suyo que este iPhone no tiene.
        let theirs = tv(addons: [SharedAddon(id: "uuid-tpb", origin: "stremio", url: AddonShare.tvMasked(keyed), name: "ThePirateBay+", order: 0),
                                 SharedAddon(id: "uuid-local", origin: "stremio", url: "http://127.0.0.1:11470/local-addon/manifest.json", name: "Local Files", order: 1, onlyOn: "tv")])
        let plan = list.plan(for: theirs, links: [:], device: "iphone", changedBy: "iPhone", now: Date(), newID: { "uuid-nuevo" })
        let body = String(data: try JSONEncoder().encode(plan.body), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains(token) || body.contains(String(token.reversed())), "ninguna clave cruza")
        XCTAssertFalse(body.contains(AddonRedaction.mask), "una dirección tapada nunca se manda")
        let tpb = try XCTUnwrap(entries(plan).first { $0["id"] == .string("uuid-tpb") }, "se reconoce por su dirección tapada")
        XCTAssertNil(tpb["url"], "va por su id, sin dirección")
        XCTAssertEqual(entries(plan).first { $0["id"] == .string("uuid-nuevo") }?["url"], .string(plain), "uno nuevo sin clave va con su dirección")
        XCTAssertEqual(plan.waitingForKeys, ["Jackett"], "con clave se queda aquí: espera las llaves por aparato")
        XCTAssertEqual(plan.tvOnly.map(\.name), ["Local Files"])
        XCTAssertTrue(plan.tvOnly[0].isTVFiles)
        // Lo que se guarda de la TV no lleva direcciones.
        XCTAssertTrue(theirs.withoutURLs.addons.allSatisfy { $0.url == nil })
        let stored = String(data: try JSONEncoder().encode(theirs.withoutURLs), encoding: .utf8) ?? ""
        XCTAssertFalse(stored.contains(AddonRedaction.mask))
        XCTAssertFalse(AddonShare.canTravel("https://comet.elfhosted.com/eyJkZWJyaWRTZXJ2aWNlcyI6W3siYXBpS2V5IjoiQUJDREVGR0gifV19/manifest.json"))
    }

    func testOptionByOptionTheOneChangedOnlyOnTheTVIsTakenAndAClashGoesToTheTV() {
        let list = list()
        var mine = TorrentioConfig.recommended
        mine.limit = 5          // solo aquí
        mine.sort = "size"      // los dos, distinto
        list.setOptions("torrentio", mine)
        var base = TorrentioConfig.recommended
        base.sort = "seeders"
        var theirs = base
        theirs.sort = "qualitysize"
        theirs.languages = ["latino"]   // solo en la TV
        func torrentio(_ o: AddonOptions) -> SharedAddon {
            SharedAddon(id: "torrentio", origin: "orbital", template: "torrentio", name: "Torrentio", order: 0, options: AddonShare.wire(o))
        }
        let merge = list.absorb(tv(revision: 4, addons: [torrentio(theirs)]), base: tv(revision: 2, addons: [torrentio(base)]), links: ["torrentio": "torrentio"])
        let now = list.torrentio?.options
        XCTAssertEqual(now?.limit, 5, "lo tuyo se queda")
        XCTAssertEqual(now?.languages, ["latino"], "lo de la TV se toma")
        XCTAssertEqual(now?.sort, "qualitysize", "si chocan, gana la TV")
        XCTAssertEqual(merge.conflicts, ["sort"])
        XCTAssertEqual(merge.mine?.sort, "size", "para «Usar la de este iPhone»")
    }

    func testWhatYouRemovedOnTheTVGoesHereAndOrderChangedOnlyThereIsTaken() {
        let list = list()
        list.importOnce([.init(name: "A", url: "https://a.strem.fun/manifest.json", resources: ["stream"]),
                         .init(name: "B", url: "https://b.strem.fun/manifest.json", resources: ["stream"])])
        let links = Dictionary(uniqueKeysWithValues: list.installed.map { ($0.id, $0.isBuiltIn ? $0.id : "s-\($0.name)") })
        let shared = list.installed.enumerated().map { i, a in SharedAddon(id: links[a.id]!, origin: a.isBuiltIn ? "orbital" : "stremio", name: a.name, order: i) }
        let base = tv(revision: 1, addons: shared)
        var reordered = shared.filter { $0.id != "s-B" }
        reordered.reverse()
        let merge = list.absorb(tv(revision: 2, addons: reordered, removed: ["s-B"]), base: base, links: links)
        XCTAssertTrue(merge.changed)
        XCTAssertFalse(list.installed.contains { $0.name == "B" }, "quitado en la TV, quitado aquí")
        XCTAssertEqual(list.installed.map(\.name), ["A", "OpenSubtitles", "Comet", "Torrentio"], "el orden cambió solo allá: se toma")
        XCTAssertTrue(merge.conflicts.isEmpty)
    }
}
