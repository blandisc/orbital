import XCTest
@testable import OrbitalModels

/// Revisión 2 del 11 nov: «4K · DV · 14,8 GB» y «4K · DV · HDR · Atmos · DD+» no se entendían. En el renglón y en Detalles va
/// en llano; las siglas, en el nombre técnico al abrir el renglón.
final class PlainQualityTests: XCTestCase {
    func testPictureInPlainWords() {
        XCTAssertEqual(AllSources.pictureWords(["DV", "HDR"]), "Dolby Vision")
        XCTAssertEqual(AllSources.pictureWords(["HDR10+"]), "HDR")
        XCTAssertNil(AllSources.pictureWords([]))
    }

    func testSoundInPlainWords() {
        XCTAssertEqual(AllSources.soundWords(["Atmos", "DD+"]), "Dolby Atmos")
        XCTAssertEqual(AllSources.soundWords(["DD+"]), "sonido envolvente")
        XCTAssertEqual(AllSources.soundWords(["5.1"]), "sonido envolvente")
        XCTAssertNil(AllSources.soundWords([]))
    }

    func testDetailsLineHasNoAcronymSoup() {
        let line = AllSources.plainQuality(resolution: "4K", hdr: ["DV", "HDR"], audio: ["Atmos", "DD+"])
        XCTAssertEqual(line, ["4K", "Dolby Vision", "Dolby Atmos"])
        for acronym in ["DV", "DD+", "HDR"] { XCTAssertFalse(line.contains(acronym), acronym) }
    }
}
