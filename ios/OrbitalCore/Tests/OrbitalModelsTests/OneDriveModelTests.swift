import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Ajustes › OneDrive (todo con red falsa, nunca el OneDrive de nadie): sin «ID de la aplicación» está apagado; conectar con
/// el código de microsoft.com/link, rechazarlo o cancelarlo a medias; elegir la carpeta (sin «..») y revisarla; si la sesión
/// caduca al revisar, vuelve a «Conectar»; desconectar olvida lo reconocido.
@MainActor
final class OneDriveModelTests: XCTestCase {
    let devicecode = "\(OneDrive.login)/devicecode", token = "\(OneDrive.login)/token"

    func children(_ path: String) -> String { "\(OneDrive.graph)\(OneDrive.childrenPath(path))" }

    func configured(_ rig: ServicesRig, linked: Bool = false, refresh: Bool = true) {
        rig.services.settings.update { $0.oneDriveClientID = "app-123" }
        if linked {
            let refreshPart = refresh ? #","refresh_token":"ref""# : ""
            rig.secrets.set(SecretKey.oneDriveTokens, #"{"access_token":"acc"\#(refreshPart),"expires_at":\#(rig.clock.now.timeIntervalSince1970 + 3600)}"#)
        }
    }

    func code(_ rig: ServicesRig) {
        rig.http.json[devicecode] = ["device_code": "dev", "user_code": "ABCD-1234", "verification_uri": "https://www.microsoft.com/link", "interval": 1, "expires_in": 900]
    }

    func testSinIDDeLaAplicacionEstaApagadoYAlPonerloSePuedeConectar() throws {
        let rig = try ServicesRig()
        let model = OneDriveModel(rig.services)
        XCTAssertEqual(model.state, .off)
        model.setClientID("  app-123 \n")
        XCTAssertEqual(model.clientID, "app-123")
        XCTAssertEqual(rig.services.appSettings.oneDriveClientID, "app-123", "se guarda en Ajustes")
        XCTAssertEqual(model.state, .unlinked)
        XCTAssertEqual(OneDriveModel(rig.services).state, .unlinked, "al volver a abrir")
    }

    func testConectarConElCodigoQuedaConectado() async throws {
        let rig = try ServicesRig()
        configured(rig)
        code(rig)
        rig.http.json[token] = ["access_token": "acc", "refresh_token": "ref", "expires_in": 3600]
        let model = OneDriveModel(rig.services)
        await model.link()
        XCTAssertEqual(model.state, .linked)
        XCTAssertTrue(rig.services.oneDrive.linked)
        XCTAssertNotNil(rig.secrets.get(SecretKey.oneDriveTokens), "la sesión queda en el llavero")
        XCTAssertFalse(rig.http.calls.contains { $0.hasPrefix(OneDrive.graph) }, "sin carpeta elegida no se revisa nada")
    }

    func testSiRechazasOMicrosoftNoDaCodigoLoDiceYNoSeBorraAlVolver() async throws {
        let rig = try ServicesRig()
        configured(rig)
        let model = OneDriveModel(rig.services)
        await model.link()
        XCTAssertEqual(model.state, .failed("Microsoft no dio un código. Revisa el ID de la aplicación."))
        code(rig)
        rig.http.json[token] = ["error": "authorization_declined"]
        rig.http.statuses[token] = 400
        await model.link()
        XCTAssertEqual(model.state, .failed("Rechazaste la conexión en Microsoft."))
        model.refresh()
        XCTAssertEqual(model.state, .failed("Rechazaste la conexión en Microsoft."), "volver a la pantalla no esconde el aviso")
        XCTAssertFalse(rig.services.oneDrive.linked)
    }

    func testCancelarAMediaConexionRegresaAConectar() async throws {
        let rig = try ServicesRig()
        configured(rig)
        code(rig)
        rig.http.json[token] = ["error": "authorization_pending"]
        rig.http.statuses[token] = 400
        let model = OneDriveModel(rig.services)
        let linking = Task { await model.link() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { if case .linking = model.state { break }; await Task.yield() }
        XCTAssertEqual(model.state, .linking(code: "ABCD-1234", url: "https://www.microsoft.com/link"), "se enseña el código")
        model.refresh()
        XCTAssertEqual(model.state, .linking(code: "ABCD-1234", url: "https://www.microsoft.com/link"), "a media conexión se deja")
        model.cancelLinking()
        await linking.value
        XCTAssertEqual(model.state, .unlinked)
        XCTAssertFalse(rig.services.oneDrive.linked)
    }

    func testElegirLaCarpetaLimpiaLaRutaLaRevisaYDesconectarLaOlvida() async throws {
        let rig = try ServicesRig()
        configured(rig, linked: true)
        rig.http.json[children("Pelis")] = ["value": [
            ["id": "a1", "name": "Dune Part Two (2024) 1080p.mkv", "size": 8_000_000_000, "file": [:]],
            ["id": "a2", "name": "Severance.S01E03.mkv", "size": 900_000_000, "file": [:]],
            ["id": "a3", "name": "notas.txt", "size": 10, "file": [:]]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=Dune%20Part%20Two.json"] = ["metas": [
            ["id": "tt15239678", "type": "movie", "name": "Dune: Part Two", "releaseInfo": "2024"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=Severance.json"] = ["metas": [
            ["id": "tt11280740", "type": "series", "name": "Severance", "releaseInfo": "2022-"]]]
        let model = OneDriveModel(rig.services)
        XCTAssertEqual(model.state, .linked)
        await model.choose("../Pelis/./")
        XCTAssertEqual(model.folder, "Pelis", "solo una ruta dentro de tu OneDrive")
        XCTAssertEqual(rig.services.appSettings.oneDriveFolder, "Pelis")
        XCTAssertFalse(model.scanning)
        XCTAssertNil(model.scanError)
        XCTAssertEqual(model.movies, 1)
        XCTAssertEqual(model.episodes, 1)
        XCTAssertNil(OneDriveModel.folderName("/"), "«/» es todo tu OneDrive")
        XCTAssertEqual(OneDriveModel.folderName("Pelis/Marvel"), "Marvel")
        await model.unlink()
        XCTAssertEqual(model.state, .unlinked)
        XCTAssertNil(model.index)
        XCTAssertEqual(model.movies, 0)
        XCTAssertNil(rig.services.oneDriveLibrary.saved, "lo reconocido se olvida")
    }

    func testSiLaSesionCaducaAlRevisarRegresaAConectar() async throws {
        let rig = try ServicesRig()
        configured(rig, linked: true, refresh: false)
        rig.services.settings.update { $0.oneDriveFolder = "Pelis" }
        rig.http.json[children("Pelis")] = ["error": ["code": "InvalidAuthenticationToken"]]
        rig.http.statuses[children("Pelis")] = 401
        let model = OneDriveModel(rig.services)
        await model.rescan()
        XCTAssertEqual(model.scanError, "Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes.")
        XCTAssertEqual(model.state, .unlinked, "Ajustes vuelve a «Conectar»")
        XCTAssertFalse(model.scanning)
        // Sin sesión, revisar ya no pide nada.
        let asked = rig.http.calls.count
        await model.rescan()
        XCTAssertEqual(rig.http.calls.count, asked)
    }
}
