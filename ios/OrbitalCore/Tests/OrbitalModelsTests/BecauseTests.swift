import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Porque viste»: cambiar de título se siente al momento (el mazo no espera a Trakt), las relacionadas de los demás se
/// traen de antemano y una respuesta que llega tarde no pisa el título en el que ya estás.
@MainActor
final class BecauseTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let shows = [("tt0386676", "The Office", "tt1266020"), ("tt14452776", "The Bear", "tt15677150"), ("tt11280740", "Severance", "tt14688458")]

    func rig() throws -> ServicesRig {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/sync/history?limit=40&extended=full"] = .array(shows.enumerated().map { i, s in
            ["type": "episode", "watched_at": .string("2025-10-0\(i + 1)T20:00:00.000Z"),
             "show": ["title": .string(s.1), "year": 2020, "ids": ["imdb": .string(s.0)]]]
        })
        for s in shows {
            rig.http.json["\(api)/shows/\(s.0)/related?limit=15&extended=full"] = [["title": "Relacionada", "year": 2021, "ids": ["imdb": .string(s.2)]]]
        }
        return rig
    }

    func relatedCalls(_ rig: ServicesRig, _ imdb: String) -> Int { rig.http.calls.filter { $0.contains("/shows/\(imdb)/related") }.count }

    func waitForPreload(_ model: ParaTiModel, count: Int) async {
        for _ in 0..<200 where model.becausePreloaded.count < count { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testTheHistoryKnowsWhenYouWatchedIt() async throws {
        let rig = try rig()
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.becauseSeeds.map(\.imdb), shows.map(\.0))
        XCTAssertNotNil(model.becauseSeeds.first?.watchedAt, "para «la viste hace 3 días»")
        XCTAssertEqual(model.becauseSelected, model.because?.seed.imdb)
    }

    func testTheOtherTitlesArePreloadedSoSwitchingIsInstant() async throws {
        let rig = try rig()
        let model = ParaTiModel(rig.services)
        await model.load()
        await waitForPreload(model, count: shows.count)
        XCTAssertEqual(Set(model.becausePreloaded.keys), Set(shows.map(\.0)), "todas traídas de antemano")
        let other = try XCTUnwrap(model.becauseSeeds.first { $0.imdb != model.because?.seed.imdb })
        let before = relatedCalls(rig, other.imdb)
        await model.chooseBecause(other)
        XCTAssertEqual(model.becauseSelected, other.imdb)
        XCTAssertEqual(model.because?.seed.imdb, other.imdb)
        XCTAssertEqual(model.because?.items.map(\.imdb), [shows.first { $0.0 == other.imdb }!.2])
        XCTAssertEqual(relatedCalls(rig, other.imdb), before, "ya estaba: no se vuelve a pedir")
    }

    func testTheDeckMovesBeforeTraktAnswersAndALateAnswerDoesNotWin() async throws {
        let rig = try rig()
        let model = ParaTiModel(rig.services)
        await model.load()
        let seeds = model.becauseSeeds
        let current = try XCTUnwrap(model.because?.seed.imdb)
        let others = seeds.filter { $0.imdb != current }
        let (slow, fast) = (others[0], others[1])
        // Sin nada traído de antemano y con la primera respuesta lenta.
        await waitForPreload(model, count: shows.count)
        model.forgetPreloadedForTesting()
        await rig.services.forYou.clearCache()
        rig.http.delays["\(api)/shows/\(slow.imdb)/related?limit=15&extended=full"] = 300
        let first = Task { await model.chooseBecause(slow) }
        await Task.yield()
        XCTAssertEqual(model.becauseSelected, slow.imdb, "el mazo cambia al tocar, sin esperar a Trakt")
        XCTAssertEqual(model.because?.seed.imdb, current, "sus relacionadas aún no llegan (la tarjeta pone su lugar)")
        await model.chooseBecause(fast)   // pasaste a otro mientras tanto
        await first.value                  // la lenta llega después
        XCTAssertEqual(model.becauseSelected, fast.imdb)
        XCTAssertEqual(model.because?.seed.imdb, fast.imdb, "la respuesta que llegó tarde no pisa la que se ve")
    }

    func testATitleWithoutRelatedSaysSoInsteadOfKeepingThePreviousOnes() async throws {
        let rig = try rig()
        let model = ParaTiModel(rig.services)
        await model.load()
        await waitForPreload(model, count: shows.count)
        let current = try XCTUnwrap(model.because?.seed.imdb)
        let other = try XCTUnwrap(model.becauseSeeds.first { $0.imdb != current })
        model.forgetPreloadedForTesting()
        await rig.services.forYou.clearCache()
        rig.http.json["\(api)/shows/\(other.imdb)/related?limit=15&extended=full"] = []
        await model.chooseBecause(other)
        XCTAssertEqual(model.because?.seed.imdb, other.imdb)
        XCTAssertEqual(model.because?.items, [], "vacía: la tarjeta dice que Trakt no relaciona nada (antes se quedaban las del anterior)")
    }
}
