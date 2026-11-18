import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// LN2 · Fernando, 18 nov, Los Simpson T37E3: la única latina («The.Simpsons.S37.1080p.WEB-DL.H.264.LAT.ENG-LATPOW») la pidió
/// el iPhone y Real-Debrid la rechazó (error 35). Salía el inglés sin explicación y parecía que Orbital no había encontrado el
/// latino. Regla: si la única de tu idioma la rechazó Real-Debrid, «Versión» lo dice («Hay latino, pero Real-Debrid no lo dejó
/// bajar»), sin ofrecer pedirla otra vez. La TV lo dice en la nota de la ficha.
@MainActor
final class LatinoRechazadoTests: XCTestCase {
    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    func source(_ json: JSON, index: Int, addon: String = "Comet") -> Source {
        Streams.parse(json, addon: addon, transportURL: "https://c.example", index: index)
    }

    /// Inglés al instante (Comet).
    var english: Source {
        source(["name": "[RD⚡] Comet 1080p", "description": "📄 The.Simpsons.S37E03.1080p.WEB.h264-ETHEL.mkv\n💾 900 MB", "url": "https://c.example/p/ethel.mkv"], index: 0)
    }

    /// La latina de Torrentio sin Real-Debrid, ya rechazada.
    func latinoRefused(index: Int = 1) -> Source {
        var s = source(["name": "Torrentio\n1080p", "title": "The.Simpsons.S37.1080p.WEB-DL.H.264.LAT.ENG-LATPOW\n👤 4 💾 9.8 GB ⚙️ 1337x\n🇲🇽 / 🇬🇧",
                        "infoHash": "f2784cb76a7f71e9432bc598e00b6ac17e61c9f1"], index: index, addon: "Torrentio")
        s.debrid = true; s.cached = false; s.refused = true
        return s
    }

    func testTheOnlyLatinoRefusedIsSaid() {
        let found = [english, latinoRefused()]
        XCTAssertTrue(SourcesModel.speaksYours(latinoRefused(), prefs: latino), "precondición: «LAT» suena seguro en latino")
        XCTAssertNil(SourcesModel.yoursToRequest(Streams.rank(found, prefs: latino, kind: "series"), rows: [], prefs: latino, limitGB: 5),
                     "rechazada: no se ofrece pedirla")
        XCTAssertEqual(SourcesModel.yoursRefused(found, prefs: latino), "es-419")
    }

    func testLatinoThatStartsNowSaysNothing() {
        let now = source(["name": "[RD⚡] Comet 1080p", "description": "📄 Simpsons.S37E03.1080p-Dual-Lat.mkv", "url": "https://c.example/p/lat.mkv"], index: 2)
        XCTAssertNil(SourcesModel.yoursRefused([english, latinoRefused(), now], prefs: latino), "hay latino al instante: nada que explicar")
    }

    func testNothingRefusedSaysNothing() {
        var pending = latinoRefused()
        pending.refused = false
        XCTAssertNil(SourcesModel.yoursRefused([english, pending], prefs: latino), "se puede pedir: eso lo dice «hay que pedirlo»")
        XCTAssertNil(SourcesModel.yoursRefused([english], prefs: latino), "no existe en latino: no hay rechazo que contar")
    }

    func testARefusedOtherLanguageSaysNothing() {
        var other = source(["name": "Torrentio\n1080p", "title": "The.Simpsons.S37E03.1080p.WEB-DL.FRENCH\n💾 1 GB\n🇫🇷",
                            "infoHash": .string(String(repeating: "9", count: 40))], index: 3, addon: "Torrentio")
        other.refused = true
        XCTAssertNil(SourcesModel.yoursRefused([english, other], prefs: latino))
    }
}
