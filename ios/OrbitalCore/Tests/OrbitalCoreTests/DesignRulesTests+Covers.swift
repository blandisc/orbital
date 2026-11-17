import XCTest

/// Lo que se abre a pantalla completa le pasa la app a mano (revisión del reproductor en la Mac, 16 nov 2026): en la Mac
/// («Diseñada para iPad») la cubierta leía sus preferencias (`interactiveDismissDisabled`, el zoom de entrada) antes de
/// heredar `AppEnvironment`, y la app tronaba al abrir el reproductor desde cualquier lado. Toda `fullScreenCover` lleva
/// `.environment(env)` en lo que muestra (en su cierre o en la función que nombra con `content:`).
/// Regla en `docs/ios-interfaz.md` § «El replanteamiento de la Mac».
extension DesignRulesTests {
    func testFullScreenCoversPassTheApp() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var missing: [String] = []
        var covers = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
            var search = code.startIndex
            while let hit = code.range(of: ".fullScreenCover(", range: search..<code.endIndex) {
                search = hit.upperBound
                covers += 1
                let body = Self.coverContent(in: code, after: hit.upperBound)
                if !(body?.contains(".environment(env)") ?? false) {
                    let line = code[..<hit.lowerBound].components(separatedBy: "\n").count
                    missing.append("\(file.lastPathComponent):\(line)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(covers, 7, "se leyeron las cubiertas de ios/App/Sources")
        XCTAssertEqual(missing, [], "Cubierta sin `.environment(env)`: en la Mac la app truena al abrirla")
    }

    /// Lo que muestra la cubierta: la función que nombra con `content:` o su cierre `{ … }`.
    private static func coverContent(in code: String, after start: String.Index) -> Substring? {
        let lineEnd = code[start...].firstIndex(of: "\n") ?? code.endIndex
        let call = code[start..<lineEnd]
        if let named = call.range(of: "content: ") {
            let name = call[named.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            guard let fn = code.range(of: "func \(name)(") else { return nil }
            return braced(code, from: fn.upperBound)
        }
        return braced(code, from: start)
    }

    /// El bloque `{ … }` que empieza en la primera llave desde `from`, con sus llaves anidadas.
    private static func braced(_ code: String, from: String.Index) -> Substring? {
        guard let open = code[from...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 } else if code[i] == "}" {
                depth -= 1
                if depth == 0 { return code[open...i] }
            }
            i = code.index(after: i)
        }
        return nil
    }
}

/// El reproductor en pantallas grandes (16 nov 2026): sus controles fijos crecen en la Mac y el iPad (`DS.PlayerPanel.big`) y
/// en la Mac el puntero los muestra.
extension DesignRulesTests {
    func testPlayerControlsFitTheMac() throws {
        let sources = repo.appendingPathComponent("ios/App/Sources")
        let tokens = try String(contentsOf: sources.appendingPathComponent("Design/Tokens+Player.swift"), encoding: .utf8)
        for token in ["playButton", "playGlyph", "sideButton", "skipGlyph", "circle", "width", "scrubHit", "scrubKnob"] {
            XCTAssertTrue(tokens.contains("static var \(token): CGFloat { big("), "`DS.PlayerPanel.\(token)` crece en la Mac y el iPad")
        }
        XCTAssertTrue(tokens.contains("ProcessInfo.processInfo.isiOSAppOnMac ? Mac.sized(points) : isPad ? points * padScale : points"),
                      "la Mac crece como su letra y el iPad con `padScale`")
        let controls = try String(contentsOf: sources.appendingPathComponent("Design/PlayerControls.swift"), encoding: .utf8)
        XCTAssertTrue(controls.contains(".frame(width: DS.PlayerPanel.circle, height: DS.PlayerPanel.circle)"),
                      "los círculos de arriba del reproductor usan `DS.PlayerPanel.circle`")
        // Todos los círculos de la barra de arriba miden lo mismo: subtítulos y AirPlay se habían quedado del tamaño del iPhone.
        for file in ["Design/SubtitlePanel.swift", "Screens/PlayerScreen+Controles.swift", "Screens/PlayerScreen+IPod.swift"] {
            let code = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(code.contains("DS.PlayerPanel.circle, height: DS.PlayerPanel.circle"), "\(file) usa `DS.PlayerPanel.circle`")
            XCTAssertFalse(code.contains("AirPlayButton().frame(width: DS.Size.touchTarget"), "\(file): AirPlay con `DS.PlayerPanel.circle`")
        }
        let gestures = try String(contentsOf: sources.appendingPathComponent("Screens/PlayerScreen+Gestos.swift"), encoding: .utf8)
        XCTAssertTrue(gestures.contains(".onContinuousHover"), "en la Mac mover el puntero muestra los controles")
    }
}
