import XCTest
@testable import OrbitalCore

/// La dirección de un complemento no se estropea al armarla (Fernando, 13 nov 2026: «sigue sin aparecer» el latino de Los
/// Simpson). `URL(string:)` volvía a codificar los «%» cuando la dirección traía un carácter inválido: la de Torrentio lleva
/// «|» entre sus opciones, así que el episodio `tt0096697%3A11%3A2` salía `%253A` y Torrentio contestaba vacío para toda serie.
final class AddonURLTests: XCTestCase {
    static let torrentio = "https://torrentio.strem.fun/sort=seeders|language=latino,spanish|qualityfilter=brremux,cam,scr|realdebrid=KEY"

    func testTheEpisodeIsNotEncodedTwice() throws {
        let url = try XCTUnwrap(addonURL("\(Self.torrentio)/stream/series/\(uriComponent("tt0096697:11:2")).json"))
        XCTAssertEqual(url.absoluteString, "https://torrentio.strem.fun/sort=seeders%7Clanguage=latino,spanish%7Cqualityfilter=brremux,cam,scr%7Crealdebrid=KEY/stream/series/tt0096697%3A11%3A2.json")
        XCTAssertFalse(url.absoluteString.contains("%25"), "ningún «%» se vuelve a codificar")
    }

    func testTheSystemAloneBreaksIt() {
        // Lo que hacía la app: por esto la regla. Si el sistema deja de hacerlo algún día, esta prueba avisa y no pasa nada.
        let broken = URL(string: "\(Self.torrentio)/stream/series/tt0096697%3A11%3A2.json")?.absoluteString ?? ""
        XCTAssertTrue(broken.contains("%253A") || broken.contains("%3A"), "cualquiera de las dos; con `addonURL` siempre la buena")
    }

    func testCleanAddressesStayAsTheyAre() throws {
        for text in ["https://comet.example/eyJhIjoxfQ==/stream/series/tt0096697%3A11%3A2.json", "https://a.example/stream/movie/tt0816692.json",
                     "https://rd.example/d/ABC/The%20Simpsons%20S11E02.mkv?x=1&y=2#t"] {
            XCTAssertEqual(try XCTUnwrap(addonURL(text)).absoluteString, text)
        }
    }

    func testSpacesAndOddCharactersAreEncodedOnce() throws {
        XCTAssertEqual(try XCTUnwrap(addonURL("https://a.example/Los Simpson [Latino] 100%25.mkv")).absoluteString,
                       "https://a.example/Los%20Simpson%20%5BLatino%5D%20100%25.mkv")
    }

    /// Regla del repo: toda dirección que sale de la de un complemento se arma con `addonURL`, nunca con `URL(string:)` directo.
    func testAddonAddressesAreBuiltWithAddonURL() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/OrbitalCore")
        for name in ["StreamFinder+Ask.swift", "StreamFinder.swift", "TorrentLookup.swift", "TorrentioProbe.swift", "ForYou.swift", "Addons.swift"] {
            let code = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            XCTAssertNil(code.range(of: #"URL\(string: "\\\((addon\.|entry\.)?base\)"#, options: .regularExpression), "\(name): usa `addonURL` para la dirección de un complemento")
        }
        let ask = try String(contentsOf: root.appendingPathComponent("StreamFinder+Ask.swift"), encoding: .utf8)
        XCTAssertTrue(ask.contains("addonURL(\"\\(addon.base)/stream/"), "las versiones se piden con `addonURL`")
    }
}
