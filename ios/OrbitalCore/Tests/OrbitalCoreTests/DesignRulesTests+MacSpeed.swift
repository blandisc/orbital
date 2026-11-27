import XCTest

/// Abrir la app, cambiar de pestaña y abrir una ficha en la Mac no arman lo que nadie ve (24 nov 2026, medido con
/// Instruments en la app instalada). Regla en `docs/ios-interfaz.md` § «Lo que no se ve no se arma».
extension DesignRulesTests {
    func testWhatIsNotSeenIsNotBuilt() throws {
        let files = try sources(["Design", "Screens", "App"])
        func code(_ name: String) throws -> String {
            let file = try XCTUnwrap(files.first { $0.name == name }, "falta \(name)")
            return file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // El panel de la derecha (inspector) arma lo de adentro solo abierto: cerrado, SwiftUI lo armaba al abrir la app y lo
        // volvía a pintar con cada sondeo de la TV (~0.3 s del arranque).
        for file in files {
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            var rest = text[...]
            while let use = rest.range(of: ".inspector(isPresented: ") {
                let after = rest[use.upperBound...]
                let shown = String(after.prefix { $0 != ")" })
                XCTAssertTrue(after.prefix(200).contains("{ if \(shown)"), "\(file.name): lo de adentro de `.inspector` se arma solo si \(shown)")
                rest = after
            }
        }
        // En la ficha, lo de abajo (episodios, reparto, detalles) se arma cuando llegó la ficha, no al abrir. En una pila
        // normal: la perezosa adivinaba su alto y la ficha se «soltaba» al final (26 nov, `testLazyStacksAreOnlyForLongLists`).
        XCTAssertTrue(try code("TitleView.swift").contains("if belowFold { VStack("), "lo de abajo de la ficha se arma al llegar la ficha")
        // «Decide por mí» no rehace su abanico de pósters en cada pasada: lo guarda hasta que el modelo cambie.
        XCTAssertTrue(try code("DecideSheet.swift").contains("DecideFanMemo"), "el abanico de «Decide por mí» se guarda por versión del modelo")
    }

    /// Lo que llega tarde a la ficha (las versiones, el pedido a la nube) se pinta en su propia pieza: leído en el cuerpo de la
    /// ficha o en su columna, cada llegada volvía a armar la ficha entera (~90 ms en la Mac). Y un estado que la ficha ancha no
    /// usa no se prende en ella (`belowFold`, que solo usa la de una columna).
    func testLateDataRedrawsOnlyItsPiece() throws {
        let file = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "TitleView.swift" })
        let code = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        for piece in ["actions(model)", "details(model)"] {
            var rest = code[...]
            var count = 0
            while let use = rest.range(of: piece) {
                let before = rest[..<use.lowerBound]
                if !before.hasSuffix("func ") {
                    count += 1
                    XCTAssertTrue(before.hasSuffix("TitleLayoutHost { AnyView("), "`\(piece)` va en su propia pieza (`TitleLayoutHost`): lee lo que llega tarde")
                }
                rest = rest[use.upperBound...]
            }
            XCTAssertGreaterThan(count, 0, "no encontré `\(piece)`")
        }
        let follow = try XCTUnwrap(code.range(of: "private struct TitleDebridFollow"), "falta `TitleDebridFollow`")
        XCTAssertFalse(code[..<follow.lowerBound].contains("model.debridRequest"), "el pedido a la nube se lee solo en `TitleDebridFollow`")
        XCTAssertTrue(code.contains("guard sizeClass != .regular, !belowFold"), "`belowFold` no se prende en la ficha ancha")
    }

    /// Un valor que se compara no avisa cuando es el mismo: con `@Tracked(always: true)` cada sondeo repintaba la ficha entera
    /// aunque nada hubiera cambiado. `always` queda para lo que no se puede comparar.
    func testTrackedValuesCompareBeforeNotifying() throws {
        let base = repo.appendingPathComponent("ios/OrbitalCore/Sources/OrbitalModels")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)).allObjects
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ObservableModel.swift" }
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("@Tracked(always: true)"), "\(url.lastPathComponent): `@Tracked` sin `always` (sus valores se comparan; con `always` repinta sin cambios)")
        }
    }
    /// Lo que responde al puntero solo se prende si el puntero se mueve: al deslizar con la rueda el puntero queda quieto y cada
    /// póster o fila que pasaba debajo crecía o sacaba sus flechas, uno tras otro (25 nov 2026). Nada usa `.onHover`; cada
    /// `onContinuousHover` que prende algo pregunta a `MacPointer`.
    func testHoverOnlyWhenPointerMoves() throws {
        let files = try sources(["Design", "Screens", "App"])
        var hovers = 0
        for file in files {
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            XCTAssertFalse(text.contains(".onHover {") || text.contains(".onHover(perform"), "\(file.name): `.onHover` se prende con el puntero quieto; usa `onContinuousHover` con `MacPointer.isMoving`")
            var rest = text[...]
            while let use = rest.range(of: ".onContinuousHover(") {
                let body = rest[use.upperBound...].prefix(400)
                if body.contains("= true") {
                    hovers += 1
                    XCTAssertTrue(body.contains("MacPointer.isMoving"), "\(file.name): lo que se prende al pasar el puntero pregunta `MacPointer.isMoving`")
                }
                rest = rest[use.upperBound...]
            }
        }
        XCTAssertGreaterThanOrEqual(hovers, 2, "no encontré los pósters ni las flechas de las filas")
        let deck = try XCTUnwrap(files.first { $0.name == "MacTabDeck.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(deck.contains(".macPointerWatch()"), "toda la ventana anota cuándo se mueve el puntero")
    }

    /// Al deslizar nada lee su lugar en la ventana en cada cuadro (26 nov 2026): cada póster anotaba su marco (`.global`) y
    /// cada fila su orilla, decenas de veces a 120 cuadros por segundo, y Explorar bajaba con 273–286 ms atrasados por segundo.
    /// Quien necesita saber dónde está lo mide una vez por ancho (`size.width ==`, al deslizar la página no cambia); solo las
    /// piezas que hay una vez por pantalla y no van en filas lo leen directo.
    func testNothingTracksTheWindowWhileScrolling() throws {
        let once: Set<String> = ["HomeMark.swift", "MacTabStrip.swift", "SimpsonsRoulette.swift", "OnboardingPlatforms.swift", "Brand.swift"]
        var tracked = 0
        for file in try sources(["Design", "Screens", "App"]) where !once.contains(file.name) {
            let text = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            var rest = text[...]
            while let use = rest.range(of: ".onGeometryChange(") {
                let after = rest[use.upperBound...]
                let transform = after.range(of: "action:").map { after[..<$0.lowerBound] } ?? after.prefix(400)   // el cálculo
                if transform.contains("frame(in: .global)") {
                    tracked += 1
                    XCTAssertTrue(transform.contains("size.width =="), "\(file.name): lee su lugar en la ventana en cada cuadro; mídelo una vez por ancho (`if g.size.width == … { return … }`)")
                }
                rest = rest[use.upperBound...]
            }
        }
        XCTAssertGreaterThanOrEqual(tracked, 2, "no encontré la fila (`RowEdgeClip`) ni la portada de Explorar")
        // El enlace de un póster no sigue su marco (la ficha de la Mac sale de su propia capa y no lo usa).
        let link = try XCTUnwrap(try sources(["Design"]).first { $0.name == "TitlePanel.swift" }).lines.joined(separator: "\n")
        XCTAssertFalse(link.contains("onGeometryChange"), "TitleNavigationLink no sigue su marco en cada cuadro")
    }
}
