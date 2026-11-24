import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Arranque rápido (23 nov 2026): los tramos de «Ver» al primer cuadro y la dirección final de Torrentio.
@MainActor
final class PlayerStartupTests: XCTestCase {
    func testTheSummarySaysHowLongEachStageTook() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var stages = StartupStages(at: t0)
        stages.mark(.found, at: t0.addingTimeInterval(0.02))
        stages.mark(.chosen, at: t0.addingTimeInterval(0.03))
        stages.mark(.link, at: t0.addingTimeInterval(0.22))
        stages.mark(.opened, at: t0.addingTimeInterval(2.72))
        stages.mark(.opened, at: t0.addingTimeInterval(9))   // un reintento no mueve la primera marca
        XCTAssertNil(stages.summary(), "todavía no suena")
        stages.mark(.playing, at: t0.addingTimeInterval(3.32))
        stages.link = "ya resuelta"
        XCTAssertEqual(stages.summary(), "arranque: buscar 0.02 · elegir 0.01 · enlace 0.19 · abrir 2.50 · primer cuadro 0.60 · total 3.32 s (ya resuelta)")
        var notStarted = StartupStages()
        notStarted.mark(.playing, at: t0)
        XCTAssertNil(notStarted.summary(), "un cambio de versión o volver a la app no es el arranque")
    }

    let addonLink = "https://a.example/resolve/realdebrid/K/\(String(repeating: "1", count: 40))/null/0/x.mkv"

    func rig(final: String?) throws -> Rig {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("best", url: addonLink)]]
        let target = final.flatMap(URL.init(string:))
        rig.model.links = StreamLinks(resolver: { _ in target })
        return rig
    }

    func testPlayOpensTheFinalAddressInsteadOfGoingThroughTheAddon() async throws {
        let rig = try rig(final: "https://cdn.example/d/ID/x.mkv")
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://cdn.example/d/ID/x.mkv"])
        await rig.model.handle(rig.playing(0))
        XCTAssertEqual(rig.model.startup, StartupStages(), "la línea del arranque sale una vez y se limpia")
    }

    func testIfTheFinalAddressDoesNotOpenTheAddonLinkIsUsed() async throws {
        let rig = try rig(final: "https://cdn.example/d/ID/x.mkv")
        rig.engine.failing = ["https://cdn.example/d/ID/x.mkv"]
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), ["https://cdn.example/d/ID/x.mkv", addonLink], "la misma versión, por el complemento")
    }

    func testWithoutAResolutionTheAddonLinkOpensAsBefore() async throws {
        let rig = try rig(final: nil)
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.map(\.url.absoluteString), [addonLink])
    }

    func testAVersionTheCloudIsStillDownloadingIsNeverResolved() async throws {
        let rig = try rig(final: "https://cdn.example/d/ID/x.mkv")
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("best", url: addonLink, name: "T\n1080p [RD download]")]]
        await rig.model.begin(rig.request())
        XCTAssertFalse(rig.engine.loads.map(\.url.absoluteString).contains("https://cdn.example/d/ID/x.mkv"), "su redirección es el video de aviso")
    }
}
