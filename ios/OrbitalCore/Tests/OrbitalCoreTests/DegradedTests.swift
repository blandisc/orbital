import XCTest
@testable import OrbitalCore

/// Modo degradado: la causa de verdad de una falla y su salida (`docs/producto/modo-degradado.md`).
final class DegradedTests: XCTestCase {
    func testWithoutNetworkItIsAlwaysOffline() {
        XCTAssertEqual(Degraded.classify(NetworkError("HTTP 503"), service: .trakt, online: false), .offline, "sin red no se culpa a Trakt")
        XCTAssertEqual(Degraded.classify(URLError(.notConnectedToInternet), service: .addons, online: true), .offline,
                       "el error del sistema manda aunque el monitor aún no se entere")
        XCTAssertEqual(Degraded.classify(NetworkError("x", code: .networkConnectionLost), service: .trakt, online: true), .offline)
    }

    func testOnlineFailuresBlameTheService() {
        XCTAssertEqual(Degraded.classify(NetworkError("HTTP 503"), service: .trakt, online: true), .down(.trakt))
        XCTAssertEqual(Degraded.classify(URLError(.timedOut), service: .addons, online: true), .down(.addons))
        XCTAssertEqual(Degraded.classify(nil, service: .realDebrid, online: true), .down(.realDebrid))
        XCTAssertEqual(Degraded.classify(NetworkError("HTTP 401"), service: .trakt, online: true), .notConnected(.trakt), "la sesión, no la red")
    }

    func testEveryStateSaysWhatToDo() {
        var states: [Degraded] = [.offline]
        for service in Degraded.Service.allCases { states += [.down(service), .notConnected(service)] }
        for state in states {
            XCTAssertFalse(state.title.isEmpty); XCTAssertFalse(state.detail.isEmpty); XCTAssertFalse(state.actionTitle.isEmpty)
            if case .down = state { XCTAssertFalse(state.detail.contains("Revisa tu conexión"), "\(state): con red no se culpa a la conexión") }
        }
        XCTAssertEqual(Degraded.offline.action, .downloads, "sin internet, lo que sí se ve: tus descargas")
        XCTAssertEqual(Degraded.down(.trakt).action, .retry)
        XCTAssertEqual(Degraded.notConnected(.trakt).action, .settings)
    }
}
