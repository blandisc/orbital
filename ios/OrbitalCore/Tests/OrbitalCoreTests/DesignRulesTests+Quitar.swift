import XCTest

/// «Lo que quitas se puede deshacer» (`docs/ios-interfaz.md`): todo «Quitar de …» de un título (Mi lista, una lista, favoritos,
/// Seguir viendo) avisa con «Deshacer». En el recorrido de la Mac (16 nov 2026) «Quitar de Seguir viendo» no lo tenía y Trakt
/// borraba tu avance en el momento; ahora sale de la fila al instante y del aparato hasta que el aviso ya se fue.
extension DesignRulesTests {
    /// Las listas de un título. Quitar un complemento o un pedido de Real-Debrid no entra: esos piden confirmación antes.
    static let titleLists = ["\"Quitar de Mi lista", "\"Quitar de esta lista", "\"Quitar de favoritos", "\"Quitar de Seguir viendo"]

    func testEveryRemoveFromAListOffersUndo() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var found = 0
        var missing: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in code.components(separatedBy: "\n").enumerated() where line.contains("Button") && Self.titleLists.contains(where: line.contains) {
                found += 1
                // Cada uno pasa por un camino con «Deshacer»: los de la ficha y los pósters (`onDismiss` → `env.remove`,
                // `removeFavorite`, `notifyListEdit`), los de Guardado (`removeFromList`) y los de Seguir viendo.
                let known = ["onDismiss(", "removeFromList(", "removeFromContinue(", "action: remove"]
                if !known.contains(where: line.contains) { missing.append("\(file.lastPathComponent):\(number + 1)") }
            }
        }
        XCTAssertGreaterThanOrEqual(found, 6, "se leyeron los «Quitar de …» de ios/App/Sources")
        XCTAssertEqual(missing, [], "«Quitar de …» por un camino sin «Deshacer»")

        let home = try String(contentsOf: root.appendingPathComponent("Screens/HomeView.swift"), encoding: .utf8)
        let helper = try XCTUnwrap(home.range(of: "private func removeFromContinue("), "Seguir viendo quita con su ayudante")
        let body = home[helper.upperBound...].prefix(500)
        XCTAssertTrue(body.contains("actionTitle: \"Deshacer\""), "«Quitada de Seguir viendo» trae «Deshacer»")
        XCTAssertTrue(body.contains("undoWindow: DS.Timing.undoCommit"), "Trakt y la biblioteca se enteran cuando ya no se puede deshacer")
        XCTAssertFalse(home.contains("await model.dismiss(item) }"), "Seguir viendo ya no quita al instante y sin vuelta")
    }
}

/// «Si el video no arranca, nada del reproductor tapa el aviso» (`docs/ios-interfaz.md`): cada capa que se dibuja encima del
/// video (±10, el iPod, «Audio y subtítulos» fijo del iPad de pie) se quita con `failed(model)`. En el recorrido de la Mac
/// (16 nov 2026) el panel fijo tapaba «Todavía no está en la nube» y su «Cerrar».
extension DesignRulesTests {
    func testNothingCoversThePlayerFailure() throws {
        let screen = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Screens/PlayerScreen.swift"), encoding: .utf8)
        let layers = ["skipLayer(model", "ipodChrome(model", "subtitleDockLayer(model"]
        for layer in layers {
            let lines = screen.components(separatedBy: "\n").filter { $0.contains(layer) && $0.contains("if ") }
            XCTAssertFalse(lines.isEmpty, "se encontró dónde se dibuja \(layer))")
            for line in lines { XCTAssertTrue(line.contains("failed(model)"), "\(layer)) se quita si el video no arranca: \(line)") }
        }
    }
}
