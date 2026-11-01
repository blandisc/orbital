import XCTest
@testable import OrbitalModels

final class ForegroundRefreshTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testAlAbrirPideTodoMenosLaBiblioteca() {
        var r = ForegroundRefresh()
        XCTAssertEqual(r.becameActive(at: t0), .launch)
    }

    func testElCentroDeControlNoPideNada() {
        var r = ForegroundRefresh()
        _ = r.becameActive(at: t0)
        // Bajar el Centro de control: la app pasa a inactiva y vuelve, sin irse a segundo plano.
        XCTAssertEqual(r.becameActive(at: t0.addingTimeInterval(600)), .skip)
    }

    func testVolverDeSegundoPlanoPideTodoSiHaceRato() {
        var r = ForegroundRefresh()
        _ = r.becameActive(at: t0)
        r.wentToBackground()
        XCTAssertEqual(r.becameActive(at: t0.addingTimeInterval(ForegroundRefresh.minimumGap + 1)), .refresh)
    }

    func testCambiarDeAppSeguidoNoPideCadaVez() {
        var r = ForegroundRefresh()
        _ = r.becameActive(at: t0)
        r.wentToBackground()
        XCTAssertEqual(r.becameActive(at: t0.addingTimeInterval(10)), .skip, "volviste a los 10 s")
        r.wentToBackground()
        XCTAssertEqual(r.becameActive(at: t0.addingTimeInterval(ForegroundRefresh.minimumGap + 5)), .refresh)
        r.wentToBackground()
        XCTAssertEqual(r.becameActive(at: t0.addingTimeInterval(ForegroundRefresh.minimumGap + 30)), .skip)
    }

    func testSiLaPrimeraVezYaVieneDeSegundoPlanoPideTodo() {
        // Abierta en segundo plano (una tarea de fondo) y luego traída al frente.
        var r = ForegroundRefresh()
        r.wentToBackground()
        XCTAssertEqual(r.becameActive(at: t0), .refresh)
    }
}
