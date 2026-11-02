import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El reloj del reproductor (auditoría del 31 oct 2026, A2): la posición avanza cuatro veces por segundo y antes cada avance
/// volvía a pintar la pantalla entera del reproductor. Ahora solo avisa `PlayerTime`; el modelo avisa por lo demás.
@MainActor
final class PlayerTimeTests: XCTestCase {
    func testAvanzarLaPosicionSoloAvisaAlReloj() async throws {
        let rig = try PlayerModelTests().twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(300))
        await rig.model.handle(rig.playing(301))   // ya corre (pasó el medio segundo de arranque)
        var screen = 0, clock = 0
        let a = rig.model.onChange { screen += 1 }, b = rig.model.time.onChange { clock += 1 }
        defer { a.cancel(); b.cancel() }
        await rig.model.handle(rig.playing(301.25))
        await rig.model.handle(rig.playing(301.5))
        XCTAssertEqual(screen, 0, "solo cambió la posición: la pantalla no se vuelve a pintar")
        XCTAssertEqual(clock, 2, "la barra de avance sí")
        XCTAssertEqual(rig.model.time.position, 301.5)
        await rig.model.handle(rig.playing(301.75, state: .paused))
        XCTAssertGreaterThan(screen, 0, "pausar sí cambia la pantalla")
    }

    func testPonerElMismoValorNoAvisa() async throws {
        let rig = try PlayerModelTests().twoSources()
        var screen = 0
        let a = rig.model.onChange { screen += 1 }
        defer { a.cancel() }
        rig.model.askInSync = false
        rig.model.subtitleDelay = 0
        rig.model.skipIntroTo = nil
        XCTAssertEqual(screen, 0)
        rig.model.subtitleDelay = 1
        XCTAssertEqual(screen, 1)
    }

    /// «Siguiente» sale al cruzar el 90 % con los controles a la vista: la posición sola no avisa a la pantalla, así que el
    /// modelo avisa una vez al cruzar la marca (auditoría, tanda 5: no salía hasta volver a tocar).
    func testCruzarElNoventaPorCientoAvisaUnaVez() async throws {
        let rig = try PlayerModelTests().twoSources()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(890, duration: 1000))
        await rig.model.handle(rig.playing(891, duration: 1000))
        XCTAssertFalse(rig.model.pastNextMark)
        var screen = 0
        let a = rig.model.onChange { screen += 1 }
        defer { a.cancel() }
        await rig.model.handle(rig.playing(899.75, duration: 1000))
        XCTAssertEqual(screen, 0, "antes del 90 %, nada")
        await rig.model.handle(rig.playing(900, duration: 1000))
        XCTAssertTrue(rig.model.pastNextMark)
        XCTAssertEqual(screen, 1, "al cruzar el 90 % la pantalla se vuelve a pintar (sale «Siguiente»)")
        await rig.model.handle(rig.playing(900.25, duration: 1000))
        XCTAssertEqual(screen, 1, "y no otra vez con cada avance")
        await rig.model.handle(rig.playing(100, duration: 1000))
        XCTAssertFalse(rig.model.pastNextMark, "regresar antes del 90 % lo quita")
    }
}
