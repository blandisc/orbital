import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// Fernando, 12 nov, Los Simpson T11E2 en latino: «puse episodio 2 de temporada 11 y me salen puros episodios en inglés…
/// Me salieron todas de Comet». La bitácora: `versiones encontradas: 11` (Comet) contra ~50 de Torrentio en otro episodio.
/// Comet contestó primero, a Torrentio se le cortó la pregunta a los 3 s y sus versiones (las latinas) no llegaban nunca.
final class LatinoNubeFinderTests: XCTestCase {
    static let torrentio = "https://torrentio.example", comet = "https://comet.example"
    static let video = "tt0096697:11:2", encoded = "tt0096697%3A11%3A2"
    static let goodHash = String(repeating: "a", count: 40), latinoHash = String(repeating: "b", count: 40)
    static let fast = SearchLimits(perAddon: 2, origin: 0.2, readyLink: 0.2, total: 4, budget: 0.2)

    final class Notes: @unchecked Sendable {
        private let lock = NSLock(); private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    func makeFinder(_ http: FakeHTTP, limits: SearchLimits = fast, health: AddonHealth? = nil) -> StreamFinder {
        http.json["\(Self.torrentio)/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        http.json["\(Self.comet)/manifest.json"] = ["name": "Comet", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        let registry = AddonRegistry(http: http, own: { [Self.torrentio, Self.comet] })
        return StreamFinder(http: http, registry: registry, health: health, limits: limits)
    }

    /// Lo de Comet (en inglés, al instante) y lo de Torrentio con Real-Debrid (las copias buenas en inglés y el latino de
    /// 15 fuentes que hay que pedir), con los nombres reales del 12 nov.
    func serve(_ http: FakeHTTP, torrentioDelay: Int) {
        http.json["\(Self.comet)/stream/series/\(Self.encoded).json"] = ["streams": [
            ["name": "[RD⚡] Comet 1080p", "description": "📄 The.Simpsons.S11E02.Brothers.Little.Helper.1080p.Web-DL.x264-OFT.mkv\n💾 1.1 GB", "url": "https://comet.example/p/1"],
        ]]
        http.json["\(Self.torrentio)/stream/series/\(Self.encoded).json"] = ["streams": [
            ["name": "[RD+] Torrentio\n1080p", "title": "The Simpsons S11E02 1080p DSNP WEB-DL\n👤 30 💾 900 MB ⚙️ TorrentGalaxy", "url": .string("https://torrentio.example/resolve/realdebrid/K/\(Self.goodHash)/null/0/x.mkv")],
            ["name": "[RD download] Torrentio\n480p", "title": "Los Simpsons (Completa Latino) 24 !!\nTemporada 11/Los Simpsons 11x02 - El cambio de Bart.flv\n👤 15 💾 60.28 MB ⚙️ ThePirateBay\n🇲🇽",
             "url": .string("https://torrentio.example/resolve/realdebrid/K/\(Self.latinoHash)/null/36/x.flv")],
        ]]
        http.delays["\(Self.torrentio)/stream/series/\(Self.encoded).json"] = torrentioDelay
    }

    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    /// Torrentio llega después del plazo: la primera búsqueda sale con lo de Comet y lo dice («no contestó»), pero sus
    /// versiones se suman en cuanto llegan; la siguiente búsqueda (la de «Versión») ya trae el latino.
    func testASlowAddonIsNotLostItsVersionsAreAddedWhenTheyArrive() async throws {
        let http = FakeHTTP()
        serve(http, torrentioDelay: 700)
        let finder = makeFinder(http)
        let first = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        XCTAssertEqual(first.map(\.addon), ["Comet"], "precondición: sale con lo que llegó a tiempo")
        let quiet = await finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quiet, ["Torrentio"])
        let late = await finder.lateAnswers(kind: "series", videoID: Self.video)
        XCTAssertTrue(late, "Torrentio trajo versiones después")
        let second = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        XCTAssertEqual(second.count, 3, "se sumó lo de Torrentio sin volver a preguntar")
        XCTAssertTrue(second.contains { $0.audio.contains { $0.code == "es-419" } }, "el latino de Torrentio ya está")
        XCTAssertEqual(http.calls.filter { $0.contains("/stream/") }.count, 2, "una pregunta por complemento")
        let quietAfter = await finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quietAfter, [], "ya contestó: no se dice que no")
    }

    /// Uno que de plano no contesta (pasa su tope): sigue como «no contestó», sin esperar de más.
    func testAnAddonThatNeverAnswersStaysQuiet() async throws {
        let http = FakeHTTP()
        serve(http, torrentioDelay: 5000)
        let finder = makeFinder(http, limits: SearchLimits(perAddon: 0.5, origin: 0.2, readyLink: 0.2, total: 4, budget: 0.2))
        _ = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        let late = await finder.lateAnswers(kind: "series", videoID: Self.video)
        XCTAssertFalse(late)
        let quiet = await finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quiet, ["Torrentio"])
    }

    /// La bitácora dice qué dio cada complemento, cuánto tardó y si llegó tarde (sin direcciones).
    func testTheLogSaysWhatEachAddonGaveAndHowLongItTook() async throws {
        let http = FakeHTTP(), notes = Notes()
        serve(http, torrentioDelay: 500)
        let finder = makeFinder(http)
        await finder.configureNotes { notes.add($0) }
        _ = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        _ = await finder.lateAnswers(kind: "series", videoID: Self.video)
        let lines = notes.all
        XCTAssertTrue(lines.contains { $0.hasPrefix("complemento Comet: 1 versiones en ") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("complemento Torrentio: sigue buscando") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("complemento Torrentio: 2 versiones en ") && $0.hasSuffix("(llegó tarde: se suman)") }, "\(lines)")
        XCTAssertFalse(lines.contains { $0.contains("http") }, "nunca una dirección (llevan tu clave)")
    }

    /// «Reintentar»: se les pregunta a todos otra vez, también al que se saltaba por no contestar.
    func testRetryAsksEveryoneAgainEvenTheSkippedOne() async throws {
        let http = FakeHTTP(), health = AddonHealth()
        serve(http, torrentioDelay: 0)
        health.fail("\(Self.torrentio)/manifest.json"); health.fail("\(Self.torrentio)/manifest.json")
        let finder = makeFinder(http, health: health)
        let skipped = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        XCTAssertEqual(skipped.map(\.addon), ["Comet"], "precondición: Torrentio se saltaba")
        let quiet = await finder.quiet(kind: "series", videoID: Self.video)
        XCTAssertEqual(quiet, ["Torrentio"])
        await finder.retryQuiet(kind: "series", videoID: Self.video)
        let again = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        XCTAssertEqual(again.count, 3)
    }

    /// Aprender de lo ya abierto: un episodio de un paquete trajo latino (lo comprobado al verlo o al revisarlo); los demás
    /// episodios del mismo paquete salen «probable latino» (`sibling`), no «comprobado».
    func testAnotherEpisodeOfTheSamePackIsProbablyInTheSameLanguages() async throws {
        let http = FakeHTTP()
        let pack = String(repeating: "c", count: 40)
        http.json["\(Self.comet)/stream/series/\(Self.encoded).json"] = ["streams": []]
        http.json["\(Self.torrentio)/stream/series/\(Self.encoded).json"] = ["streams": [
            ["name": "[RD+] Torrentio\n1080p", "title": "The.Simpsons.S01.to.S35.MULTi-VF2-ESP.1080p.DSNP.EAC3.DD5.1.x265-NFW\nThe Simpsons - S11E02 - Brother's Little Helper.mkv\n👤 2 💾 414.6 MB ⚙️ EXT\nMulti Audio",
             "url": .string("https://torrentio.example/resolve/realdebrid/K/\(pack)/null/250/x.mkv")],
        ]]
        let finder = makeFinder(http)
        let store = TitlePreferences(InMemoryKeyValueStore())
        store.rememberChecked(key: "Torrentio|other-episode|", codes: ["en", "es-419", "fr"], pack: pack)
        await finder.configure(origin: { _, _ in nil }, checked: { store.checkedAudio($0) })
        let found = try await finder.find(kind: "series", videoID: Self.video, prefs: latino)
        let audio = try XCTUnwrap(found.first?.audio)
        XCTAssertTrue(audio.contains { $0.code == "es-419" && $0.evidence == .sibling }, "\(audio)")
        XCTAssertFalse(audio.contains { $0.evidence == .checked }, "no se abrió este: no es «comprobado»")
        XCTAssertEqual(found.first?.dub, "latino")
    }
}
