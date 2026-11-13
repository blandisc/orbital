import XCTest

/// Las pruebas del reproductor en el simulador van en silencio (Fernando, 13 nov 2026: el video de demostración sonaba por
/// las bocinas de la Mac). Cualquier prueba de interfaz puede acabar en el reproductor (tocar «Ver» en una ficha), así que
/// todo lanzamiento de demostración lleva `-demo-mute`; la bandera pone el volumen del motor en 0 (AetherEngine y AVPlayer),
/// sin tocar el del sistema. Regla en `docs/ios-interfaz.md` § «Las preguntas son tarjetas de la app».
extension DesignRulesTests {
    func testUITestsLaunchTheDemoMuted() throws {
        let root = repo.appendingPathComponent("ios/App/UITests")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var loud: [String] = []
        var launches = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains(#"["-demo""#) {
                launches += 1
                if !line.contains(#""-demo-mute""#) { loud.append("\(file.lastPathComponent):\(i + 1)") }
            }
        }
        XCTAssertGreaterThan(launches, 10, "se leyeron los lanzamientos de ios/App/UITests")
        XCTAssertEqual(loud, [], "Lanzamiento de demostración sin `-demo-mute` (el reproductor sonaría en la Mac)")

        let demo = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Support/Demo.swift"), encoding: .utf8)
        XCTAssertTrue(demo.contains(#"static var mute: Bool { has("-demo-mute") }"#), "existe `-demo-mute`")
        for engine in ["Platform/AetherEnginePlayer.swift", "Platform/PlayerEngines.swift"] {
            let code = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/" + engine), encoding: .utf8)
            XCTAssertTrue(code.contains("Demo.mute"), "\(engine) se calla con `-demo-mute`")
        }
    }
}
