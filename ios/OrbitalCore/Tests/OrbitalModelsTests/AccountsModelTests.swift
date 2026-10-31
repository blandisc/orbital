import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Ajustes › Cuentas y Complementos, lo que no cubre la guía (`OnboardingModelTests`): Real-Debrid sin red o con una clave
/// que no reconoce (no se guarda nada), cambiar la clave a medias, «Quitar» que olvida todo, el estado guardado un día, y los
/// complementos cuando algo falla (una dirección que no es dirección, «Volver a importar» sin red).
@MainActor
final class AccountsModelTests: XCTestCase {
    let user = "https://api.real-debrid.com/rest/1.0/user"
    let token = String(repeating: "QX7MZ2K9PL", count: 5) + "AB"

    func premium(_ rig: ServicesRig) { rig.http.json[user] = ["username": "fernando", "type": "premium", "premium": .int(143 * 86400)] }

    func testSinRedLaClaveNoSeGuardaYDiceQueRevisesTuConexion() async throws {
        let rig = try ServicesRig(signedIn: false)
        rig.http.offline = true
        let model = DebridModel(rig.services)
        model.token = "  \(token)\n"
        await model.verify()
        XCTAssertEqual(model.check, .failed(DebridError.network("").description))
        XCTAssertFalse(model.hasToken, "no se guarda")
        XCTAssertFalse(model.ready)
        XCTAssertTrue(rig.services.addonList.installed.isEmpty, "los recomendados no se arman")
    }

    func testUnaClaveQueRealDebridNoReconoceNoSeGuarda() async throws {
        let rig = try ServicesRig(signedIn: false)
        rig.http.json[user] = ["error": "bad_token"]
        rig.http.statuses[user] = 401
        let model = DebridModel(rig.services)
        model.token = token
        await model.verify()
        XCTAssertEqual(model.check, .failed(DebridError.invalidToken.description))
        XCTAssertFalse(model.hasToken)
        XCTAssertNil(model.status)
    }

    func testCambiarLaClaveBorraElAvisoYSinClaveNoSePregunta() async throws {
        let rig = try ServicesRig(signedIn: false)
        let model = DebridModel(rig.services)
        model.token = "corta"
        await model.verify()
        XCTAssertEqual(model.check, .failed(DebridError.malformedToken.description))
        model.token = "corta2"
        XCTAssertEqual(model.check, .idle, "al escribir otra, el aviso viejo se quita")
        model.token = "   "
        await model.verify()
        XCTAssertEqual(model.check, .idle, "en blanco no se comprueba nada")
        XCTAssertFalse(rig.http.calls.contains(user))
    }

    func testElEstadoGuardadoSirveUnDiaYQuitarOlvidaTodo() async throws {
        let rig = try ServicesRig(signedIn: false)
        premium(rig)
        let model = DebridModel(rig.services)
        model.token = token
        await model.verify()
        XCTAssertTrue(model.ready)
        let asked = rig.http.calls.filter { $0 == user }.count
        // Al volver a Ajustes el mismo día: el estado guardado, sin preguntar.
        let reopened = DebridModel(rig.services)
        XCTAssertEqual(reopened.status?.username, "fernando")
        await reopened.load()
        XCTAssertEqual(rig.http.calls.filter { $0 == user }.count, asked)
        await reopened.load(force: true)
        XCTAssertEqual(rig.http.calls.filter { $0 == user }.count, asked + 1, "«Actualizar» sí pregunta")
        await reopened.remove()
        XCTAssertFalse(reopened.hasToken)
        XCTAssertNil(reopened.status)
        XCTAssertEqual(reopened.token, "")
        XCTAssertEqual(reopened.check, .idle)
        XCTAssertFalse(reopened.ready)
        XCTAssertNil(DebridModel(rig.services).status, "tampoco al volver a abrir")
    }

    func testUnaDireccionQueNoEsDireccionDiceQuePegarYSePuedeQuitarElAviso() async throws {
        let rig = try ServicesRig(signedIn: false)
        let model = AddonsModel(rig.services)
        let added = await model.add(address: "no es una dirección")
        XCTAssertFalse(added)
        XCTAssertEqual(model.error, "Pega la dirección completa del complemento (https://…).")
        XCTAssertFalse(model.working)
        XCTAssertTrue(model.items.isEmpty)
        model.clearError()
        XCTAssertNil(model.error)
    }

    func testVolverAImportarSinRedDiceQuePasoYLaListaSeQueda() async throws {
        let rig = try ServicesRig(signedIn: true)
        let model = AddonsModel(rig.services)
        rig.services.addonList.startWithRecommended()
        let template = try XCTUnwrap(AddonCatalog.recommended.first)
        await model.remove(template.id)
        XCTAssertEqual(model.missingRecommended.map(\.id), [template.id])
        await model.add(template)
        XCTAssertTrue(model.missingRecommended.isEmpty)
        let before = model.items
        rig.http.offline = true
        await model.importAgain()
        XCTAssertNotNil(model.error, "sin red, el aviso dice qué pasó")
        XCTAssertFalse(model.working)
        XCTAssertEqual(model.items, before, "lo que tenías se queda")
    }
}
