import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// R5/R6: los avisos de Torrentio no son versiones, un reintento nunca le pide otra descarga a Real-Debrid y lo que ya se
/// pidió no se pide dos veces.
@MainActor
final class RealDebridRetryTests: XCTestCase {
    let video = "tt0386676:1:1"

    func testARetryNeverOpensAVersionRealDebridWouldHaveToDownload() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            rig.stream("best"), rig.stream("download", size: "💾 2.1 GB", name: "T\n1080p [RD download]"), rig.stream("other", size: "💾 2.4 GB")]]
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.notice, .triedAnotherSource(attempt: 2, of: 2), "solo cuenta las que arrancan al instante")
        await rig.model.handle(rig.playing(0, state: .failed("403")))
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.engine.loads.map(\.url.lastPathComponent), ["best.mkv", "other.mkv"], "la «[RD download]» no se abre")
        XCTAssertEqual(rig.model.failure, .noneWorked)
    }

    func testTheRDErrorVersionIsNeverOfferedAndAsksRealDebridWhatHappened() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "Torrentio\nRD error", "title": "Invalid RealDebrid account", "url": "https://torrentio.strem.fun/videos/failed_access_v2.mp4"]),
            rig.stream("download", name: "T\n1080p [RD download]")]]
        let asked = Counter()
        let expired = DebridStatus(service: "Real-Debrid", username: "x", isPremium: false, expires: rig.clock.now.addingTimeInterval(-2 * 86_400), checkedAt: rig.clock.now)
        rig.model.debridTrouble = { asked.add(); return .status(expired) }
        await rig.model.begin(rig.request())
        XCTAssertFalse(rig.model.sourceChoices.contains { $0.notice != nil }, "el aviso no es una versión")
        XCTAssertEqual(rig.model.lastNotice, .access)
        XCTAssertEqual(asked.value, 1, "se le preguntó a Real-Debrid")
        XCTAssertEqual(rig.model.debridHealth, .status(expired))
        XCTAssertEqual(rig.model.cause, .debridExpired, "el reproductor dice «Tu Real-Debrid venció» con «Renovar»")
    }

    func testABlockedFileSaysRealDebridDidNotLetIt() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "Torrentio\n[RD download] 1080p", "title": "x", "url": "https://torrentio.strem.fun/videos/failed_infringement_v3.mp4"])]]
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.model.failure, .noSources)
        XCTAssertEqual(rig.model.cause, .debridRefused)
    }

    func testAVersionAlreadyAskedForIsNotAskedForAgain() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("download", name: "T\n1080p [RD download]")]]
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.count, 1, "la primera vez se abre: así se le pide")
        await rig.model.handle(rig.playing(0, duration: 30))   // su video de «descargando»
        await rig.model.waitForTransition()
        XCTAssertEqual(rig.model.lastNotice, .downloading)
        XCTAssertEqual(rig.model.failure, .noSources)
        await rig.model.retry()
        XCTAssertEqual(rig.engine.loads.count, 1, "«Reintentar» no la vuelve a pedir")
        XCTAssertEqual(rig.model.lastNotice, .downloading, "dice que ya está pedida")
        XCTAssertEqual(rig.model.cause, .notInDebrid(language: "es-419"), "sin variante marcada, tu lista de fábrica: latino primero")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
