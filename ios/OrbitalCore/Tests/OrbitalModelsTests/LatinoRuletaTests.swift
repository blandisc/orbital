import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Fernando, 13 nov, ya con los arreglos del 12: «Sigue pasando que no aparecen las versiones en latino, solamente inglés,
/// francés y una que otra. Sobre todo pasa cuando le doy a la ruleta esta de los Simpsons, ya sea que entre por widget o por
/// control panel». Su bitácora de T15E12: Torrentio RD 0 versiones, Comet 43 (ninguna en latino), y se abrió una en inglés.
/// Sin Real-Debrid, Torrentio sí tiene 3 en latino. La ruleta abre el reproductor directo, sin pasar por «Versión».
/// Regla (docs/ios-interfaz.md § «Tu idioma, aunque haya que pedirlo»): el reproductor directo sigue eligiendo la mejor que
/// hay, pero si ninguna de tu idioma arranca al instante y tu idioma existe para pedir, lo dice una vez y «Versión» lo ofrece.
@MainActor
final class LatinoRuletaTests: XCTestCase {
    static let id = "tt0096697", video = "tt0096697:15:12", encoded = "tt0096697%3A15%3A12"
    static let comet = "https://c.example"
    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    /// Lo de Comet, con los nombres reales: inglés, un «MULTi-VF2-ESP» (español sin decir cuál) y un «Multi Audio».
    static let cometStreams: JSON = ["streams": [
        ["name": "[RD⚡] Comet 1080p", "description": "📄 The.Simpsons.S15E12.Milhouse.Doesnt.Live.Here.Anymore.1080p.BluRay.10bit.EAC3.5.1.x265-iVy.mkv\n💾 600 MB", "url": "https://c.example/p/ivy.mkv"],
        ["name": "[RD⚡] Comet 1080p", "description": "📄 The.Simpsons.S01.to.S35.MULTi-VF2-ESP.1080p.DSNP.EAC3.DD5.1.x265-NFW\n💾 360 MB", "url": "https://c.example/p/nfw.mkv"],
        ["name": "[RD⚡] Comet 720p", "description": "📄 The.Simpsons.S15E12.MULTi.HDRip.720p.AAC.x264-ZiGZaG.mkv\n💾 157 MB\nMulti Audio / 🇬🇧 / 🇫🇷", "url": "https://c.example/p/zigzag.mkv"],
    ]]
    /// Lo que existe sin Real-Debrid: los 3 en latino del Torrentio público para T15E12 (y uno en inglés).
    static let keylessStreams: JSON = ["streams": [
        ["name": "Torrentio\n1080p", "title": "Simpsons.S15E12.2005.1080p-Dual-Lat\n👤 0 💾 429.35 MB ⚙️ Cinecalidad\nDual Audio / 🇲🇽", "infoHash": .string(String(repeating: "1", count: 40))],
        ["name": "Torrentio\nSD", "title": "Los Simpsons (Completa Latino) 24 !!\nTemporada 15/Los Simpsons 15x12 - Milhouse Ya no Vive Aquí.mp4\n👤 15 💾 34.56 MB ⚙️ ThePirateBay\n🇲🇽",
         "infoHash": .string(String(repeating: "2", count: 40)), "fileIdx": 300],
        ["name": "Torrentio\nSD", "title": "Los Simpsons latino \n15/15x12 - Milhouse ya no vive aquí.mp4\n👤 1 💾 284.88 MB ⚙️ 1337x\n🇪🇸 / 🇲🇽",
         "infoHash": .string(String(repeating: "3", count: 40)), "fileIdx": 12],
        ["name": "Torrentio\n1080p", "title": "The Simpsons S15E12 1080p DSNP WEB-DL\n👤 36 💾 860 MB ⚙️ EXT", "infoHash": .string(String(repeating: "4", count: 40))],
    ]]

    func rig(torrentioRD: JSON = ["streams": []]) throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.secrets.set(AddonKeys.realDebridToken, String(repeating: "K", count: 52))
        rig.secrets.set(SecretKey.ownAddons, "https://a.example/manifest.json\n\(Self.comet)/manifest.json")
        rig.http.json["https://a.example/manifest.json"] = ["name": "Torrentio RD", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        rig.http.json["\(Self.comet)/manifest.json"] = ["name": "Comet | ElfHosted | RD", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        rig.http.json["\(Self.comet)/stream/series/\(Self.encoded).json"] = Self.cometStreams
        rig.http.json["https://a.example/stream/series/\(Self.encoded).json"] = torrentioRD
        let base = try XCTUnwrap(rig.services.debridRequests.keylessBase)
        rig.http.json["\(base)/stream/series/\(Self.encoded).json"] = Self.keylessStreams
        rig.services.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        return rig
    }

    func sources(_ streams: JSON, addon: String = "Comet") -> [Source] {
        (streams["streams"]?.array ?? []).enumerated().map { Streams.parse($1, addon: addon, transportURL: Self.comet, index: $0) }
    }

    // MARK: la regla pura

    /// Un «ESP» sin variante, un «MULTi» o un «tal vez» no son latino al instante; un «Dual-Lat» sí.
    func testOnlySolidYourLanguageThatStartsNowCounts() {
        let comet = sources(Self.cometStreams)
        XCTAssertFalse(YourLanguageNow.available(comet, prefs: latino), "\(comet.map { ($0.release, $0.audio) })")
        XCTAssertTrue(YourLanguageNow.summary(comet, prefs: latino).hasPrefix("sin es-419 al instante: "), YourLanguageNow.summary(comet, prefs: latino))
        let lat = sources(["streams": [["name": "[RD⚡] Comet 1080p", "description": "📄 Simpsons.S11E03.1999.1080p-Dual-Lat.mkv", "url": "https://c.example/p/lat.mkv"]]])
        XCTAssertTrue(YourLanguageNow.available(comet + lat, prefs: latino))
        XCTAssertEqual(YourLanguageNow.summary(comet + lat, prefs: latino), "en es-419 al instante: 1")
        var mustDownload = lat[0]
        mustDownload.cached = false; mustDownload.debrid = true
        XCTAssertFalse(YourLanguageNow.available(comet + [mustDownload], prefs: latino), "la que hay que pedir no arranca al instante")
    }

    /// De lo que existe sin Real-Debrid, la mejor en latino para pedir (nunca la de inglés, ni una que ya está en tu lista).
    func testTheBestLatinoToRequestComesFromWhatExistsWithoutRealDebrid() throws {
        let keyless = sources(Self.keylessStreams, addon: "Torrentio")
        let pick = try XCTUnwrap(PlayerModel.yoursFromLookup(keyless, choices: sources(Self.cometStreams), prefs: latino, limitGB: 5))
        XCTAssertEqual(pick.version.code, "es-419")
        XCTAssertEqual(pick.version.option.speed, .realDebridMustDownload)
        XCTAssertNotEqual(pick.source.torrent?.hash, String(repeating: "4", count: 40))
        let known = Set(keyless.filter { SourcesModel.speaksYours($0, prefs: latino) }.compactMap { $0.torrent?.hash })
        XCTAssertNil(PlayerModel.yoursFromLookup(keyless, choices: sources(Self.cometStreams), prefs: latino, limitGB: 5, refused: known),
                     "lo que Real-Debrid no dejó bajar no se ofrece")
    }

    // MARK: «Versión»

    /// El caso real en «Versión»: el «MULTi-VF2-ESP» y el «Multi Audio» de Comet no esconden «Hay latino, pero hay que pedirlo».
    func testVersionSaysLatinoMustBeRequestedEvenWithSpanishOrMultiAtOnce() async throws {
        let rig = try rig()
        try await Task.sleep(nanoseconds: 50_000_000)
        let list = SourcesModel(rig.services, kind: "series", metaID: Self.id, videoID: Self.video)
        await list.load()
        XCTAssertFalse(list.ranked.isEmpty, "precondición: lo de Comet")
        let yours = try XCTUnwrap(list.yoursToRequest, "el renglón «hay que pedirlo»")
        XCTAssertEqual(yours.code, "es-419")
    }

    // MARK: el reproductor directo (ruleta, widget, Centro de control, «Continuar»)

    func player(_ rig: ServicesRig) -> (PlayerModel, FakeEngine) {
        let engine = FakeEngine()
        let model = PlayerModel(engine: engine, finder: rig.services.finder, watch: rig.services.watch, titlePrefs: rig.services.titlePrefs,
                                settings: rig.services.settings, clock: { rig.clock.now })
        model.queued = QueuedOnRealDebrid()
        model.debridRequests = rig.services.debridRequests
        return (model, engine)
    }

    func request() -> PlayRequest {
        PlayRequest(kind: "series", metaID: Self.id, videoID: Self.video, originalTitle: "The Simpsons", displayTitle: "Los Simpson", episodeLabel: "T15 · E12", meta: nil)
    }

    /// Torrentio RD 0 + Comet sin latino + 3 en latino para pedir: se abre la mejor que hay (la regla no cambia), y una vez,
    /// «No está en latino al instante · Versión», donde la de latino espera con «Pedir a la nube».
    func testTheDirectPlayerOpensTheBestAndSaysLatinoCanBeRequested() async throws {
        let rig = try rig()
        try await Task.sleep(nanoseconds: 50_000_000)
        let (model, engine) = player(rig)
        await model.begin(request())
        XCTAssertEqual(engine.loads.count, 1, "abre una, como siempre")
        XCTAssertFalse(model.source.map { SourcesModel.speaksYours($0, prefs: latino) } ?? true, "precondición: ninguna en latino al instante")
        for _ in 0..<50 where model.notice == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(model.notice, .yoursOnlyByRequest(language: "es-419"))
        XCTAssertEqual(model.yoursToRequest?.code, "es-419")
        XCTAssertNotNil(model.yoursToRequestHash)
    }

    /// Lo de la bitácora del 13 nov: Torrentio RD manda puros torrents (la dirección va sin tu clave). No se toma como «no
    /// tiene»: se rearma y, si sigue igual, se dice que no contestó; el reproductor sigue con Comet y avisa del latino.
    func testTorrentioRDSendingTorrentsStillEndsInTheLatinoNotice() async throws {
        let rig = try rig(torrentioRD: Self.keylessStreams)
        try await Task.sleep(nanoseconds: 50_000_000)
        let (model, engine) = player(rig)
        await model.begin(request())
        XCTAssertEqual(engine.loads.count, 1)
        XCTAssertTrue(model.source?.addon.hasPrefix("Comet") == true)
        let quiet = await rig.services.finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quiet, ["Torrentio RD"])
        for _ in 0..<50 where model.notice == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(model.notice, .yoursOnlyByRequest(language: "es-419"))
    }

    /// Con latino al instante no se busca ni se avisa nada.
    func testNoNoticeWhenYourLanguageStartsNow() async throws {
        let rig = try rig(torrentioRD: ["streams": [
            ["name": "[RD+] Torrentio\n1080p", "title": "Simpsons.S15E12.2005.1080p-Dual-Lat\n💾 429 MB ⚙️ Cinecalidad\n🇲🇽",
             "url": .string("https://a.example/resolve/realdebrid/K/\(String(repeating: "1", count: 40))/null/0/x.mkv")]]])
        try await Task.sleep(nanoseconds: 50_000_000)
        let (model, _) = player(rig)
        await model.begin(request())
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.yoursToRequest)
        XCTAssertFalse(rig.http.calls.contains { $0.hasPrefix(AddonCatalog.torrentioBase) }, "no se le pregunta a Torrentio sin Real-Debrid")
    }
}
