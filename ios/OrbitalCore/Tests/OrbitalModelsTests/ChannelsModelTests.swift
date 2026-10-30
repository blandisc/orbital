import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Canales: qué episodios entran (ya estrenados, sin especiales), cuánto dura cada uno y que elegir se guarde.
@MainActor
final class ChannelsModelTests: XCTestCase {
    let pick = ChannelsModel.Pick(id: "tt0096697", title: "Los Simpson", poster: "p")
    let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!

    func meta(runtime: String) -> JSON {
        func video(_ s: Int, _ e: Int, _ name: String, _ released: String) -> JSON {
            ["id": .string("tt0096697:\(s):\(e)"), "season": .int(s), "episode": .int(e), "name": .string(name),
             "thumbnail": .string("https://episodes/\(s)/\(e).jpg"), "released": .string(released)]
        }
        return ["runtime": .string(runtime), "logo": "https://logo", "videos": [
            video(1, 1, "Simpsons Roasting on an Open Fire", "1989-12-17T00:00:00.000Z"),
            video(1, 2, "Bart the Genius", "1990-01-14T00:00:00.000Z"),
            video(0, 1, "Especial", "1990-01-01T00:00:00.000Z"),
            video(38, 1, "Futuro", "2027-01-01T00:00:00.000Z"),
        ]]
    }

    func testSoloEpisodiosEstrenadosYSinEspeciales() throws {
        let channel = try XCTUnwrap(ChannelsModel.channel(pick, meta: meta(runtime: "24 min"), now: now))
        XCTAssertEqual(channel.episodes.map(\.videoID), ["tt0096697:1:1", "tt0096697:1:2"])
        XCTAssertEqual(channel.episodes.first?.still, "https://episodes/1/1.jpg")
        XCTAssertEqual(channel.episodes.first?.name, "Simpsons Roasting on an Open Fire")
        XCTAssertEqual(channel.length, 24 * 60)
        XCTAssertEqual(channel.logo, "https://logo")
    }

    func testSinDuracionUsaLaDeSiempre() throws {
        let channel = try XCTUnwrap(ChannelsModel.channel(pick, meta: meta(runtime: ""), now: now))
        XCTAssertEqual(channel.length, TimeInterval(ChannelsModel.defaultMinutes * 60))
    }

    func testArrancaConLosDeSiempreYElegirSeGuarda() throws {
        let rig = try ServicesRig()
        let model = ChannelsModel(rig.services)
        XCTAssertEqual(model.picks, ChannelsModel.starters)
        let extra = ChannelsModel.suggested[0]
        model.toggle(extra)
        model.toggle(ChannelsModel.starters[0])
        XCTAssertFalse(model.suggestions.contains(extra))
        let again = ChannelsModel(rig.services)
        XCTAssertEqual(again.picks.map(\.id), ChannelsModel.starters.dropFirst().map(\.id) + [extra.id])
    }
}
