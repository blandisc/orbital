import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// Fernando, 13 nov, Los Simpson desde la ruleta: «Sigue pasando que no aparecen las versiones en latino, solamente inglés».
/// Su bitácora: «complemento Torrentio RD: 0 versiones en 0,2 s» dos veces. El Torrentio público, con sus mismas opciones y
/// SIN la parte `realdebrid=`, contesta 59 entradas y ninguna con enlace (solo el torrent): exactamente «0 versiones».
/// Con cualquier clave, 40 con enlace y la primera es «[RD+] Los Simpsons (Completa Latino)». La regla: la bitácora dice qué
/// trajo cada complemento (sin claves) y unos torrents en lugar de enlaces de un complemento con Real-Debrid no son «no hay».
final class TorrentioSinClaveTests: XCTestCase {
    static let video = "tt0096697:15:12", encoded = "tt0096697%3A15%3A12"
    static let options = "sort=seeders|language=latino,spanish|qualityfilter=brremux,cam,scr"
    static let key = String(repeating: "K", count: 52)
    static let fast = SearchLimits(perAddon: 2, origin: 0.2, readyLink: 0.2, total: 4, budget: 0.2)

    final class Notes: @unchecked Sendable {
        private let lock = NSLock(); private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    /// Lo que contesta Torrentio sin la clave: el torrent y su archivo, nunca `url`.
    static func keyless(_ title: String, hash: Character) -> JSON {
        ["name": "Torrentio\n1080p", "title": .string(title), "infoHash": .string(String(repeating: hash, count: 40)), "fileIdx": 3]
    }

    func testTheReportCountsEntriesWithoutLinksNoticesAndOptionsWithoutTheKey() throws {
        let streams: [JSON] = [Self.keyless("The Simpsons S15E12 1080p\n👤 30", hash: "a"), Self.keyless("Los Simpsons (Completa Latino)\n🇲🇽", hash: "b"),
                               ["name": "Torrentio\nRD error", "title": "Invalid RealDebrid ApiKey/Token!", "url": "https://torrentio.strem.fun/videos/failed_access_v3.mp4"]]
        let withoutKey = AddonAnswerReport(streams: streams, addonName: "Torrentio RD", addonURL: "https://torrentio.strem.fun/\(Self.options)/manifest.json")
        XCTAssertEqual(withoutKey.total, 3)
        XCTAssertEqual(withoutKey.withLink, 1)
        XCTAssertEqual(withoutKey.onlyTorrent, 2)
        XCTAssertEqual(withoutKey.notices, [.access: 1])
        XCTAssertFalse(withoutKey.keyInAddress)
        XCTAssertEqual(withoutKey.line, "3 entradas · 1 con enlace · 2 solo torrent · avisos: 1 access · opciones: \(Self.options) · clave en la dirección: no")
        let withKey = AddonAnswerReport(streams: [], addonName: "Torrentio RD",
                                        addonURL: "https://torrentio.strem.fun/\(Self.options)|debridoptions=nodownloadlinks|realdebrid=\(Self.key)/manifest.json")
        XCTAssertTrue(withKey.keyInAddress)
        XCTAssertFalse(withKey.line.contains(Self.key), "la clave nunca va a la bitácora")
        XCTAssertTrue(withKey.line.contains("opciones: \(Self.options)|debridoptions=nodownloadlinks"), withKey.line)
        XCTAssertTrue(withKey.line.hasSuffix("clave en la dirección: sí"))
        XCTAssertNil(AddonAnswerReport(streams: [], addonName: "Comet", addonURL: "https://comet.example/abc/manifest.json").torrentioOptions)
    }

    func testOnlyTheKnownTorrentioOptionsAreLogged() {
        let url = "https://torrentio.strem.fun/providers=yts,eztv|sizefilter=5GB|limit=3|realdebrid=\(Self.key)|premiumize=SECRETO|algo=raro/manifest.json"
        let said = TorrentioConfig.publicOptions(url)
        XCTAssertEqual(said, "providers=yts,eztv|limit=3|sizefilter=5GB")
        XCTAssertFalse(said?.contains("SECRETO") ?? true)
        XCTAssertEqual(TorrentioConfig.publicOptions("https://torrentio.strem.fun/manifest.json"), "")
    }

    func testDebridAddonsThatSendTorrentsInsteadOfLinksAreFlagged() {
        let torrents = [Self.keyless("x", hash: "a")]
        XCTAssertTrue(AddonAnswerReport(streams: torrents, addonName: "Torrentio RD", addonURL: "https://torrentio.strem.fun/manifest.json").torrentsInsteadOfLinks,
                      "dice «RD» y no trae enlaces: la dirección va sin tu clave")
        XCTAssertTrue(AddonAnswerReport(streams: torrents, addonName: "Torrentio", addonURL: "https://torrentio.strem.fun/realdebrid=\(Self.key)/manifest.json").torrentsInsteadOfLinks)
        XCTAssertFalse(AddonAnswerReport(streams: torrents, addonName: "Torrentio", addonURL: "https://torrentio.strem.fun/manifest.json").torrentsInsteadOfLinks,
                       "un Torrentio sin Real-Debrid a propósito da torrents: eso es lo suyo")
        XCTAssertFalse(AddonAnswerReport(streams: [], addonName: "Torrentio RD", addonURL: "https://torrentio.strem.fun/manifest.json").torrentsInsteadOfLinks,
                       "vacío de verdad no es lo mismo")
        XCTAssertFalse(AddonAnswerReport(streams: torrents, addonName: "Brrd", addonURL: "https://x.example/manifest.json").torrentsInsteadOfLinks)
    }

    /// El caso real: Torrentio RD manda puros torrents. La bitácora lo dice, sus complementos se rearman y se le pregunta otra
    /// vez; lo que traiga ya con su clave entra a la lista, y no se guarda como «no tiene».
    func testTorrentsInsteadOfLinksRebuildTheAddonsAndAskAgain() async throws {
        let http = FakeHTTP(), notes = Notes()
        let torrentio = "https://torrentio.example", comet = "https://comet.example"
        http.json["\(torrentio)/manifest.json"] = ["name": "Torrentio RD", "resources": ["stream"], "types": ["series"], "idPrefixes": ["tt"]]
        http.json["\(comet)/manifest.json"] = ["name": "Comet | ElfHosted | RD", "resources": ["stream"], "types": ["series"], "idPrefixes": ["tt"]]
        http.json["\(comet)/stream/series/\(Self.encoded).json"] = ["streams": [
            ["name": "[RD⚡] Comet 1080p", "description": "📄 The.Simpsons.S15E12.1080p.BluRay.10bit.EAC3.5.1.x265-iVy.mkv", "url": "https://comet.example/p/1"]]]
        http.json["\(torrentio)/stream/series/\(Self.encoded).json"] = ["streams": [Self.keyless("The Simpsons S15E12", hash: "a"), Self.keyless("Los Simpsons latino", hash: "b")]]
        let registry = AddonRegistry(http: http, own: { [torrentio, comet] })
        let finder = StreamFinder(http: http, registry: registry, limits: Self.fast)
        await finder.configureNotes { notes.add($0) }
        let found = try await finder.find(kind: "series", videoID: Self.video, prefs: Preferences(audio: "es", spanish: "es-419"))
        XCTAssertEqual(found.map(\.addon), ["Comet"], "los torrents no se pueden ver en el iPhone")
        XCTAssertTrue(notes.all.contains("complemento Torrentio RD: 2 entradas sin enlace: la dirección va sin tu clave"), "\(notes.all)")
        XCTAssertTrue(notes.all.contains { $0.hasPrefix("complemento Torrentio RD: 2 entradas · 0 con enlace · 2 solo torrent") }, "\(notes.all)")
        XCTAssertTrue(notes.all.contains("se rearman tus complementos y se pregunta otra vez"))
        XCTAssertEqual(http.calls.filter { $0 == "\(torrentio)/stream/series/\(Self.encoded).json" }.count, 2, "una vez más, con la lista rearmada")
        XCTAssertEqual(http.calls.filter { $0 == "\(torrentio)/manifest.json" }.count, 2, "la dirección se vuelve a armar")
        let quiet = await finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quiet, ["Torrentio RD"], "«No contestó a tiempo: Torrentio RD · Reintentar», nunca «no hay»")
    }

    /// Un «HTTP 4xx» cuenta como «no tiene ese video», pero la bitácora dice cuál fue (un 403 de Torrentio no es «vacío»).
    func testAnHTTPErrorIsNamedInTheLog() async throws {
        let http = FakeHTTP(), notes = Notes()
        let torrentio = "https://torrentio.example"
        http.json["\(torrentio)/manifest.json"] = ["name": "Torrentio RD", "resources": ["stream"], "types": ["series"], "idPrefixes": ["tt"]]
        http.json["\(torrentio)/stream/series/\(Self.encoded).json"] = ["streams": []]
        http.statuses["\(torrentio)/stream/series/\(Self.encoded).json"] = 403
        let finder = StreamFinder(http: http, registry: AddonRegistry(http: http, own: { [torrentio] }), limits: Self.fast)
        await finder.configureNotes { notes.add($0) }
        _ = try? await finder.find(kind: "series", videoID: Self.video, prefs: Preferences())
        XCTAssertTrue(notes.all.contains("complemento Torrentio RD: HTTP 403 (cuenta como «no tiene ese video»)"), "\(notes.all)")
    }
}
