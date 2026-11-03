import XCTest
@testable import OrbitalCore

final class StreamsTests: XCTestCase {
    func testParseMatchesPython() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/streams.json")["parsed"]?.array).enumerated() {
            let r = try XCTUnwrap(c["result"])
            let s = Streams.parse(try XCTUnwrap(c["stream"]), addon: "Torrentio Lite", transportURL: "https://torrentio.example/KEY/manifest.json", index: i)
            XCTAssertEqual(s.addon, r["addon"]?.string, "addon \(i)")
            XCTAssertEqual(s.resolution, r["resolution"]?.string, "resolución \(i)")
            XCTAssertEqual(s.hdr, r["hdr"]?.array?.compactMap(\.string), "hdr \(i)")
            XCTAssertEqual(s.size, r["size"]?.intValue, "tamaño \(i)")
            XCTAssertEqual(s.seeders, r["seeders"]?.intValue, "seeders \(i)")
            XCTAssertEqual(s.site, r["site"]?.string, "sitio \(i)")
            XCTAssertEqual(s.cached, r["cached"]?.bool, "cached \(i)")
            XCTAssertEqual(s.debrid, r["debrid"]?.bool, "debrid \(i)")
            XCTAssertEqual(s.languages, r["languages"]?.array?.compactMap(\.string), "idiomas \(i)")
            XCTAssertEqual(s.release, r["release"]?.string, "release \(i)")
            XCTAssertEqual(s.tags, r["tags"]?.array?.compactMap(\.string), "etiquetas \(i)")
            XCTAssertEqual(s.binge, r["binge"]?.string, "binge \(i)")
            XCTAssertEqual(s.dub, r["dub"]?.string, "doblaje \(i)")
            XCTAssertEqual(audioLangs(s), r["audio_langs"]?.object?.compactMapValues(\.string), "audio_langs \(i)")
        }
    }

    /// El audio como lo da la TV: idioma → qué tan seguro es («seen», «name», «site», «original», «assumed», «maybe»).
    func audioLangs(_ s: Source) -> [String: String] {
        Dictionary(s.audio.map { ($0.code, $0.evidence.tv) }, uniquingKeysWith: { a, _ in a })
    }

    func testRankMatchesPython() throws {
        let samples = try XCTUnwrap(Fixtures.json("ios/streams.json")["parsed"]?.array).compactMap { $0["stream"] }
        for c in try XCTUnwrap(Fixtures.json("ios/streams.json")["ranked"]?.array) {
            let prefs = Preferences(audio: c["audio"]!.string!, quality: c["quality"]!.string!)
            let kind = c["kind"]!.string!
            let sources = samples.enumerated().map { Streams.parse($1, addon: "Torrentio", transportURL: "https://t.example/manifest.json", index: $0) }
            let ranked = Streams.rank(sources, prefs: prefs, kind: kind)
            XCTAssertEqual(ranked.map(\.index), c["order"]?.array?.compactMap(\.intValue), "orden \(prefs) \(kind)")
            for s in ranked {
                XCTAssertEqual(s.score, number(c["scores"]?[String(s.index)]), accuracy: 1e-9, "puntaje \(s.index) \(prefs) \(kind)")
            }
        }
    }

    /// Latino, castellano o cualquiera: el mismo orden y los mismos puntos que la TV (`streams.language_score`).
    func testSpanishVariantRankMatchesPython() throws {
        for c in try XCTUnwrap(Fixtures.json("ios/streams_spanish.json").array) {
            let prefs = Preferences(audio: c["audio"]!.string!, quality: c["quality"]!.string!, spanish: c["spanish"]!.string!)
            let kind = c["kind"]!.string!
            let samples = try XCTUnwrap(c["streams"]?.array)
            let sources = samples.enumerated().map { Streams.parse($1, addon: "Torrentio", transportURL: "https://t.example/manifest.json", index: $0) }
            let ranked = Streams.rank(sources, prefs: prefs, kind: kind)
            XCTAssertEqual(ranked.map(\.index), c["order"]?.array?.compactMap(\.intValue), "orden \(prefs) \(kind)")
            for s in ranked {
                XCTAssertEqual(s.score, number(c["scores"]?[String(s.index)]), accuracy: 1e-9, "puntaje \(s.index) \(prefs) \(kind)")
                XCTAssertEqual(audioLangs(s), c["audio_langs"]?[String(s.index)]?.object?.compactMapValues(\.string), "audio_langs \(s.index)")
                // El doblaje, con la regla de la TV (`set_languages`): solo si es seguro (comprobado, dicho o el original).
                let sure = (c["audio_langs"]?[String(s.index)]?.object ?? [:]).filter { ["seen", "name", "site", "original"].contains($0.value.string ?? "") }
                XCTAssertEqual(s.dub, sure["es-419"] != nil ? "latino" : sure["es-ES"] != nil ? "castellano" : "", "doblaje \(s.index)")
            }
        }
    }

    func testStableIndexMatchesPython() throws {
        for c in try XCTUnwrap(Fixtures.json("ios/streams.json")["hashes"]?.array) {
            XCTAssertEqual(Streams.stableIndex(addonURL: c["addon_url"]!.string!, stream: c["stream"]!), c["index"]?.intValue)
        }
    }

    func testSizeNumberMatchesPython() throws {
        for c in try XCTUnwrap(Fixtures.json("ios/streams.json")["sizes"]?.array) {
            XCTAssertEqual(Streams.sizeNumber(c["text"]!.string!), number(c["value"]), accuracy: 1e-9, c["text"]!.string!)
        }
    }

    func testSHA1KnownVectors() {
        XCTAssertEqual(SHA1.hex(Array("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hex([]), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    func testOnlyHTTPSourcesCanPlayOnIPhone() {
        let url = Streams.parse(["name": "x", "url": "https://rd.example/a.mkv"], addon: "T", transportURL: "https://t/manifest.json", index: 1)
        let magnet = Streams.parse(["name": "x", "url": "magnet:?xt=urn:btih:abc"], addon: "T", transportURL: "https://t/manifest.json", index: 2)
        let hash = Streams.parse(["name": "x", "infoHash": "abcdef0123456789abcdef0123456789abcdef01"], addon: "T", transportURL: "https://t/manifest.json", index: 3)
        XCTAssertNotNil(url.playbackURL)
        XCTAssertNil(magnet.playbackURL)
        XCTAssertNil(hash.playbackURL)
    }

    func testDownloadPrefersModerateHEVCOverRemux() {
        let remux = Streams.parse(["name": "T\n4k [RD+]", "title": "Peli.2160p.REMUX\n👤 100 💾 58 GB"], addon: "T", transportURL: "u", index: 1)
        let small = Streams.parse(["name": "T\n1080p [RD+]", "title": "Peli.1080p.WEB-DL.x265\n👤 100 💾 2.1 GB"], addon: "T", transportURL: "u", index: 2)
        let prefs = Preferences(audio: "en", quality: "1080p")
        XCTAssertEqual(Streams.rank([remux, small], prefs: prefs, purpose: .download).first?.index, 2)
    }

    /// El botón «Ver» dice lo mejor sin repetir: DV ya implica HDR y Atmos ya implica DD+.
    func testQualitySummaryDropsWhatIsImplied() {
        let best = Streams.parse(["name": "T\n4K [RD+]", "title": "Peli.2160p.DV.HDR10.DDP5.1.Atmos.REMUX"], addon: "T", transportURL: "u", index: 0)
        XCTAssertEqual(best.qualitySummary, ["4K", "Dolby Vision", "Atmos"])
        let plain = Streams.parse(["name": "T\n1080p", "title": "Peli.1080p.WEB-DL.x265"], addon: "T", transportURL: "u", index: 1)
        XCTAssertEqual(plain.qualitySummary, ["1080p"])
    }
}

/// R5: los avisos de Torrentio se reconocen por su nombre o por la ruta de su video (sin abrir nada).
final class TorrentioNoticeTests: XCTestCase {
    func testStaticVideosAndTheRDErrorVersion() {
        func notice(_ path: String) -> StreamNotice? { TorrentioNotices.notice(url: URL(string: "https://torrentio.strem.fun\(path)")) }
        XCTAssertEqual(notice("/videos/downloading_v3.mp4"), .downloading)
        XCTAssertEqual(notice("/videos/downloading_v2.mp4"), .downloading, "la versión del nombre cambia")
        XCTAssertEqual(notice("/videos/failed_access_v3.mp4"), .access)
        XCTAssertEqual(notice("/videos/blocked_access_v2.mp4"), .blocked)
        XCTAssertEqual(notice("/videos/failed_infringement_v3.mp4"), .infringing)
        XCTAssertEqual(notice("/videos/limits_exceeded_v2.mp4"), .limits)
        XCTAssertEqual(notice("/videos/failed_too_big_v2.mp4"), .downloadFailed)
        XCTAssertEqual(notice("/videos/failed_rar_v1.mp4"), .downloadFailed)
        XCTAssertEqual(notice("/videos/something_new_v4.mp4"), .downloadFailed, "uno que aún no se conoce: falla de Real-Debrid")
        XCTAssertNil(notice("/resolve/realdebrid/KEY/abc/0/Movie.mkv"))
        XCTAssertNil(notice("/videos/movies/Movie.2020.mp4"), "solo la ruta exacta de los avisos")
        XCTAssertEqual(TorrentioNotices.notice(name: "Torrentio\nRD error", url: URL(string: "https://x.example/y")), .access)
        XCTAssertNil(TorrentioNotices.notice(name: "Torrentio\n1080p [RD+]", url: URL(string: "https://x.example/y.mkv")))
        XCTAssertTrue(StreamNotice.access.aboutTheAccount)
        XCTAssertFalse(StreamNotice.downloading.aboutTheAccount)
    }

    func testAnInstantVersionIsCachedOrNotFromADownloadService() {
        let cached = Streams.parse(["name": "Torrentio\n[RD+] 1080p", "url": "https://x/a.mkv"], addon: "Torrentio", transportURL: "", index: 0)
        let download = Streams.parse(["name": "Torrentio\n[RD download] 1080p", "url": "https://x/b.mkv"], addon: "Torrentio", transportURL: "", index: 1)
        let direct = Streams.parse(["name": "Directo 1080p", "url": "https://x/c.mkv"], addon: "Directo", transportURL: "", index: 2)
        XCTAssertEqual([cached.instant, download.instant, direct.instant], [true, false, true])
    }
}

/// D5/R1: la causa sale en el orden de la tabla común con la TV, con sus textos y una sola salida.
final class UnavailableCauseTests: XCTestCase {
    func testOrderTextsAndActions() {
        XCTAssertEqual(UnavailableCause.first(notice: .infringing, account: .expired, language: "es-419"), .debridExpired, "tu cuenta va primero")
        XCTAssertEqual(UnavailableCause.first(notice: nil, account: .free, language: "en"), .noPremium)
        XCTAssertEqual(UnavailableCause.first(notice: .access, account: .invalidKey, language: "en"), .reconnectDebrid)
        XCTAssertEqual(UnavailableCause.first(notice: .infringing, account: .ok, language: "en"), .debridRefused)
        XCTAssertEqual(UnavailableCause.first(notice: .access, account: .ok, language: "en"), .debridRefused, "sin acceso con la cuenta bien: no lo dejó")
        XCTAssertEqual(UnavailableCause.first(notice: .downloading, account: .unknown, language: "es-419"), .notInDebrid(language: "es-419"))
        XCTAssertNil(UnavailableCause.first(notice: nil, account: .ok, language: "en"), "sin nada mejor: el mensaje de siempre")
        XCTAssertEqual(UnavailableCause.debridExpired.title(), "Tu Real-Debrid venció")
        XCTAssertEqual(UnavailableCause.debridExpired.action, .renew)
        XCTAssertEqual(UnavailableCause.label(.renew), "Renovar")
        XCTAssertNil(UnavailableCause.debridExpired.detail())
        XCTAssertEqual(UnavailableCause.notInDebrid(language: "es-419").detail(languageName: { $0 == "es-419" ? "latino" : $0 }),
                       "Lo puede bajar por ti, de preferencia en latino; tarda según cuánta gente lo comparte")
        XCTAssertEqual(UnavailableCause.downloading(percent: 42).title(), "Bajando en Real-Debrid · 42 %")
        XCTAssertEqual(UnavailableCause.noAddonsOn.detail(), "Ajustes › Complementos")
        XCTAssertEqual(UnavailableCause.noAddonsOn.action, .settings)
        XCTAssertEqual(UnavailableCause.debridRefused.action, .otherVersion)
    }
}
