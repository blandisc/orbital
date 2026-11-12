import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Lo que ya suena no se cambia solo por otra versión salvo que de verdad falle (Fernando, 12 nov: en la bitácora del iPhone
/// el video ya sonaba y un segundo después salía «Probando otra versión… Sigue en el mismo punto» y volvía a cargar el mismo
/// archivo desde 0). El motor dice un momento una duración corta (lo que lleva leído, no el episodio) y eso se tomaba por el
/// aviso de «descargando» de Real-Debrid.
@MainActor
final class RetryOnlyWhenItFailsTests: XCTestCase {
    let page = "https://a.example/stream/series/tt0386676%3A1%3A1.json"
    let dualLat = "The.Office.S01E01.1080p-Dual-Lat.mkv"

    /// La misma versión en dos torrents (el mismo archivo) y otra distinta, las tres ya en Real-Debrid.
    func rig() throws -> Rig {
        let rig = try Rig()
        func file(_ id: String, _ filename: String, _ quality: String = "1080p") -> JSON {
            .object(["name": .string("Comet\n\(quality) [RD+]"), "title": .string("📄 \(filename)\n💾 1.2 GB"),
                     "url": .string("https://rd.example/\(id).mkv"), "behaviorHints": ["filename": .string(filename)]])
        }
        rig.http.json[page] = ["streams": [file("dual", dualLat), file("dual-copy", dualLat), file("other", "The.Office.S01E01.720p.WEB-DL.mkv", "720p")]]
        return rig
    }

    func testAVersionThatAlreadyPlaysIsNotSwitchedForAShortReading() async throws {
        let rig = try rig()
        await rig.model.begin(rig.request())
        let first = try XCTUnwrap(rig.model.source)
        await rig.model.handle(rig.playing(0, duration: 0))   // suena: el motor aún no sabe cuánto dura
        XCTAssertEqual(rig.model.phase, .playing)
        // Un segundo después dice lo que lleva leído (8 s, luego 16 s) antes que lo que dura el episodio.
        for (second, length) in [(1.0, 8.0), (2, 16), (3, 24), (4, 1320)] {
            rig.clock.advance(1)
            await rig.model.handle(rig.playing(second, duration: length))
        }
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.count, 1, "no se vuelve a cargar nada")
        XCTAssertTrue(rig.model.failedSources.isEmpty, "no se marca como fallida")
        XCTAssertNotEqual(rig.model.notice, .triedAnotherSource(attempt: 2, of: 2), "sin «Probando otra versión»")
        XCTAssertEqual(rig.model.source?.index, first.index)
        XCTAssertEqual(rig.model.phase, .playing)
    }

    /// La secuencia de la bitácora: suena → cambias a otra versión (o el audio la vuelve a abrir) → suena → lectura corta.
    func testAfterAReloadThatPlaysAShortReadingDoesNotSwitchEither() async throws {
        let rig = try rig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, duration: 1320))
        rig.clock.advance(3)
        let other = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("WEB-DL") })
        await rig.model.switchSource(to: other.index)
        await rig.model.handle(rig.playing(1, duration: 0))   // la recarga suena
        rig.clock.advance(1)
        await rig.model.handle(rig.playing(2, duration: 6))   // y un segundo después, la lectura corta
        rig.clock.advance(1)
        await rig.model.handle(rig.playing(3, duration: 1320))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.count, 2, "solo la recarga que pediste")
        XCTAssertEqual(rig.model.source?.index, other.index, "se queda con la que suena")
        XCTAssertTrue(rig.model.failedSources.isEmpty)
    }

    /// El aviso de verdad (una duración corta que no cambia) sigue detectándose, también en una «ya en Real-Debrid»; y la
    /// siguiente nunca es el mismo archivo desde otro torrent.
    func testTheRealNoticeIsStillCaughtAndTheSameFileIsNotTriedAgain() async throws {
        let rig = try rig()
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.last?.url.lastPathComponent, "dual.mkv")
        for second in 0...Int(PlayerModel.placeholderConfirmSeconds) {
            await rig.model.handle(rig.playing(Double(second), duration: 30))
            rig.clock.advance(1)
        }
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.map(\.url.lastPathComponent), ["dual.mkv", "other.mkv"], "ni «dual-copy»: es el mismo archivo")
    }

    func testIfOnlyTheSameFileIsLeftItIsNotReloadedFromZero() async throws {
        let rig = try Rig()
        func file(_ id: String) -> JSON {
            .object(["name": "Comet\n1080p [RD+]", "title": .string("📄 \(dualLat)\n💾 1.2 GB"), "url": .string("https://rd.example/\(id).mkv"),
                     "behaviorHints": ["filename": .string(dualLat)]])
        }
        rig.http.json[page] = ["streams": [file("dual"), file("dual-copy")]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("se cortó")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.count, 1, "el mismo archivo desde otro enlace no es «otra versión»")
        XCTAssertEqual(rig.model.failure, .noneWorked)
    }

    /// Regla: toda versión que se da por fallida pasa por `markFailed`, que lo anota en la bitácora con su motivo.
    func testEveryFailedMarkGoesThroughTheLoggedHelper() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        dir.appendPathComponent("Sources/OrbitalModels")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 5)
        var offenders: [String] = []
        for file in files where file.lastPathComponent != "PlayerModel+Failures.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("failedSources.insert(") || text.contains("failedSources.formUnion(") { offenders.append(file.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "marca la versión con `markFailed(_:_:)` (anota el motivo en la bitácora)")
    }
}
