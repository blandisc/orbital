import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Tu año» (B2): lo trae el modelo; sin Trakt no hay año y la carga termina.
@MainActor
final class YearReviewModelTests: XCTestCase {
    func testSinTraktTerminaSinAno() async throws {
        let rig = try ServicesRig()
        let model = YearReviewModel(rig.services)
        XCTAssertTrue(model.loading)
        await model.load()
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.review)
        XCTAssertNil(model.lastDay)
    }

    func testUnAnoYaArmadoNoPideNadaYAbreEnElUltimoDia() async throws {
        let rig = try ServicesRig()
        let calendar = Calendar(identifier: .gregorian)
        let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }
        let plays = [TraktPlay(at: day(3), kind: "movie", imdb: "tt1", title: "Uno", minutes: 100, genres: []),
                     TraktPlay(at: day(20), kind: "movie", imdb: "tt2", title: "Dos", minutes: 90, genres: [])]
        let year = YearInReview.make(plays, year: 2026, calendar: calendar)
        let model = YearReviewModel(rig.services, preset: year)
        await model.load()
        XCTAssertEqual(model.review, year)
        XCTAssertEqual(model.lastDay, year.plays.keys.max())
        XCTAssertNotNil(model.lastDay)
        XCTAssertTrue(rig.http.calls.isEmpty, "la demostración no pide nada")
    }
}
