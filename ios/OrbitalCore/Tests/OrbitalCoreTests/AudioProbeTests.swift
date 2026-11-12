import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// «Revisar por dentro» (Fernando, 12 nov: «Sí, vamos a hacer la 2»): leer las pistas de audio del encabezado de un MKV sin
/// abrirlo, y solo de las versiones donde vale la pena y no le cuesta nada a Real-Debrid.
final class AudioProbeTests: XCTestCase {
    func source(_ stream: String, addon: String = "Comet", index: Int = 0) -> Source {
        Streams.parse(JSON.parse(Data(stream.utf8))!, addon: addon, transportURL: "https://comet.example", index: index)
    }

    // MARK: El encabezado

    func testTheHeaderSaysWhichAudioTracksTheFileHas() {
        let head = MatroskaTracks.sampleHeader(audio: [("eng", "English"), ("spa", "Español Latino")])
        guard case .tracks(let tracks) = MatroskaTracks.read(head: head) else { return XCTFail("debió leer las pistas") }
        let audio = tracks.filter { $0.kind == .audio }
        XCTAssertEqual(audio.map(\.language), ["eng", "spa"])
        XCTAssertEqual(audio.last?.title, "Español Latino")
    }

    func testWhenTheIndexPointsElsewhereItSaysWhere() {
        let file = MatroskaTracks.sampleHeader(audio: [("eng", nil), ("fre", nil)], seekOnly: true, padding: 4096)
        let head = file.prefix(1024)   // lo leído no alcanza a las pistas: solo su índice
        guard case .elsewhere(let offset) = MatroskaTracks.read(head: head) else { return XCTFail("debió decir dónde están") }
        XCTAssertGreaterThan(offset, 1024)
        let tracks = MatroskaTracks.read(tracksAt: file.subdata(in: Int(offset)..<file.count))
        XCTAssertEqual(tracks?.map(\.language), ["eng", "fre"], "y de ahí se leen")
    }

    func testSomethingThatIsNotAnMKVIsUnknown() {
        XCTAssertEqual(MatroskaTracks.read(head: Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8)), .unknown)
        XCTAssertEqual(MatroskaTracks.read(head: Data()), .unknown)
        XCTAssertEqual(MatroskaTracks.read(head: Data([0x1A, 0x45, 0xDF])), .unknown, "cortado: no truena")
    }

    // MARK: Leer con «Range»

    func testItReadsOnlyThePieceItNeedsAndRemembersItTried() async {
        let http = FakeHTTP()
        let url = "https://comet.example/p/multi.mkv"
        http.raw[url] = MatroskaTracks.sampleHeader(audio: [("eng", "English"), ("spa", "Latino")])
        http.status = 206
        let probe = AudioProbe(reader: HTTPRangeReader(http: http))
        let multi = source(#"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.S01E02.MULTi.1080p.mkv", "url": "\#(url)"}"#)
        let tracks = await probe.audioTracks(of: multi)
        XCTAssertEqual(tracks?.filter { $0.kind == .audio }.count, 2)
        XCTAssertTrue(probe.tried(multi.key), "no se repite")
        XCTAssertTrue(http.headers.last?["Range"]?.hasPrefix("bytes=0-") == true, "solo un pedazo del principio")
    }

    func testAServerThatSendsTheWholeFileIsNotUsed() async {
        let http = FakeHTTP()
        let url = "https://comet.example/p/big.mkv"
        http.raw[url] = Data(count: AudioProbe.headBytes + 10)
        http.status = 200
        let probe = AudioProbe(reader: HTTPRangeReader(http: http))
        let big = source(#"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.mkv", "url": "\#(url)"}"#)
        let tracks = await probe.audioTracks(of: big)
        XCTAssertNil(tracks)
    }

    // MARK: Cuáles se revisan

    let instantMulti = #"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.S01E02.MULTi.1080p.WEB.mkv", "url": "https://comet.example/p/1"}"#
    let instantPlain = #"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.S01E02.1080p.WEB.mkv", "url": "https://comet.example/p/2"}"#
    let instantMP4 = #"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.S01E02.1080p.WEB.mp4", "url": "https://comet.example/p/3"}"#
    let toDownload = #"{"name": "Torrentio\n[RD download] 1080p", "title": "Show.S01E02.MULTi.1080p.mkv", "url": "https://torrentio.example/resolve/realdebrid/K/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/null/0/x.mkv"}"#
    let instantLatino = #"{"name": "[RD⚡] Comet 1080p", "description": "📄 Show.S01E02.1080p.Latino.mkv", "url": "https://comet.example/p/4"}"#

    func testOnlyInstantMKVsWithDoubtfulAudioAndNeverOneToDownload() {
        let ranked = [instantMulti, instantMP4, toDownload, instantPlain].enumerated().map { source($1, index: $0) }
        let picks = AudioProbe.candidates(ranked, wanted: "es-419", tried: { _ in false })
        XCTAssertFalse(picks.contains { !$0.instant }, "pedir el enlace de una por bajar se la pide a Real-Debrid")
        XCTAssertFalse(picks.contains { $0.release.lowercased().contains("mp4") || ($0.playbackURL?.path ?? "").hasSuffix("/3") }, "solo MKV")
        XCTAssertEqual(picks.count, 2)
    }

    func testNothingIsCheckedWhenYourLanguageIsAlreadyThereOrAlreadyTried() {
        let withLatino = [instantMulti, instantLatino].enumerated().map { source($1, index: $0) }
        XCTAssertEqual(AudioProbe.candidates(withLatino, wanted: "es-419", tried: { _ in false }), [], "ya hay latino al instante")
        let ranked = [instantMulti, instantPlain].enumerated().map { source($1, index: $0) }
        XCTAssertEqual(AudioProbe.candidates(ranked, wanted: "es-419", tried: { _ in true }), [], "lo intentado no se repite")
        let many = (0..<8).map { source(instantPlain.replacingOccurrences(of: "/p/2", with: "/p/x\($0)"), index: $0) }
        XCTAssertEqual(AudioProbe.candidates(many, wanted: "es-419", tried: { _ in false }).count, AudioProbe.limit, "pocas")
    }
}
