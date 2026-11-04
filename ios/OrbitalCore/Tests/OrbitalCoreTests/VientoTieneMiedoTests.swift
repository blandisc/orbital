import XCTest
@testable import OrbitalCore
@testable import OrbitalAddons

/// Fernando, 3 nov, probando la 1729 con «El viento tiene miedo» (México, 1968, tt0061752): título en inglés, «Ya está» y al
/// abrirla «no llega a ningún lado», la versión pedida sin salir como «Al instante» ni recomendada. Con lo que de verdad da
/// Torrentio sin Real-Debrid para esa película (`tests/fixtures/streams/torrentio_tt0061752_sin_rd_2026-11-03.json`).
final class VientoTieneMiedoTests: XCTestCase {
    static let id = "tt0061752"
    static let yts1080 = "b3bdbf12d9d59e94fcff16bf1e7f893a37a75d78"
    static let mexico = TitleOrigin(language: "es", country: "Mexico", year: 1968, titles: ["Hasta el viento tiene miedo", "Even the Wind Is Afraid"])
    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    /// Lo mismo, como lo da Torrentio con Real-Debrid: «[RD+]» lo de `cached`, «[RD download]» lo demás, con su dirección
    /// `/resolve/realdebrid/<clave>/<huella>/null/<archivo>/…`.
    static func withDebrid(cached: Set<String> = [], dropping: Set<String> = []) throws -> JSON {
        let raw = try Fixtures.json("streams/torrentio_tt0061752_sin_rd_2026-11-03.json")
        let streams: [JSON] = (raw["streams"]?.array ?? []).compactMap { s in
            guard var o = s.object, let hash = s["infoHash"]?.string, !dropping.contains(hash) else { return nil }
            let quality = (s["name"]?.string ?? "").components(separatedBy: "\n").last ?? ""
            o["name"] = .string("\(cached.contains(hash) ? "[RD+]" : "[RD download]") Torrentio\n\(quality)")
            o["url"] = .string("https://torrentio.strem.fun/resolve/realdebrid/KEY/\(hash)/null/\(s["fileIdx"]?.intValue ?? 0)/x.mkv")
            o["infoHash"] = nil; o["fileIdx"] = nil
            return .object(o)
        }
        return ["streams": .array(streams)]
    }

    func finder(_ http: FakeHTTP, streams: JSON) -> StreamFinder {
        http.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie"], "idPrefixes": ["tt"]]
        http.json["https://a.example/stream/movie/\(Self.id).json"] = streams
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://a.example"] }, clock: { Date() })
        return StreamFinder(http: http, registry: registry)
    }

    // MARK: 1 · el título
    /// TMDB no traduce al mismo idioma: en «es-MX» una película mexicana trae el título en inglés. Va su título original.
    func testAMovieMadeInSpanishKeepsItsOriginalSpanishTitle() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/movie/41?language=es-MX&api_key=K"] = [
            "title": "Even the Wind Is Afraid", "original_title": "Hasta el viento tiene miedo", "original_language": "es", "overview": "Unas alumnas…"]
        http.json["https://api.themoviedb.org/3/movie/42?language=es-MX&api_key=K"] = [
            "title": "Interestelar", "original_title": "Interstellar", "original_language": "en", "overview": "Un grupo…"]
        let tmdb = Tmdb(http: http, key: "K")
        let mexican = try await tmdb.translation(kind: "movie", tmdbID: 41, language: "es-MX")
        XCTAssertEqual(mexican.title, "Hasta el viento tiene miedo")
        XCTAssertTrue(mexican.native, "hecha en español: el logo en inglés de metahub no le queda")
        XCTAssertEqual(Localizer.apply(["name": "Even the Wind Is Afraid"], mexican)[Localizer.nativeKey]?.bool, true)
        let english = try await tmdb.translation(kind: "movie", tmdbID: 42, language: "es-MX")
        XCTAssertEqual(english.title, "Interestelar", "una película de otro idioma sigue con su traducción")
        XCTAssertFalse(english.native)
    }

    // MARK: 3, 4 y 5 · un pedido listo
    /// Real-Debrid ya bajó la que pediste, pero Torrentio la sigue llamando «[RD download]»: sale «Al instante · la pediste»
    /// y de primera (la que pone «Ver» y el «Ver ahora» del aviso). Y no hay que esperar 10 minutos a que caduque la lista.
    func testTheReadyRequestIsInstantAndRecommendedRightAway() async throws {
        let http = FakeHTTP()
        let finder = finder(http, streams: try Self.withDebrid())
        let readyNow = Flag()
        await finder.configure(origin: { _, _ in Self.mexico }, checked: { _ in nil })
        await finder.configureReady({ _, _ in readyNow.on ? [ReadyTorrent(hash: Self.yts1080, fileIdx: 0)] : [] }, link: { _, _ in nil })
        let before = try await finder.find(kind: "movie", videoID: Self.id, prefs: latino)
        XCTAssertFalse(before.contains(where: \.cached), "precondición: Real-Debrid no tiene ninguna")
        readyNow.on = true   // «Ya está»
        let after = try await finder.find(kind: "movie", videoID: Self.id, prefs: latino)
        let first = try XCTUnwrap(after.first)
        XCTAssertEqual(first.torrent?.hash, Self.yts1080, "la que pediste va de primera: \(after.map(\.release))")
        XCTAssertTrue(first.cached && first.requested && first.instant)
        XCTAssertEqual(after.filter(\.requested).count, 1, "solo esa")
    }

    /// Con «solo lo que ya está» (o su límite) Torrentio ni la lista: se ve igual, con el enlace de tu Real-Debrid.
    func testAReadyRequestTorrentioDoesNotListStillPlays() async throws {
        let http = FakeHTTP()
        let finder = finder(http, streams: try Self.withDebrid(dropping: [Self.yts1080]))
        await finder.configure(origin: { _, _ in Self.mexico }, checked: { _ in nil })
        await finder.configureReady({ _, _ in [ReadyTorrent(hash: Self.yts1080, fileIdx: 0, release: "Even the Wind Is afraid 1968 1080p BluRay")] },
                                    link: { hash, video in hash == Self.yts1080 && video == Self.id ? URL(string: "https://download.real-debrid.com/d/ABC/x.mp4") : nil })
        let found = try await finder.find(kind: "movie", videoID: Self.id, prefs: latino)
        let first = try XCTUnwrap(found.first)
        XCTAssertEqual(first.playbackURL?.absoluteString, "https://download.real-debrid.com/d/ABC/x.mp4")
        XCTAssertTrue(first.requested && first.cached)
        XCTAssertEqual(first.resolution, "1080p")
        XCTAssertEqual(Streams.playingLanguage(first, latino)?.code, "es-419", "con el idioma original del título, como las demás")
    }

    /// El enlace de un pedido listo es el de SU archivo (los de Real-Debrid empiezan en 1 y solo hay de los elegidos).
    func testTheReadyLinkIsTheRequestedFile() {
        let files = [RDFile(id: 1, path: "/a.nfo", bytes: 1, selected: false), RDFile(id: 2, path: "/E01.mkv", bytes: 900, selected: true),
                     RDFile(id: 3, path: "/E02.mkv", bytes: 1000, selected: true)]
        let torrent = RDTorrent(id: "R", hash: "h", filename: "x", status: "downloaded", progress: 100, files: files, links: ["L-E01", "L-E02"])
        XCTAssertEqual(torrent.link(fileIdx: 1), "L-E01")
        XCTAssertEqual(torrent.link(fileIdx: 2), "L-E02")
        XCTAssertEqual(torrent.link(fileIdx: nil), "L-E02", "sin saber cuál, el video más grande")
        XCTAssertNil(torrent.link(fileIdx: 0), "un archivo que no se eligió no tiene enlace")
    }

    // MARK: lo que existe sin Real-Debrid (para pedir)
    /// Sin el idioma original, la de YTS (sin banderas) era «Inglés» al pedir y «Latino (original)» en la lista.
    func testTheKeylessLookupReadsLanguagesLikeTheVersionList() async throws {
        let http = FakeHTTP()
        http.json["https://t.example/stream/movie/\(Self.id).json"] = try Fixtures.json("streams/torrentio_tt0061752_sin_rd_2026-11-03.json")
        let lookup = TorrentLookup(http: http)
        let answer = await lookup.torrents(base: "https://t.example", kind: "movie", videoID: Self.id, prefs: latino, origin: Self.mexico)
        let found = try XCTUnwrap(answer)
        let yts = try XCTUnwrap(found.first { $0.torrent?.hash == Self.yts1080 })
        XCTAssertEqual(Streams.playingLanguage(yts, latino)?.code, "es-419")
        XCTAssertEqual(found.first?.torrent?.hash, Self.yts1080, "la mejor para pedir es la misma que recomienda la lista")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var on: Bool { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
}
