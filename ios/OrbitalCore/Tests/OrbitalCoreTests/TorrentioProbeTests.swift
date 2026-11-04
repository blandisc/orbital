import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// T9: la prueba con un título dice cuántas versiones daría y, si no queda nada, el arreglo de un toque.
final class TorrentioProbeTests: XCTestCase {
    private func stream(_ name: String) -> JSON { ["name": .string(name), "title": "x", "url": "https://torrentio.strem.fun/resolve/realdebrid/K/h/null/1/a.mkv"] }

    func testItCountsInstantAndToRequestAndSkipsNotices() {
        let streams = [stream("[RD+] Torrentio\n1080p"), stream("[RD download] Torrentio\n720p"), stream("[RD download] Torrentio\n4k"),
                       ["name": "Torrentio\nRD error", "url": "https://torrentio.strem.fun/videos/failed_access_v3.mp4"]]
        XCTAssertEqual(TorrentioProbe.verdict(streams: streams, options: AddonOptions(), recommendedCount: nil), .found(instant: 1, toRequest: 2, other: 0))
    }

    func testZeroVersionsBecauseOfYourFiltersOffersTheFix() {
        var options = AddonOptions()
        options.excludedQualities = ["4k", "1080p", "720p", "cam"]
        options.debridOptions = ["nodownloadlinks"]
        let verdict = TorrentioProbe.verdict(streams: [], options: options, recommendedCount: 5)
        XCTAssertEqual(verdict, .nothing(fixes: [.allowRequests, .showQuality("1080p"), .recommended]))
        let fixed = TorrentioProbe.apply(.showQuality("1080p"), to: options)
        XCTAssertEqual(fixed.excludedQualities, ["4k", "720p", "cam"])
        XCTAssertEqual(TorrentioProbe.apply(.allowRequests, to: options).debridOptions, [])
    }

    func testZeroVersionsEvenWithTheRecommendedIsNotYourFilters() {
        XCTAssertEqual(TorrentioProbe.verdict(streams: [], options: AddonOptions(excludedQualities: ["720p"]), recommendedCount: 0), .titleHasNothing)
    }

    func testBackToRecommendedKeepsWhatTheAppDoesNotKnow() {
        let mine = AddonOptions(excludedQualities: ["4k"], languages: ["japanese"], sort: "seeders", limit: 2, sizeFilter: "5GB",
                                providers: ["yts"], debridOptions: ["nodownloadlinks", "nocatalog"], verbatim: ["futuro=1"])
        let back = TorrentioProbe.recommended(keeping: mine)
        XCTAssertEqual(back.languages, ["latino", "spanish"])
        XCTAssertEqual(back.excludedQualities, ["cam", "scr", "unknown"])
        XCTAssertNil(back.sort); XCTAssertNil(back.limit); XCTAssertNil(back.sizeFilter); XCTAssertEqual(back.providers, [])
        XCTAssertEqual(back.debridOptions, ["nocatalog"], "«sin catálogo» no tiene pantalla: se queda")
        XCTAssertEqual(back.verbatim, ["futuro=1"])
        XCTAssertEqual(TorrentioProbe.fixes(for: back), [], "ya es lo recomendado")
    }

    func testTheProbeAddressNeverLeaksWithoutAKeyAndUsesYourOptions() throws {
        let url = try XCTUnwrap(TorrentioProbe.streamURL(options: AddonOptions(excludedQualities: ["cam"], languages: ["latino"]), token: nil))
        XCTAssertEqual(url.absoluteString.removingPercentEncoding, "https://torrentio.strem.fun/language=latino|qualityfilter=cam/stream/series/tt0386676:1:1.json")
        let keyed = try XCTUnwrap(TorrentioProbe.streamURL(options: AddonOptions(), token: "KEY123456"))
        XCTAssertTrue(keyed.absoluteString.removingPercentEncoding?.contains("realdebrid=KEY123456/stream/series/") == true)
    }
}

/// M1, M2, M3: «al instante» como lo dice cada complemento, el tamaño y el nombre del estándar, y los datos que pide un enlace.
final class OtherAddonsTests: XCTestCase {
    private func parse(_ stream: JSON, addon: String, url: String) -> Source {
        Streams.parse(stream, addon: addon, transportURL: url, index: 0)
    }

    func testInstantRecognitionPerAddon() {
        let torrentio = parse(["name": "[RD+] Torrentio\n1080p", "url": "https://x/a.mkv"], addon: "Torrentio", url: "https://torrentio.strem.fun/manifest.json")
        XCTAssertTrue(torrentio.cached && torrentio.debrid && torrentio.instant)
        let torrentioLater = parse(["name": "[RD download] Torrentio\n1080p", "url": "https://x/a.mkv"], addon: "Torrentio", url: "https://torrentio.strem.fun/manifest.json")
        XCTAssertTrue(!torrentioLater.cached && torrentioLater.debrid && !torrentioLater.instant)
        let comet = parse(["name": "[RD⚡] Comet 1080p", "url": "https://x/a.mkv"], addon: "Comet", url: "https://comet.elfhosted.com/abc/manifest.json")
        XCTAssertTrue(comet.cached && comet.instant, "Comet dice «[RD⚡]»")
        let cometLater = parse(["name": "[RD⬇️] Comet 1080p", "url": "https://x/a.mkv"], addon: "Comet", url: "https://comet.elfhosted.com/abc/manifest.json")
        XCTAssertTrue(!cometLater.cached && cometLater.debrid)
        let fusion = parse(["name": "MediaFusion | RD ⚡️ 1080p", "url": "https://x/a.mkv"], addon: "MediaFusion", url: "https://mediafusion.elfhosted.com/x/manifest.json")
        XCTAssertTrue(fusion.cached && fusion.instant, "MediaFusion dice «⚡️»")
        let fusionLater = parse(["name": "MediaFusion | RD ⏳ 1080p", "url": "https://x/a.mkv"], addon: "MediaFusion", url: "https://mediafusion.elfhosted.com/x/manifest.json")
        XCTAssertTrue(!fusionLater.cached && fusionLater.debrid && !fusionLater.instant)
        let unknown = parse(["name": "[AD+] Otro\n720p", "url": "https://x/a.mkv"], addon: "Otro", url: "https://otro.example/manifest.json")
        XCTAssertTrue(unknown.cached, "de respaldo: «+]»")
        let plain = parse(["name": "Otro\n720p", "url": "https://x/a.mkv"], addon: "Otro", url: "https://otro.example/manifest.json")
        XCTAssertTrue(!plain.cached && !plain.debrid && plain.instant, "sin servicio de descarga arranca al instante")
    }

    func testSizeAndFilenameFromBehaviorHintsAndProxyHeaders() {
        let stream: JSON = ["name": "[RD⚡] Comet 1080p", "url": "https://x/a.mkv",
                            "behaviorHints": ["videoSize": .int(2_147_483_648), "filename": "Movie.2024.1080p.WEB-DL.mkv",
                                              "proxyHeaders": ["request": ["User-Agent": "Stremio", "Referer": "https://site.example"]]]]
        let source = parse(stream, addon: "Comet", url: "https://comet.elfhosted.com/abc/manifest.json")
        XCTAssertEqual(source.size, 2_147_483_648, "M2: el tamaño declarado")
        XCTAssertEqual(source.release, "Movie.2024.1080p.WEB-DL.mkv", "M2: sin descripción, el nombre del archivo")
        XCTAssertEqual(source.resolution, "1080p")
        XCTAssertEqual(source.requestHeaders, ["User-Agent": "Stremio", "Referer": "https://site.example"], "M3")
        let torrentio: JSON = ["name": "[RD+] Torrentio\n1080p", "title": "Movie.1080p\n👤 5 💾 1.5 GB", "url": "https://x/b.mkv", "behaviorHints": ["videoSize": .int(99)]]
        XCTAssertEqual(parse(torrentio, addon: "Torrentio", url: "https://torrentio.strem.fun/manifest.json").size, 1_500_000_000, "lo que escribe Torrentio manda")
    }

    /// T2 → R6: si no hay en tu idioma, el siguiente de tu lista antes que cualquier otro. FQ1-A (Fernando, 3 nov): uno de tu
    /// lista que arranca ya le gana al tuyo que hay que pedir (la ficha ofrece pedir el tuyo al lado); a la par, el tuyo gana.
    func testTheLanguageOrderIsThePlanB() {
        var prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        func src(_ code: String, cached: Bool = true) -> Source {
            var s = Source(index: 0, addon: "Torrentio", stream: .null, transportURL: ""); s.cached = cached; s.debrid = true; s.resolution = "1080p"
            s.setAudio([AudioLanguage(code, .name)]); return s
        }
        let japanese = src("ja"), russian = src("ru")
        XCTAssertEqual(Streams.score(japanese, prefs: prefs), Streams.score(russian, prefs: prefs), "sin plan B, iguales")
        prefs.fallback = ["es-419", "es-ES", "ja"]
        XCTAssertGreaterThan(Streams.score(japanese, prefs: prefs), Streams.score(russian, prefs: prefs), "japonés está en tu lista")
        XCTAssertGreaterThan(Streams.score(japanese, prefs: prefs), Streams.score(src("es-419", cached: false), prefs: prefs), "el de tu lista que arranca ya gana (FQ1-A)")
        XCTAssertGreaterThan(Streams.score(src("es-419"), prefs: prefs), Streams.score(japanese, prefs: prefs), "a la par, tu idioma gana")
        XCTAssertGreaterThan(Streams.score(src("es-419", cached: false), prefs: prefs), Streams.score(src("ru"), prefs: prefs), "fuera de tu lista, ni al instante")
    }
}
