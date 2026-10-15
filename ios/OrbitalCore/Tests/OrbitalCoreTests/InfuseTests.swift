import XCTest
@testable import OrbitalCore

final class InfuseTests: XCTestCase {
    func testPlayURLEncodesEverythingFully() throws {
        let video = URL(string: "https://torrentio.example/resolve/realdebrid/KEY/abc/null/0/Show%20S01E02.mkv?x=1&y=2")!
        let url = try XCTUnwrap(Infuse.playURL(.init(video: video, position: 754, subtitle: URL(string: "https://s.example/es.srt?a=1&b=2"), filename: "Show - S01E02.mkv")))
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix("infuse://x-callback-url/play?url="))
        XCTAssertFalse(text.dropFirst("infuse://x-callback-url/play?".count).contains("://"), "ningún valor lleva «://» sin codificar")
        let items = URLComponents(string: text)?.queryItems ?? []
        func raw(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(raw("url"), video.absoluteString, "al decodificar vuelve exacta")
        XCTAssertEqual(raw("position"), "754")
        XCTAssertEqual(raw("sub"), "https://s.example/es.srt?a=1&b=2")
        XCTAssertEqual(raw("filename"), "Show - S01E02.mkv")
        XCTAssertEqual(raw("x-success"), Infuse.successURL)
        XCTAssertEqual(raw("x-error"), Infuse.errorURL)
        XCTAssertTrue(text.contains("url=https%3A%2F%2Ftorrentio.example%2Fresolve"), "«:» y «/» van codificados, como en el ejemplo oficial")
        XCTAssertTrue(text.contains("%3Fx%3D1%26y%3D2"), "«?», «=» y «&» de la URL del video no rompen la petición")
    }

    func testNoPositionWhenStartingFromZero() throws {
        let url = try XCTUnwrap(Infuse.playURL(.init(video: URL(string: "https://x/a.mkv")!, position: 0)))
        XCTAssertFalse(url.absoluteString.contains("position="))
        XCTAssertFalse(url.absoluteString.contains("sub="))
    }

    func testParseCallbacks() throws {
        let ok = try XCTUnwrap(Infuse.parseCallback(URL(string: "orbital-ios://infuse-done?lastPlayedUrl=https%3A%2F%2Fx%2Fa.mkv&position=1234")!))
        XCTAssertEqual(ok, .closed(lastPlayed: URL(string: "https://x/a.mkv"), position: 1234, progress: nil))
        let progress = try XCTUnwrap(Infuse.parseCallback(URL(string: "orbital-ios://infuse-done?progress=0.5")!))
        XCTAssertEqual(Infuse.seconds(from: progress, knownDuration: 3000), 1500)
        XCTAssertNil(Infuse.seconds(from: progress, knownDuration: nil))
        let bad = try XCTUnwrap(Infuse.parseCallback(URL(string: "orbital-ios://infuse-error?errorCode=3&errorMessage=No%20abre&failedUrl=https%3A%2F%2Fx%2Fb")!))
        XCTAssertEqual(bad, .failed(code: "3", message: "No abre", url: URL(string: "https://x/b")))
        XCTAssertNil(Infuse.parseCallback(URL(string: "otra-app://infuse-done")!))
        XCTAssertNil(Infuse.parseCallback(URL(string: "orbital-ios://otra-cosa")!))
    }

    func testFilenames() {
        XCTAssertEqual(Infuse.filename(title: "Severance", year: nil, season: 2, episode: 5), "Severance - S02E05.mkv")
        XCTAssertEqual(Infuse.filename(title: "Dune: Parte dos", year: "2024", season: nil, episode: nil), "Dune - Parte dos (2024).mkv")
        XCTAssertEqual(Infuse.filename(title: "Peli", year: nil, season: nil, episode: nil, ext: "mp4"), "Peli.mp4")
    }

    func testRuntimeSeconds() {
        XCTAssertEqual(CinemetaParsing.runtimeSeconds("22 min"), 1320)
        XCTAssertEqual(CinemetaParsing.runtimeSeconds("2h 46min"), 9960)
        XCTAssertEqual(CinemetaParsing.runtimeSeconds("1 h 40 min"), 6000)
        XCTAssertEqual(CinemetaParsing.runtimeSeconds("90"), 5400)
        XCTAssertEqual(CinemetaParsing.runtimeSeconds(""), 0)
    }
}
