import XCTest
@testable import OrbitalModels

/// `TitleCommands` (⌘↩, ⌘D, ⌥⌘V en iPad y Mac): igual mientras es la misma ficha (sin repintado sin fin), distinto en cuanto
/// cambia el título (para que el teclado actúe sobre la ficha que ves, no sobre la primera que abriste).
final class TitleCommandsTests: XCTestCase {
    func commands(_ metaID: String, kind: String = "movie", log: @escaping (String) -> Void) -> TitleCommands {
        TitleCommands(kind: kind, metaID: metaID, play: { log("play \(metaID)") }, save: { log("save \(metaID)") }, versions: { log("versions \(metaID)") })
    }

    func testLaMismaFichaSigueIgualAunqueSusFuncionesSeanNuevas() {
        let a = commands("tt1", log: { _ in }), b = commands("tt1", log: { _ in })
        XCTAssertEqual(a, b, "en cada pasada de la misma ficha: no cuenta como cambio (no repinta todo)")
    }

    func testOtraFichaCuentaComoCambio() {
        XCTAssertNotEqual(commands("tt1", log: { _ in }), commands("tt2", log: { _ in }))
        XCTAssertNotEqual(commands("tt1", kind: "movie", log: { _ in }), commands("tt1", kind: "series", log: { _ in }))
    }

    /// Lo que pasaba: con «siempre igual», quien guarda el valor solo lo cambia si `!=`, y ⌘↩ ponía la primera ficha.
    func testElTecladoActuaSobreLaFichaQueVes() {
        var log: [String] = []
        var published: TitleCommands?
        func publish(_ new: TitleCommands) { if published != new { published = new } }   // como guarda SwiftUI un valor enfocado
        publish(commands("tt1", log: { log.append($0) }))
        publish(commands("tt2", log: { log.append($0) }))
        published?.play()
        XCTAssertEqual(log, ["play tt2"])
    }
}
