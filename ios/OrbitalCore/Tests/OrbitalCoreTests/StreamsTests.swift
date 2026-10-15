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
        }
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
}
