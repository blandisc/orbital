import XCTest

/// Al mandar algo a la TV, el iPhone se queda en silencio (Fernando, 26 nov 2026: «la puse en la tele y estaba
/// reproduciendo el audio del iPhone»). Toda llamada que manda a reproducir a la TV pasa por `playOnTV`, que calla el
/// reproductor de aquí (`silenceThisDevice`), y el reproductor deja su motor a la mano (`lastLocalEngine`).
extension DesignRulesTests {
    func testSendingToTheTVSilencesThePhone() throws {
        let files = try sources(["App", "Screens"])
        let orbital = try XCTUnwrap(files.first { $0.name == "AppEnvironment+Orbital.swift" }).lines.joined(separator: "\n")
        let body = try XCTUnwrap(orbital.range(of: "func playOnTV").map { String(orbital[$0.lowerBound...].prefix(600)) })
        XCTAssertTrue(body.contains("await silenceThisDevice()"), "`playOnTV` calla el iPhone antes de mandar a la TV")
        XCTAssertTrue(orbital.contains("await engine.stop()"), "`silenceThisDevice` detiene el motor, no solo la pantalla")
        let player = try XCTUnwrap(files.first { $0.name == "PlayerScreen.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(player.contains("env.lastLocalEngine = holder.engine"), "el reproductor deja su motor a la mano")
    }

    /// Saliste mientras cargaba: la carga a medias no cae a «directo» ni se pone a sonar sin pantalla (26 nov: Thunderbolts*
    /// siguió cargando tras cerrar, por la vuelta a «directo» después de la cancelación).
    func testALoadYouLeftNeverStartsPlaying() throws {
        let files = try sources(["Platform"])
        let aether = try XCTUnwrap(files.first { $0.name == "AetherEnginePlayer.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(aether.contains("error is CancellationError"), "cancelar no se trata como fallo de varias conexiones")
        XCTAssertGreaterThanOrEqual(aether.components(separatedBy: "try stillWanted()").count - 1, 3,
                                    "tras cada espera de la carga se revisa que alguien la siga queriendo")
        XCTAssertTrue(aether.contains("func stop() async { loads += 1"), "detener invalida la carga a medias")
    }
}
