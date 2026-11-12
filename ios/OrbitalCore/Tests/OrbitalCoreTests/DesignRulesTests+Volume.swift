import XCTest

/// El volumen no se mueve solo (Fernando, 11 nov 2026: «cuando abro Orbital como que aparece la barra de volumen, como si
/// hubiera cambiado el volumen»). Regla en `docs/ios-interfaz.md` § «El volumen no se mueve solo».
extension DesignRulesTests {
    func testVolumeIsOnlyTouchedInPlatform() throws {
        let files = try sources(["Design", "Screens", "Platform"])
        let allowed: Set<String> = ["HardwareVolumeButtons.swift", "SystemVolumeControl.swift", "PlayerScreen+Gestos.swift"]
        check(hits(#"MPVolumeView|outputVolume"#, in: files) { allowed.contains($0.name) },
              "El volumen del iPhone solo se lee o se mueve en `Platform/` y en el gesto del reproductor")
    }

    func testRemoteVolumeButtonsNeverMoveTheVolumeUncovered() throws {
        let file = try XCTUnwrap(try sources(["Platform"]).first { $0.name == "HardwareVolumeButtons.swift" })
        let code = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        // La tapa vive en la ventana, no en la vista que se monta y se desmonta.
        XCTAssertTrue(code.contains("window?.addSubview(cover)"), "La tapa del aviso se pone en la ventana")
        XCTAssertFalse(code.contains("-> MPVolumeView"), "La vista de SwiftUI no es la tapa: se iría antes de regresar el volumen")
        // Al volver a la app, el volumen encontrado es el punto de partida.
        XCTAssertTrue(code.contains("didBecomeActiveNotification") && code.contains("willResignActiveNotification"),
                      "Salir y volver a la app no cuenta como botón del control")
        // Acercarse al centro espera a que la tapa se asiente.
        XCTAssertNil(code.range(of: #"DispatchQueue\.main\.async \{[^}]*set\("#, options: .regularExpression),
                     "El volumen no se mueve en el mismo instante de montar la vista")
    }
}
