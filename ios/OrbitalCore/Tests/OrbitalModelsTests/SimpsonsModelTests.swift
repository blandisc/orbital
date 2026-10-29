import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Un Simpson al azar» sin interfaz (antes vivía dentro de `AppEnvironment`, sin pruebas).
@MainActor
final class SimpsonsModelTests: XCTestCase {
    private static let metaURL = "https://v3-cinemeta.strem.io/meta/series/tt0096697.json"

    private func meta(seasons: [Int], episodesPerSeason: Int = 3) -> JSON {
        var videos: [JSON] = []
        for season in seasons {
            for episode in 1...episodesPerSeason {
                videos.append(["id": .string("tt0096697:\(season):\(episode)"), "season": .int(season), "episode": .int(episode), "title": .string("Capítulo \(season)-\(episode)")])
            }
        }
        return ["name": "The Simpsons", "videos": .array(videos)]
    }

    private func rig(seasons: [Int] = [1, 5, 6, 37]) throws -> (ServicesRig, SimpsonsModel) {
        let rig = try ServicesRig()
        rig.http.json[Self.metaURL] = ["meta": meta(seasons: seasons)]
        return (rig, SimpsonsModel(rig.services, reelLength: 3))
    }

    func testDrawPicksOnlyFromTheChosenSeasons() async throws {
        let (rig, model) = try rig()
        rig.services.settings.update { $0.simpsonsSeasons = [5, 6] }
        for _ in 0..<5 {
            let drawMaybe = await model.draw()
        let draw = try XCTUnwrap(drawMaybe)
            XCTAssertEqual(draw.reel.count, 3, "la tira trae `reelLength` canales, el último es el elegido")
            XCTAssertTrue(draw.reel.allSatisfy { [5, 6].contains($0.season) }, "solo de las temporadas de Ajustes")
            XCTAssertEqual(draw.name, "The Simpsons")
        }
    }

    func testDrawFallsBackToEverySeasonWhenNoneOfTheChosenExist() async throws {
        let (rig, model) = try rig(seasons: [1, 2])
        rig.services.settings.update { $0.simpsonsSeasons = [30] }
        let drawMaybe = await model.draw()
        let draw = try XCTUnwrap(drawMaybe)
        XCTAssertTrue(draw.reel.allSatisfy { [1, 2].contains($0.season) })
    }

    func testDrawReportsWhenCinemetaDoesNotAnswer() async throws {
        let rig = try ServicesRig()
        let model = SimpsonsModel(rig.services, reelLength: 3)
        var said: [String] = []
        model.onError = { text, _ in said.append(text) }
        let draw = await model.draw()
        XCTAssertNil(draw)
        XCTAssertEqual(said, ["No pude traer los episodios de Los Simpson"])
        _ = await model.draw(quiet: true)
        XCTAssertEqual(said.count, 1, "en silencio no avisa (el prefetch)")
    }

    func testPrefetchWarmsTheStillsAndTakeServesItWithoutTheNetwork() async throws {
        let (rig, model) = try rig()
        var warmed: [String] = []
        model.warmImages = { warmed = $0 }
        await model.prefetch()
        XCTAssertEqual(warmed.count, 3)
        XCTAssertTrue(warmed.allSatisfy { $0.hasPrefix("https://episodes.metahub.space/tt0096697/") })

        rig.http.offline = true
        let servedMaybe = await model.take()
        let served = try XCTUnwrap(servedMaybe)
        XCTAssertEqual(model.servedFromPrefetch, 1, "el que estaba listo, sin salir a la red")
        XCTAssertEqual(served.reel.count, 3)
    }

    func testSeasonsChangedDiscardsTheReadyOne() async throws {
        let (rig, model) = try rig()
        await model.prefetch()
        model.seasonsChanged()
        rig.services.settings.update { $0.simpsonsSeasons = [37] }
        let draw = await model.take()
        XCTAssertEqual(model.servedFromPrefetch, 0, "el listo se descartó: se eligió otro de nuevo")
        XCTAssertTrue(draw?.reel.allSatisfy { $0.season == 37 } == true, "y el nuevo ya es de las temporadas nuevas")
    }

    func testRequestStartsFromTheBeginningStandingUpWithTheEpisodeLabel() async throws {
        let (rig, model) = try rig()
        rig.services.episodeLabel = { "T\($0) · E\($1)" }
        let drawMaybe = await model.draw()
        let draw = try XCTUnwrap(drawMaybe)
        let request = model.request(draw)
        XCTAssertEqual(request.kind, "series")
        XCTAssertEqual(request.metaID, SimpsonsModel.seriesID)
        XCTAssertEqual(request.videoID, draw.chosen.episode.id)
        XCTAssertTrue(request.fromStart)
        XCTAssertTrue(request.startPortrait)
        XCTAssertEqual(request.episodeLabel, "T\(draw.chosen.season) · E\(draw.chosen.episode.episode) · \(draw.chosen.episode.title)")
    }

    func testSeasonNumbersComeFromCinemetaOrTheKnownRange() async throws {
        let (_, model) = try rig(seasons: [3, 1, 2])
        let numbers = await model.seasonNumbers()
        XCTAssertEqual(numbers, [1, 2, 3])
        let offline = try ServicesRig()
        let fallback = await SimpsonsModel(offline.services, reelLength: 3).seasonNumbers()
        XCTAssertEqual(fallback, Array(1...SimpsonsModel.knownSeasons))
    }
}
