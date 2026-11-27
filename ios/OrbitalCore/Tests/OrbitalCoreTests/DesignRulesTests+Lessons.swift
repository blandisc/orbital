import XCTest

/// Las lecciones de Aprende se leen completas en claro y en oscuro (pasada del iPhone Duo, 27 nov 2026):
/// - El lienzo de la escena forzaba el modo oscuro entero; con la app en claro, «Tus idiomas», «Lo que viste», los precios y
///   los nombres de los aparatos salían en letra blanca sobre el fondo claro. El lienzo sigue el modo de la app y solo lo que
///   es oscuro de verdad (el iPhone y la tele dibujados, las etiquetas flotantes) lo pide, cada pieza.
/// - En pantallas bajas (el SE, el Duo cerrado) la última línea del texto quedaba debajo de los botones: la escena se achica
///   lo que haga falta (`sceneRoom`) para que el texto quepa.
/// Regla en `docs/ios-proyeccion.md` § 7 «Modo claro y oscuro» y § «Bordes» de `docs/ios-interfaz.md`.
extension DesignRulesTests {
    func testLessonsReadInBothModesAndAboveTheButtons() throws {
        let kit = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Lessons/LessonKit.swift"), encoding: .utf8)
        func body(of name: String) throws -> Substring {
            let start = try XCTUnwrap(kit.range(of: "struct \(name)"), "existe \(name)")
            let end = kit[start.upperBound...].range(of: "\n}\n")?.lowerBound ?? kit.endIndex
            return kit[start.lowerBound..<end]
        }
        XCTAssertFalse(try body(of: "LessonCanvas").contains("colorScheme, .dark"),
                       "El lienzo de la lección no fuerza el modo oscuro: en claro la letra sale blanca sobre el fondo claro")
        for piece in ["LessonPhone", "LessonTV", "LessonChip"] {
            XCTAssertTrue(try body(of: piece).contains(".environment(\\.colorScheme, .dark)"), "\(piece) es oscuro en los dos modos")
        }

        // Todo struct de las escenas con vidrio (`.ultraThinMaterial`) va sobre el video: oscuro en los dos modos. El aviso de
        // arriba (`LessonNote`) es la excepción: va sobre el lienzo, como el aviso del sistema, claro en claro.
        let folder = repo.appendingPathComponent("ios/App/Sources/Design/Lessons")
        var glassy: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let code = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            for chunk in code.components(separatedBy: "\nstruct ").dropFirst() {
                let piece = chunk.prefix { $0 != ":" && $0 != "<" && $0 != " " }
                if chunk.contains(".ultraThinMaterial"), piece != "LessonNote", !chunk.contains("colorScheme, .dark") { glassy.append("\(name): \(piece)") }
            }
            // El dedo fantasma es una sola pieza que cambia de tinta con el modo (blanco en claro no se ve).
            if name != "LessonKit.swift" { XCTAssertFalse(code.contains("Lesson.fingerFill"), "\(name): el dedo se dibuja con LessonFingerDot") }
        }
        XCTAssertEqual(glassy, [], "Vidrio sobre el video sin `.environment(\\.colorScheme, .dark)`: en claro queda gris sobre gris")
        XCTAssertTrue(try body(of: "LessonFingerDot").contains("scheme == .dark ? DS.paper : DS.text"), "el dedo cambia de tinta con el modo")

        let view = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Screens/LessonView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("maxHeight: sceneRoom"), "La escena se achica para que el texto quepa sobre los botones")
        XCTAssertTrue(view.contains("textHeight = $0"), "Se mide el texto más alto de la lección (la escena no salta entre pasos)")
        XCTAssertTrue(view.contains("ForEach(lesson.steps.indices"), "El alto se toma de todos los pasos")
        XCTAssertTrue(view.contains("onScrollGeometryChange"), "Se mide lo que se ve entre la barra de arriba y los botones")
    }
}
