import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Ajustes › Cuentas y Complementos, lo que no cubre la guía (`OnboardingModelTests`): Real-Debrid sin red o con una clave
/// que no reconoce (no se guarda nada), cambiar la clave a medias, «Quitar» que olvida todo, el estado guardado un día, y los
/// complementos cuando algo falla («Volver a traer» sin red).
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

    /// P6-A: lo que dice tu cuenta es verdad al abrirla. Se le pregunta a Real-Debrid cada vez; mientras, no se confirma nada
    /// (aunque ayer sirviera); si ya no la acepta, se dice; sin respuesta, tampoco «Conectada».
    func testAbrirTuCuentaRevisaLaClaveYNuncaConfirmaLoDeAyer() async throws {
        let rig = try ServicesRig(signedIn: false)
        premium(rig)
        let model = DebridModel(rig.services)
        model.token = token
        await model.verify()
        XCTAssertEqual(model.keyCheck, .confirmed, "la acabas de pegar")
        // Otra visita: lo guardado se enseña, pero sin confirmar hasta que Real-Debrid conteste.
        let visit = DebridModel(rig.services)
        XCTAssertEqual(visit.keyCheck, .checking)
        XCTAssertNotNil(visit.status, "lo último que se supo")
        await visit.recheck()
        XCTAssertEqual(visit.keyCheck, .confirmed)
        // La cambiaste en real-debrid.com: ya no sirve.
        rig.http.statuses[user] = 401
        rig.http.json[user] = ["error": "bad_token"]
        let later = DebridModel(rig.services)
        await later.recheck()
        XCTAssertEqual(later.keyCheck, .rejected, "«Vuelve a conectar Real-Debrid»")
        XCTAssertTrue(later.hasToken, "la clave no se borra sola")
        // Sin internet: no se sabe, y no se dice «Conectada».
        rig.http.statuses[user] = nil
        rig.http.offline = true
        let offline = DebridModel(rig.services)
        await offline.recheck()
        XCTAssertEqual(offline.keyCheck, .unreachable)
    }

    func testVolverAImportarSinRedDiceQuePasoYLaListaSeQueda() async throws {
        let rig = try ServicesRig(signedIn: true)
        rig.services.addonList.startWithRecommended()
        let model = AddonsModel(rig.services)
        let template = try XCTUnwrap(AddonCatalog.recommended.first)
        let removed = await model.remove(template.id)
        XCTAssertFalse(removed, "los que vienen con Orbital no se quitan, solo se apagan")
        XCTAssertTrue(model.missingRecommended.isEmpty)
        let before = model.items
        rig.http.offline = true
        await model.importAgain()
        XCTAssertNotNil(model.error, "sin red, el aviso dice qué pasó")
        XCTAssertFalse(model.working)
        XCTAssertEqual(model.items, before, "lo que tenías se queda")
    }

    /// OpenSubtitles ya no es complemento (Fernando, 3 nov): ni el de Orbital ni el traído de Stremio salen en la lista, no se
    /// ofrece en «Agregar», y «Ordenar» mueve lo que ves aunque OpenSubtitles esté en medio de la lista completa.
    func testOpenSubtitlesNoSaleEnLaListaYOrdenarSigueBien() async throws {
        let rig = try ServicesRig(signedIn: true)
        let list = rig.services.addonList
        list.startWithRecommended()   // Torrentio, Comet, OpenSubtitles
        list.importOnce([.init(name: "OpenSubtitles v3", url: "https://opensubtitles-v3.strem.io/manifest.json", resources: ["subtitles"]),
                         .init(name: "ThePirateBay+", url: "https://tpb.example/manifest.json", resources: ["stream"])])
        let model = AddonsModel(rig.services)
        XCTAssertEqual(model.items.map(\.name), ["Torrentio", "Comet", "ThePirateBay+"])
        XCTAssertFalse(model.missingRecommended.contains { $0.id == "opensubtitles" })
        await model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)   // ThePirateBay+ arriba de todo
        XCTAssertEqual(model.items.map(\.name), ["ThePirateBay+", "Torrentio", "Comet"])
        XCTAssertTrue(list.installed.contains { $0.origin == .recommended("opensubtitles") }, "OpenSubtitles sigue guardado: solo no se enseña")
    }

    /// Fernando, 3 nov: quitó Local Files sin querer y la TV lo borraba. Lo que vive en la TV no se quita desde aquí, aunque
    /// su dirección no sea la de la computadora (se reconoce por el nombre).
    func testLocalFilesNoSeQuitaDesdeElIPhone() async throws {
        let rig = try ServicesRig(signedIn: true)
        let list = rig.services.addonList
        list.startWithRecommended()
        list.importOnce([.init(name: "Local Files (without catalog support)", url: "https://local.example/manifest.json", resources: ["stream"])])
        let model = AddonsModel(rig.services)
        let local = try XCTUnwrap(model.items.first { $0.name.hasPrefix("Local Files") })
        XCTAssertFalse(model.canRemove(local))
        let removed = await model.remove(local.id)
        XCTAssertFalse(removed)
        XCTAssertFalse(list.removedIDs.contains(local.id), "no se le dice a la TV que lo quite")
    }
}
