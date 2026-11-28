import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Revisión del 28 nov 2026: conectar otra cuenta de Trakt no mezcla lo de la anterior.
@MainActor
final class TraktAccountChangeTests: XCTestCase {
    func testAnotherAccountDropsWhatWaitedForTheOldOne() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let model = SettingsModel(rig.services)
        await model.forgetIfAnotherAccount("ana")
        rig.services.traktOutbox.enqueue(.rating(imdb: "tt1", series: false, 8))
        await model.forgetIfAnotherAccount("ana")
        XCTAssertEqual(rig.services.traktOutbox.pending.count, 1, "la misma cuenta: lo pendiente se queda")
        await model.forgetIfAnotherAccount("beto")
        XCTAssertTrue(rig.services.traktOutbox.pending.isEmpty, "otra cuenta: no se manda a esta lo de la anterior")
    }
}
